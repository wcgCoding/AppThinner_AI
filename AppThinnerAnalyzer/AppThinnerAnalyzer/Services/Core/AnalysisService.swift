import Foundation
import CoreData

// MARK: - AnalysisService 协议

protocol AnalysisServiceProtocol {
    func analyzeProject(
        projectPath: String?,
        ipaPath: String?,
        linkmapPath: String?,
        externalUnusedResources: [String]?,
        externalUnusedClasses: [String]?,
        analysisOptions: AnalysisOptions,
        progressUpdates: (@Sendable (Double, String) -> Void)?,
        progressStageCompleted: (@Sendable (String) -> Void)?
    ) async throws -> AnalysisProject
    
    func getAnalysisHistory() async throws -> [AnalysisProject]
    func deleteAnalysis(_ project: AnalysisProject) async throws
    func exportAnalysisData(_ project: AnalysisProject) async throws -> Data
    func importAnalysisData(_ data: Data) async throws -> AnalysisProject
}

// MARK: - AnalysisService 实现（纯调度层）
// 负责协调各子服务完成三阶段分析流程：
//   Phase 1：并发解析数据源（IPA/App + 工程目录 + LinkMap）
//   Phase 2：并发执行数据整合、无用内容扫描、重复扫描、Pods 依赖扫描
//   Phase 3：写入 CoreData 并返回 AnalysisProject

class AnalysisService: AnalysisServiceProtocol {
    
    // MARK: - 依赖

    private let packageParser: PackageParserProtocol
    private let linkmapAnalyzer: LinkmapAnalyzerProtocol
    private let resourceScanner: ProjectResourceScannerProtocol
    private let pathMappingResolver: PathMappingResolverProtocol
    private let coreDataManager: CoreDataManagerProtocol
    private let filePermissionService: FilePermissionService
    private let unusedScanService: UnusedScanServiceProtocol
    private let codeAnalyzer: CodeAnalyzerProtocol
    private let codeDuplicateScanService: CodeDuplicateScanServiceProtocol
    private let resourceDuplicateScanService: ResourceDuplicateScanServiceProtocol
    private let podsDependencyScanService: PodsDependencyScanServiceProtocol
    private let externalDataImporter: ExternalDataImporterProtocol
    private let dataIntegrationService: DataIntegrationService
    
    // MARK: - 初始化

    init(
        packageParser: PackageParserProtocol = PackageParser(),
        linkmapAnalyzer: LinkmapAnalyzerProtocol = LinkmapAnalyzer(),
        resourceScanner: ProjectResourceScannerProtocol = ProjectResourceScanner(),
        pathMappingResolver: PathMappingResolverProtocol = PathMappingResolver(),
        coreDataManager: CoreDataManagerProtocol = CoreDataManager.shared,
        filePermissionService: FilePermissionService = .shared,
        unusedScanService: UnusedScanServiceProtocol = UnusedScanService(),
        codeAnalyzer: CodeAnalyzerProtocol = CodeAnalyzer(),
        codeDuplicateScanService: CodeDuplicateScanServiceProtocol = CodeDuplicateScanService(),
        resourceDuplicateScanService: ResourceDuplicateScanServiceProtocol = ResourceDuplicateScanService(),
        podsDependencyScanService: PodsDependencyScanServiceProtocol = PodsDependencyScanService(),
        externalDataImporter: ExternalDataImporterProtocol = ExternalDataImporter(),
        dataIntegrationService: DataIntegrationService = DataIntegrationService()
    ) {
        self.packageParser = packageParser
        self.linkmapAnalyzer = linkmapAnalyzer
        self.resourceScanner = resourceScanner
        self.pathMappingResolver = pathMappingResolver
        self.coreDataManager = coreDataManager
        self.filePermissionService = filePermissionService
        self.unusedScanService = unusedScanService
        self.codeAnalyzer = codeAnalyzer
        self.codeDuplicateScanService = codeDuplicateScanService
        self.resourceDuplicateScanService = resourceDuplicateScanService
        self.podsDependencyScanService = podsDependencyScanService
        self.externalDataImporter = externalDataImporter
        self.dataIntegrationService = dataIntegrationService
    }
    
    // MARK: - 公共方法

    func analyzeProject(
        projectPath: String?,
        ipaPath: String?,
        linkmapPath: String?,
        externalUnusedResources: [String]? = nil,
        externalUnusedClasses: [String]? = nil,
        analysisOptions: AnalysisOptions = .default,
        progressUpdates: (@Sendable (Double, String) -> Void)? = nil,
        progressStageCompleted: (@Sendable (String) -> Void)? = nil
    ) async throws -> AnalysisProject {
        func report(_ progress: Double, _ operation: String) {
            progressUpdates?(progress, operation)
        }
        func stageCompleted(_ stageId: String) {
            progressStageCompleted?(stageId)
        }
        try validateAnalysisInputs(
            projectPath: projectPath,
            ipaPath: ipaPath,
            linkmapPath: linkmapPath
        )
        
        var analysisFailures: [AnalysisFailure] = []
        var availableData = PartialAnalysisData(
            packageFiles: [],
            projectResources: [],
            projectFileEntries: [],
            codeSizeInfo: [],
            appBundlePath: nil,
            extractedTempDirectoryPath: nil
        )
        
        let analysisStart = Date()
        func elapsed(since t: Date) -> String { String(format: "%.2f", Date().timeIntervalSince(t)) }

        print("🚀 [AnalysisService] 开始分析  project=\(projectPath ?? "nil")  ipa=\(ipaPath ?? "nil")  linkmap=\(linkmapPath ?? "nil")")
        print("📋 [AnalysisService] 分析配置  codeDuplicate=\(analysisOptions.enableCodeDuplicateScan) resourceDuplicate=\(analysisOptions.enableResourceDuplicateScan) podsDependency=\(analysisOptions.enablePodsDependencyScan)")

        // ── Phase 1：解析所有数据源（IPA + 工程 并发，Linkmap 顺序）──
        let tParse = Date()
        do {
            availableData = try await parseDataSources(
                projectPath: projectPath,
                ipaPath: ipaPath,
                linkmapPath: linkmapPath,
                tolerant: false
            )
            report(0.5, "File parsing complete")
            stageCompleted("fileParsing")
        } catch {
            report(0.5, "File parsing complete")
            stageCompleted("fileParsing")
            print("⚠️ [AnalysisService] 数据源解析部分失败，尝试降级: \(error.localizedDescription)")
            analysisFailures.append(AnalysisFailure(
                component: "Data Source Parsing",
                error: error,
                description: "Some data sources could not be parsed: \(error.localizedDescription)"
            ))
            availableData = try await parseDataSources(
                projectPath: projectPath,
                ipaPath: ipaPath,
                linkmapPath: linkmapPath,
                tolerant: true
            )
            report(0.5, "File parsing complete")
            stageCompleted("fileParsing")
        }
        print("⏱️ [TIMING] Phase 1 - 数据解析: \(elapsed(since: tParse))s  (工程:\(availableData.projectFileEntries.count) 文件, 包:\(availableData.packageFiles.count) 文件, linkmap:\(availableData.codeSizeInfo.count) 条)")

        if availableData.packageFiles.isEmpty &&
           availableData.projectResources.isEmpty &&
           availableData.projectFileEntries.isEmpty &&
           availableData.codeSizeInfo.isEmpty {
            throw AnalysisError.parsingError("No data could be extracted from any source")
        }

        report(0.55, "Integrating data...")
        var extractedTempToCleanup: String?
        if let temp = availableData.extractedTempDirectoryPath { extractedTempToCleanup = temp }
        defer {
            if let temp = extractedTempToCleanup {
                try? FileManager.default.removeItem(atPath: temp)
                print("📐 [AnalysisService] 已清理 IPA 解压临时目录")
            }
        }

        do {
            // ── Phase 2：数据整合 + 无用内容扫描 + 代码重复扫描（按配置）并发执行 ──
            let tIntegrate = Date()
            let data = availableData
            let integratedTask = Task {
                let result = await dataIntegrationService.buildIntegratedData(
                    projectFileEntries: data.projectFileEntries,
                    packageFiles: data.packageFiles,
                    codeSizeInfo: data.codeSizeInfo,
                    appBundlePath: data.appBundlePath,
                    projectPath: projectPath
                )
                stageCompleted("dataIntegration")
                return result
            }
            let unusedTask = Task {
                let result = await buildUnusedContentResults(
                    projectPath: projectPath,
                    projectFileEntries: data.projectFileEntries,
                    externalUnusedResources: externalUnusedResources,
                    externalUnusedClasses: externalUnusedClasses,
                    codeSizeInfo: data.codeSizeInfo,
                    projectFileCount: data.projectFileEntries.count,
                    packageFiles: data.packageFiles,
                    appBundlePath: data.appBundlePath,
                    analysisOptions: analysisOptions
                )
                stageCompleted("unusedScan")
                return result
            }
            let duplicateTask = Task { () -> [DuplicateCodeGroup] in
                guard analysisOptions.enableCodeDuplicateScan, let path = projectPath else { return [] }
                do {
                    let groups = try await codeDuplicateScanService.scanDuplicateCode(
                        projectPath: path,
                        projectFileEntries: data.projectFileEntries
                    )
                    print("📊 [AnalysisService] 代码重复扫描完成: \(groups.count) 组")
                    stageCompleted("codeDuplicate")
                    return groups
                } catch {
                    print("⚠️ [AnalysisService] 代码重复扫描失败: \(error.localizedDescription)")
                    stageCompleted("codeDuplicate")
                    return []
                }
            }
            let resourceDuplicateTask = Task { () -> [DuplicateResourceGroup] in
                guard analysisOptions.enableResourceDuplicateScan, let path = projectPath else {
                    stageCompleted("resourceDuplicate")
                    return []
                }
                do {
                    let groups = try await resourceDuplicateScanService.scanDuplicateResources(
                        projectPath: path,
                        projectFileEntries: data.projectFileEntries
                    )
                    print("📊 [AnalysisService] 资源重复扫描完成: \(groups.count) 组")
                    stageCompleted("resourceDuplicate")
                    return groups
                } catch {
                    print("⚠️ [AnalysisService] 资源重复扫描失败: \(error.localizedDescription)")
                    stageCompleted("resourceDuplicate")
                    return []
                }
            }
            let podsTask = Task { () -> PodsDependencyResult? in
                guard analysisOptions.enablePodsDependencyScan, let path = projectPath else {
                    stageCompleted("podsDependency")
                    return nil
                }
                do {
                    let result = try await podsDependencyScanService.scanPodsDependencies(projectPath: path)
                    if let r = result { print("📊 [AnalysisService] Pods 依赖扫描完成: \(r.pods.count) 个") }
                    stageCompleted("podsDependency")
                    return result
                } catch {
                    print("⚠️ [AnalysisService] Pods 依赖扫描失败: \(error.localizedDescription)")
                    stageCompleted("podsDependency")
                    return nil
                }
            }
            let integratedData = await integratedTask.value
            let unusedContentResults = await unusedTask.value
            let duplicateCodeGroups = await duplicateTask.value
            let duplicateResourceGroups = await resourceDuplicateTask.value
            let podsDependencyResult = await podsTask.value
            print("⏱️ [TIMING] Phase 2 - 整合+无用扫描（并发）: \(elapsed(since: tIntegrate))s  (整合:\(integratedData.files.count), 无用资源:\(unusedContentResults.unusedResources.count), 无用类:\(unusedContentResults.unusedCode.count), 代码重复:\(duplicateCodeGroups.count), 资源重复:\(duplicateResourceGroups.count), Pods:\(podsDependencyResult?.pods.count ?? 0))")

            report(0.85, "Generating analysis...")

            // ── Phase 3：写入 CoreData ──
            let tSave = Date()
            let analysisProject = try await createAnalysisProject(
                integratedData: integratedData,
                unusedContentResults: unusedContentResults,
                duplicateCodeGroups: duplicateCodeGroups,
                duplicateResourceGroups: duplicateResourceGroups,
                podsDependencyResult: podsDependencyResult,
                projectPath: projectPath,
                ipaPath: ipaPath,
                linkmapPath: linkmapPath,
                appBundlePath: availableData.appBundlePath
            )
            print("⏱️ [TIMING] Phase 3 - CoreData 写入: \(elapsed(since: tSave))s")
            print("⏱️ [TIMING] ✅ 总耗时: \(elapsed(since: analysisStart))s")

            report(0.9, "Analysis generation complete")
            stageCompleted("analysisGeneration")
            return analysisProject

        } catch {
            throw error
        }
    }
    
    func getAnalysisHistory() async throws -> [AnalysisProject] {
        return try await coreDataManager.fetchAllAnalysisProjects()
    }
    
    func deleteAnalysis(_ project: AnalysisProject) async throws {
        try await coreDataManager.deleteAnalysisProject(project)
    }
    
    func exportAnalysisData(_ project: AnalysisProject) async throws -> Data {
        return try await coreDataManager.exportAnalysisProject(project)
    }
    
    func importAnalysisData(_ data: Data) async throws -> AnalysisProject {
        return try await coreDataManager.importAnalysisProject(from: data)
    }
    
    // MARK: - 输入校验

    private func validateAnalysisInputs(
        projectPath: String?,
        ipaPath: String?,
        linkmapPath: String?
    ) throws {
        // 至少需要提供一个数据源
        guard projectPath != nil || ipaPath != nil || linkmapPath != nil else {
            throw AnalysisError.invalidFilePath("At least one data source must be provided")
        }
        
        if let projectPath = projectPath {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: projectPath, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw AnalysisError.invalidFilePath("Project directory not found: \(projectPath)")
            }
        }
        
        if let ipaPath = ipaPath {
            guard FileManager.default.fileExists(atPath: ipaPath) else {
                throw AnalysisError.invalidFilePath("IPA file not found: \(ipaPath)")
            }
        }
        
        if let linkmapPath = linkmapPath {
            guard FileManager.default.fileExists(atPath: linkmapPath) else {
                throw AnalysisError.invalidFilePath("Linkmap file not found: \(linkmapPath)")
            }
        }
    }
    
    // MARK: - 数据源解析辅助方法

    /// 解析 IPA 或 .app 包，返回包文件列表、.app 路径和临时目录路径
    private func parseIPAOrAppFiles(
        ipaPath: String?,
        scopedURL: URL?
    ) async throws -> (packageFiles: [PackageFileInfo], appBundlePath: String?, tempDir: String?) {
        guard let ipaPath else { return ([], nil, nil) }
        let t0 = Date()
        if ipaPath.hasSuffix(".ipa") {
            guard let scopedURL else {
                throw AnalysisError.insufficientPermissions(
                    "无法访问 IPA 文件（沙盒未授权）。请点击「IPA 文件」旁的「选择」按钮，在文件选择器中重新选择该 IPA 后再进行分析。")
            }
            let result = try await packageParser.parseIPA(at: scopedURL)
            print("⏱️ [TIMING]   IPA 解压+列文件: \(String(format: "%.2f", Date().timeIntervalSince(t0)))s  (\(result.packageFiles.count) 个文件)")
            return (result.packageFiles, result.appBundlePath?.path, result.tempDirectoryForCleanup?.path)
        } else if ipaPath.hasSuffix(".app") {
            let result = try await packageParser.parseApp(at: ipaPath)
            print("⏱️ [TIMING]   App 解析: \(String(format: "%.2f", Date().timeIntervalSince(t0)))s  (\(result.packageFiles.count) 个文件)")
            return (result.packageFiles, result.appBundlePath?.path, nil)
        }
        return ([], nil, nil)
    }

    /// 扫描工程目录，返回所有文件条目
    private func scanProjectFiles(_ projectPath: String?) async throws -> [ProjectFileEntry] {
        guard let projectPath else { return [] }
        let t0 = Date()
        let entries = try await resourceScanner.scanProjectDirectoryAllFiles(at: projectPath)
        print("⏱️ [TIMING]   工程目录扫描: \(String(format: "%.2f", Date().timeIntervalSince(t0)))s  (\(entries.count) 个文件)")
        return entries
    }

    /// 解析 LinkMap 文件，返回代码体积信息列表
    private func parseLinkmapFiles(
        linkmapPath: String,
        scopedURL: URL?,
        projectFileEntries: [ProjectFileEntry]?,
        projectPath: String? = nil
    ) async throws -> [CodeSizeInfo] {
        guard scopedURL != nil else {
            throw AnalysisError.insufficientPermissions(
                "无法访问 Linkmap 文件（沙盒未授权）。请点击「Linkmap」旁的「选择」按钮重新选择该文件后再分析。")
        }
        let t0 = Date()
        let parseResult = try await linkmapAnalyzer.parseLinkmapFile(at: linkmapPath, projectPath: projectPath)
        print("⏱️ [TIMING]   Linkmap 文件解析: \(String(format: "%.2f", Date().timeIntervalSince(t0)))s  (\(parseResult.objectFileInfos.count) .o, \(parseResult.symbols.count) 符号)")
        let tMap = Date()
        let entries = projectFileEntries ?? []
        let index = entries.isEmpty ? [:] : LinkmapAnalyzer.makeProjectFileIndex(from: entries)
        let result = try await linkmapAnalyzer.mapObjectFilesToProjectStructure(
            parseResult: parseResult,
            projectFileIndex: index,
            projectFileEntries: entries.isEmpty ? nil : entries,
            linkmapPathPrefixesToStrip: LinkmapPathAdapter.defaultPrefixesToStrip,
            projectPath: projectPath
        )
        print("⏱️ [TIMING]   Linkmap→工程映射: \(String(format: "%.2f", Date().timeIntervalSince(tMap)))s  (\(result.count) 代码文件)")
        return result
    }

    /// IPA/App 解析与工程目录扫描并发执行，Linkmap 解析在拿到工程文件列表后再执行（便于使用工程索引做路径映射）。
    private func parseDataSources(
        projectPath: String?,
        ipaPath: String?,
        linkmapPath: String?,
        tolerant: Bool
    ) async throws -> PartialAnalysisData {
        let ipaScope = ipaPath.flatMap { path -> URL? in
            guard path.hasSuffix(".ipa") else { return nil }
            return filePermissionService.resolveAndStartAccessingSecurityScopedResource(for: path)
        }
        let linkmapScope = linkmapPath.flatMap {
            filePermissionService.resolveAndStartAccessingSecurityScopedResource(for: $0)
        }
        defer {
            ipaScope?.stopAccessingSecurityScopedResource()
            linkmapScope?.stopAccessingSecurityScopedResource()
        }

        async let ipaTask = parseIPAOrAppFiles(ipaPath: ipaPath, scopedURL: ipaScope)
        async let projectTask = scanProjectFiles(projectPath)

        var packageFiles: [PackageFileInfo] = []
        var appBundlePath: String?
        var extractedTempDirectoryPath: String?
        var projectFileEntries: [ProjectFileEntry] = []

        do {
            let result = try await ipaTask
            packageFiles = result.packageFiles
            appBundlePath = result.appBundlePath
            extractedTempDirectoryPath = result.tempDir
        } catch {
            if tolerant {
                print("⚠️ [AnalysisService] IPA/App 解析失败，尝试降级: \(error.localizedDescription)")
                if let path = ipaPath,
                   let attrs = try? FileManager.default.attributesOfItem(atPath: path) {
                    let size = attrs[.size] as? Int64 ?? 0
                    let url = URL(fileURLWithPath: path)
                    packageFiles = [PackageFileInfo(
                        relativePath: url.lastPathComponent,
                        fileName: url.lastPathComponent,
                        size: size,
                        fileType: .other,
                        isMainExecutable: false
                    )]
                }
            } else {
                print("❌ [AnalysisService] 解析失败: \(error.localizedDescription)")
                throw error
            }
        }

        do {
            projectFileEntries = try await projectTask
        } catch {
            if tolerant {
                print("⚠️ [AnalysisService] 工程目录扫描失败: \(error.localizedDescription)")
            } else {
                throw error
            }
        }

        var codeSizeInfo: [CodeSizeInfo] = []
        if let path = linkmapPath, linkmapScope != nil {
            do {
                // 非容错模式下 projectFileEntries 已就绪，可用于精确路径映射
                codeSizeInfo = try await parseLinkmapFiles(
                    linkmapPath: path,
                    scopedURL: linkmapScope,
                    projectFileEntries: tolerant ? nil : projectFileEntries,
                    projectPath: projectPath
                )
            } catch {
                if tolerant {
                    print("⚠️ [AnalysisService] Linkmap 解析失败: \(error.localizedDescription)")
                } else {
                    throw error
                }
            }
        }

        return PartialAnalysisData(
            packageFiles: packageFiles,
            projectResources: ProjectResourceScanner.resourceEntries(from: projectFileEntries),
            projectFileEntries: projectFileEntries,
            codeSizeInfo: codeSizeInfo,
            appBundlePath: appBundlePath,
            extractedTempDirectoryPath: extractedTempDirectoryPath
        )
    }
    
    // MARK: - 无用内容扫描

    /// 构建无用内容结果：本地 Swift 无用扫描 + 外部导入列表合并，并按 LinkMap 符号表为无用类填充 estimatedSize。
    private func buildUnusedContentResults(
        projectPath: String?,
        projectFileEntries: [ProjectFileEntry],
        externalUnusedResources: [String]?,
        externalUnusedClasses: [String]?,
        codeSizeInfo: [CodeSizeInfo],
        projectFileCount: Int,
        packageFiles: [PackageFileInfo],
        appBundlePath: String? = nil,
        analysisOptions: AnalysisOptions = .default
    ) async -> UnusedContentResults {
        let runLocalUnused = analysisOptions.enableUnusedCodeScan || analysisOptions.enableUnusedResourceScan
        if !runLocalUnused {
            let externalResources = externalUnusedResources ?? []
            let externalClasses = externalUnusedClasses ?? []
            let mergedResources = externalDataImporter.mergeWithLocalAnalysis(externalUnusedResources: externalResources, localUnusedResources: [])
            let mergedCode = externalDataImporter.mergeWithLocalAnalysis(externalUnusedClasses: externalClasses, localUnusedCode: [])
            print("📊 [AnalysisService] 未启用无用代码/资源扫描，仅使用外部数据: 资源 \(mergedResources.count), 类 \(mergedCode.count)")
            return UnusedContentResults(unusedResources: mergedResources, unusedCode: mergedCode)
        }
        print("📊 [AnalysisService] 开始构建无用内容结果 projectPath=\(projectPath ?? "nil")")
        var localResources: [UnusedResource] = []
        var localCode: [UnusedCode] = []
        if let path = projectPath {
            // 大工程时本地无用扫描非常耗时，这里按工程规模做一次自动降级：
            // projectFileCount ≈ 工程内文件总数，经验上 code 文件数通常同量级甚至更大。
            let localScanFileThreshold = 50_000
            if projectFileCount > localScanFileThreshold {
                print("📊 [AnalysisService] 工程文件数 \(projectFileCount) 超过阈值 \(localScanFileThreshold)，自动跳过本地无用扫描（仅使用外部无用列表和 LinkMap 体积）。")
            } else {
                // 主二进制路径：优先用解析阶段得到的 .app 路径（IPA 解压或直接选 .app），否则再尝试从工程目录下找 .app（少见）
                let binaryPath: String? = {
                    guard let mainBinary = packageFiles.first(where: { $0.isMainExecutable }) else { return nil }
                    if let appRoot = appBundlePath, !appRoot.isEmpty {
                        return (appRoot as NSString).appendingPathComponent(mainBinary.fileName)
                    }
                    if let appRel = projectFileEntries.first(where: { $0.relativePath.hasSuffix(".app") })?.relativePath {
                        return URL(fileURLWithPath: path).appendingPathComponent(appRel).appendingPathComponent(mainBinary.fileName).path
                    }
                    return nil
                }()
                
                if let binaryPath = binaryPath {
                    print("📊 [AnalysisService] 主二进制路径: \(binaryPath)")
                }
                
                if let scanResult = await unusedScanService.runLocalUnusedScan(
                    projectPath: path,
                    projectFileEntries: projectFileEntries,
                    binaryPath: binaryPath,
                    codeSizeInfo: codeSizeInfo
                ) {
                    localResources = scanResult.unusedResources
                    localCode = scanResult.unusedCode
                    print("📊 [AnalysisService] 本地无用扫描完成: 资源 \(localResources.count) 项, 类/文件 \(localCode.count) 项")
                } else {
                    print("📊 [AnalysisService] 本地无用扫描未返回结果（路径无效或扫描异常）")
                }
            }
        } else {
            print("📊 [AnalysisService] 未选择工程路径，跳过本地无用扫描")
        }
        let externalResources = externalUnusedResources ?? []
        let externalClasses = externalUnusedClasses ?? []
        print("📊 [AnalysisService] 外部数据: 资源 \(externalResources.count) 条, 类 \(externalClasses.count) 条")
        let mergedResources = externalDataImporter.mergeWithLocalAnalysis(externalUnusedResources: externalResources, localUnusedResources: localResources)
        var mergedCode = externalDataImporter.mergeWithLocalAnalysis(externalUnusedClasses: externalClasses, localUnusedCode: localCode)
        print("📊 [AnalysisService] 合并后: 无用资源 \(mergedResources.count) 项, 无用类/文件 \(mergedCode.count) 项")

        // 有 LinkMap 时：为无用类填充 estimatedSize，同时补全 filePath 为空的条目。
        let allSymbols = codeSizeInfo.flatMap { $0.symbols }
        if !allSymbols.isEmpty, !mergedCode.isEmpty {
            print("📊 [AnalysisService] 正在用 LinkMap 符号（\(allSymbols.count) 条）为 \(mergedCode.count) 个无用类统计 estimatedSize…")
            let classNamesSet = Set(mergedCode.map(\.className))
            let sizeByClass = await Task.detached(priority: .userInitiated) {
                Self.buildCodeSizeByClassFromSymbols(allSymbols, classNames: classNamesSet)
            }.value

            // 为 filePath 仍为空的类，在 codeSizeInfo 中按 ObjC 符号精确匹配一次路径
            let needsPath = Set(mergedCode.filter { $0.filePath.isEmpty }.map(\.className))
            var pathByClass: [String: String] = [:]
            if !needsPath.isEmpty {
                for info in codeSizeInfo {
                    for symbol in info.symbols {
                        guard let cls = BinaryUnusedCodeAnalyzer.extractObjCClassName(from: symbol.symbolName),
                              needsPath.contains(cls),
                              pathByClass[cls] == nil else { continue }
                        pathByClass[cls] = info.relativePath
                    }
                }
            }

            mergedCode = mergedCode.map { item in
                let size = sizeByClass[item.className] ?? 0
                let path = item.filePath.isEmpty ? (pathByClass[item.className] ?? "") : item.filePath
                return UnusedCode(
                    className: item.className,
                    filePath: path,
                    estimatedSize: size,
                    detectionMethod: item.detectionMethod,
                    dependencies: item.dependencies,
                    riskLevel: item.riskLevel
                )
            }
            print("📊 [AnalysisService] 已用 LinkMap 为无用类填充 estimatedSize 完成")
        } else if mergedCode.isEmpty == false {
            print("📊 [AnalysisService] 无 LinkMap 符号，无用类 estimatedSize 保持为原值（Mach-O 路径已由 BinaryUnusedCodeAnalyzer 填充）")
        }
        return UnusedContentResults(unusedResources: mergedResources, unusedCode: mergedCode)
    }
    
    // MARK: - LinkMap 符号体积统计

    /// 符号量超过此值时不再做「按类名 contains」回退，仅用 ObjC 正则解析，避免百万级符号 × 数百类名导致卡死。
    private static let symbolCountLimitForContainsFallback = 80_000

    /// 单遍遍历 LinkMap 符号，按类名聚合大小。优先用 ObjC 符号正则；符号数过大时跳过 contains 回退以防卡顿。
    public static func buildCodeSizeByClassFromSymbols(_ symbols: [SymbolInfo], classNames: Set<String>) -> [String: Int64] {
        var sizeByClass: [String: Int64] = [:]
        guard !symbols.isEmpty, !classNames.isEmpty else { return sizeByClass }
        let skipContainsFallback = symbols.count > Self.symbolCountLimitForContainsFallback
        if skipContainsFallback {
            print("📊 [AnalysisService] 符号数 \(symbols.count) 超过阈值，仅用 ObjC 符号解析，Swift 类 estimatedSize 可能为 0")
        }
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
    
    // MARK: - 虚拟 .o 节点辅助方法

    /// 判断 codeSizeInfo.relativePath 是否为「.framework/.a 下的虚拟 .o 节点」路径。
    /// 特征：路径中含 "(" ，如 Pods/SDWebImage/SDWebImage.framework/SDWebImage(SDImageCache.o)
    static func isVirtualObjectPath(_ path: String) -> Bool {
        path.contains("(") && path.hasSuffix(".o)")
    }

    /// 判断虚拟 .o 节点路径是否含有无用类（通过路径内的 ObjC 符号提取类名与 unusedClassNames 比对）。
    static func virtualNodeContainsUnusedClass(_ relativePath: String, unusedClassNames: Set<String>) -> Bool {
        guard let openParen = relativePath.lastIndex(of: "("),
              let closeParen = relativePath.lastIndex(of: ")"),
              openParen < closeParen else { return false }
        let inner = String(relativePath[relativePath.index(after: openParen)..<closeParen])
        let baseName = inner.hasSuffix(".o") ? String(inner.dropLast(2)) : inner
        if unusedClassNames.contains(baseName) { return true }
        return unusedClassNames.contains(where: { cls in
            baseName == cls
                || baseName.hasPrefix(cls + "+")
                || baseName.hasPrefix(cls + "-")
        })
    }

    // MARK: - CoreData 写入

    private func createAnalysisProject(
        integratedData: IntegratedAnalysisData,
        unusedContentResults: UnusedContentResults,
        duplicateCodeGroups: [DuplicateCodeGroup],
        duplicateResourceGroups: [DuplicateResourceGroup],
        podsDependencyResult: PodsDependencyResult?,
        projectPath: String?,
        ipaPath: String?,
        linkmapPath: String?,
        appBundlePath: String?
    ) async throws -> AnalysisProject {
        
        // 计算含无用内容的更新汇总
        let unusedResourceSize = unusedContentResults.unusedResources.reduce(0) { $0 + $1.size }
        let unusedCodeSize = unusedContentResults.unusedCode.reduce(0) { $0 + $1.estimatedSize }
        let potentialSavings = unusedResourceSize + unusedCodeSize
        
        let updatedSummary = AnalysisSummary(
            totalSize: integratedData.summary.totalSize,
            codeSize: integratedData.summary.codeSize,
            resourceSize: integratedData.summary.resourceSize,
            frameworkSize: integratedData.summary.frameworkSize,
            unusedResourceSize: unusedResourceSize,
            unusedCodeSize: unusedCodeSize,
            potentialSavings: potentialSavings
        )
        
        // 写入 CoreData（含汇总：主二进制/资源/Frameworks 便于仪表盘展示）
        let analysisProject = try await coreDataManager.createAnalysisProject(
            name: generateProjectName(projectPath: projectPath, ipaPath: ipaPath, appBundlePath: appBundlePath),
            projectPath: projectPath,
            ipaPath: ipaPath,
            linkmapPath: linkmapPath,
            totalSize: updatedSummary.totalSize,
            summaryCodeSize: updatedSummary.codeSize,
            summaryResourceSize: updatedSummary.resourceSize,
            summaryFrameworkSize: updatedSummary.frameworkSize
        )
        
        // 预构建 Set 实现 O(1) 无用内容查找（替代逐文件 O(N) 线性搜索）
        let unusedResourcePaths = Set(unusedContentResults.unusedResources.map { $0.relativePath })
        let unusedClassNames = Set(unusedContentResults.unusedCode.map { $0.className })
        let sourceFileExtensions: Set<String> = ["m", "mm", "swift", "c", "cc", "cpp"]
        let unusedCodeSourcePaths = Set(
            unusedContentResults.unusedCode
                .map { $0.filePath }
                .filter { path in
                    let ext = (path as NSString).pathExtension.lowercased()
                    return sourceFileExtensions.contains(ext)
                }
        )

        // 批量写入，每批后 save 一次降低 I/O 压力
        let batchSize = 500
        let total = integratedData.files.count
        print("📊 [AnalysisService] 写入 \(total) 条分析结果（批大小: \(batchSize)）")

        for (index, file) in integratedData.files.enumerated() {
            // isUnusedCode 判断：
            //   - 虚拟 .o 节点（relativePath 含 "("）：检查该编译单元的符号集与 unusedClassNames 是否有交集
            //   - 普通源文件节点：按路径精确匹配 unusedCodeSourcePaths
            let isUnusedCode: Bool
            if Self.isVirtualObjectPath(file.relativePath) {
                isUnusedCode = Self.virtualNodeContainsUnusedClass(
                    file.relativePath,
                    unusedClassNames: unusedClassNames
                )
            } else {
                isUnusedCode = unusedCodeSourcePaths.contains(file.relativePath)
            }

            try await coreDataManager.createAnalysisResult(
                for: analysisProject,
                relativePath: file.relativePath,
                fileName: file.fileName,
                fileType: file.fileType.rawValue,
                codeSize: file.codeSize,
                resourceSize: file.resourceSize,
                frameworkSize: file.frameworkSize,
                isUnusedResource: unusedResourcePaths.contains(file.relativePath),
                isUnusedCode: isUnusedCode,
                isExternallyMarked: false
            )
            let nextIndex = index + 1
            if nextIndex % batchSize == 0 || nextIndex == total {
                try await coreDataManager.saveContext()
            }
        }
        
        print("✅ [AnalysisService] Successfully created \(total) analysis results")
        
        // 写入代码重复、资源重复、Pods 依赖扫描结果（JSON 存入 Binary 属性）
        if !duplicateCodeGroups.isEmpty,
           let data = try? JSONEncoder().encode(duplicateCodeGroups) {
            analysisProject.duplicateCodeGroupsData = data
        }
        if !duplicateResourceGroups.isEmpty,
           let data = try? JSONEncoder().encode(duplicateResourceGroups) {
            analysisProject.duplicateResourceGroupsData = data
        }
        if let pods = podsDependencyResult,
           let data = try? JSONEncoder().encode(pods) {
            analysisProject.podsDependencyData = data
        }
        
        // 使用汇总的 Total（解压后 Payload 大小），不采用 result 行求和，以免漏计未匹配到项目的包内文件
        analysisProject.totalSize = updatedSummary.totalSize
        analysisProject.updatedAt = Date()
        try await coreDataManager.updateAnalysisProject(analysisProject)
        
        return analysisProject
    }
    
    // MARK: - 工程名生成

    private func generateProjectName(projectPath: String?, ipaPath: String?, appBundlePath: String?) -> String {
        var base: String
        if let projectPath = projectPath {
            base = URL(fileURLWithPath: projectPath).lastPathComponent
        } else if let ipaPath = ipaPath {
            base = URL(fileURLWithPath: ipaPath).deletingPathExtension().lastPathComponent
        } else {
            base = "Analysis \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))"
        }
        // 从 .app/Info.plist 读取版本号与 Build No
        if let bundlePath = appBundlePath {
            let plistURL = URL(fileURLWithPath: bundlePath).appendingPathComponent("Info.plist")
            if let data = try? Data(contentsOf: plistURL),
               let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                let version = plist["CFBundleShortVersionString"] as? String ?? ""
                let build   = plist["CFBundleVersion"] as? String ?? ""
                if !version.isEmpty && !build.isEmpty {
                    base += " \(version) (\(build))"
                } else if !version.isEmpty {
                    base += " \(version)"
                } else if !build.isEmpty {
                    base += " (\(build))"
                }
            }
        }
        return base
    }
}

// MARK: - 辅助数据结构

struct PartialAnalysisData {
    let packageFiles: [PackageFileInfo]
    let projectResources: [ProjectFileEntry]
    let projectFileEntries: [ProjectFileEntry]
    let codeSizeInfo: [CodeSizeInfo]
    /// .app 在磁盘上的路径；用于 Assets.car 解析（.ipa 解压后为 Payload/xxx.app）
    let appBundlePath: String?
    /// 仅 .ipa 解压时非 nil；分析完成后需删除
    let extractedTempDirectoryPath: String?
}

struct AnalysisFailure {
    let component: String
    let error: Error
    let description: String
}

struct IntegratedAnalysisData {
    let files: [IntegratedFileInfo]
    let summary: AnalysisSummary
}

struct IntegratedFileInfo {
    let relativePath: String
    let fileName: String
    let fileType: FileType
    let resourceSize: Int64
    let codeSize: Int64
    let frameworkSize: Int64
    let hasPackageData: Bool
    let hasProjectData: Bool
    let hasLinkmapData: Bool
}

private struct UnusedContentResults {
    let unusedResources: [UnusedResource]
    let unusedCode: [UnusedCode]
}

// MARK: - 扩展

extension ResourceType {
    func toFileType() -> FileType {
        switch self {
        case .image, .audio, .video, .data:
            return .resource
        case .other:
            return .other
        }
    }
}
