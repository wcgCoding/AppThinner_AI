import Foundation

#if canImport(MachOKit)
import MachOKit
#endif
#if canImport(MachOObjCSection)
import MachOObjCSection
#endif

// MARK: - BinaryUnusedCodeAnalyzer Protocol

protocol BinaryUnusedCodeAnalyzerProtocol {
    /// 基于 .app 主二进制与 linkmap 符号，分析候选无用 ObjC 类。
    /// - Parameters:
    ///   - binaryPath: .app 内主二进制的绝对路径
    ///   - codeSizeInfo: linkmap 映射到工程路径后的符号信息
    /// - Returns: UnusedCode 列表（className + filePath + estimatedSize）
    func analyzeUnusedClasses(
        binaryPath: String,
        codeSizeInfo: [CodeSizeInfo]
    ) async -> [UnusedCode]
}

// MARK: - BinaryUnusedCodeAnalyzer Implementation

final class BinaryUnusedCodeAnalyzer: BinaryUnusedCodeAnalyzerProtocol {
    
    func analyzeUnusedClasses(
        binaryPath: String,
        codeSizeInfo: [CodeSizeInfo]
    ) async -> [UnusedCode] {
        guard FileManager.default.fileExists(atPath: binaryPath) else {
            print("⚠️ [BinaryUnusedCodeAnalyzer] binary 不存在: \(binaryPath)")
            return []
        }
        
        #if canImport(MachOKit)
        do {
            return try analyzeWithMachOKit(binaryPath: binaryPath, codeSizeInfo: codeSizeInfo)
        } catch {
            print("⚠️ [BinaryUnusedCodeAnalyzer] 基于 MachOKit 的无用类分析失败: \(error.localizedDescription)")
            return []
        }
        #else
        print("⚠️ [BinaryUnusedCodeAnalyzer] 未集成 MachOKit，已跳过基于 Mach-O 的无用类分析。")
        return []
        #endif
    }
    
#if canImport(MachOKit)
    // MARK: - Private Helpers
    
    /// 使用 MachOKit（及可选 MachOObjCSection）从 Mach-O 里提取 ObjC 类定义/引用并计算差集，
    /// 再结合 LinkMap 统计 estimatedSize 与工程路径。
    private func analyzeWithMachOKit(
        binaryPath: String,
        codeSizeInfo: [CodeSizeInfo]
    ) throws -> [UnusedCode] {
        let url = URL(fileURLWithPath: binaryPath)
        let file = try MachOKit.loadFromFile(url: url)

        let machOFiles: [MachOFile]
        switch file {
        case .machO(let m):
            machOFiles = [m]
        case .fat(let fat):
            machOFiles = try fat.machOFiles()
        }

        var definedClasses = Set<String>()
        var referencedClasses = Set<String>()

        #if canImport(MachOObjCSection)
        for machO in machOFiles {
            let objc = machO.objc

            // ① 定义类：classlist
            for c in objc.classes64 ?? [] {
                guard let ro = c.classROData(in: machO), let n = ro.name(in: machO) else { continue }
                definedClasses.insert(n)

                // ② 父类名（superrefs 替代方案）：父类被使用，不能算无用
                if let superName = c.superClassName(in: machO) {
                    referencedClasses.insert(superName)
                }
            }
            for c in objc.classes32 ?? [] {
                guard let ro = c.classROData(in: machO), let n = ro.name(in: machO) else { continue }
                definedClasses.insert(n)
                if let superName = c.superClassName(in: machO) {
                    referencedClasses.insert(superName)
                }
            }

            // ③ 直接引用类：classrefs
            for c in objc.classrefs64 ?? [] {
                if let ro = c.classROData(in: machO), let n = ro.name(in: machO) { referencedClasses.insert(n) }
            }
            for c in objc.classrefs32 ?? [] {
                if let ro = c.classROData(in: machO), let n = ro.name(in: machO) { referencedClasses.insert(n) }
            }

            // ④ Category 宿主类：有 category 附着说明类在被扩展/使用，不能算无用
            for cat in (objc.categories64 ?? []) + (objc.categories2_64 ?? []) {
                if let hostName = cat.className(in: machO) { referencedClasses.insert(hostName) }
            }
            for cat in (objc.categories32 ?? []) + (objc.categories2_32 ?? []) {
                if let hostName = cat.className(in: machO) { referencedClasses.insert(hostName) }
            }
        }
        #else
        for machO in machOFiles {
            if let symbols = machO.symbols64 {
                for sym in symbols {
                    let name = sym.name
                    if name.hasPrefix("_OBJC_CLASS_$_") {
                        let cls = String(name.dropFirst("_OBJC_CLASS_$_".count))
                        if !cls.isEmpty { definedClasses.insert(cls) }
                    }
                }
            }
        }
        if referencedClasses.isEmpty && !definedClasses.isEmpty {
            print("⚠️ [BinaryUnusedCodeAnalyzer] 已用 MachOKit 符号表解析到 \(definedClasses.count) 个定义类，但未集成 MachOObjCSection 无法解析引用类，已跳过无用类差集分析。请添加 MachOObjCSection 包以启用：https://github.com/p-x9/MachOObjCSection")
            return []
        }
        #endif

        if definedClasses.isEmpty {
            print("⚠️ [BinaryUnusedCodeAnalyzer] MachOKit 未能从主二进制解析到 ObjC 类定义（classes 为空）")
            return []
        }

        // 初步差集：defined − referenced
        var candidates = definedClasses.subtracting(referencedClasses)

        // ⑤ 白名单过滤：以下后缀/前缀的类高度依赖运行时动态初始化，静态差集无法准确判定
        let whitelistSuffixes = [
            "ViewController", "Controller",
            "Cell", "View", "Button",
            "Delegate", "DataSource",
            "AppDelegate", "SceneDelegate",
            "Module", "Router", "Coordinator",
        ]
        candidates = candidates.filter { name in
            !whitelistSuffixes.contains(where: { name.hasSuffix($0) || name == $0 })
        }

        if candidates.isEmpty {
            print("📊 [BinaryUnusedCodeAnalyzer] 差集 + 白名单过滤后无候选无用类")
            return []
        }

        print("📊 [BinaryUnusedCodeAnalyzer] 定义类=\(definedClasses.count) 被引用(classrefs+superrefs+catHost)=\(referencedClasses.count) 差集=\(definedClasses.subtracting(referencedClasses).count) 白名单过滤后=\(candidates.count)")

        // 路径查找：用候选类名在 LinkMap 符号表里检索含该类的编译单元，取其已映射好的项目路径。
        // 方向：className → 在 codeSizeInfo 中找含该类 ObjC 符号（_OBJC_CLASS_$_Foo / _-[Foo bar]）
        //        的 CodeSizeInfo → relativePath（已在 mapObjectFilesToProjectStructure 映射为项目路径或 .framework 目录路径）。
        // 注意：不使用 contains 回退，只用严格 ObjC 符号匹配，避免误命中同名方法或子字符串。
        var pathByClass: [String: String] = [:]
        for info in codeSizeInfo {
            for symbol in info.symbols {
                guard let cls = extractClassName(from: symbol.symbolName),
                      candidates.contains(cls),
                      pathByClass[cls] == nil else { continue }
                pathByClass[cls] = info.relativePath
            }
        }

        let allSymbols = codeSizeInfo.flatMap { $0.symbols }
        let sizeByClass: [String: Int64]
        #if UNUSED_SYMBOL_SCANNER_CLI
        sizeByClass = Self.buildCodeSizeByClassFromSymbols(allSymbols, classNames: candidates)
        #else
        sizeByClass = AnalysisService.buildCodeSizeByClassFromSymbols(allSymbols, classNames: candidates)
        #endif

        // 对路径仍为空的候选类，尝试按类名前缀在 codeSizeInfo.relativePath 里做目录级模糊匹配兜底
        // （针对 Swift 类：LinkMap 中没有 _OBJC_CLASS_$_ 符号，但 relativePath 往往含类名或模块名）
        let unmappedCandidates = candidates.filter { pathByClass[$0] == nil }
        if !unmappedCandidates.isEmpty {
            // 为每条 CodeSizeInfo 建「relativePath 小写 → relativePath」索引，O(1) 查找
            for info in codeSizeInfo where !info.relativePath.isEmpty {
                let pathLower = info.relativePath.lowercased()
                for cls in unmappedCandidates where pathByClass[cls] == nil {
                    if pathLower.contains(cls.lowercased()) {
                        pathByClass[cls] = info.relativePath
                    }
                }
            }
        }

        var results: [UnusedCode] = []
        for className in candidates.sorted() {
            let estimatedSize = sizeByClass[className] ?? 0
            let path = pathByClass[className] ?? ""
            results.append(
                UnusedCode(
                    className: className,
                    filePath: path,
                    estimatedSize: estimatedSize,
                    detectionMethod: .staticAnalysis,
                    dependencies: [],
                    riskLevel: .medium
                )
            )
        }

        let mappedCount = results.filter { !$0.filePath.isEmpty }.count
        print("📊 [BinaryUnusedCodeAnalyzer] 路径映射: \(mappedCount)/\(results.count) 个候选类找到项目路径")
        return results
    }
#endif
    
    #if UNUSED_SYMBOL_SCANNER_CLI
    private static let symbolCountLimitForContainsFallback = 80_000
    private static func buildCodeSizeByClassFromSymbols(_ symbols: [SymbolInfo], classNames: Set<String>) -> [String: Int64] {
        var sizeByClass: [String: Int64] = [:]
        guard !symbols.isEmpty, !classNames.isEmpty else { return sizeByClass }
        let skipContainsFallback = symbols.count > symbolCountLimitForContainsFallback
        let objcClassPattern = try? NSRegularExpression(pattern: "_OBJC_(?:CLASS|METACLASS)_\\$_(\\w+)")
        let objcMethodPattern = try? NSRegularExpression(pattern: "_[-+]\\[(\\w+)\\s")
        for symbol in symbols {
            let name = symbol.symbolName
            var added: Set<String> = []
            if let p = objcClassPattern {
                let range = NSRange(name.startIndex..., in: name)
                p.enumerateMatches(in: name, range: range) { match, _, _ in
                    guard let m = match, m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: name) else { return }
                    let cls = String(name[r])
                    if classNames.contains(cls), !added.contains(cls) {
                        sizeByClass[cls, default: 0] += symbol.size
                        added.insert(cls)
                    }
                }
            }
            if let p = objcMethodPattern {
                let range = NSRange(name.startIndex..., in: name)
                p.enumerateMatches(in: name, range: range) { match, _, _ in
                    guard let m = match, m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: name) else { return }
                    let cls = String(name[r])
                    if classNames.contains(cls), !added.contains(cls) {
                        sizeByClass[cls, default: 0] += symbol.size
                        added.insert(cls)
                    }
                }
            }
            if added.isEmpty, !skipContainsFallback {
                for className in classNames {
                    if symbol.symbolName.contains(className) || symbol.fileName.contains(className) {
                        sizeByClass[className, default: 0] += symbol.size
                        break
                    }
                }
            }
        }
        return sizeByClass
    }
    #endif

    /// 从符号名中提取 ObjC 类名。
    /// 支持：`_OBJC_CLASS_$_Foo`、`_OBJC_METACLASS_$_Foo`、`_-[Foo bar]`、`_+[Foo bar]`
    /// 以 `static` 暴露，供 AnalysisService 在 filePath 补全阶段复用。
    static func extractObjCClassName(from symbolName: String) -> String? {
        if symbolName.hasPrefix("_OBJC_CLASS_$_") || symbolName.hasPrefix("_OBJC_METACLASS_$_") {
            if let range = symbolName.range(of: "_$_") {
                return String(symbolName[range.upperBound...])
            }
        }
        if symbolName.hasPrefix("_-[") || symbolName.hasPrefix("_- [") || symbolName.hasPrefix("_+[") {
            if let open = symbolName.firstIndex(of: "["),
               let space = symbolName[symbolName.index(after: open)...].firstIndex(of: " ") {
                return String(symbolName[symbolName.index(after: open)..<space])
            }
        }
        return nil
    }

    private func extractClassName(from symbolName: String) -> String? {
        Self.extractObjCClassName(from: symbolName)
    }
}

