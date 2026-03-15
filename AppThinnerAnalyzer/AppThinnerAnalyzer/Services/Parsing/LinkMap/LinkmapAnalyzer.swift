import Foundation

// MARK: - LinkmapAnalyzer Protocol

protocol LinkmapAnalyzerProtocol {
    /// 解析 linkmap，以 Object files 为基础数据返回编译单元汇总 + 符号明细。若传 projectPath 则边解析边解析路径并缓存，结果带 resolvedRelativePath，可省去后续映射步骤。
    func parseLinkmapFile(at path: String, projectPath: String?) async throws -> LinkmapParseResult
    /// 将 Object 文件汇总匹配到项目相对路径，生成 CodeSizeInfo；支持 projectFileEntries 与 pathPrefixesToStrip 以适配 Framework/静态库路径差异。
    /// 若提供 projectPath，对未映射路径会优先用 project.pbxproj 解析、兜底项目目录检索并缓存。
    func mapObjectFilesToProjectStructure(
        parseResult: LinkmapParseResult,
        projectFileIndex: [String: [String]],
        projectFileEntries: [ProjectFileEntry]?,
        linkmapPathPrefixesToStrip: [String],
        projectPath: String?
    ) async throws -> [CodeSizeInfo]
    /// 从已扫描的 projectFileEntries 构建「文件名/基名 -> 相对路径列表」索引
    static func makeProjectFileIndex(from projectFileEntries: [ProjectFileEntry]) -> [String: [String]]
}

// MARK: - Linkmap 路径与项目路径适配

/// 将 Linkmap 中的 Object 路径（含 .framework/Name(Obj.o)、.a(Obj.o)）解析并匹配到项目真实源文件路径。
struct LinkmapPathAdapter {
    let projectFileIndex: [String: [String]]
    /// 静态库匹配索引：key = "pathComponent|baseName"（小写），value = 项目相对路径
    private let staticLibLookup: [String: String]
    /// 静态库「linkmap 库名」→ 项目路径：用于 path 中无对应 pathComponent 时的回退（如 linkmap 库名 ThumbPlayer vs 项目路径 TMEThumbPlayer）
    private let staticLibNameToPath: [String: String]
    /// framework 名（小写，不含 .framework 后缀）→ 项目中 .framework 目录相对路径
    /// 用于将 linkmap 中 `XXX.framework/XXX(Obj.o)` 整体映射到项目里对应的 .framework 目录
    private let frameworkNameToPath: [String: String]
    let pathPrefixesToStrip: [String]

    init(projectFileIndex: [String: [String]], projectFileEntries: [ProjectFileEntry], pathPrefixesToStrip: [String]) {
        self.projectFileIndex = projectFileIndex
        self.pathPrefixesToStrip = pathPrefixesToStrip
        self.staticLibLookup = Self.buildStaticLibLookup(projectFileEntries: projectFileEntries)
        self.staticLibNameToPath = Self.buildStaticLibNameToPath(projectFileEntries: projectFileEntries)
        self.frameworkNameToPath = Self.buildFrameworkNameToPath(projectFileEntries: projectFileEntries)
    }

    /// 常见构建/归档根路径前缀，用于将 linkmap 绝对路径变为可与项目路径对齐的相对形式。
    static let defaultPrefixesToStrip: [String] = [
        "/Volumes/data/workspace/",
        "/var/folders/",
        "/tmp/",
        "/Users/bkdevops/Library/Developer/Xcode/DerivedData/",
    ]

    /// 用于「直接映射」的 workspace 前缀：以该前缀开头的 linkmap 路径可直接 strip 后作为项目相对路径，无需走 projectFileIndex/静态库/Framework 查找，加快解析。
    static let workspacePrefixesForDirectMapping: [String] = [
        "/Volumes/data/workspace/",
    ]

    /// 若 linkmap 路径以 workspace 前缀开头，则直接 strip 并规范化后作为项目相对路径。
    /// 以下情况不直接映射，交给 fallback 解析为真实项目/源码路径：
    /// - 含 XCFrameworkIntermediates（构建产物与 Pods 下 xcframework 不一致）
    /// - 含 Release-iphoneos 且含 .a(（静态库 .o 在构建目录，需 fallback 查 .m/.mm 源码）
    static func directRelativePathFromLinkmap(linkmapPath: String) -> String? {
        let trimmed = linkmapPath.trimmingCharacters(in: .whitespaces)
        if trimmed.contains("XCFrameworkIntermediates") { return nil }
        if trimmed.contains("Release-iphoneos") && trimmed.contains(".a(") { return nil }
        guard let prefix = workspacePrefixesForDirectMapping.first(where: { trimmed.hasPrefix($0) }) else {
            return nil
        }
        var relative = String(trimmed.dropFirst(prefix.count))
        if relative.hasPrefix("/") { relative = String(relative.dropFirst()) }
        // 将最后一层中的 "Name(Obj.o)" 规范为 "Name/Obj.o"
        if let openIdx = relative.lastIndex(of: "("), let closeIdx = relative.lastIndex(of: ")"), openIdx < closeIdx {
            let beforeParen = String(relative[..<openIdx])
            let inner = String(relative[relative.index(after: openIdx)..<closeIdx])
            relative = beforeParen + "/" + inner
        }
        return relative.isEmpty ? nil : relative
    }

    /// 从 linkmap 路径解析出用于查找的「对象基名」（.o 对应的源文件基名）。
    /// - Framework: ".../Name.framework/Name(Obj.o)" → "Obj"
    /// - Static lib: ".../libX.a(Obj.o)" 或 ".../X.a(Obj.o)" → "Obj"
    static func objectBaseName(fromLinkmapPath path: String, fileName: String) -> String? {
        // 优先从 fileName（lastPathComponent）解析 "Name(Obj.o)" 或 "Obj.o"
        if fileName.contains("("), let open = fileName.firstIndex(of: "("), let close = fileName.firstIndex(of: ")") {
            let inner = String(fileName[fileName.index(after: open)..<close])
            if inner.hasSuffix(".o") {
                return (inner as NSString).deletingPathExtension
            }
            return inner
        }
        return (fileName as NSString).deletingPathExtension
    }

    /// 从 linkmap 路径中提取 .framework 名称（不含 .framework 后缀）。
    /// 例：`UnityAds/UnityAds.framework/UnityAds(X.o)` → `"unityads"`
    /// 例：`Ads-Global/PAGAdSDK.framework/PAGAdSDK(PAGDevice.o)` → `"pagadsdk"`
    static func frameworkName(fromLinkmapPath path: String) -> String? {
        guard let fwRange = path.range(of: ".framework/") ?? path.range(of: ".framework") else { return nil }
        let before = String(path[..<fwRange.lowerBound])
        let name = (before as NSString).lastPathComponent
        return name.isEmpty ? nil : name.lowercased()
    }

    /// 预构建「pathComponent|基名」-> 项目路径 索引，使静态库匹配由 O(entries) 降为 O(1)。
    private static func buildStaticLibLookup(projectFileEntries: [ProjectFileEntry]) -> [String: String] {
        var lookup: [String: String] = [:]
        let sep = "|"
        for entry in projectFileEntries {
            let base = (entry.fileName as NSString).deletingPathExtension.lowercased()
            let pathLower = entry.relativePath.lowercased()
            let components = pathLower.split(separator: "/").map(String.init)
            for comp in components where !comp.isEmpty {
                let key = comp + sep + base
                if lookup[key] == nil {
                    lookup[key] = entry.relativePath
                }
            }
        }
        return lookup
    }

    /// 从 .a 文件名推导 linkmap 中的库名（libThumbPlayer.a → ThumbPlayer），建立「库名小写 → 项目路径」回退表，便于路径组件与 linkmap 库名不一致时仍能匹配（如 TMEThumbPlayer 目录下的 libThumbPlayer.a）。
    private static func buildStaticLibNameToPath(projectFileEntries: [ProjectFileEntry]) -> [String: String] {
        var nameToPath: [String: String] = [:]
        for entry in projectFileEntries {
            let fn = entry.fileName
            guard fn.lowercased().hasSuffix(".a") else { continue }
            var name = (fn as NSString).deletingPathExtension
            if name.lowercased().hasPrefix("lib") {
                name = String(name.dropFirst(3))
            }
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            if nameToPath[key] == nil {
                nameToPath[key] = entry.relativePath
            }
        }
        if !nameToPath.isEmpty {
            print("🔗 [LinkmapPathAdapter] Static lib name→path fallback: \(nameToPath.count) libs, e.g. \(Array(nameToPath.keys).prefix(3).joined(separator: ", "))")
        }
        return nameToPath
    }

    /// 扫描 projectFileEntries，提取所有落在 .framework 目录内的文件，
    /// 向上取到 .framework 目录路径，建立「framework 名（小写）→ 项目相对路径（到 .framework 目录）」索引。
    ///
    /// 例：entry.relativePath = "Pods/UnityAds/UnityAds.xcframework/ios-arm64/UnityAds.framework/UnityAds"
    ///     → frameworkDir = "Pods/UnityAds/UnityAds.xcframework/ios-arm64/UnityAds.framework"
    ///     → key = "unityads"
    ///
    /// 当同名 framework 存在多个路径（xcframework 的模拟器切片 vs 设备切片）时，
    /// 优先保留路径中含 "ios-arm64" 但不含 "simulator" 的设备切片路径。
    private static func buildFrameworkNameToPath(projectFileEntries: [ProjectFileEntry]) -> [String: String] {
        var nameToPath: [String: String] = [:]
        for entry in projectFileEntries {
            let path = entry.relativePath
            // 找到路径中 .framework 后缀的目录段
            let components = path.components(separatedBy: "/")
            guard let fwIdx = components.firstIndex(where: { $0.lowercased().hasSuffix(".framework") }) else { continue }
            let fwDir = components[...fwIdx].joined(separator: "/")
            let fwName = (components[fwIdx] as NSString).deletingPathExtension.lowercased()
            guard !fwName.isEmpty else { continue }

            if let existing = nameToPath[fwName] {
                // 已有路径时：优先选设备切片（含 ios-arm64，不含 simulator）
                let existingIsDevice = existing.contains("ios-arm64") && !existing.lowercased().contains("simulator")
                let newIsDevice = fwDir.contains("ios-arm64") && !fwDir.lowercased().contains("simulator")
                if !existingIsDevice && newIsDevice {
                    nameToPath[fwName] = fwDir
                }
            } else {
                nameToPath[fwName] = fwDir
            }
        }
        if !nameToPath.isEmpty {
            print("🔗 [LinkmapPathAdapter] Framework name→path index: \(nameToPath.count) frameworks, e.g. \(Array(nameToPath.keys).prefix(5).joined(separator: ", "))")
        }
        return nameToPath
    }

    /// 是否为静态库形式路径：.../libX.a(Obj.o)、.../libX.a[N](Obj.o) 或 .../X.a(Obj.o)
    static func staticLibName(fromLinkmapPath path: String) -> String? {
        // 支持 .a( 与 .a[ 两种格式（Xcode 常见为 .a[index](Obj.o)）
        let marker = path.contains(".a[") ? ".a[" : (path.contains(".a(") ? ".a(" : nil)
        guard let m = marker, let range = path.range(of: m) else { return nil }
        let beforeA = String(path[..<range.lowerBound])
        let lastComp = (beforeA as NSString).lastPathComponent
        var name = lastComp
        if name.hasPrefix("lib") {
            name = String(name.dropFirst(3))
        }
        return name.isEmpty ? nil : name
    }

    /// 去掉配置的前缀，得到更接近项目根相对路径的字符串（用于展示或匹配）。
    /// 若未匹配到配置前缀，会尝试去掉「.../DerivedData/」及其之前部分，以兼容不同机器上的 Xcode 构建路径。
    func strippedPath(_ path: String) -> String {
        var s = path
        for prefix in pathPrefixesToStrip where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
            return s
        }
        // 通用规则：任意路径中的 DerivedData/ 及其之前部分可剥离，便于跨机器
        if let range = s.range(of: "DerivedData/"), range.lowerBound > s.startIndex {
            s = String(s[range.upperBound...])
        }
        return s
    }

    /// 静态方法：仅按前缀剥离路径（不依赖 Adapter 实例），用于 linkmap 仅 direct+fallback 的快速路径。
    static func simpleStrippedPath(_ path: String, prefixes: [String] = defaultPrefixesToStrip) -> String {
        var s = path
        for prefix in prefixes where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
            if s.hasPrefix("/") { s = String(s.dropFirst()) }
            return s
        }
        if let range = s.range(of: "DerivedData/"), range.lowerBound > s.startIndex {
            s = String(s[range.upperBound...])
        }
        return s
    }

    /// 将 linkmap 中的一条 Object 路径解析并匹配到项目中的相对路径。
    /// 返回 `(resolvedPath, isMapped)`：isMapped=true 表示命中了项目路径索引，false 表示回退到 strippedPath。
    ///
    /// 匹配优先级：
    ///   1. 静态库（.a / .a[N]）：pathComponent|基名 精确查 staticLibLookup；失败则查 staticLibNameToPath
    ///   2. Framework：从路径提取 .framework 名，查 frameworkNameToPath（将整个编译单元归属到 .framework 目录）
    ///   3. 按对象基名查 projectFileIndex（主 Target 普通 .o、Framework 内有对应源文件时）
    ///   4. 回退：strippedPath（去掉绝对前缀，保留相对形态，标记为未映射）
    func resolveToProjectPath(linkmapObjectPath path: String, fileName: String) -> (resolved: String, isMapped: Bool) {
        let baseName = Self.objectBaseName(fromLinkmapPath: path, fileName: fileName)
        let baseLower = baseName?.lowercased() ?? ""

        // 1) 静态库（.a 或 .a[N]）：先查 pathComponent|base，再回退到「linkmap 库名 → 项目路径」
        if let libName = Self.staticLibName(fromLinkmapPath: path), !baseLower.isEmpty {
            let key = libName.lowercased() + "|" + baseLower
            if let resolved = staticLibLookup[key] { return (resolved, true) }
            if let resolved = staticLibNameToPath[libName.lowercased()] { return (resolved, true) }
        }

        // 2) Framework（含 xcframework 设备切片内的 .framework）：
        //    路径中含 .framework/ 时，提取 framework 名查索引。
        //    resolved 保留「.framework 目录 + "/" + 原始带括号文件名」形式，
        //    如 Pods/SDWebImage/SDWebImage.framework/SDWebImage(SDImageCache.o)，
        //    便于 AnalysisService 将其识别为虚拟 .o 节点并精确到编译单元粒度展示。
        if path.contains(".framework") {
            if let fwName = Self.frameworkName(fromLinkmapPath: path),
               let fwDirPath = frameworkNameToPath[fwName] {
                // 保留带括号的编译单元文件名，挂在 .framework 目录下
                let virtualPath = fwDirPath + "/" + fileName
                return (virtualPath, true)
            }
        }

        // 3) 按对象基名在 projectFileIndex 中查找（主 Target 普通 .o 等）
        if !baseLower.isEmpty, let candidates = projectFileIndex[baseLower], let first = candidates.first {
            return (first, true)
        }
        if let candidates = projectFileIndex[fileName.lowercased()], let first = candidates.first {
            return (first, true)
        }

        // 4) 回退：去掉前缀的 linkmap 路径（未映射到项目路径）
        return (strippedPath(path), false)
    }

}

// MARK: - LinkmapAnalyzer Implementation

class LinkmapAnalyzer: LinkmapAnalyzerProtocol {
    
    // MARK: - Public Methods
    
    /// 解析 linkmap：以 Object files 为基础，返回编译单元汇总 + 带 objectFileIndex 的符号列表。传 projectPath 时边解析边解析路径并缓存，objectFileInfos 带 resolvedRelativePath。
    func parseLinkmapFile(at path: String, projectPath: String? = nil) async throws -> LinkmapParseResult {
        guard FileManager.default.fileExists(atPath: path) else {
            throw AnalysisError.invalidFilePath(path)
        }
        let content = try Self.readLinkmapContent(at: path)
        return try await parseLinkmapContentWithObjectFiles(content, projectPath: projectPath)
    }
    
    /// 读取 linkmap 文件内容，兼容非严格 UTF-8（如含非法字节或 BOM）
    private static func readLinkmapContent(at path: String) throws -> String {
        let url = URL(fileURLWithPath: path)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw AnalysisError.corruptedFile("Could not read linkmap file: \(error.localizedDescription)")
        }
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        return String(decoding: data, as: UTF8.self)
    }
    
    /// 以 ObjectFileInfo 为基础匹配项目路径，生成 CodeSizeInfo。
    /// 若解析时已带 resolvedRelativePath（边解析边解析路径），则直接使用，不再做映射，可省去本步骤耗时。
    func mapObjectFilesToProjectStructure(
        parseResult: LinkmapParseResult,
        projectFileIndex: [String: [String]],
        projectFileEntries: [ProjectFileEntry]? = nil,
        linkmapPathPrefixesToStrip: [String] = LinkmapPathAdapter.defaultPrefixesToStrip,
        projectPath: String? = nil
    ) async throws -> [CodeSizeInfo] {
        let allResolved = parseResult.objectFileInfos.allSatisfy { $0.resolvedRelativePath != nil }
        if allResolved, !parseResult.objectFileInfos.isEmpty {
            let symbolsByIndex = Dictionary(grouping: parseResult.symbols) { $0.objectFileIndex }
            let codeSizeInfos: [CodeSizeInfo] = parseResult.objectFileInfos.map { obj in
                let path = obj.resolvedRelativePath!
                let fileSymbols = symbolsByIndex[obj.index] ?? []
                let displayFileName = (path as NSString).lastPathComponent
                return CodeSizeInfo(relativePath: path, fileName: displayFileName, totalSize: obj.totalSize, symbols: fileSymbols)
            }
            return codeSizeInfos.sorted { $0.totalSize > $1.totalSize }
        }
        let useAdapter = (projectFileEntries ?? []).isEmpty == false
        let adapter: LinkmapPathAdapter? = useAdapter ? LinkmapPathAdapter(
            projectFileIndex: projectFileIndex,
            projectFileEntries: projectFileEntries ?? [],
            pathPrefixesToStrip: linkmapPathPrefixesToStrip
        ) : nil
        let fallbackResolver = LinkmapPathFallbackResolver(projectPath: projectPath)
        var codeSizeInfos: [CodeSizeInfo] = []
        let symbolsByIndex = Dictionary(grouping: parseResult.symbols) { $0.objectFileIndex }
        var unmappedEntries: [(path: String, size: Int64)] = []

        for objectFile in parseResult.objectFileInfos {
            let fileSymbols = symbolsByIndex[objectFile.index] ?? []
            var resolved: String
            var isMapped: Bool
            let usedDirect: Bool
            if let direct = LinkmapPathAdapter.directRelativePathFromLinkmap(linkmapPath: objectFile.filePath) {
                resolved = direct
                isMapped = true
                usedDirect = true
            } else if let adapter = adapter {
                let normalizedPath = Self.normalizeLinkmapPathForMatching(objectFile.filePath)
                (resolved, isMapped) = adapter.resolveToProjectPath(linkmapObjectPath: normalizedPath, fileName: objectFile.fileName)
                if !isMapped, let fallback = fallbackResolver?.resolve(linkmapObjectPath: normalizedPath, fileName: objectFile.fileName) {
                    resolved = fallback
                    isMapped = true
                }
                usedDirect = false
            } else {
                let normalizedPath = Self.normalizeLinkmapPathForMatching(objectFile.filePath)
                if let fallback = fallbackResolver?.resolve(linkmapObjectPath: normalizedPath, fileName: objectFile.fileName) {
                    resolved = fallback
                    isMapped = true
                } else {
                    resolved = LinkmapPathAdapter.simpleStrippedPath(normalizedPath, prefixes: linkmapPathPrefixesToStrip)
                    isMapped = false
                }
                usedDirect = false
            }
            if !isMapped {
                unmappedEntries.append((path: resolved, size: objectFile.totalSize))
            }
            let displayFileName = usedDirect ? (resolved as NSString).lastPathComponent : objectFile.fileName
            codeSizeInfos.append(CodeSizeInfo(
                relativePath: resolved,
                fileName: displayFileName,
                totalSize: objectFile.totalSize,
                symbols: fileSymbols
            ))
        }

        if !useAdapter {
            print("🔗 [LinkmapAnalyzer] 已走 linkmap 快速路径（仅 direct + fallback），未使用工程目录索引")
        }
        Self.logUnmappedLinkmapEntries(unmappedEntries)
        let sorted = codeSizeInfos.sorted { $0.totalSize > $1.totalSize }
        return sorted
    }

    /// 打印未能映射到项目路径的 linkmap 编译单元，按体积降序排列，用于分析汇总体积与 .app 体积差距的原因。
    private static func logUnmappedLinkmapEntries(_ entries: [(path: String, size: Int64)]) {
        guard !entries.isEmpty else {
            print("🔗 [LinkmapAnalyzer] 所有编译单元均已映射到项目路径，无遗漏。")
            return
        }
        let sorted = entries.sorted { $0.size > $1.size }
        let totalSize = sorted.reduce(0) { $0 + $1.size }
        print("⚠️ [LinkmapAnalyzer] 未映射到项目路径的编译单元: \(sorted.count) 个，合计 \(totalSize / 1024) KB（\(totalSize / 1024 / 1024) MB）")
        print("   （这部分体积在 Treemap 中将以 linkmap 原始路径显示，可能导致汇总体积小于 .app 实际体积）")
        for (path, size) in sorted.prefix(30) {
            print("   - \(size / 1024) KB  \(path)")
        }
        if sorted.count > 30 {
            let remaining = sorted.dropFirst(30).reduce(0) { $0 + $1.size }
            print("   ... 另有 \(sorted.count - 30) 个条目，合计 \(remaining / 1024) KB")
        }
    }

    /// 对比「linkmap 中 path 包含某子串」的原始总大小 与 「匹配到项目路径后」该路径的总大小，用于判断是否因匹配错误导致体积偏小。
    private static func logLinkmapPathVsResolvedSize(parseResult: LinkmapParseResult, codeSizeInfos: [CodeSizeInfo], linkmapPathSubstrings: [String]) {
        let byResolvedPath = Dictionary(grouping: codeSizeInfos) { $0.relativePath }.mapValues { $0.reduce(0) { $0 + $1.totalSize } }
        for sub in linkmapPathSubstrings {
            let rawTotal = parseResult.objectFileInfos
                .filter { Self.normalizeLinkmapPathForMatching($0.filePath).contains(sub) }
                .reduce(0) { $0 + $1.totalSize }
            let resolvedTotal = byResolvedPath.filter { $0.key.contains(sub) }.values.reduce(0, +)
            let diff = rawTotal - resolvedTotal
            let status = diff == 0 ? "一致" : (diff > 0 ? "匹配后少 \(diff/1024) KB" : "匹配后多 \(-diff/1024) KB")
            print("🔗 [LinkmapAnalyzer] path 含 \"\(sub)\": linkmap 原始=\(rawTotal/1024) KB, 匹配后=\(resolvedTotal/1024) KB → \(status)")
        }
    }

    /// 汇总 codeSize 映射结果，便于排查静态库/三方库是否落入预期项目路径。
    /// 说明：静态库/静态 framework 的 Treemap 体积来自 linkmap 的「链接后」codeSize（.o 符号之和），可能小于 .a/.framework 文件体积（未链接部分不计入）。
    private static func logCodeSizeMappingSummary(codeSizeInfos: [CodeSizeInfo]) {
        let byPath = Dictionary(grouping: codeSizeInfos) { $0.relativePath }.mapValues { $0.reduce(0) { $0 + $1.totalSize } }
        let totalPaths = byPath.count
        print("🔗 [LinkmapAnalyzer] CodeSize mapping: \(codeSizeInfos.count) objects → \(totalPaths) unique paths (静态库/静态 framework 为 linkmap 链接体积，可能小于文件体积)")
        let keywords = ["ThumbPlayer", "DownloadProxy", "TMEThumb", ".a", "Light", "light"]
        for kw in keywords {
            let matches = byPath.filter { $0.key.contains(kw) }.sorted { $0.value > $1.value }
            if matches.isEmpty { continue }
            let total = matches.reduce(0) { $0 + $1.value }
            print("   - paths containing \"\(kw)\": \(matches.count), total codeSize: \(total) (\(total / 1024) KB)")
            for (path, size) in matches.prefix(5) {
                print("      \(size) → \(path)")
            }
        }
        let topBySize = byPath.sorted { $0.value > $1.value }.prefix(8)
        print("   - top paths by codeSize: \(topBySize.map { "\($0.value/1024)KB \($0.key)" }.joined(separator: " | "))")
    }

    /// 使用 Release-iphoneos 分割取后半段，再移除 XCFrameworkIntermediates/ 前缀，便于与项目目录路径匹配。
    /// 例：.../Release-iphoneos/AFNetworking/libAFNetworking.a(AF.o) → AFNetworking/libAFNetworking.a(AF.o)
    /// 例：.../Release-iphoneos/XCFrameworkIntermediates/Ads-Global/PangleSDK/PAGAdSDK.framework/PAGAdSDK(PAGDevice.o) → Ads-Global/PangleSDK/PAGAdSDK.framework/PAGAdSDK(PAGDevice.o)
    private static func normalizeLinkmapPathForMatching(_ path: String) -> String {
        var s = path
        if let range = s.range(of: "Release-iphoneos") {
            s = String(s[range.upperBound...])
            if s.hasPrefix("/") { s = String(s.dropFirst()) }
            if s.hasPrefix("XCFrameworkIntermediates/") { s = String(s.dropFirst("XCFrameworkIntermediates/".count)) }
        }
        return s
    }

    /// 从已扫描的 projectFileEntries 构建「文件名/基名 -> 相对路径列表」索引，避免重复扫描项目目录。
    static func makeProjectFileIndex(from projectFileEntries: [ProjectFileEntry]) -> [String: [String]] {
        var index: [String: [String]] = [:]
        for entry in projectFileEntries {
            let last = entry.fileName.lowercased()
            let base = URL(fileURLWithPath: entry.fileName).deletingPathExtension().lastPathComponent.lowercased()
            index[last, default: []].append(entry.relativePath)
            if base != last {
                index[base, default: []].append(entry.relativePath)
            }
        }
        return index
    }
    
    // MARK: - Private Methods
    
    private func detectSection(from line: String) -> LinkmapSection? {
        if line.contains("# Object files:") {
            return .objectFiles
        } else if line.contains("# Sections:") {
            return .sections
        } else if line.contains("# Symbols:") {
            return .symbols
        } else if line.contains("# Dead Stripped Symbols:") {
            return .deadStripped
        }
        return nil
    }
    
    /// 仅当 Object files 中无对应编号时，从符号名推断文件名（兜底）
    fileprivate func extractFileName(from symbolName: String) -> String {
        if symbolName.hasPrefix("-[") || symbolName.hasPrefix("+[") {
            let pattern = #"^[+-]\[(\w+)\s"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: symbolName, range: NSRange(symbolName.startIndex..., in: symbolName)),
               let range = Range(match.range(at: 1), in: symbolName) {
                return "\(String(symbolName[range])).m"
            }
        }
        if symbolName.contains("::") {
            if let first = symbolName.components(separatedBy: "::").first, let last = first.components(separatedBy: " ").last {
                return "\(last).cpp"
            }
        }
        if symbolName.hasPrefix("_T") || symbolName.hasPrefix("$s") { return "Swift.swift" }
        if symbolName.hasPrefix("_") { return "\(String(symbolName.dropFirst())).c" }
        return "Unknown.o"
    }
}

// MARK: - Supporting Types

private enum LinkmapSection {
    case none
    case objectFiles
    case sections
    case symbols
    case deadStripped
}

// MARK: - Enhanced LinkmapAnalyzer with Object File Mapping

extension LinkmapAnalyzer {
    
    func parseLinkmapWithObjectFiles(at path: String) async throws -> LinkmapParseResult {
        let content = try LinkmapAnalyzer.readLinkmapContent(at: path)
        return try await parseLinkmapContentWithObjectFiles(content, projectPath: nil)
    }
    
    /// 一次逐行解析：Object files 段在前、Symbols 段在后。传 projectPath 时边解析边解析路径并写入缓存，避免后续单独映射步骤。
    private func parseLinkmapContentWithObjectFiles(_ content: String, projectPath: String? = nil) async throws -> LinkmapParseResult {
        let lines = content.components(separatedBy: .newlines)
        var objectFileDict: [Int: ObjectFileInfo] = [:]
        var currentSection: LinkmapSection = .none
        var pathResolutionCache: [String: String] = [:]
        let fallbackResolver = projectPath.flatMap { LinkmapPathFallbackResolver(projectPath: $0) }
        
        // 第一阶段：顺序解析 Object Files 段，可选边解析边解析路径（带缓存）
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.isEmpty else { continue }
            
            if let section = detectSection(from: trimmedLine) {
                if currentSection == .symbols {
                    break
                }
                currentSection = section
                continue
            }
            
            if currentSection == .objectFiles {
                guard let obj = parseObjectFileLine(trimmedLine) else { continue }
                if let projectPath = projectPath {
                    let resolved: String
                    if let cached = pathResolutionCache[obj.filePath] {
                        resolved = cached
                    } else {
                        if let direct = LinkmapPathAdapter.directRelativePathFromLinkmap(linkmapPath: obj.filePath) {
                            resolved = direct
                        } else {
                            let normalized = Self.normalizeLinkmapPathForMatching(obj.filePath)
                            if let fb = fallbackResolver?.resolve(linkmapObjectPath: normalized, fileName: obj.fileName) {
                                resolved = fb
                            } else {
                                resolved = LinkmapPathAdapter.simpleStrippedPath(normalized)
                            }
                        }
                        pathResolutionCache[obj.filePath] = resolved
                    }
                    let withResolved = ObjectFileInfo(index: obj.index, filePath: obj.filePath, fileName: obj.fileName, totalSize: 0, resolvedRelativePath: resolved)
                    objectFileDict[withResolved.index] = withResolved
                } else {
                    objectFileDict[obj.index] = obj
                }
            } else if currentSection == .symbols {
                return await parseSymbolsInParallel(lines: lines, startingFrom: lines.firstIndex(of: line) ?? 0, objectFileDict: objectFileDict)
            }
        }
        
        let objectFileInfos = objectFileDict.values.sorted(by: { $0.index < $1.index })
        if projectPath != nil, !pathResolutionCache.isEmpty {
            print("🔗 [LinkmapAnalyzer] 解析阶段路径缓存命中: \(pathResolutionCache.count) 种路径（已写入 resolvedRelativePath，跳过单独映射步骤）")
        }
        return LinkmapParseResult(objectFileInfos: objectFileInfos, symbols: [])
    }
    
    /// 并行解析符号段，大幅提升大文件处理性能
    private func parseSymbolsInParallel(lines: [String], startingFrom startIndex: Int, objectFileDict: [Int: ObjectFileInfo]) async -> LinkmapParseResult {
        return await withTaskGroup(of: [SymbolInfo].self) { group in
            var allSymbols: [SymbolInfo] = []
            var objectFileSizeUpdates: [Int: Int64] = [:]
            
            // 分批处理符号行，避免内存峰值
            let batchSize = 5000
            var currentBatch: [String] = []
            
            for i in startIndex..<lines.count {
                let line = lines[i]
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                guard !trimmedLine.isEmpty else { continue }
                
                // 检查是否进入新段
                if detectSection(from: trimmedLine) != nil {
                    break
                }
                
                currentBatch.append(line)
                
                if currentBatch.count >= batchSize {
                    let batch = currentBatch
                    currentBatch = []
                    
                    group.addTask {
                        return await self.processSymbolBatch(batch, objectFileDict: objectFileDict)
                    }
                }
            }
            
            // 处理最后一批
            if !currentBatch.isEmpty {
                group.addTask {
                    return await self.processSymbolBatch(currentBatch, objectFileDict: objectFileDict)
                }
            }
            
            // 收集所有结果并更新object file sizes
            for await batchResult in group {
                allSymbols.append(contentsOf: batchResult)
                
                // 批量更新object file sizes
                for symbol in batchResult {
                    objectFileSizeUpdates[symbol.objectFileIndex, default: 0] += symbol.size
                }
            }
            
            // 应用size更新到object file dict
            var updatedObjectFileDict = objectFileDict
            for (index, size) in objectFileSizeUpdates {
                if var obj = updatedObjectFileDict[index] {
                    obj.totalSize += size
                    updatedObjectFileDict[index] = obj
                }
            }
            
            let objectFileInfos = updatedObjectFileDict.values.sorted(by: { $0.index < $1.index })
            return LinkmapParseResult(objectFileInfos: objectFileInfos, symbols: allSymbols)
        }
    }
    
    /// 顺序解析符号批次（避免为每行创建 Task 带来的过度调度开销）
    private func processSymbolBatch(_ lines: [String], objectFileDict: [Int: ObjectFileInfo]) async -> [SymbolInfo] {
        var symbols: [SymbolInfo] = []
        symbols.reserveCapacity(lines.count)
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.isEmpty else { continue }
            if detectSection(from: trimmedLine) != nil { continue }
            if let symbol = parseSymbolLineWithObjectFile(trimmedLine, objectFileDict: objectFileDict) {
                symbols.append(symbol)
            }
        }
        return symbols
    }
    
    /// 缓存的 Object file 行正则：格式为 `[  N] /path/to/file.o`
    private static let objectFileLineRegex: NSRegularExpression? = try? NSRegularExpression(pattern: #"^\[\s*(\d+)\]\s+(.+)$"#)

    /// 解析一行 Object file，直接返回 ObjectFileInfo（totalSize 初值为 0，在 Symbol 段逐行累加）。
    private func parseObjectFileLine(_ line: String) -> ObjectFileInfo? {
        guard let regex = Self.objectFileLineRegex,
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let indexRange = Range(match.range(at: 1), in: line),
              let pathRange = Range(match.range(at: 2), in: line),
              let index = Int(String(line[indexRange])) else {
            return nil
        }
        let filePath = String(line[pathRange])
        let fileName = URL(fileURLWithPath: filePath).lastPathComponent
        return ObjectFileInfo(index: index, filePath: filePath, fileName: fileName, totalSize: 0, resolvedRelativePath: nil)
    }
    
    private func parseSymbolLineWithObjectFile(
        _ line: String,
        objectFileDict: [Int: ObjectFileInfo]
    ) -> SymbolInfo? {
        let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard components.count >= 4,
              components[0].hasPrefix("0x"),
              components[1].hasPrefix("0x") else { return nil }
        let size = Int64(components[1].dropFirst(2), radix: 16) ?? 0
        let fileRefString = components[2]
        guard fileRefString.hasPrefix("["), fileRefString.hasSuffix("]"),
              let fileIndex = Int(fileRefString.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        let symbolName = components.dropFirst(3).joined(separator: " ")
        let fileName = objectFileDict[fileIndex]?.fileName ?? extractFileName(from: symbolName)
        return SymbolInfo(
            address: components[0],
            size: size,
            fileName: fileName,
            symbolName: symbolName,
            objectFileIndex: fileIndex
        )
    }
}
