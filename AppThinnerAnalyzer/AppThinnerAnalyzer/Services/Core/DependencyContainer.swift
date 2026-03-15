import Foundation

// MARK: - 依赖注入容器
// 统一管理所有 Service 实例及其依赖关系，通过 lazy 属性实现按需初始化。

class DependencyContainer {
    static let shared = DependencyContainer()
    
    // MARK: - 基础设施服务
    
    lazy var coreDataManager: CoreDataManagerProtocol = {
        return CoreDataManager.shared
    }()
    
    lazy var systemCompatibilityService: SystemCompatibilityService = {
        return SystemCompatibilityService.shared
    }()
    
    lazy var filePermissionService: FilePermissionService = {
        return FilePermissionService.shared
    }()
    
    lazy var errorHandlingService: ErrorHandlingService = {
        return ErrorHandlingService.shared
    }()
    
    // MARK: - 解析服务
    
    lazy var packageParser: PackageParserProtocol = {
        return PackageParser()
    }()
    
    lazy var linkmapAnalyzer: LinkmapAnalyzerProtocol = {
        return LinkmapAnalyzer()
    }()

    lazy var unusedSymbolMappingService: UnusedSymbolMappingServiceProtocol = {
        return UnusedSymbolMappingService()
    }()
    
    lazy var resourceScanner: ProjectResourceScannerProtocol = {
        return ProjectResourceScanner()
    }()
    
    lazy var codeAnalyzer: CodeAnalyzerProtocol = {
        return CodeAnalyzer()
    }()
    
    lazy var pathMappingResolver: PathMappingResolverProtocol = {
        return PathMappingResolver()
    }()
    
    lazy var externalDataImporter: ExternalDataImporterProtocol = {
        return ExternalDataImporter()
    }()
    
    // MARK: - 可视化服务
    
    lazy var treemapGenerator: TreemapGeneratorProtocol = {
        return TreemapGenerator()
    }()
    
    lazy var reportGenerator: ReportGeneratorProtocol = {
        return ReportGenerator()
    }()
    
    // MARK: - 优化服务（协议与实现见 OptimizationService.swift）
    
    lazy var optimizationService: OptimizationServiceProtocol = {
        return OptimizationService(
            filePermissionService: filePermissionService
        )
    }()
    
    // MARK: - 对比服务
    
    lazy var comparisonService: ComparisonServiceProtocol = {
        return ComparisonService(
            coreDataManager: coreDataManager
        )
    }()
    
    // MARK: - 高层服务
    
    lazy var analysisService: AnalysisServiceProtocol = {
        return AnalysisService(
            packageParser: packageParser,
            linkmapAnalyzer: linkmapAnalyzer,
            resourceScanner: resourceScanner,
            pathMappingResolver: pathMappingResolver,
            coreDataManager: coreDataManager,
            filePermissionService: filePermissionService
        )
    }()
    
    lazy var historicalDataManager: HistoricalDataManagerProtocol = {
        return HistoricalDataManager(
            coreDataManager: coreDataManager
        )
    }()
    
    // MARK: - ViewModel 工厂方法
    
    @MainActor
    func makeMainViewModel() -> MainViewModel {
        return MainViewModel(
            analysisService: analysisService,
            coreDataManager: coreDataManager,
            systemCompatibilityService: systemCompatibilityService,
            filePermissionService: filePermissionService,
            errorHandlingService: errorHandlingService
        )
    }
    
    @MainActor
    func makeTreemapViewModel() -> TreemapViewModel {
        return TreemapViewModel(
            treemapGenerator: treemapGenerator
        )
    }
    
    @MainActor
    func makeOptimizationViewModel() -> OptimizationViewModel {
        return OptimizationViewModel(
            optimizationService: optimizationService
        )
    }
    
    @MainActor
    func makeComparisonViewModel() -> ComparisonViewModel {
        return ComparisonViewModel(
            comparisonService: comparisonService
        )
    }
    
    @MainActor
    func makeHistoryViewModel() -> HistoryViewModel {
        return HistoryViewModel(
            historicalDataManager: historicalDataManager,
            coreDataManager: coreDataManager
        )
    }
    
    // MARK: - 私有初始化
    
    private init() {}
}

// NOTE: OptimizationServiceProtocol / OptimizationService 定义已迁移至 OptimizationService.swift
// NOTE: ComparisonServiceProtocol / ReportGeneratorProtocol / HistoricalDataManagerProtocol
//       的正式定义分别位于 ComparisonService.swift、ReportGenerator.swift、HistoricalDataManager.swift 中。