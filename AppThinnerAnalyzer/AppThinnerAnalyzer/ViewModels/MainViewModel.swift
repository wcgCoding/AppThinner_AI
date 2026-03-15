import SwiftUI
import CoreData
import UniformTypeIdentifiers

@MainActor
class MainViewModel: ObservableObject {
    @Published var currentProject: AnalysisProject?
    @Published var analysisHistory: [AnalysisProject] = []
    @Published var isAnalyzing = false
    @Published var analysisProgress: Double = 0.0
    @Published var currentOperation: String = ""
    /// 已完成的进度阶段 ID（用于 Analysis Progress Details 各阶段勾选）
    @Published var completedProgressStages: Set<String> = []
    @Published var errorMessage: String?
    @Published var draggedFiles: [URL] = []
    @Published var systemCompatibilityInfo: String = ""
    @Published var isSystemCompatible: Bool = true
    
    // File input properties
    @Published var selectedProjectPath: String?
    @Published var selectedIpaPath: String?
    @Published var selectedLinkmapPath: String?
    @Published var externalUnusedResources: [String] = []
    @Published var externalUnusedClasses: [String] = []
    
    /// 分析配置选项（代码重复 / 资源重复 / Pods 依赖扫描），持久化到 UserDefaults
    @Published var analysisOptions: AnalysisOptions = .default
    
    // UserDefaults keys for cached paths and options
    private enum CacheKeys {
        static let projectPath = "AppThinner.cachedProjectPath"
        static let ipaPath = "AppThinner.cachedIpaPath"
        static let linkmapPath = "AppThinner.cachedLinkmapPath"
        static let enableCodeDuplicateScan = "AppThinner.analysisOptions.enableCodeDuplicateScan"
        static let enableResourceDuplicateScan = "AppThinner.analysisOptions.enableResourceDuplicateScan"
        static let enablePodsDependencyScan = "AppThinner.analysisOptions.enablePodsDependencyScan"
        static let enableUnusedCodeScan = "AppThinner.analysisOptions.enableUnusedCodeScan"
        static let enableUnusedResourceScan = "AppThinner.analysisOptions.enableUnusedResourceScan"
    }
    
    // 标记是否正在加载缓存，避免触发保存
    private var isLoadingCachedPaths = false
    
    // MARK: - Dependencies
    
    private let analysisService: AnalysisServiceProtocol
    private let coreDataManager: CoreDataManagerProtocol
    private let systemCompatibilityService: SystemCompatibilityService
    private let filePermissionService: FilePermissionService
    private let errorHandlingService: ErrorHandlingService
    
    // MARK: - Initialization
    
    init(
        analysisService: AnalysisServiceProtocol,
        coreDataManager: CoreDataManagerProtocol,
        systemCompatibilityService: SystemCompatibilityService,
        filePermissionService: FilePermissionService,
        errorHandlingService: ErrorHandlingService = .shared
    ) {
        self.analysisService = analysisService
        self.coreDataManager = coreDataManager
        self.systemCompatibilityService = systemCompatibilityService
        self.filePermissionService = filePermissionService
        self.errorHandlingService = errorHandlingService
        
        checkSystemCompatibility()
        loadAnalysisHistory()
        loadCachedPaths()
        loadAnalysisOptions()
    }
    
    // Convenience initializer for backward compatibility
    convenience init(coreDataManager: CoreDataManagerProtocol = CoreDataManager.shared) {
        let container = DependencyContainer.shared
        self.init(
            analysisService: container.analysisService,
            coreDataManager: coreDataManager,
            systemCompatibilityService: container.systemCompatibilityService,
            filePermissionService: container.filePermissionService
        )
    }
    
    // MARK: - System Compatibility
    
    private func checkSystemCompatibility() {
        isSystemCompatible = systemCompatibilityService.isSystemCompatible()
        systemCompatibilityInfo = systemCompatibilityService.systemInfoString
        
        if !isSystemCompatible {
            errorMessage = "System compatibility issues detected. Please check system requirements."
        }
    }
    
    func refreshSystemInfo() {
        checkSystemCompatibility()
    }
    
    // MARK: - Computed Properties
    
    var hasValidInput: Bool {
        return selectedIpaPath != nil || selectedLinkmapPath != nil || selectedProjectPath != nil
    }
    
    // MARK: - Analysis Methods
    
    func startAnalysis(
        projectPath: String? = nil,
        ipaPath: String? = nil,
        linkmapPath: String? = nil,
        externalUnusedResources: [String]? = nil,
        externalUnusedClasses: [String]? = nil,
        analysisOptions: AnalysisOptions? = nil
    ) async {
        guard !isAnalyzing else { return }
        
        // Check system compatibility before starting analysis
        guard isSystemCompatible else {
            errorMessage = "Cannot start analysis: System compatibility issues detected. Please check system requirements."
            return
        }
        
        isAnalyzing = true
        analysisProgress = 0.0
        errorMessage = nil
        
        do {
            currentOperation = "Checking system compatibility..."
            analysisProgress = 0.05
            
            // Perform Apple Silicon optimization if applicable
            systemCompatibilityService.optimizeForAppleSilicon()
            
            currentOperation = "Initializing analysis..."
            analysisProgress = 0.1
            
            // Use provided parameters or fall back to instance properties
            let projectPathToUse = projectPath ?? selectedProjectPath
            let ipaPathToUse = ipaPath ?? selectedIpaPath
            let linkmapPathToUse = linkmapPath ?? selectedLinkmapPath
            let externalResourcesToUse = externalUnusedResources ?? self.externalUnusedResources
            let externalClassesToUse = externalUnusedClasses ?? self.externalUnusedClasses
            let optionsToUse = analysisOptions ?? self.analysisOptions
            
            // Validate file permissions before proceeding
            currentOperation = "Validating file permissions..."
            analysisProgress = 0.15
            
            var urlsToValidate: [URL] = []
            if let projectPath = projectPathToUse {
                urlsToValidate.append(URL(fileURLWithPath: projectPath))
            }
            if let ipaPath = ipaPathToUse {
                urlsToValidate.append(URL(fileURLWithPath: ipaPath))
            }
            if let linkmapPath = linkmapPathToUse {
                urlsToValidate.append(URL(fileURLWithPath: linkmapPath))
            }
            
            let validationResult = await filePermissionService.validateFileAccess(for: urlsToValidate)
            
            if !validationResult.isFullyAccessible {
                let deniedFiles = validationResult.deniedURLs.map { $0.lastPathComponent }.joined(separator: ", ")
                throw AnalysisError.insufficientPermissions("Access denied to required files: \(deniedFiles)")
            }
            
            currentOperation = "Running analysis..."
            analysisProgress = 0.3
            completedProgressStages = []
            
            let progressUpdates: (@Sendable (Double, String) -> Void)? = { [weak self] progress, operation in
                Task { @MainActor in
                    guard let self = self else { return }
                    if progress >= self.analysisProgress || progress >= 1.0 {
                        self.analysisProgress = progress
                    }
                    self.currentOperation = operation
                }
            }
            let progressStageCompleted: (@Sendable (String) -> Void)? = { [weak self] stageId in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.completedProgressStages.insert(stageId)
                }
            }
            let project = try await analysisService.analyzeProject(
                projectPath: projectPathToUse,
                ipaPath: ipaPathToUse,
                linkmapPath: linkmapPathToUse,
                externalUnusedResources: externalResourcesToUse.isEmpty ? nil : externalResourcesToUse,
                externalUnusedClasses: externalClassesToUse.isEmpty ? nil : externalClassesToUse,
                analysisOptions: optionsToUse,
                progressUpdates: progressUpdates,
                progressStageCompleted: progressStageCompleted
            )
            
            currentProject = project
            await loadAnalysisHistory()
            
            analysisProgress = 1.0
            currentOperation = "Analysis complete"
            
        } catch {
            errorHandlingService.handleError(error, context: .analysis)
        }
        
        isAnalyzing = false
    }
    
    func loadAnalysisHistory() {
        Task {
            await loadAnalysisHistoryAsync()
        }
    }
    
    /// 异步加载分析历史（可被 await，用于删除后刷新）
    func loadAnalysisHistoryAsync() async {
        do {
            analysisHistory = try await analysisService.getAnalysisHistory()
        } catch {
            errorHandlingService.handleError(error, context: .general)
        }
    }
    
    func deleteProject(_ project: AnalysisProject) async {
        do {
            // 在删除前保存项目 ID，避免删除后访问已失效的 NSManagedObject 导致 crash
            let projectIdToDelete = project.id
            let isDeletingCurrentProject = (currentProject?.id == projectIdToDelete)
            
            // 先从 UI 数据源中移除，避免 ForEach 仍持有已删除对象导致访问 id 时崩溃
            analysisHistory = analysisHistory.filter { $0.id != projectIdToDelete }
            if isDeletingCurrentProject {
                currentProject = nil
            }
            
            // 再执行 Core Data 删除
            try await analysisService.deleteAnalysis(project)
            
            // 可选：重新从数据库拉取一次，保持与持久化一致
            await loadAnalysisHistoryAsync()
        } catch {
            errorHandlingService.handleError(error, context: .general)
        }
    }
    
    // MARK: - File Handling
    
    func handleDroppedFiles(_ urls: [URL]) {
        draggedFiles = urls
        
        Task {
            // Validate file access permissions
            let validationResult = await filePermissionService.validateFileAccess(for: urls)
            
            if !validationResult.isFullyAccessible {
                // Handle permission issues
                let deniedFiles = validationResult.deniedURLs.map { $0.lastPathComponent }.joined(separator: ", ")
                errorMessage = "Access denied to files: \(deniedFiles). Please grant permission to continue."
                return
            }
            
            // Process accessible files
            for url in validationResult.accessibleURLs {
                let pathExtension = url.pathExtension.lowercased()
                
                switch pathExtension {
                case "ipa":
                    selectedIpaPath = url.path
                    saveCachedPaths()
                case "txt":
                    if url.lastPathComponent.lowercased().contains("linkmap") {
                        selectedLinkmapPath = url.path
                        saveCachedPaths()
                    }
                default:
                    if url.hasDirectoryPath {
                        selectedProjectPath = url.path
                        saveCachedPaths()
                    }
                }
            }
        }
    }
    
    /// 从 URL 设置项目路径（用于 SwiftUI .fileImporter 等回调）
    /// 会保存 security-scoped bookmark 并写入缓存
    func setSelectedProjectPath(from url: URL) {
        if filePermissionService.storeSecurityScopedBookmark(for: url) {
            selectedProjectPath = url.path
            saveCachedPaths()
            print("✅ [MainViewModel] Set and cached project path: \(url.path)")
        } else {
            selectedProjectPath = url.path
            saveCachedPaths()
            // bookmark 保存失败仍保留路径（非沙盒环境可能不需要）
        }
    }
    
    /// 从 URL 设置 IPA 路径（用于 SwiftUI .fileImporter 等回调）
    func setSelectedIpaPath(from url: URL) {
        if filePermissionService.storeSecurityScopedBookmark(for: url) {
            selectedIpaPath = url.path
            saveCachedPaths()
            print("✅ [MainViewModel] Set and cached IPA path: \(url.path)")
        } else {
            selectedIpaPath = url.path
            saveCachedPaths()
        }
    }
    
    /// 从 URL 设置 Linkmap 路径（用于 SwiftUI .fileImporter 等回调）
    func setSelectedLinkmapPath(from url: URL) {
        if filePermissionService.storeSecurityScopedBookmark(for: url) {
            selectedLinkmapPath = url.path
            saveCachedPaths()
            print("✅ [MainViewModel] Set and cached linkmap path: \(url.path)")
        } else {
            selectedLinkmapPath = url.path
            saveCachedPaths()
        }
    }
    
    /// 通过 NSOpenPanel 选择项目目录（当前 UI 未使用，保留供其他地方调用）
    func selectProjectPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select project directory for analysis"
        panel.prompt = "Grant Access"
        
        if panel.runModal() == .OK, let url = panel.url {
            setSelectedProjectPath(from: url)
        }
    }
    
    /// 通过 NSOpenPanel 选择 IPA 文件（当前 UI 未使用，保留供其他地方调用）
    func selectIpaFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "ipa") ?? UTType.data]
        panel.message = "Select IPA file for analysis"
        panel.prompt = "Grant Access"
        
        if panel.runModal() == .OK, let url = panel.url {
            setSelectedIpaPath(from: url)
        }
    }
    
    /// 通过 NSOpenPanel 选择 Linkmap 文件（当前 UI 未使用，保留供其他地方调用）
    func selectLinkmapFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.plainText]
        panel.message = "Select linkmap.txt file for analysis"
        panel.prompt = "Grant Access"
        
        if panel.runModal() == .OK, let url = panel.url {
            setSelectedLinkmapPath(from: url)
        }
    }
    
    // MARK: - Export/Import
    
    func exportProject(_ project: AnalysisProject) async throws {
        _ = try await analysisService.exportAnalysisData(project)
        // TODO: Handle the exported data (save to file, show save dialog, etc.)
    }
    
    func importProject(from url: URL) async throws {
        let data = try Data(contentsOf: url)
        let project = try await analysisService.importAnalysisData(data)
        currentProject = project
        await loadAnalysisHistory()
    }
    
    // MARK: - Path Caching Methods
    
    /// 加载缓存的文件路径
    private func loadCachedPaths() {
        isLoadingCachedPaths = true
        defer { isLoadingCachedPaths = false }
        
        let userDefaults = UserDefaults.standard
        
        // 加载项目路径（先恢复 security-scoped bookmark，再验证文件是否存在）
        if let cachedProjectPath = userDefaults.string(forKey: CacheKeys.projectPath) {
            // 先尝试恢复 security-scoped bookmark 访问权限
            let hasAccess = filePermissionService.restoreAccessForCachedPath(cachedProjectPath)
            
            // 检查文件是否存在（如果恢复了访问权限，fileExists 应该能正常工作）
            if hasAccess && FileManager.default.fileExists(atPath: cachedProjectPath) {
                selectedProjectPath = cachedProjectPath
                print("✅ [MainViewModel] Restored cached project path: \(cachedProjectPath)")
            } else if FileManager.default.fileExists(atPath: cachedProjectPath) {
                // 即使没有 bookmark，文件也存在（可能是非沙盒环境或路径在容器内）
                selectedProjectPath = cachedProjectPath
                print("✅ [MainViewModel] Restored cached project path (no bookmark needed): \(cachedProjectPath)")
            } else {
                // 文件不存在或无法访问，清除无效缓存
                print("⚠️ [MainViewModel] Cached project path invalid or inaccessible: \(cachedProjectPath)")
                userDefaults.removeObject(forKey: CacheKeys.projectPath)
            }
        }
        
        // 加载 IPA 路径（先恢复 security-scoped bookmark，再验证文件是否存在）
        if let cachedIpaPath = userDefaults.string(forKey: CacheKeys.ipaPath) {
            // 先尝试恢复 security-scoped bookmark 访问权限
            let hasAccess = filePermissionService.restoreAccessForCachedPath(cachedIpaPath)
            
            // 检查文件是否存在
            if hasAccess && FileManager.default.fileExists(atPath: cachedIpaPath) {
                selectedIpaPath = cachedIpaPath
                print("✅ [MainViewModel] Restored cached IPA path: \(cachedIpaPath)")
            } else if FileManager.default.fileExists(atPath: cachedIpaPath) {
                // 即使没有 bookmark，文件也存在
                selectedIpaPath = cachedIpaPath
                print("✅ [MainViewModel] Restored cached IPA path (no bookmark needed): \(cachedIpaPath)")
            } else {
                // 文件不存在或无法访问，清除无效缓存
                print("⚠️ [MainViewModel] Cached IPA path invalid or inaccessible: \(cachedIpaPath)")
                userDefaults.removeObject(forKey: CacheKeys.ipaPath)
            }
        }
        
        // 加载 Linkmap 路径（先恢复 security-scoped bookmark，再验证文件是否存在）
        if let cachedLinkmapPath = userDefaults.string(forKey: CacheKeys.linkmapPath) {
            // 先尝试恢复 security-scoped bookmark 访问权限
            let hasAccess = filePermissionService.restoreAccessForCachedPath(cachedLinkmapPath)
            
            // 检查文件是否存在
            if hasAccess && FileManager.default.fileExists(atPath: cachedLinkmapPath) {
                selectedLinkmapPath = cachedLinkmapPath
                print("✅ [MainViewModel] Restored cached linkmap path: \(cachedLinkmapPath)")
            } else if FileManager.default.fileExists(atPath: cachedLinkmapPath) {
                // 即使没有 bookmark，文件也存在
                selectedLinkmapPath = cachedLinkmapPath
                print("✅ [MainViewModel] Restored cached linkmap path (no bookmark needed): \(cachedLinkmapPath)")
            } else {
                // 文件不存在或无法访问，清除无效缓存
                print("⚠️ [MainViewModel] Cached linkmap path invalid or inaccessible: \(cachedLinkmapPath)")
                userDefaults.removeObject(forKey: CacheKeys.linkmapPath)
            }
        }
    }
    
    /// 保存文件路径到缓存
    private func saveCachedPaths() {
        // 如果正在加载缓存，不保存（避免循环）
        guard !isLoadingCachedPaths else { return }
        
        let userDefaults = UserDefaults.standard
        
        // 保存项目路径
        if let projectPath = selectedProjectPath {
            userDefaults.set(projectPath, forKey: CacheKeys.projectPath)
        } else {
            userDefaults.removeObject(forKey: CacheKeys.projectPath)
        }
        
        // 保存 IPA 路径
        if let ipaPath = selectedIpaPath {
            userDefaults.set(ipaPath, forKey: CacheKeys.ipaPath)
        } else {
            userDefaults.removeObject(forKey: CacheKeys.ipaPath)
        }
        
        // 保存 Linkmap 路径
        if let linkmapPath = selectedLinkmapPath {
            userDefaults.set(linkmapPath, forKey: CacheKeys.linkmapPath)
        } else {
            userDefaults.removeObject(forKey: CacheKeys.linkmapPath)
        }
        
        userDefaults.synchronize()
    }
    
    /// 清除项目路径并更新缓存
    func clearSelectedProjectPath() {
        selectedProjectPath = nil
        saveCachedPaths()
    }
    
    /// 清除 IPA 路径并更新缓存
    func clearSelectedIpaPath() {
        selectedIpaPath = nil
        saveCachedPaths()
    }
    
    /// 清除 Linkmap 路径并更新缓存
    func clearSelectedLinkmapPath() {
        selectedLinkmapPath = nil
        saveCachedPaths()
    }
    
    /// 清除所有缓存的路径
    func clearCachedPaths() {
        let userDefaults = UserDefaults.standard
        userDefaults.removeObject(forKey: CacheKeys.projectPath)
        userDefaults.removeObject(forKey: CacheKeys.ipaPath)
        userDefaults.removeObject(forKey: CacheKeys.linkmapPath)
        userDefaults.synchronize()
        
        selectedProjectPath = nil
        selectedIpaPath = nil
        selectedLinkmapPath = nil
    }
    
    // MARK: - Analysis Options (persisted in UserDefaults)
    
    private func loadAnalysisOptions() {
        let ud = UserDefaults.standard
        analysisOptions = AnalysisOptions(
            enableCodeDuplicateScan: ud.bool(forKey: CacheKeys.enableCodeDuplicateScan),
            enableResourceDuplicateScan: ud.bool(forKey: CacheKeys.enableResourceDuplicateScan),
            enablePodsDependencyScan: ud.bool(forKey: CacheKeys.enablePodsDependencyScan),
            enableUnusedCodeScan: ud.bool(forKey: CacheKeys.enableUnusedCodeScan),
            enableUnusedResourceScan: ud.bool(forKey: CacheKeys.enableUnusedResourceScan)
        )
        // bool(forKey:) 在 key 不存在时返回 false，与默认值一致，无需额外判断
    }
    
    private func saveAnalysisOptions() {
        let ud = UserDefaults.standard
        ud.set(analysisOptions.enableCodeDuplicateScan, forKey: CacheKeys.enableCodeDuplicateScan)
        ud.set(analysisOptions.enableResourceDuplicateScan, forKey: CacheKeys.enableResourceDuplicateScan)
        ud.set(analysisOptions.enablePodsDependencyScan, forKey: CacheKeys.enablePodsDependencyScan)
        ud.set(analysisOptions.enableUnusedCodeScan, forKey: CacheKeys.enableUnusedCodeScan)
        ud.set(analysisOptions.enableUnusedResourceScan, forKey: CacheKeys.enableUnusedResourceScan)
        ud.synchronize()
    }
    
    func setEnableCodeDuplicateScan(_ value: Bool) {
        analysisOptions.enableCodeDuplicateScan = value
        saveAnalysisOptions()
    }
    
    func setEnableResourceDuplicateScan(_ value: Bool) {
        analysisOptions.enableResourceDuplicateScan = value
        saveAnalysisOptions()
    }
    
    func setEnablePodsDependencyScan(_ value: Bool) {
        analysisOptions.enablePodsDependencyScan = value
        saveAnalysisOptions()
    }

    func setEnableUnusedCodeScan(_ value: Bool) {
        analysisOptions.enableUnusedCodeScan = value
        saveAnalysisOptions()
    }

    func setEnableUnusedResourceScan(_ value: Bool) {
        analysisOptions.enableUnusedResourceScan = value
        saveAnalysisOptions()
    }
    
    // MARK: - Helper Methods
    
    private func generateProjectName(projectPath: String?, ipaPath: String?, linkmapPath: String?) -> String {
        if let projectPath = projectPath {
            return URL(fileURLWithPath: projectPath).lastPathComponent
        } else if let ipaPath = ipaPath {
            return URL(fileURLWithPath: ipaPath).deletingPathExtension().lastPathComponent
        } else if let linkmapPath = linkmapPath {
            return "Linkmap Analysis - \(URL(fileURLWithPath: linkmapPath).deletingPathExtension().lastPathComponent)"
        } else {
            return "Analysis - \(DateFormatter.shortDateTime.string(from: Date()))"
        }
    }
    
    private func createSampleAnalysisData(for project: AnalysisProject) async {
        // Create some sample analysis results for demonstration
        let sampleFiles = [
            ("Sources/ViewModels/MainViewModel.swift", "MainViewModel.swift", "Code", 15000, 0, 0),
            ("Sources/Views/MainView.swift", "MainView.swift", "Code", 8000, 0, 0),
            ("Resources/Images/app-icon.png", "app-icon.png", "Resource", 0, 25000, 0),
            ("Resources/Images/unused-image.png", "unused-image.png", "Resource", 0, 12000, 0),
            ("Frameworks/SomeFramework.framework", "SomeFramework.framework", "Framework", 0, 0, 500000)
        ]
        
        for (relativePath, fileName, fileType, codeSize, resourceSize, frameworkSize) in sampleFiles {
            let result = coreDataManager.createAnalysisResult(
                for: project,
                relativePath: relativePath,
                fileName: fileName,
                fileType: fileType
            )
            result.codeSize = Int64(codeSize)
            result.resourceSize = Int64(resourceSize)
            result.frameworkSize = Int64(frameworkSize)
            
            // Mark unused-image.png as unused resource
            if fileName == "unused-image.png" {
                result.markAsUnusedResource()
            }
            
            project.addAnalysisResult(result)
        }
        
        project.updateTotalSize()
    }
}

// MARK: - Extensions

extension DateFormatter {
    static let shortDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

extension MainViewModel {
    // MARK: - Permission Management
    
    func requestPermissionForFile(at url: URL) async {
        if await filePermissionService.requestFileAccess(for: url) {
            errorMessage = nil
            // Refresh file paths if permission was granted
            if url.hasDirectoryPath {
                selectedProjectPath = url.path
                saveCachedPaths()
            } else {
                let pathExtension = url.pathExtension.lowercased()
                switch pathExtension {
                case "ipa":
                    selectedIpaPath = url.path
                    saveCachedPaths()
                case "txt":
                    if url.lastPathComponent.lowercased().contains("linkmap") {
                        selectedLinkmapPath = url.path
                        saveCachedPaths()
                    }
                default:
                    break
                }
            }
        } else {
            let deniedInfo = filePermissionService.handlePermissionDenied(for: url)
            errorMessage = deniedInfo.errorMessage
        }
    }
    
    func showPermissionRecoveryOptions(for url: URL) -> String {
        let deniedInfo = filePermissionService.handlePermissionDenied(for: url)
        return deniedInfo.recoverySuggestion
    }
    
    var filePermissionStatus: PermissionStatus {
        return filePermissionService.permissionStatus
    }
}
