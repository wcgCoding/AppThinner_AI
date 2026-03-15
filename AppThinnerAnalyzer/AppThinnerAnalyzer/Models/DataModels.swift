import Foundation
import CoreGraphics
import CoreData

// MARK: - Enums

enum FileType: String, CaseIterable {
    case code = "Code"
    case resource = "Resource"
    case framework = "Framework"
    case directory = "Directory"
    case other = "Other"
}

enum UnusedSource: String, CaseIterable {
    case staticAnalysis = "Static Analysis"
    case externalData = "External Data"
    case manual = "Manual"
    case machO = "Mach-O Binary"
}

enum ResourceType: String, CaseIterable {
    case image = "Image"
    case audio = "Audio"
    case video = "Video"
    case data = "Data"
    case other = "Other"
}

enum RecommendedAction {
    case safeToDelete
    case reviewRequired
    case keepForCompatibility
}

enum RiskLevel {
    case low, medium, high
}

enum ChangeType {
    case added, removed, modified, unchanged
}

enum TrendDirection {
    case increasing, decreasing, stable
}

enum CompressionLevel {
    case conservative, balanced, aggressive
}

// MARK: - Analysis Options

/// 分析配置选项，控制是否执行代码重复、资源重复、Pods 依赖等扫描
struct AnalysisOptions {
    /// 启用代码重复扫描分析
    var enableCodeDuplicateScan: Bool
    /// 启用资源重复扫描分析
    var enableResourceDuplicateScan: Bool
    /// 启用 Pods 库依赖扫描分析
    var enablePodsDependencyScan: Bool
    /// 启用无用代码扫描（默认关，耗时长）
    var enableUnusedCodeScan: Bool
    /// 启用无用资源扫描（默认关，耗时长）
    var enableUnusedResourceScan: Bool

    static let `default` = AnalysisOptions(
        enableCodeDuplicateScan: false,
        enableResourceDuplicateScan: false,
        enablePodsDependencyScan: false,
        enableUnusedCodeScan: false,
        enableUnusedResourceScan: false
    )
}

// MARK: - Code Duplicate Scan Result

/// 单份重复代码所在位置（文件路径 + 可选行范围）
struct DuplicateCodeEntry: Codable, Hashable {
    let relativePath: String
    let startLine: Int?
    let endLine: Int?
}

/// 一组重复代码：多份内容相同或高度相似的代码及其路径列表
struct DuplicateCodeGroup: Codable, Identifiable {
    var id: String { fingerprint }
    /// 内容指纹（如归一化后的哈希），用于分组
    let fingerprint: String
    /// 重复份数
    let count: Int
    /// 各份所在路径及可选行号
    let entries: [DuplicateCodeEntry]
    /// 相似度 0~1（完全一致为 1）
    let similarity: Double
}

// MARK: - Resource Duplicate Scan Result

/// 单份重复资源所在路径及大小
struct DuplicateResourceEntry: Codable, Hashable {
    let relativePath: String
    let size: Int64
}

/// 一组重复资源：多份内容相同（哈希一致）的资源及其路径列表
struct DuplicateResourceGroup: Codable, Identifiable {
    var id: String { fingerprint }
    let fingerprint: String
    let count: Int
    let entries: [DuplicateResourceEntry]
    let totalSize: Int64
    let similarity: Double
}

// MARK: - Pods Dependency Scan Result

/// 单个 Pod 依赖信息（名称、版本、子依赖）
struct PodsDependencyInfo: Codable, Identifiable {
    var id: String { "\(name)_\(version)" }
    let name: String
    let version: String
    let subspecs: [String]
    let children: [PodsDependencyInfo]
    /// 预估体积（来自 LinkMap/包内路径匹配时填充，否则 0）
    let estimatedSize: Int64
}

/// Pods 依赖扫描根结果
struct PodsDependencyResult: Codable {
    let pods: [PodsDependencyInfo]
    let podfileLockPath: String?
}

/// 主库维度一行（列表展示用）：名称、版本、体积、无用体积/占比、被依赖库数量、被依赖库列表
struct PodsMainLibRow: Identifiable {
    var id: String { "\(name)_\(version)" }
    let name: String
    let version: String
    let size: Int64
    let unusedSize: Int64
    /// 无用体积 / 总体积，0~1
    let unusedRatio: Double
    let dependedByCount: Int
    let dependedByList: [String]
}

// MARK: - TreemapNode (Value Type)

struct TreemapNode: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let relativePath: String
    let size: Int64
    var children: [TreemapNode]
    let isUnused: Bool
    /// 当前节点（或目录下）无用类/资源占该节点总大小的比例，0~1，用于冷→暖着色
    let unusedRatio: Double
    let fileType: FileType
    var rect: CGRect = .zero // TreeMap layout calculation result
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: TreemapNode, rhs: TreemapNode) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - File Information Structures

/// IPA/App 包解析得到的文件信息
struct PackageFileInfo {
    let relativePath: String
    let fileName: String
    let size: Int64
    let fileType: FileType
    /// 是否为 .app 根目录下 Info.plist 中 CFBundleExecutable 指定的主二进制（用于正确统计 Code Size）
    let isMainExecutable: Bool
}

struct SymbolInfo {
    let address: String
    let size: Int64
    let fileName: String
    let symbolName: String
    /// Linkmap Object files 段中的编号，表示该符号属于哪个编译单元
    let objectFileIndex: Int
}

/// Linkmap 中一个编译单元（.o）的汇总信息，作为「按文件看体积」的基础数据
struct ObjectFileInfo {
    /// Object files 段中的编号
    let index: Int
    /// 完整路径（linkmap 中的原始路径）
    let filePath: String
    /// 文件名（如 xxx.o）
    let fileName: String
    /// 该编译单元在 linkmap 中的符号总大小（解析 Symbol 段时在对应 Object 上累加）
    var totalSize: Int64
    /// 解析时已解析的项目相对路径（若在解析阶段传入 projectPath 并走快速路径则会有值，可省去后续「Linkmap→工程映射」步骤）
    var resolvedRelativePath: String?
}

/// Linkmap 解析结果：以 Object 文件为基准的汇总 + 符号明细（供查看单文件内符号分布）
struct LinkmapParseResult {
    let objectFileInfos: [ObjectFileInfo]
    let symbols: [SymbolInfo]
}

struct CodeSizeInfo {
    let relativePath: String
    let fileName: String
    let totalSize: Int64
    let symbols: [SymbolInfo]
}

// MARK: - Unused Symbol (LinkMap 粒度)

/// 单条无用符号：名称 + 大小，并映射到 LinkMap 中的 Object File，作为无用体积的一部分。
struct UnusedSymbolRecord: Identifiable {
    var id: String { "\(symbolName)_\(objectFileIndex)" }
    /// 符号名（如 _OBJC_CLASS_$_Foo、_-[Foo bar]）
    let symbolName: String
    /// 该符号在 LinkMap 中的大小（字节）
    let size: Int64
    /// LinkMap Object files 段中的编号
    let objectFileIndex: Int
    /// LinkMap 中该 Object 的原始路径（如 /path/to/File.o 或 .a(Obj.o)）
    let objectFilePath: String
    /// 解析后的项目相对路径（与 Treemap/分析结果一致，便于与 CodeSizeInfo 对齐）
    let resolvedRelativePath: String
    /// 所属无用类名（若由无用类推导）
    let className: String?
}

/// 无用符号检索+映射结果：按 Object File 聚合，便于展示「每个 .o 下的无用符号列表及小计」。
struct UnusedSymbolMappingResult {
    /// 所有无用符号明细（含名称、大小、映射到的 Object File）
    let unusedSymbols: [UnusedSymbolRecord]
    /// 按 Object File index 聚合：index -> (objectFilePath, resolvedPath, symbols)
    let byObjectFile: [Int: (objectFilePath: String, resolvedPath: String, symbols: [UnusedSymbolRecord])]
    /// 无用符号总体积（应与无用类 estimatedSize 之和一致）
    var totalUnusedSymbolSize: Int64 { unusedSymbols.reduce(0) { $0 + $1.size } }
}

// MARK: - ObjC 静态调用图（方法级）结果

/// 单个 ObjC 方法节点（仅用于静态调用图与 LinkMap 交叉分析）
struct ObjCMethodSymbol: Identifiable {
    var id: String { identifier }
    /// 内部唯一 ID，例如 "objc:-[FooViewController refreshData]"
    let identifier: String
    /// 底层链接符号名，用于与 LinkMap/Mach-O 对齐
    let mangledName: String
    /// 展示用名称（如 "-[FooViewController refreshData]")
    let displayName: String
    /// 工程内相对路径
    let sourceFile: String
    /// 定义行号
    let line: Int
    /// 所属编译单元（LinkMap Object files 段中的路径，如 xxx.o 或 libXXX.a(Obj.o)）
    let objectFile: String?
    /// 在 LinkMap 中的体积（字节），若未对齐成功则为 0
    let sizeInBinary: Int64
    /// 是否被判定为静态可达（从根方法出发 DFS/BFS 可到达）
    let isReachable: Bool
}

/// 无用 ObjC 方法分析结果：供 AppThinner 消费并映射回文件/模块
struct ObjCStaticUnusedResult {
    /// 所有参与分析的 ObjC 方法节点（含可达与不可达）
    let allMethods: [ObjCMethodSymbol]
    /// 被判定为「静态不可达且仍在二进制中」的无用方法子集
    let unusedMethods: [ObjCMethodSymbol]
    /// 按源文件聚合：relativePath -> 该文件下无用 ObjC 方法总体积
    let unusedBytesByFile: [String: Int64]
    /// 无用 ObjC 方法总体积（字节）
    var totalUnusedBytes: Int64 { unusedMethods.reduce(0) { $0 + $1.sizeInBinary } }
}

/// 项目目录下的单文件条目（代码 + 资源），用于构建分析树骨架；资源条目通过 resourceType 区分
struct ProjectFileEntry {
    let relativePath: String
    let fileName: String
    let size: Int64
    let isSourceCode: Bool
    /// 资源类型（仅资源文件有值）
    let resourceType: ResourceType?
}

// MARK: - Path Mapping Structures

struct PathMappingTable {
    let mappings: [String: String] // project path -> package path
    let conflicts: [PathMappingConflict]
    let unmappedFiles: [String]
    let accuracy: Double // mapping accuracy percentage
}

struct PathMappingConflict {
    let projectPath: String
    let candidatePackagePaths: [String]
    let recommendedResolution: String
}

struct PathMappingResult {
    let mappingTable: PathMappingTable
    let resolutions: [PathMappingResolution]
    let accuracyReport: MappingAccuracyReport
}

struct PathMappingResolution {
    let conflict: PathMappingConflict
    let selectedPath: String
    let confidence: Double
    let reasoning: String
}

struct MappingAccuracyReport {
    let totalFiles: Int
    let mappedFiles: Int
    let conflictedFiles: Int
    let unmappedFiles: Int
    let overallAccuracy: Double
    let recommendations: [String]
}

// MARK: - Analysis Result Structures (TreeMap / Directory)

struct FileNode {
    let relativePath: String
    let fileName: String
    let codeSize: Int64      // from linkmap
    let resourceSize: Int64  // from ipa/app
    let frameworkSize: Int64 // from framework analysis
    let isUnused: Bool       // static analysis + external data
    let unusedSource: UnusedSource
}

struct DirectoryNode {
    let name: String
    let relativePath: String
    let children: [DirectoryNode]
    let files: [FileNode]
    let totalSize: Int64
    let unusedSize: Int64
}

struct AnalysisSummary {
    let totalSize: Int64
    let codeSize: Int64
    let resourceSize: Int64
    let frameworkSize: Int64
    let unusedResourceSize: Int64
    let unusedCodeSize: Int64
    let potentialSavings: Int64
}

// MARK: - Unused Content Structures

struct UnusedResource {
    let relativePath: String
    let fileName: String
    let size: Int64
    let resourceType: ResourceType
    let detectionMethod: UnusedSource
    let recommendedAction: RecommendedAction
}

struct UnusedCode {
    let className: String
    let filePath: String
    let estimatedSize: Int64
    let detectionMethod: UnusedSource
    let dependencies: [String]
    let riskLevel: RiskLevel
}

// MARK: - Optimization Structures

struct OptimizationResults {
    let originalSize: Int64
    let optimizedSize: Int64
    let savedSize: Int64
    let processedFiles: Int
    let failedFiles: [String]
    let backupLocation: URL
}

struct OptimizationEstimate {
    let estimatedSavings: Int64
    let affectedFiles: Int
    let riskLevel: RiskLevel
    let recommendations: [String]
}

// MARK: - Comparison Structures

#if !UNUSED_SYMBOL_SCANNER_CLI
struct ProjectComparison {
    let projects: [AnalysisProject]
    let sizeChanges: [SizeChange]
    let newFiles: [String]
    let removedFiles: [String]
    let modifiedFiles: [FileChange]
    let summary: ComparisonSummary
}

struct SizeChange {
    let category: String
    let oldSize: Int64
    let newSize: Int64
    let change: Int64
    let changePercentage: Double
}

struct FileChange {
    let filePath: String
    let oldSize: Int64
    let newSize: Int64
    let changeType: ChangeType
}

struct ComparisonSummary {
    let totalSizeChange: Int64
    let totalSizeChangePercentage: Double
    let addedFiles: Int
    let removedFiles: Int
    let modifiedFiles: Int
    let significantChanges: [String]
}

struct MultiProjectComparison {
    let projects: [AnalysisProject]
    let trends: [SizeTrend]
    let consistentUnusedFiles: [String]
    let recommendations: [String]
}
#endif

struct SizeTrend {
    let category: String
    let dataPoints: [(Date, Int64)]
    let trend: TrendDirection
    let averageChange: Double
}

// MARK: - Error Types

enum AnalysisError: Error, LocalizedError {
    case invalidFilePath(String)
    case unsupportedFileFormat(String)
    case corruptedFile(String)
    case insufficientPermissions(String)
    case pathMappingFailed(String)
    case coreDataError(String)
    case parsingError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidFilePath(let path):
            return "Invalid file path: \(path)"
        case .unsupportedFileFormat(let format):
            return "Unsupported file format: \(format)"
        case .corruptedFile(let file):
            return "Corrupted file: \(file)"
        case .insufficientPermissions(let path):
            return "Insufficient permissions for: \(path)"
        case .pathMappingFailed(let reason):
            return "Path mapping failed: \(reason)"
        case .coreDataError(let error):
            return "Core Data error: \(error)"
        case .parsingError(let reason):
            return "Parsing error: \(reason)"
        }
    }
}

enum ImportError: Error, LocalizedError {
    case unsupportedFormat(String)
    case invalidData(String)
    case fileNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            return "Unsupported format: \(format)"
        case .invalidData(let reason):
            return "Invalid data: \(reason)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        }
    }
}

// MARK: - Storage Management Structures

struct StorageUsage {
    let totalProjects: Int
    let totalAnalysisResults: Int
    let estimatedDatabaseSize: Int64
    let oldestProjectDate: Date?
    let averageProjectSize: Int64
}

struct ImportValidationResult {
    let isValid: Bool
    let projectCount: Int
    let errors: [String]
    let warnings: [String]
    let estimatedImportSize: Int64
}

// MARK: - Historical Data Structures

#if !UNUSED_SYMBOL_SCANNER_CLI
struct HistoricalAnalysis {
    let project: AnalysisProject
    let analysisDate: Date
    let summary: AnalysisSummary
}
#endif

#if !UNUSED_SYMBOL_SCANNER_CLI
struct ProjectHistory {
    let projectName: String
    let analyses: [HistoricalAnalysis]
    let sizeProgression: [SizeDataPoint]
    let trends: ProjectTrends
}
#endif

struct SizeDataPoint {
    let date: Date
    let totalSize: Int64
    let codeSize: Int64
    let resourceSize: Int64
    let frameworkSize: Int64
}

struct ProjectTrends {
    let overallTrend: TrendDirection
    let codeTrend: TrendDirection
    let resourceTrend: TrendDirection
    let frameworkTrend: TrendDirection
    let averageGrowthRate: Double
    let projectedSize: Int64?
}
