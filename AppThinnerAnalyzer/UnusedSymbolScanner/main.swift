#!/usr/bin/env swift
/**
 无用符号检索与 LinkMap 映射 - 第一步 CLI
 输入：工程路径、LinkMap、IPA 或 .app → 输出无用类 + 无用符号按 Object File 聚合的 JSON。
 设计文档：doc/Technical_Files/无用符号检索与LinkMap映射设计.md
 */

import Foundation

// MARK: - 命令行参数

struct CLIArgs {
    var projectPath: String?
    var linkmapPath: String?
    var ipaPath: String?
    var appPath: String?
    /// 主二进制直接路径（优先于从 --ipa/--app 解析）
    var binaryPath: String?
    var outputPath: String?

    static func parse() -> CLIArgs? {
        var args = CLIArgs()
        var i = 1
        while i < CommandLine.arguments.count {
            let a = CommandLine.arguments[i]
            switch a {
            case "--project", "-p":
                i += 1
                if i < CommandLine.arguments.count { args.projectPath = CommandLine.arguments[i] }
            case "--linkmap", "-l":
                i += 1
                if i < CommandLine.arguments.count { args.linkmapPath = CommandLine.arguments[i] }
            case "--ipa":
                i += 1
                if i < CommandLine.arguments.count { args.ipaPath = CommandLine.arguments[i] }
            case "--app":
                i += 1
                if i < CommandLine.arguments.count { args.appPath = CommandLine.arguments[i] }
            case "--binary", "-b":
                i += 1
                if i < CommandLine.arguments.count { args.binaryPath = CommandLine.arguments[i] }
            case "--output", "-o":
                i += 1
                if i < CommandLine.arguments.count { args.outputPath = CommandLine.arguments[i] }
            case "--help", "-h":
                return nil
            default:
                if a.hasPrefix("-") {
                    fputs("未知参数: \(a)\n", stderr)
                    return nil
                }
                if args.linkmapPath == nil { args.linkmapPath = a }
                else if args.projectPath == nil { args.projectPath = a }
            }
            i += 1
        }
        return args
    }
}

func printUsage() {
    print("""
    UnusedSymbolScanner - 无用符号检索与 LinkMap 映射（第一步 CLI）
    用法: UnusedSymbolScanner --linkmap <path> [--project <path>] [--ipa <path> | --app <path> | --binary <path>] [--output <path>]

    必选:
      --linkmap, -l <path>   LinkMap 文件路径
    可选:
      --project, -p <path> 工程根目录（用于将 LinkMap Object 路径解析为项目相对路径）
      --ipa <path>          IPA 路径（用于解析主二进制做无用类分析）
      --app <path>          .app 路径（同上）
      --binary, -b <path>   主二进制直接路径（优先使用，无需从 .app 解析）
      --output, -o <path>   输出 JSON 文件路径（默认 stdout）
      --help, -h            显示此帮助
    """)
}

// MARK: - JSON 输出结构（Codable）

struct UnusedSymbolRecordOutput: Codable {
    let symbolName: String
    let size: Int64
    let objectFileIndex: Int
    let objectFilePath: String
    let resolvedRelativePath: String
    let className: String?
}

struct ObjectFileGroupOutput: Codable {
    let objectFilePath: String
    let resolvedPath: String
    let symbols: [UnusedSymbolRecordOutput]
    let totalSize: Int64
}

struct UnusedSymbolMappingOutput: Codable {
    let unusedSymbols: [UnusedSymbolRecordOutput]
    let byObjectFile: [ObjectFileGroupOutput]
    let totalUnusedSymbolSize: Int64
}

struct UnusedClassOutput: Codable {
    let className: String
    let filePath: String?
    let estimatedSize: Int64
}

/// 纯基于 Mach-O 符号引用关系得到的无用符号（不依赖无用类集合）。
struct MachOOnlyUnusedSymbolOutput: Codable {
    let symbolName: String
    let size: Int64
    let objectFileIndex: Int
    let objectFilePath: String
    let resolvedRelativePath: String
}

struct CLIResultOutput: Codable {
    let unusedClasses: [UnusedClassOutput]
    let unusedSymbolMapping: UnusedSymbolMappingOutput
    /// 纯基于 Mach-O 符号引用关系得到的无用符号列表（当前为保守/占位实现，后续逐步补全）
    let machOOnlyUnusedSymbols: [MachOOnlyUnusedSymbolOutput]
    let summary: SummaryOutput
}

struct SummaryOutput: Codable {
    let projectPath: String?
    let linkmapPath: String?
    let binaryPath: String?
    let unusedClassCount: Int
    let unusedSymbolCount: Int
    let totalUnusedSymbolSize: Int64
}

// MARK: - Main

func runCLI() async {
    guard let args = CLIArgs.parse() else {
            printUsage()
            exit(1)
        }
        guard let linkmapPath = args.linkmapPath, !linkmapPath.isEmpty else {
            fputs("错误: 必须指定 --linkmap\n", stderr)
            printUsage()
            exit(1)
        }
        let projectPath = args.projectPath
        let ipaPath = args.ipaPath
        let appPath = args.appPath
        let outputPath = args.outputPath

        var appBundlePath: String?
        var packageFiles: [PackageFileInfo] = []
        var tempDirToClean: URL?
        defer { if let d = tempDirToClean { try? FileManager.default.removeItem(at: d) } }

        let packageParser = PackageParser()
        if let path = ipaPath {
            do {
                let result = try await packageParser.parseIPA(at: path)
                appBundlePath = result.appBundlePath?.path
                packageFiles = result.packageFiles
                tempDirToClean = result.tempDirectoryForCleanup
            } catch {
                fputs("警告: 解析 IPA 失败，将跳过无用类分析: \(error.localizedDescription)\n", stderr)
            }
        } else if let path = appPath {
            do {
                let result = try await packageParser.parseApp(at: path)
                appBundlePath = result.appBundlePath?.path
                packageFiles = result.packageFiles
            } catch {
                fputs("警告: 解析 .app 失败，将跳过无用类分析: \(error.localizedDescription)\n", stderr)
            }
        }

        let mainBinaryPath: String? = {
            if let bin = args.binaryPath, !bin.isEmpty, FileManager.default.fileExists(atPath: bin) {
                return bin
            }
            guard let appRoot = appBundlePath, !appRoot.isEmpty,
                  let main = packageFiles.first(where: { $0.isMainExecutable }) else { return nil }
            return (appRoot as NSString).appendingPathComponent(main.fileName)
        }()

        let resourceScanner = ProjectResourceScanner()
        var projectFileEntries: [ProjectFileEntry] = []
        if let path = projectPath {
            do {
                projectFileEntries = try await resourceScanner.scanProjectDirectoryAllFiles(at: path)
            } catch {
                fputs("警告: 工程目录扫描失败: \(error.localizedDescription)\n", stderr)
            }
        }

        let linkmapAnalyzer = LinkmapAnalyzer()
        let parseResult: LinkmapParseResult
        let codeSizeInfo: [CodeSizeInfo]
        do {
            parseResult = try await linkmapAnalyzer.parseLinkmapFile(at: linkmapPath, projectPath: projectPath)
            let index = projectFileEntries.isEmpty ? [:] : LinkmapAnalyzer.makeProjectFileIndex(from: projectFileEntries)
            codeSizeInfo = try await linkmapAnalyzer.mapObjectFilesToProjectStructure(
                parseResult: parseResult,
                projectFileIndex: index,
                projectFileEntries: projectFileEntries.isEmpty ? nil : projectFileEntries,
                linkmapPathPrefixesToStrip: LinkmapPathAdapter.defaultPrefixesToStrip,
                projectPath: projectPath
            )
        } catch {
            fputs("错误: LinkMap 解析失败: \(error.localizedDescription)\n", stderr)
            exit(1)
        }

        var unusedClasses: [UnusedCode] = []
        if let binaryPath = mainBinaryPath {
            let analyzer = BinaryUnusedCodeAnalyzer()
            unusedClasses = await analyzer.analyzeUnusedClasses(binaryPath: binaryPath, codeSizeInfo: codeSizeInfo)
        }

        let unusedClassNames = Set(unusedClasses.map { $0.className })
        let mappingService = UnusedSymbolMappingService()
        let mappingResult = mappingService.buildUnusedSymbolMapping(
            parseResult: parseResult,
            codeSizeInfo: codeSizeInfo,
            unusedClassNames: unusedClassNames
        )

        let byObjectFileOutput: [ObjectFileGroupOutput] = mappingResult.byObjectFile.map { _, value in
            ObjectFileGroupOutput(
                objectFilePath: value.objectFilePath,
                resolvedPath: value.resolvedPath,
                symbols: value.symbols.map { r in
                    UnusedSymbolRecordOutput(
                        symbolName: r.symbolName,
                        size: r.size,
                        objectFileIndex: r.objectFileIndex,
                        objectFilePath: r.objectFilePath,
                        resolvedRelativePath: r.resolvedRelativePath,
                        className: r.className
                    )
                },
                totalSize: value.symbols.reduce(0) { $0 + $1.size }
            )
        }

        let unusedSymbolOutput = UnusedSymbolMappingOutput(
            unusedSymbols: mappingResult.unusedSymbols.map { r in
                UnusedSymbolRecordOutput(
                    symbolName: r.symbolName,
                    size: r.size,
                    objectFileIndex: r.objectFileIndex,
                    objectFilePath: r.objectFilePath,
                    resolvedRelativePath: r.resolvedRelativePath,
                    className: r.className
                )
            },
            byObjectFile: byObjectFileOutput,
            totalUnusedSymbolSize: mappingResult.totalUnusedSymbolSize
        )

        let unusedClassesOutput = unusedClasses.map { u in
            UnusedClassOutput(className: u.className, filePath: u.filePath, estimatedSize: u.estimatedSize)
        }

        // 纯符号引用关系的无用符号（目前为占位实现，后续在 MachOUnusedSymbolAnalyzer 内补充真实逻辑）
        var machOOnlyUnusedSymbolsOutput: [MachOOnlyUnusedSymbolOutput] = []
        if let binaryPath = mainBinaryPath {
            let machOAnalyzer = MachOUnusedSymbolAnalyzer()
            let machOUnused = await machOAnalyzer.findUnusedSymbols(
                binaryPath: binaryPath,
                linkmapParseResult: parseResult
            )
            machOOnlyUnusedSymbolsOutput = machOUnused.map { r in
                MachOOnlyUnusedSymbolOutput(
                    symbolName: r.symbolName,
                    size: r.size,
                    objectFileIndex: r.objectFileIndex,
                    objectFilePath: r.objectFilePath,
                    resolvedRelativePath: r.resolvedRelativePath
                )
            }
        }

        let summary = SummaryOutput(
            projectPath: projectPath,
            linkmapPath: linkmapPath,
            binaryPath: mainBinaryPath,
            unusedClassCount: unusedClasses.count,
            unusedSymbolCount: mappingResult.unusedSymbols.count,
            totalUnusedSymbolSize: mappingResult.totalUnusedSymbolSize
        )

        let result = CLIResultOutput(
            unusedClasses: unusedClassesOutput,
            unusedSymbolMapping: unusedSymbolOutput,
            machOOnlyUnusedSymbols: machOOnlyUnusedSymbolsOutput,
            summary: summary
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if #available(macOS 10.15, *) {
            encoder.dateEncodingStrategy = .iso8601
        }
        do {
            let data = try encoder.encode(result)
            let json = String(data: data, encoding: .utf8) ?? ""
            if let outPath = outputPath {
                try json.write(toFile: outPath, atomically: true, encoding: .utf8)
            } else {
                print(json)
            }
        } catch {
            fputs("错误: 输出 JSON 失败: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
}

// 无 @main 时由顶层代码启动，避免与同模块其他文件冲突
Task {
    await runCLI()
    exit(0)
}
RunLoop.main.run()
