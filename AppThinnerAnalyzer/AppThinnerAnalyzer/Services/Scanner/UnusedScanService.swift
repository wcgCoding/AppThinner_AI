import Foundation

#if canImport(MachOKit)
import MachOKit
#endif
#if canImport(MachOObjCSection)
import MachOObjCSection
#endif

// MARK: - 无用内容扫描服务协议
// 负责扫描工程中的无用资源和无用代码，支持本地 Swift 静态分析
// 和 Mach-O 二进制符号分析两种检测方式。

protocol UnusedScanServiceProtocol {
    /// 执行本地无用代码/资源扫描。
    /// - Parameters:
    ///   - projectPath: 工程根目录路径
    ///   - projectFileEntries: 工程文件列表（Phase 1 扫描结果）
    ///   - binaryPath: 主二进制文件路径（可选，用于 Mach-O 无用类分析）
    ///   - codeSizeInfo: LinkMap 符号信息（可选，用于 Mach-O 无用类分析）
    /// - Returns: 扫描结果，包含无用资源和无用代码列表
    func runLocalUnusedScan(
        projectPath: String,
        projectFileEntries: [ProjectFileEntry],
        binaryPath: String?,
        codeSizeInfo: [CodeSizeInfo]?
    ) async -> UnusedScanResult?
}

// MARK: - UnusedScanResult

struct UnusedScanResult {
    let unusedResources: [UnusedResource]
    let unusedCode: [UnusedCode]
}

// MARK: - UnusedScanService Implementation

/// 使用 Swift 原生实现无用资源扫描：收集代码文件中的资源引用名 → 与资源文件列表比对 → 未出现即无用。
/// 无用类分析完全由 Mach-O 二进制解析（BinaryUnusedCodeAnalyzer）负责，本 Service 不再涉及类扫描逻辑。
final class UnusedScanService: UnusedScanServiceProtocol {

    private let ignoreFiles = ["main.m", "AppDelegate.h", "AppDelegate.m", "main.swift", "Podfile", "Podfile.lock"]
    private let codeExts = ["swift", "m", "mm", "h"]
    private let resourceExts = ["png", "jpg", "jpeg", "gif", "xib", "storyboard", "xcassets"]

    func runLocalUnusedScan(
        projectPath: String,
        projectFileEntries: [ProjectFileEntry],
        binaryPath: String?,
        codeSizeInfo: [CodeSizeInfo]?
    ) async -> UnusedScanResult? {
        guard FileManager.default.fileExists(atPath: projectPath) else {
            print("⚠️ [UnusedScan] 工程路径不存在，跳过: \(projectPath)")
            return nil
        }
        let t0 = Date()
        func e(_ from: Date) -> String { String(format: "%.2f", Date().timeIntervalSince(from)) }
        let base = URL(fileURLWithPath: projectPath)

        // 复用 Phase 1 的扫描结果，避免重复遍历文件系统
        let (codeFiles, resourceFiles) = collectProjectFilesFromEntries(
            projectFileEntries: projectFileEntries,
            base: base
        )

        // 基于资源路径推导 Lottie 资源文件夹名集合
        var lottieFolderNames: Set<String> = []
        for url in resourceFiles {
            let comps = url.pathComponents
            if let idx = comps.firstIndex(of: "LottieAnimation"), idx + 1 < comps.count {
                lottieFolderNames.insert(comps[idx + 1])
            }
        }

        // ==================== 无用类分析（Mach-O 二进制）====================
        var unusedCode: [UnusedCode] = []
        if let binaryPath = binaryPath, FileManager.default.fileExists(atPath: binaryPath) {
            print("📊 [UnusedScan] 使用 Mach-O 二进制分析无用类: \(binaryPath)")
            unusedCode = await analyzeUnusedClassesFromBinary(
                binaryPath: binaryPath,
                codeSizeInfo: codeSizeInfo ?? []
            )
            print("📊 [UnusedScan] Mach-O 分析完成，发现 \(unusedCode.count) 个候选无用类")
        }

        // ==================== 无用资源扫描 ====================
        // 扫描代码文件，仅收集资源引用名（不做类定义/引用提取）
        let referencedResourceNames = await collectResourceReferences(
            codeFiles: codeFiles,
            lottieFolderNames: lottieFolderNames
        )

        let unusedResources = buildUnusedResources(
            base: base,
            resourceURLs: resourceFiles,
            referencedNames: referencedResourceNames,
            lottieFolderNames: lottieFolderNames
        )

        print("⏱️ [TIMING]   无用扫描总计: \(e(t0))s  (无用类:\(unusedCode.count), 无用资源:\(unusedResources.count))")
        return UnusedScanResult(unusedResources: unusedResources, unusedCode: unusedCode)
    }

    // MARK: - 资源引用收集

    /// 并行扫描代码文件，仅提取资源引用名，返回所有被引用的资源逻辑名集合。
    private func collectResourceReferences(
        codeFiles: [URL],
        lottieFolderNames: Set<String>
    ) async -> Set<String> {
        let t0 = Date()
        print("🔍 [UnusedScan] 代码文件数: \(codeFiles.count)")

        // 分批提交，每批 batchSize 个文件各自一个 Task 并行执行
        let batchSize = 100
        var referencedNames: Set<String> = []

        for batchStart in stride(from: 0, to: codeFiles.count, by: batchSize) {
            let batch = Array(codeFiles[batchStart..<min(batchStart + batchSize, codeFiles.count)])

            let batchResults = await withTaskGroup(of: Set<String>.self) { group in
                for url in batch {
                    group.addTask {
                        await self.collectResourceReferencesInFile(
                            url: url,
                            lottieFolderNames: lottieFolderNames
                        )
                    }
                }
                var merged = Set<String>()
                for await result in group { merged.formUnion(result) }
                return merged
            }

            referencedNames.formUnion(batchResults)
        }

        let elapsed = String(format: "%.2f", Date().timeIntervalSince(t0))
        print("⏱️ [TIMING]     代码文件扫描(\(codeFiles.count)个): \(elapsed)s  资源引用:\(referencedNames.count)")
        return referencedNames
    }

    /// 从单个代码文件中提取资源引用名（并行调用）
    private func collectResourceReferencesInFile(
        url: URL,
        lottieFolderNames: Set<String>
    ) async -> Set<String> {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var referencedNames = Set<String>()
        extractResourceReferences(
            content: content,
            ext: url.pathExtension,
            filePath: url.path,
            lottieFolderNames: lottieFolderNames,
            referencedNames: &referencedNames
        )
        return referencedNames
    }

    /// 从代码内容中提取资源引用（图片 / nib / storyboard / 文件路径等），按资源「逻辑名」写入 referencedNames。
    /// 根据语言区分使用不同的正则；按需求已移除 nibWithNibName/storyboardWithName 的匹配。
    private func extractResourceReferences(
        content: String,
        ext: String,
        filePath: String,
        lottieFolderNames: Set<String>,
        referencedNames: inout Set<String>
    ) {
        let isSwift = ext.lowercased() == "swift"
        // 通用：根据语言选择合适的字符串模式
        let debugTarget = ""
        if isSwift {
            // Swift 常见资源引用：UIImage(named:), path(forResource:ofType:)
            for match in content.match(regex: "UIImage\\(named:\\s*\"([^\"]+)\"\\)") where match.count > 1 {
                referencedNames.insert(resourceBaseName(match[1]))
            }
            for match in content.match(regex: "path\\(forResource:\\s*\"([^\"]+)\"") where match.count > 1 {
                referencedNames.insert(resourceBaseName(match[1]))
            }
        } else {
            // ObjC 常见资源引用：imageNamed:，wsImageNamed:，pathForResource:，以及直接通过 stringByAppendingPathComponent 拼接的文件名
            for match in content.match(regex: "imageNamed:\\s*@\"([^\"]+)\"") where match.count > 1 {
                let logical = resourceBaseName(match[1])
                referencedNames.insert(logical)
                if logical == debugTarget {
                    print("🔍 [UnusedScan][Debug] imageNamed:@\"\(match[1])\" captured as \"\(logical)\" in \(filePath)")
                }
            }
            for match in content.match(regex: "wsImageNamed:\\s*@\"([^\"]+)\"") where match.count > 1 {
                let logical = resourceBaseName(match[1])
                referencedNames.insert(logical)
                if logical == debugTarget {
                    print("🔍 [UnusedScan][Debug] wsImageNamed:@\"\(match[1])\" captured as \"\(logical)\" in \(filePath)")
                }
            }
            for match in content.match(regex: "wsImageNamed:\\s*\"([^\"]+)\"") where match.count > 1 {
                let logical = resourceBaseName(match[1])
                referencedNames.insert(logical)
                if logical == debugTarget {
                    print("🔍 [UnusedScan][Debug] wsImageNamed:\"\(match[1])\" captured as \"\(logical)\" in \(filePath)")
                }
            }
            for match in content.match(regex: "pathForResource:\\s*@\"([^\"]+)\"") where match.count > 1 {
                referencedNames.insert(resourceBaseName(match[1]))
            }
            // 例如 [[NSBundle wsBundle].resourcePath stringByAppendingPathComponent:@"QQyuantu.png"]
            for match in content.match(regex: "stringByAppendingPathComponent:\\s*@\"([^\"]+)\"") where match.count > 1 {
                let logical = resourceBaseName(match[1])
                referencedNames.insert(logical)
                if logical == debugTarget {
                    print("🔍 [UnusedScan][Debug] stringByAppendingPathComponent:@\"\(match[1])\" captured as \"\(logical)\" in \(filePath)")
                }
            }
        }
        // LottieAnimation：如果代码中出现某个 Lottie 资源文件夹名的字符串，也视为被引用
        if !lottieFolderNames.isEmpty {
            for folder in lottieFolderNames {
                if content.contains("\"\(folder)\"") {
                    referencedNames.insert(folder)
                }
            }
        }
    }

    // MARK: - 无用资源扫描
    
    /// 基于资源 URL 列表和代码扫描阶段收集到的「已引用资源名」集合，判定未使用资源。并行处理优化性能。
    private func buildUnusedResources(
        base: URL,
        resourceURLs: [URL],
        referencedNames: Set<String>,
        lottieFolderNames: Set<String>
    ) -> [UnusedResource] {
        let t0 = Date()
        let projectPath = base.path
        let debugTargets: Set<String> = ["good_voice_c_bg", "default_bg"]
        
        // 并行处理资源文件判定
        let lock = NSLock()
        var allUnusedResources: [UnusedResource] = []
        
        DispatchQueue.concurrentPerform(iterations: resourceURLs.count) { index in
            let url = resourceURLs[index]
            let comps = url.pathComponents
            var lottieFolder: String?
            var assetLogicalName: String?
            
            if let idx = comps.firstIndex(of: "LottieAnimation"), idx + 1 < comps.count {
                lottieFolder = comps[idx + 1]
            }
            if let imagesetIdx = comps.firstIndex(where: { $0.hasSuffix(".imageset") }) {
                let imagesetFolder = comps[imagesetIdx]
                let logical = (imagesetFolder as NSString).deletingPathExtension
                if !logical.isEmpty {
                    assetLogicalName = logical
                }
            }
            
            let name = url.deletingPathExtension().lastPathComponent
            var baseName = name
            if baseName.hasSuffix("@2x") || baseName.hasSuffix("@3x") || baseName.hasSuffix("@1x") {
                baseName = String(baseName.dropLast(3))
            }
            
            // 判断是否被引用
            let isReferenced: Bool
            if let folder = lottieFolder {
                isReferenced = referencedNames.contains(folder)
            } else if let assetName = assetLogicalName {
                // .xcassets 内资源
                isReferenced = referencedNames.contains(assetName)
                    || referencedNames.contains(baseName)
                    || referencedNames.contains(name)
                    || referencedNames.contains { ref in
                        guard let last = ref.split(separator: "_").last else { return false }
                        return String(last) == baseName
                    }
            } else {
                // 直接文件名命中
                isReferenced = referencedNames.contains(baseName)
                    || referencedNames.contains(name)
                    || referencedNames.contains { ref in
                        guard let last = ref.split(separator: "_").last else { return false }
                        return String(last) == baseName
                    }
            }
            
            if isReferenced {
                return
            }
            
            // Debug日志
            if debugTargets.contains(baseName) || debugTargets.contains(name) || (assetLogicalName.map { debugTargets.contains($0) } ?? false) {
                DispatchQueue.main.async {
                    print("🔍 [UnusedScan][Debug] marking image as unused: path=\(url.path)")
                    print("   - assetLogicalName=\(assetLogicalName ?? "nil"), baseName=\(baseName), fileName=\(name)")
                    print("   - referenced(assetLogicalName)=\(assetLogicalName.map { referencedNames.contains($0) } ?? false)")
                    print("   - referenced(baseName/fileName)=\(referencedNames.contains(baseName) || referencedNames.contains(name))")
                }
            }
            
            var rel = url.path
            if rel.hasPrefix(projectPath) {
                rel = String(rel.dropFirst(projectPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            let ext = url.pathExtension.lowercased()
            let type: ResourceType = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "heic", "heif", "svg"].contains(ext) ? .image : .data
            
            let resource = UnusedResource(
                relativePath: rel,
                fileName: url.lastPathComponent,
                size: size,
                resourceType: type,
                detectionMethod: .staticAnalysis,
                recommendedAction: .reviewRequired
            )
            
            lock.lock()
            allUnusedResources.append(resource)
            lock.unlock()
        }
        
        let elapsed = String(format: "%.2f", Date().timeIntervalSince(t0))
        print("⏱️ [TIMING]     无用资源扫描: \(elapsed)s  (资源文件:\(resourceURLs.count), 判定为无用:\(allUnusedResources.count))")
        return allUnusedResources
    }

    private func resourceBaseName(_ name: String) -> String {
        var base = (name as NSString).deletingPathExtension
        for suffix in ["@3x", "@2x", "@1x"] {
            if base.hasSuffix(suffix) { base = String(base.dropLast(suffix.count)); break }
        }
        return base
    }

    /// 从 Phase 1 扫描结果中提取代码文件和资源文件 URL，避免重复遍历文件系统
    private func collectProjectFilesFromEntries(
        projectFileEntries: [ProjectFileEntry],
        base: URL
    ) -> (codeFiles: [URL], resourceFiles: [URL]) {
        var codeFiles: [URL] = []
        var resourceFiles: [URL] = []
        
        let codeExtSet = Set(codeExts.map { $0.lowercased() })
        let resourceExtSet = Set(resourceExts.map { $0.lowercased() })
        
        for entry in projectFileEntries {
            // 构建完整URL
            let url = base.appendingPathComponent(entry.relativePath)
            let extLower = url.pathExtension.lowercased()
            
            // 跳过 ignoreFiles
            if ignoreFiles.contains(entry.fileName) { continue }
            
            // 代码文件：按扩展名匹配
            if codeExtSet.contains(extLower) {
                codeFiles.append(url)
            }
            
            // 资源文件：按扩展名匹配
            if resourceExtSet.contains(extLower) {
                resourceFiles.append(url)
            }
        }
        
        return (codeFiles, resourceFiles)
    }
    
}

// MARK: - String Regex Helpers（带正则缓存，避免大工程重复编译开销）

private enum _RegexCache {
    private static var cache: [String: NSRegularExpression] = [:]
    private static let lock = NSLock()
    
    static func regex(for pattern: String) -> NSRegularExpression? {
        lock.lock()
        defer { lock.unlock() }
        if let existing = cache[pattern] { return existing }
        guard let compiled = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        cache[pattern] = compiled
        return compiled
    }
}

private extension String {
    /// 返回所有匹配的捕获组数组，每个元素为 [整段, 组1, 组2, ...]
    func match(regex pattern: String) -> [[String]] {
        guard let compiled = _RegexCache.regex(for: pattern) else { return [] }
        let range = NSRange(startIndex..., in: self)
        let matches = compiled.matches(in: self, range: range)
        return matches.map { match in
            (0..<match.numberOfRanges).compactMap { i -> String? in
                guard let r = Range(match.range(at: i), in: self) else { return nil }
                return String(self[r])
            }
        }
    }
}

// MARK: - BinaryUnusedCodeAnalyzer Integration

extension UnusedScanService {
    /// 使用 BinaryUnusedCodeAnalyzer 进行 Mach-O 二进制分析
    /// - Parameters:
    ///   - binaryPath: Mach-O 二进制文件路径
    ///   - codeSizeInfo: LinkMap 符号信息（用于映射类名到源文件）
    /// - Returns: 无用类信息列表
    func analyzeUnusedClassesFromBinary(
        binaryPath: String,
        codeSizeInfo: [CodeSizeInfo]
    ) async -> [UnusedCode] {
        // 直接调用 BinaryUnusedCodeAnalyzer
        let analyzer = BinaryUnusedCodeAnalyzer()
        return await analyzer.analyzeUnusedClasses(
            binaryPath: binaryPath,
            codeSizeInfo: codeSizeInfo
        )
    }
}
