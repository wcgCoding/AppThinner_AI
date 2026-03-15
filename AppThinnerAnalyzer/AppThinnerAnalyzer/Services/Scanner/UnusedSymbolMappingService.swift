import Foundation

// MARK: - UnusedSymbolMappingService Protocol

/// 无用符号检索 + 映射到 LinkMap Object Files：根据无用类名从 LinkMap 符号中筛出无用符号，并映射到具体 .o / Object 文件，作为无用体积的一部分。
protocol UnusedSymbolMappingServiceProtocol {
    /// 从 LinkMap 解析结果与无用类集合中，检索无用符号（名称+大小）并映射到 Object File。
    /// - Parameters:
    ///   - parseResult: LinkMap 解析结果（含 objectFileInfos + symbols），为 nil 时仅用 codeSizeInfo 做路径解析
    ///   - codeSizeInfo: 已按工程路径聚合的代码信息（含 symbols），用于 objectFileIndex → resolvedRelativePath
    ///   - unusedClassNames: 无用类名集合（与 UnusedCode 一致）
    /// - Returns: 无用符号明细及按 Object File 聚合结果；无无用类或无符号时返回空结果
    func buildUnusedSymbolMapping(
        parseResult: LinkmapParseResult?,
        codeSizeInfo: [CodeSizeInfo],
        unusedClassNames: Set<String>
    ) -> UnusedSymbolMappingResult
}

// MARK: - 无用符号映射服务实现

final class UnusedSymbolMappingService: UnusedSymbolMappingServiceProtocol {

    private static let symbolCountLimitForContainsFallback = 80_000

    func buildUnusedSymbolMapping(
        parseResult: LinkmapParseResult?,
        codeSizeInfo: [CodeSizeInfo],
        unusedClassNames: Set<String>
    ) -> UnusedSymbolMappingResult {
        guard !unusedClassNames.isEmpty else {
            return UnusedSymbolMappingResult(unusedSymbols: [], byObjectFile: [:])
        }
        let allSymbols = codeSizeInfo.flatMap { $0.symbols }
        guard !allSymbols.isEmpty else {
            return UnusedSymbolMappingResult(unusedSymbols: [], byObjectFile: [:])
        }

        let objectFileInfos = parseResult?.objectFileInfos ?? []
        let indexToObjectFile: [Int: ObjectFileInfo] = Dictionary(uniqueKeysWithValues: objectFileInfos.map { ($0.index, $0) })
        var objectFileIndexToResolvedPath: [Int: String] = [:]
        for info in codeSizeInfo {
            for symbol in info.symbols {
                objectFileIndexToResolvedPath[symbol.objectFileIndex] = info.relativePath
            }
        }

        let skipContainsFallback = allSymbols.count > Self.symbolCountLimitForContainsFallback
        let objcClassPattern = try? NSRegularExpression(pattern: "_OBJC_(?:CLASS|METACLASS)_\\$_(\\w+)")
        let objcMethodPattern = try? NSRegularExpression(pattern: "_[-+]\\[(\\w+)\\s")

        var unusedSymbols: [UnusedSymbolRecord] = []
        for symbol in allSymbols {
            guard let className = symbolBelongsToUnusedClass(
                symbol.symbolName,
                fileName: symbol.fileName,
                unusedClassNames: unusedClassNames,
                skipContainsFallback: skipContainsFallback,
                objcClassPattern: objcClassPattern,
                objcMethodPattern: objcMethodPattern
            ) else { continue }

            let objectFilePath = indexToObjectFile[symbol.objectFileIndex]?.filePath ?? ""
            let resolvedPath = objectFileIndexToResolvedPath[symbol.objectFileIndex] ?? ""

            unusedSymbols.append(UnusedSymbolRecord(
                symbolName: symbol.symbolName,
                size: symbol.size,
                objectFileIndex: symbol.objectFileIndex,
                objectFilePath: objectFilePath,
                resolvedRelativePath: resolvedPath,
                className: className
            ))
        }

        var byObjectFile: [Int: (objectFilePath: String, resolvedPath: String, symbols: [UnusedSymbolRecord])] = [:]
        for record in unusedSymbols {
            let idx = record.objectFileIndex
            let path = record.objectFilePath
            let resolved = record.resolvedRelativePath
            var existing = byObjectFile[idx] ?? (path, resolved, [])
            existing.symbols.append(record)
            byObjectFile[idx] = existing
        }

        return UnusedSymbolMappingResult(unusedSymbols: unusedSymbols, byObjectFile: byObjectFile)
    }

    /// 判断符号是否属于某无用类；若属于则返回该类名，否则返回 nil。
    private func symbolBelongsToUnusedClass(
        _ symbolName: String,
        fileName: String,
        unusedClassNames: Set<String>,
        skipContainsFallback: Bool,
        objcClassPattern: NSRegularExpression?,
        objcMethodPattern: NSRegularExpression?
    ) -> String? {
        if let p = objcClassPattern {
            let range = NSRange(symbolName.startIndex..., in: symbolName)
            var matchClass: String?
            p.enumerateMatches(in: symbolName, range: range) { match, _, _ in
                guard let m = match, m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: symbolName) else { return }
                let cls = String(symbolName[r])
                if unusedClassNames.contains(cls) { matchClass = cls }
            }
            if let c = matchClass { return c }
        }
        if let p = objcMethodPattern {
            let range = NSRange(symbolName.startIndex..., in: symbolName)
            var matchClass: String?
            p.enumerateMatches(in: symbolName, range: range) { match, _, _ in
                guard let m = match, m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: symbolName) else { return }
                let cls = String(symbolName[r])
                if unusedClassNames.contains(cls) { matchClass = cls }
            }
            if let c = matchClass { return c }
        }
        if !skipContainsFallback {
            for cls in unusedClassNames {
                if symbolName.contains(cls) || fileName.contains(cls) { return cls }
            }
        }
        return nil
    }
}
