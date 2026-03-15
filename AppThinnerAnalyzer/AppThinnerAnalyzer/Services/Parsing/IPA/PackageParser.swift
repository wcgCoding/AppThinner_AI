import Foundation
import UniformTypeIdentifiers

// MARK: - Parse Result

/// 解析 IPA/.app 的返回：文件列表、.app 在磁盘上的路径（用于 Assets.car 等）、若为 IPA 解压则需在分析完成后清理的临时目录。
struct PackageParseResult {
    let packageFiles: [PackageFileInfo]
    /// .app 的绝对路径（IPA 解压后为 Payload/xxx.app，.app 直接选择时为所选路径）
    let appBundlePath: URL?
    /// 仅解析 .ipa 时非 nil，调用方在分析结束后需删除此目录以释放磁盘
    let tempDirectoryForCleanup: URL?
}

// MARK: - PackageParser 协议
// 负责解析 .ipa 和 .app 包，提取包内所有文件的相对路径和大小，
// 并识别主二进制文件（CFBundleExecutable）。
// .ipa 解析时会解压到临时目录，调用方需在分析结束后清理该目录。

protocol PackageParserProtocol {
    func parseIPA(at path: String) async throws -> PackageParseResult
    /// 使用已具备 security-scoped 访问权限的 URL 解析 IPA（沙盒下必须用此接口才能正确读取）；
    /// 解压后保留 .app 路径供 Assets.car 解析，临时目录由调用方在分析结束后清理。
    func parseIPA(at url: URL) async throws -> PackageParseResult
    func parseApp(at path: String) async throws -> PackageParseResult
}

// MARK: - PackageParser 实现

class PackageParser: PackageParserProtocol {

    // MARK: - 公共方法

    func parseIPA(at path: String) async throws -> PackageParseResult {
        let url = URL(fileURLWithPath: path)
        return try await parseIPA(at: url)
    }

    func parseIPA(at url: URL) async throws -> PackageParseResult {
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw AnalysisError.invalidFilePath(path)
        }
        guard url.pathExtension.lowercased() == "ipa" else {
            throw AnalysisError.unsupportedFileFormat(
                "Expected .ipa file, got .\(url.pathExtension)")
        }

        let tempDir = try createTemporaryDirectory()
        // 不再在此处删除临时目录，由调用方在分析结束后清理，以便使用解压后的 .app 路径解析 Assets.car

        let tempIpaURL = tempDir.appendingPathComponent("archive.ipa")
        try readSecurityScopedFile(at: url, writingTo: tempIpaURL)

        try await extractZipFile(from: tempIpaURL, to: tempDir)
        let appBundle = try findAppBundle(in: tempDir)
        let packageFiles = try await parseAppBundle(at: appBundle.path)
        return PackageParseResult(
            packageFiles: packageFiles,
            appBundlePath: appBundle,
            tempDirectoryForCleanup: tempDir
        )
    }

    func parseApp(at path: String) async throws -> PackageParseResult {
        let url = URL(fileURLWithPath: path)

        // Validate file exists and is a directory
        guard FileManager.default.fileExists(atPath: path) else {
            throw AnalysisError.invalidFilePath(path)
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw AnalysisError.unsupportedFileFormat("Expected .app bundle directory")
        }

        // Validate .app extension
        guard url.pathExtension.lowercased() == "app" else {
            throw AnalysisError.unsupportedFileFormat(
                "Expected .app bundle, got .\(url.pathExtension)")
        }

        let packageFiles = try await parseAppBundle(at: path)
        return PackageParseResult(
            packageFiles: packageFiles,
            appBundlePath: url,
            tempDirectoryForCleanup: nil
        )
    }

    // MARK: - Private Methods

    private func createTemporaryDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppThinnerAnalyzer_\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    /// 从 security-scoped 的源 URL 读取内容并写入目标 URL。使用 InputStream 避免 FileHandle 在只读 security-scoped 下触发系统误报。
    private func readSecurityScopedFile(at sourceURL: URL, writingTo destinationURL: URL) throws {
        guard FileManager.default.createFile(atPath: destinationURL.path, contents: nil) else {
            throw AnalysisError.corruptedFile(
                "Failed to create temp IPA file at \(destinationURL.path)")
        }
        guard let input = InputStream(url: sourceURL) else {
            throw AnalysisError.corruptedFile("Failed to open IPA stream: \(sourceURL.path)")
        }
        input.open()
        defer { input.close() }
        guard let output = FileHandle(forWritingAtPath: destinationURL.path) else {
            throw AnalysisError.corruptedFile("Failed to open temp IPA for writing")
        }
        defer { try? output.close() }
        let bufferSize = 1024 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while input.hasBytesAvailable {
            let read = input.read(buffer, maxLength: bufferSize)
            if read > 0 {
                try output.write(contentsOf: Data(bytes: buffer, count: read))
            }
            if read <= 0 { break }
        }
    }

    private func extractZipFile(from sourceURL: URL, to destinationURL: URL) async throws {
        // 在后台队列执行，避免阻塞主线程
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                    process.arguments = ["-q", "-o", sourceURL.path, "-d", destinationURL.path]
                    process.currentDirectoryURL = nil

                    let pipe = Pipe()
                    process.standardError = pipe
                    process.standardOutput = Pipe()

                    try process.run()
                    process.waitUntilExit()

                    if process.terminationStatus != 0 {
                        let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                        pipe.fileHandleForReading.closeFile()
                        let errorString =
                            String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(
                            throwing: AnalysisError.corruptedFile(
                                "Failed to extract IPA: \(errorString)"))
                        return
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(
                        throwing: AnalysisError.corruptedFile(
                            "Failed to extract IPA: \(error.localizedDescription)"))
                }
            }
        }
    }

    private func findAppBundle(in directory: URL) throws -> URL {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )

        // Look for Payload directory first (standard IPA structure)
        if let payloadDir = contents.first(where: { $0.lastPathComponent == "Payload" }) {
            let payloadContents = try FileManager.default.contentsOfDirectory(
                at: payloadDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )

            if let appBundle = payloadContents.first(where: { $0.pathExtension == "app" }) {
                return appBundle
            }
        }

        // Fallback: look for .app bundle directly in the directory
        if let appBundle = contents.first(where: { $0.pathExtension == "app" }) {
            return appBundle
        }

        throw AnalysisError.corruptedFile("No .app bundle found in IPA")
    }

    private func parseAppBundle(at path: String) async throws -> [PackageFileInfo] {
        let bundleURL = URL(fileURLWithPath: path)
        var fileInfos: [PackageFileInfo] = []

        let bundleBasePath = bundleURL.path
        let mainExecutableName = readCFBundleExecutable(from: bundleURL)

        // Recursively scan all files in the app bundle
        let enumerator = FileManager.default.enumerator(
            at: bundleURL,
            includingPropertiesForKeys: [
                .fileSizeKey,
                .isDirectoryKey,
                .contentTypeKey,
            ],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [
                    .fileSizeKey,
                    .isDirectoryKey,
                    .contentTypeKey,
                ])

                // Skip directories
                guard let isDirectory = resourceValues.isDirectory,
                    !isDirectory
                else {
                    continue
                }

                // Get file size
                let fileSize = resourceValues.fileSize ?? 0

                // Calculate relative path from bundle root
                let relativePath = String(fileURL.path.dropFirst(bundleBasePath.count + 1))
                let fileName = fileURL.lastPathComponent
                let isRootFile = !relativePath.contains("/")
                let isMainExecutable = isRootFile && mainExecutableName != nil && fileName == mainExecutableName!

                let fileType = determineFileType(
                    for: fileURL,
                    contentType: resourceValues.contentType
                )

                let fileInfo = PackageFileInfo(
                    relativePath: relativePath,
                    fileName: fileName,
                    size: Int64(fileSize),
                    fileType: fileType,
                    isMainExecutable: isMainExecutable
                )

                fileInfos.append(fileInfo)

            } catch {
                // Log error but continue processing other files
                print("Warning: Could not read properties for file \(fileURL.path): \(error)")
                continue
            }
        }

        return fileInfos
    }

    /// 从 .app 根目录 Info.plist 读取 CFBundleExecutable，作为主二进制名称（用于准确统计 Code Size）。
    private func readCFBundleExecutable(from bundleURL: URL) -> String? {
        let plistURL = bundleURL.appendingPathComponent("Info.plist")
        guard FileManager.default.fileExists(atPath: plistURL.path) else { return nil }
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let name = plist["CFBundleExecutable"] as? String, !name.isEmpty else {
            return nil
        }
        return name
    }

    private func determineFileType(for url: URL, contentType: UTType?) -> FileType {
        let pathExtension = url.pathExtension.lowercased()

        // Check by content type first
        if let contentType = contentType {
            if contentType.conforms(to: .sourceCode) || contentType.conforms(to: .swiftSource)
                || contentType.conforms(to: .objectiveCSource)
            {
                return .code
            }

            if contentType.conforms(to: .image) || contentType.conforms(to: .audio)
                || contentType.conforms(to: .video) || contentType.conforms(to: .data)
            {
                return .resource
            }
        }

        // Fallback to extension-based detection
        switch pathExtension {
        // Code files
        case "swift", "m", "mm", "h", "hpp", "cpp", "c", "cc":
            return .code

        // Resource files
        case "png", "jpg", "jpeg", "gif", "svg", "pdf", "tiff", "bmp":
            return .resource
        case "mp3", "wav", "aac", "m4a", "flac":
            return .resource
        case "mp4", "mov", "avi", "mkv":
            return .resource
        case "json", "plist", "xml", "txt", "strings", "stringsdict":
            return .resource
        case "storyboard", "xib", "nib":
            return .resource
        case "xcassets", "imageset", "colorset":
            return .resource

        // Framework files
        case "framework", "dylib", "a":
            return .framework

        // Executable and binary files
        case "":
            // Check if it's the main executable (no extension, in root of bundle)
            let relativePath = String(
                url.path.dropFirst(url.deletingLastPathComponent().path.count + 1))
            if !relativePath.contains("/") {
                return .code
            }
            return .other

        default:
            return .other
        }
    }
}

// MARK: - Helper Extensions

extension FileManager {
    func sizeOfFile(at url: URL) throws -> Int64 {
        let attributes = try attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }
}
