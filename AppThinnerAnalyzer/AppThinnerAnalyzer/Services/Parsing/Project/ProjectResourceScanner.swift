import Foundation
import UniformTypeIdentifiers

// MARK: - ProjectResourceScanner 协议
// 负责扫描工程目录，枚举所有文件（代码 + 资源），构建分析树骨架。
// 支持全量扫描（代码+资源）和仅资源扫描两种模式，
// 并提供路径映射表构建和无用资源检测能力。

protocol ProjectResourceScannerProtocol {
    /// 仅扫描资源类文件（图片、plist、xib 等），返回资源类型的 ProjectFileEntry
    func scanProjectDirectory(at path: String) async throws -> [ProjectFileEntry]
    /// 扫描项目目录下所有文件（代码+资源），用于构建分析树骨架
    func scanProjectDirectoryAllFiles(at path: String) async throws -> [ProjectFileEntry]
    func detectUnusedResources(
        in project: String,
        using packageInfo: [PackageFileInfo]
    ) async throws -> [UnusedResource]
    func buildPathMappingTable(
        projectPath: String,
        packageFiles: [PackageFileInfo]
    ) async throws -> PathMappingTable
}

// MARK: - ProjectResourceScanner 实现

class ProjectResourceScanner: ProjectResourceScannerProtocol {

    // MARK: - 公共方法

    /// 仅扫描资源类文件。实现上由「全量扫描」结果派生，不再单独扫盘。
    func scanProjectDirectory(at path: String) async throws -> [ProjectFileEntry] {
        let entries = try await scanProjectDirectoryAllFiles(at: path)
        return Self.resourceEntries(from: entries)
    }

    /// 从全量文件条目中筛出资源类型的 ProjectFileEntry
    static func resourceEntries(from entries: [ProjectFileEntry]) -> [ProjectFileEntry] {
        entries.filter { e in e.resourceType != nil && e.resourceType != .other }
    }

    func scanProjectDirectoryAllFiles(at path: String) async throws -> [ProjectFileEntry] {
        let projectURL = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw AnalysisError.invalidFilePath("Project directory not found: \(path)")
        }

        return await withTaskGroup(of: [ProjectFileEntry].self) { group in
            var allEntries: [ProjectFileEntry] = []
            let pathPrefixCount = path.count + 1

            let batchSize = 1000
            var currentBatch: [URL] = []
            // .framework 目录条目：直接同步收集，无需批处理
            var frameworkDirEntries: [ProjectFileEntry] = []

            let enumerator = FileManager.default.enumerator(
                at: projectURL,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            while let fileURL = enumerator?.nextObject() as? URL {
                guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]) else { continue }

                let isDir = resourceValues.isDirectory ?? false

                if isDir {
                    // .framework 目录：作为一个 entry 记录，并跳过其内部（内部二进制不参与文件名索引）
                    if fileURL.pathExtension.lowercased() == "framework",
                       !shouldSkipDirectory(fileURL) {
                        let relativePath = String(fileURL.path.dropFirst(pathPrefixCount))
                        frameworkDirEntries.append(ProjectFileEntry(
                            relativePath: relativePath,
                            fileName: fileURL.lastPathComponent,
                            size: 0,
                            isSourceCode: false,
                            resourceType: .other
                        ))
                        enumerator?.skipDescendants()
                    }
                    continue
                }

                guard !shouldSkipFile(fileURL), !Self.isHeaderFile(fileURL) else { continue }

                currentBatch.append(fileURL)

                if currentBatch.count >= batchSize {
                    let batch = currentBatch
                    currentBatch = []
                    group.addTask {
                        return await self.processFileBatch(batch, pathPrefixCount: pathPrefixCount)
                    }
                }
            }

            if !currentBatch.isEmpty {
                group.addTask {
                    return await self.processFileBatch(currentBatch, pathPrefixCount: pathPrefixCount)
                }
            }

            for await batchResult in group {
                allEntries.append(contentsOf: batchResult)
            }
            allEntries.append(contentsOf: frameworkDirEntries)

            return allEntries
        }
    }
    
    /// 顺序处理文件批次（避免为每个文件创建 Task 带来的过度调度开销）
    private func processFileBatch(_ fileURLs: [URL], pathPrefixCount: Int) async -> [ProjectFileEntry] {
        var entries: [ProjectFileEntry] = []
        entries.reserveCapacity(fileURLs.count)
        for fileURL in fileURLs {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                  let isDir = resourceValues.isDirectory, !isDir,
                  !shouldSkipFile(fileURL),
                  !Self.isHeaderFile(fileURL) else { continue }

            let relativePath = String(fileURL.path.dropFirst(pathPrefixCount))
            let isSource = Self.isSourceCodeFile(fileURL)
            let resourceType: ResourceType? = isSource ? nil : determineResourceType(for: fileURL, contentType: nil)

            entries.append(ProjectFileEntry(
                relativePath: relativePath,
                fileName: fileURL.lastPathComponent,
                size: Int64(resourceValues.fileSize ?? 0),
                isSourceCode: isSource,
                resourceType: resourceType
            ))
        }
        return entries
    }

    /// 是否为参与编译的源码文件（会产生 .o 编译单元，可落地 linkmap 体积映射）。
    /// 头文件（.h/.hpp）不产生 .o，故不纳入。
    private static func isSourceCodeFile(_ url: URL) -> Bool {
        ["m", "mm", "swift", "c", "cc", "cpp"].contains(url.pathExtension.lowercased())
    }

    /// 是否为头文件（不产生编译单元，不纳入 ProjectFileEntry）。
    private static func isHeaderFile(_ url: URL) -> Bool {
        ["h", "hpp"].contains(url.pathExtension.lowercased())
    }

    func detectUnusedResources(
        in project: String,
        using packageInfo: [PackageFileInfo]
    ) async throws -> [UnusedResource] {
        let projectResources = try await scanProjectDirectory(at: project)
        let packageResourcePaths = Set(packageInfo.map { $0.relativePath })
        let sourceFiles = try await findSourceFiles(in: project)
        var unusedResources: [UnusedResource] = []
        for resource in projectResources {
            let isReferenced = try await isResourceReferenced(resource: resource, in: sourceFiles)
            if !isReferenced {
                unusedResources.append(UnusedResource(
                    relativePath: resource.relativePath,
                    fileName: resource.fileName,
                    size: resource.size,
                    resourceType: resource.resourceType ?? .other,
                    detectionMethod: .staticAnalysis,
                    recommendedAction: determineRecommendedAction(
                        for: resource,
                        existsInPackage: packageResourcePaths.contains(resource.relativePath)
                    )
                ))
            }
        }
        return unusedResources
    }

    func buildPathMappingTable(
        projectPath: String,
        packageFiles: [PackageFileInfo]
    ) async throws -> PathMappingTable {
        let projectResources = try await scanProjectDirectory(at: projectPath)
        return PathMappingResolver().buildInitialMappingTable(
            projectResources: projectResources,
            packageFiles: packageFiles
        )
    }

    // MARK: - Private Methods

    private func shouldSkipFile(_ url: URL) -> Bool {
        let path = url.path
        let skipPatterns = [
            "/build/", "/DerivedData/", "/.git/", "/node_modules/",
            ".xcworkspace/", ".xcodeproj/", "ios-arm64_x86_64-simulator/", "ios-x86_64-simulator",
            "_CodeSignature/", "LICENSE",
            "/Pods/Headers/",
        ]
        for pattern in skipPatterns {
            if path.contains(pattern) { return true }
        }
        return ["o", "dylib", "dSYM", "pch", "gch", "sh"].contains(url.pathExtension.lowercased())
    }

    /// 判断一个目录是否应该整体跳过（不录入也不递归进入）。
    /// 注意：.framework 目录本身会被作为 entry 录入，但其内部文件通过 skipDescendants 跳过，
    /// 所以此方法仅用于判断是否连 .framework 目录本身都不需要录入（如 DerivedData、build 内的）。
    private func shouldSkipDirectory(_ url: URL) -> Bool {
        let path = url.path
        let skipPatterns = [
            "/build/", "/DerivedData/", "/.git/",
            ".xcworkspace/", ".xcodeproj/",
            "ios-arm64_x86_64-simulator/", "ios-x86_64-simulator",
        ]
        for pattern in skipPatterns {
            if path.contains(pattern) { return true }
        }
        return false
    }

    private func determineResourceType(for url: URL, contentType: UTType?) -> ResourceType {
        let pathExtension = url.pathExtension.lowercased()
        if let contentType = contentType {
            if contentType.conforms(to: .image) { return .image }
            if contentType.conforms(to: .audio) { return .audio }
            if contentType.conforms(to: .video) { return .video }
            if contentType.conforms(to: .data) { return .data }
        }
        switch pathExtension {
        case "png", "jpg", "jpeg", "gif", "svg", "pdf", "tiff", "bmp", "webp", "heic", "heif":
            return .image
        case "mp3", "wav", "aac", "m4a", "flac", "ogg", "wma": return .audio
        case "mp4", "mov", "avi", "mkv", "wmv", "flv", "webm": return .video
        case "json", "plist", "xml", "txt", "strings", "stringsdict", "csv", "yaml", "yml",
             "storyboard", "xib", "nib", "xcassets", "imageset", "colorset", "dataset":
            return .data
        default: return .other
        }
    }

    private func findSourceFiles(in projectPath: String) async throws -> [URL] {
        let projectURL = URL(fileURLWithPath: projectPath)
        var sourceFiles: [URL] = []
        let sourceExtensions = ["swift", "m", "mm", "cpp", "c", "cc", "storyboard", "xib", "strings", "stringsdict"] // "h", "hpp",
        let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            if sourceExtensions.contains(fileURL.pathExtension.lowercased()) && !shouldSkipFile(fileURL) {
                sourceFiles.append(fileURL)
            }
        }
        return sourceFiles
    }

    private func isResourceReferenced(resource: ProjectFileEntry, in sourceFiles: [URL]) async throws -> Bool {
        let searchPatterns = generateSearchPatterns(for: resource)
        for sourceFile in sourceFiles {
            guard let content = try? String(contentsOf: sourceFile, encoding: .utf8) else { continue }
            for pattern in searchPatterns {
                if content.contains(pattern) { return true }
            }
        }
        return false
    }

    private func generateSearchPatterns(for resource: ProjectFileEntry) -> [String] {
        let fileName = resource.fileName
        let baseName = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        var patterns = [fileName, baseName, "\"\(fileName)\"", "\"\(baseName)\""]
        switch resource.resourceType ?? .other {
        case .image:
            patterns += ["UIImage(named: \"\(baseName)\")", "Image(\"\(baseName)\")", "imageNamed:\"\(baseName)\""]
        case .audio, .video:
            patterns += ["Bundle.main.url(forResource: \"\(baseName)\"", "NSBundle.mainBundle().URLForResource(\"\(baseName)\""]
        case .data:
            if fileName.hasSuffix(".plist") {
                patterns += ["Bundle.main.path(forResource: \"\(baseName)\"", "NSBundle.mainBundle().pathForResource(\"\(baseName)\""]
            }
        case .other: break
        }
        return patterns
    }

    private func determineRecommendedAction(for resource: ProjectFileEntry, existsInPackage: Bool) -> RecommendedAction {
        if !existsInPackage { return .safeToDelete }
        switch resource.resourceType ?? .other {
        case .image: return resource.size > 100_000 ? .reviewRequired : .safeToDelete
        case .data: return .reviewRequired
        case .audio, .video: return .safeToDelete
        case .other: return .reviewRequired
        }
    }

}
