import Foundation

#if canImport(MachOKit)
import MachOKit
#endif

/// 基于 Mach-O 符号引用关系的无用符号分析器。
/// 目标：在不依赖「无用类」集合的前提下，直接从 Mach-O 的符号表/引用关系中推导出「定义但未被引用」的符号，
/// 再通过 LinkMap 符号(address/size/objectFileIndex)映射到具体 .o / 工程相对路径。
///
/// 阶段 1：打通 Mach-O 符号表(LC_SYMTAB) → 已定义符号地址 → LinkMap 按地址对齐，输出「能对齐到 LinkMap 的已定义符号」。
/// 阶段 2（后续）：收集「被引用符号」集合，计算 defined − referenced，只输出未引用符号。
/// 阶段 3（后续）：补全 relocation/导出/入口白名单等。
protocol MachOUnusedSymbolAnalyzerProtocol {
    /// - Parameters:
    ///   - binaryPath: 主二进制绝对路径
    ///   - linkmapParseResult: LinkMap 解析结果（含所有 SymbolInfo + ObjectFileInfo）
    /// - Returns: 仅基于符号引用关系得到的无用符号列表；阶段 1 先返回「能对齐到 LinkMap 的已定义符号」用于验证链路
    func findUnusedSymbols(
        binaryPath: String,
        linkmapParseResult: LinkmapParseResult
    ) async -> [UnusedSymbolRecord]
}

final class MachOUnusedSymbolAnalyzer: MachOUnusedSymbolAnalyzerProtocol {

    func findUnusedSymbols(
        binaryPath: String,
        linkmapParseResult: LinkmapParseResult
    ) async -> [UnusedSymbolRecord] {
        guard FileManager.default.fileExists(atPath: binaryPath) else {
            print("⚠️ [MachOUnusedSymbolAnalyzer] binary 不存在: \(binaryPath)")
            return []
        }

        #if canImport(MachOKit)
        do {
            return try await runPhase1Alignment(
                binaryPath: binaryPath,
                linkmapParseResult: linkmapParseResult
            )
        } catch {
            print("⚠️ [MachOUnusedSymbolAnalyzer] 分析失败: \(error.localizedDescription)")
            return []
        }
        #else
        print("⚠️ [MachOUnusedSymbolAnalyzer] 未集成 MachOKit，跳过纯符号无用分析。")
        return []
        #endif
    }

#if canImport(MachOKit)
    /// 阶段 1：从 Mach-O 读「已定义符号 + 地址」，与 LinkMap 按地址对齐，打通整条链路。
    /// 当前不做「被引用」过滤，返回所有能对齐到 LinkMap 的已定义符号（用于验证）；阶段 2 再在此基础上做 defined − referenced。
    private func runPhase1Alignment(
        binaryPath: String,
        linkmapParseResult: LinkmapParseResult
    ) async throws -> [UnusedSymbolRecord] {
        let url = URL(fileURLWithPath: binaryPath)
        let file = try MachOKit.loadFromFile(url: url)

        let machOFiles: [MachOFile]
        switch file {
        case .machO(let m):
            machOFiles = [m]
        case .fat(let fat):
            machOFiles = try fat.machOFiles()
        }

        // LinkMap 地址 → 该地址下的所有 SymbolInfo（同一地址可能有多条，取其一或全部；LinkMap 通常一条地址一条符号）
        let addressToSymbols = buildLinkMapAddressIndex(linkmapParseResult.symbols)
        let objectFileInfos = linkmapParseResult.objectFileInfos
        var definedCount = 0
        var matchedCount = 0
        var results: [UnusedSymbolRecord] = []

        for machO in machOFiles {
            // 遍历 LC_SYMTAB 中的符号，只保留「在 section 内定义」的符号（N_SECT）
            if let symbols64 = machO.symbols64 {
                for symbol in symbols64 {
                    guard symbol.nlist.flags?.type == .sect else { continue }
                    definedCount += 1
                    let addrKey = formatAddressKey(symbol.offset)
                    guard let linkMapSymbols = addressToSymbols[addrKey] else { continue }
                    for linkSym in linkMapSymbols {
                        matchedCount += 1
                        let objInfo = objectFileInfos.first { $0.index == linkSym.objectFileIndex }
                        results.append(UnusedSymbolRecord(
                            symbolName: linkSym.symbolName,
                            size: linkSym.size,
                            objectFileIndex: linkSym.objectFileIndex,
                            objectFilePath: objInfo?.filePath ?? linkSym.fileName,
                            resolvedRelativePath: objInfo?.resolvedRelativePath ?? linkSym.fileName,
                            className: nil
                        ))
                    }
                }
            } else if let symbols32 = machO.symbols32 {
                for symbol in symbols32 {
                    guard symbol.nlist.flags?.type == .sect else { continue }
                    definedCount += 1
                    let addrKey = formatAddressKey(symbol.offset)
                    guard let linkMapSymbols = addressToSymbols[addrKey] else { continue }
                    for linkSym in linkMapSymbols {
                        matchedCount += 1
                        let objInfo = objectFileInfos.first { $0.index == linkSym.objectFileIndex }
                        results.append(UnusedSymbolRecord(
                            symbolName: linkSym.symbolName,
                            size: linkSym.size,
                            objectFileIndex: linkSym.objectFileIndex,
                            objectFilePath: objInfo?.filePath ?? linkSym.fileName,
                            resolvedRelativePath: objInfo?.resolvedRelativePath ?? linkSym.fileName,
                            className: nil
                        ))
                    }
                }
            }
        }

        // 按 (symbolName, objectFileIndex) 去重，同一 LinkMap 符号可能被多个 Mach-O 条目匹配
        var seen: Set<String> = []
        let unique = results.filter { seen.insert($0.id).inserted }

        print("ℹ️ [MachOUnusedSymbolAnalyzer] 阶段1 对齐: Mach-O 已定义符号(N_SECT)=\(definedCount), 与 LinkMap 按地址匹配数=\(matchedCount), 去重后记录数=\(unique.count)")
        return unique
    }

    /// 构建「地址字符串 → [SymbolInfo]」索引，便于按 Mach-O n_value 查找 LinkMap 符号。
    /// LinkMap 地址格式为 "0x..."，统一转为小写以与 String(radix: 16) 一致。
    private func buildLinkMapAddressIndex(_ symbols: [SymbolInfo]) -> [String: [SymbolInfo]] {
        var map: [String: [SymbolInfo]] = [:]
        for sym in symbols {
            let key = sym.address.lowercased()
            map[key, default: []].append(sym)
        }
        return map
    }

    private func formatAddressKey(_ offset: Int) -> String {
        "0x" + String(offset, radix: 16)
    }
#endif
}
