import SwiftUI
import Foundation

@MainActor
class OptimizationViewModel: ObservableObject {
    @Published var selectedUnusedResources: Set<AnalysisResult> = []
    @Published var selectedUnusedCode: Set<AnalysisResult> = []
    @Published var isOptimizing = false
    @Published var optimizationProgress: Double = 0.0
    @Published var currentOperation: String = ""
    @Published var optimizationResults: OptimizationResults?
    @Published var backupLocation: URL?
    @Published var errorMessage: String?
    
    // Enhanced selection tracking for requirement 4.5
    @Published var selectionSummary: OptimizationSelectionSummary?
    @Published var compressionLevel: CompressionLevel = .balanced
    @Published var enableImageCompression = true
    @Published var enableSafeDelete = true
    
    // Cached optimization estimate to avoid recalculating on every view update
    @Published private(set) var cachedEstimate: OptimizationEstimate?
    
    // MARK: - Dependencies
    
    private let optimizationService: OptimizationServiceProtocol
    
    // MARK: - Initialization
    
    init(optimizationService: OptimizationServiceProtocol) {
        self.optimizationService = optimizationService
    }
    
    // Convenience initializer for backward compatibility
    convenience init() {
        self.init(optimizationService: DependencyContainer.shared.optimizationService)
    }
    
    // MARK: - Selection Methods
    
    func selectAllUnusedResources(from project: AnalysisProject) {
        selectedUnusedResources = Set(project.unusedResources)
        updateSelectionSummary(from: project)
        invalidateEstimateCache()
    }
    
    func selectAllUnusedCode(from project: AnalysisProject) {
        selectedUnusedCode = Set(project.unusedCode)
        updateSelectionSummary(from: project)
        invalidateEstimateCache()
    }
    
    func clearSelection() {
        selectedUnusedResources.removeAll()
        selectedUnusedCode.removeAll()
        selectionSummary = nil
        invalidateEstimateCache()
    }
    
    func toggleResourceSelection(_ resource: AnalysisResult, from project: AnalysisProject) {
        if selectedUnusedResources.contains(resource) {
            selectedUnusedResources.remove(resource)
        } else {
            selectedUnusedResources.insert(resource)
        }
        updateSelectionSummary(from: project)
        invalidateEstimateCache()
    }
    
    func toggleCodeSelection(_ code: AnalysisResult, from project: AnalysisProject) {
        if selectedUnusedCode.contains(code) {
            selectedUnusedCode.remove(code)
        } else {
            selectedUnusedCode.insert(code)
        }
        updateSelectionSummary(from: project)
        invalidateEstimateCache()
    }
    
    func selectResourcesByType(_ resourceType: ResourceType, from project: AnalysisProject) {
        let resourcesOfType = project.unusedResources.filter { result in
            // Determine resource type based on file extension
            let fileExtension = URL(fileURLWithPath: result.fileName).pathExtension.lowercased()
            return getResourceType(from: fileExtension) == resourceType
        }
        
        for resource in resourcesOfType {
            selectedUnusedResources.insert(resource)
        }
        updateSelectionSummary(from: project)
        invalidateEstimateCache()
    }
    
    func selectResourcesBySize(minimumSize: Int64, from project: AnalysisProject) {
        let largeResources = project.unusedResources.filter { $0.resourceSize >= minimumSize }
        for resource in largeResources {
            selectedUnusedResources.insert(resource)
        }
        updateSelectionSummary(from: project)
        invalidateEstimateCache()
    }
    
    func selectCodeByRisk(_ riskLevel: RiskLevel, from project: AnalysisProject) {
        let codeByRisk = project.unusedCode.filter { result in
            // Determine risk based on file type and dependencies
            return getRiskLevel(for: result) == riskLevel
        }
        
        for code in codeByRisk {
            selectedUnusedCode.insert(code)
        }
        updateSelectionSummary(from: project)
        invalidateEstimateCache()
    }
    
    // MARK: - Estimation Methods
    
    func estimateOptimizationSavings() -> OptimizationEstimate {
        // Always calculate fresh estimate to avoid stale cache issues
        // The cache is only used to prevent infinite recursion during view updates
        let resourceSavings = calculateResourceSavings()
        let codeSavings = selectedUnusedCode.reduce(0) { $0 + $1.codeSize }
        let compressionSavings = calculateCompressionSavings()
        let totalSavings = resourceSavings + codeSavings + compressionSavings
        
        let affectedFiles = selectedUnusedResources.count + selectedUnusedCode.count
        
        // Enhanced risk assessment for requirement 4.5
        let riskLevel = calculateOverallRiskLevel()
        let recommendations = generateRecommendations(resourceSavings: resourceSavings, codeSavings: codeSavings, compressionSavings: compressionSavings, totalSavings: totalSavings)
        
        let estimate = OptimizationEstimate(
            estimatedSavings: totalSavings,
            affectedFiles: affectedFiles,
            riskLevel: riskLevel,
            recommendations: recommendations
        )
        
        // Update cache only if it's different to avoid unnecessary view updates
        if cachedEstimate?.estimatedSavings != estimate.estimatedSavings ||
           cachedEstimate?.affectedFiles != estimate.affectedFiles {
            cachedEstimate = estimate
        }
        
        return estimate
    }
    
    func calculateDetailedSavings(from project: AnalysisProject) -> DetailedSavingsBreakdown {
        let originalTotalSize = project.totalSize
        let originalResourceSize = project.totalResourceSize
        let originalCodeSize = project.totalCodeSize
        
        let resourceDeletionSavings = selectedUnusedResources.reduce(0) { $0 + $1.resourceSize }
        let codeDeletionSavings = selectedUnusedCode.reduce(0) { $0 + $1.codeSize }
        let compressionSavings = calculateCompressionSavings()
        
        let totalSavings = resourceDeletionSavings + codeDeletionSavings + compressionSavings
        let finalSize = originalTotalSize - totalSavings
        let savingsPercentage = originalTotalSize > 0 ? Double(totalSavings) / Double(originalTotalSize) * 100 : 0
        
        return DetailedSavingsBreakdown(
            originalSize: originalTotalSize,
            finalSize: finalSize,
            totalSavings: totalSavings,
            savingsPercentage: savingsPercentage,
            resourceDeletionSavings: resourceDeletionSavings,
            codeDeletionSavings: codeDeletionSavings,
            compressionSavings: compressionSavings,
            affectedResourceFiles: selectedUnusedResources.count,
            affectedCodeFiles: selectedUnusedCode.count
        )
    }
    
    private func calculateResourceSavings() -> Int64 {
        if enableSafeDelete {
            return selectedUnusedResources.reduce(0) { $0 + $1.resourceSize }
        }
        return 0
    }
    
    private func calculateCompressionSavings() -> Int64 {
        guard enableImageCompression else { return 0 }
        
        let imageResources = selectedUnusedResources.filter { result in
            let fileExtension = URL(fileURLWithPath: result.fileName).pathExtension.lowercased()
            return ["png", "jpg", "jpeg", "tiff", "bmp"].contains(fileExtension)
        }
        
        let compressionRatio: Double
        switch compressionLevel {
        case .conservative:
            compressionRatio = 0.15 // 15% savings
        case .balanced:
            compressionRatio = 0.30 // 30% savings
        case .aggressive:
            compressionRatio = 0.50 // 50% savings
        }
        
        let totalImageSize = imageResources.reduce(0) { $0 + $1.resourceSize }
        return Int64(Double(totalImageSize) * compressionRatio)
    }
    
    private func calculateOverallRiskLevel() -> RiskLevel {
        let codeRiskFactors = selectedUnusedCode.map { getRiskLevel(for: $0) }
        let hasHighRiskCode = codeRiskFactors.contains(.high)
        let hasMediumRiskCode = codeRiskFactors.contains(.medium)
        
        if hasHighRiskCode || selectedUnusedCode.count > 10 {
            return .high
        } else if hasMediumRiskCode || selectedUnusedCode.count > 5 {
            return .medium
        } else {
            return .low
        }
    }
    
    private func generateRecommendations(resourceSavings: Int64, codeSavings: Int64, compressionSavings: Int64, totalSavings: Int64) -> [String] {
        var recommendations: [String] = []
        
        if !selectedUnusedResources.isEmpty {
            recommendations.append("Create backup before deleting resources")
            
            if selectedUnusedResources.count > 20 {
                recommendations.append("Consider processing resources in smaller batches")
            }
        }
        
        if !selectedUnusedCode.isEmpty {
            recommendations.append("Review code dependencies before deletion")
            recommendations.append("Test thoroughly after code removal")
            
            let highRiskCode = selectedUnusedCode.filter { getRiskLevel(for: $0) == .high }
            if !highRiskCode.isEmpty {
                recommendations.append("High-risk code detected - manual review recommended")
            }
        }
        
        if enableImageCompression && compressionLevel == .aggressive {
            recommendations.append("Aggressive compression may affect image quality")
        }
        
        if totalSavings > 100_000_000 { // > 100MB
            recommendations.append("Large optimization detected - verify available disk space")
        }
        
        return recommendations
    }
    
    // MARK: - Optimization Operations
    
    func performOptimization() async throws {
        // NOTE: Optimization features (image compression, resource/code deletion) are not yet
        // implemented. All operations currently return simulated results without modifying any files.
        throw AnalysisError.invalidFilePath("Optimization features are under development and not yet available.")
    }
    
    func performOptimization_impl() async throws {
        guard !isOptimizing else { return }
        guard !selectedUnusedResources.isEmpty || !selectedUnusedCode.isEmpty else {
            throw AnalysisError.invalidFilePath("No files selected for optimization")
        }
        
        isOptimizing = true
        optimizationProgress = 0.0
        errorMessage = nil
        
        do {
            // Phase 1: Create backup
            currentOperation = "Creating backup..."
            optimizationProgress = 0.1
            let backupURL = try await createBackup()
            
            // Phase 2: Process image compression
            if enableImageCompression {
                currentOperation = "Compressing images..."
                optimizationProgress = 0.2
                let imageResources = Array(selectedUnusedResources.filter { result in
                    let fileExtension = URL(fileURLWithPath: result.fileName).pathExtension.lowercased()
                    return ["png", "jpg", "jpeg", "tiff", "bmp"].contains(fileExtension)
                })
                
                if !imageResources.isEmpty {
                    let compressionResults = try await optimizationService.compressImages(
                        imageResources,
                        compressionLevel: compressionLevel
                    )
                    // Update progress based on compression results
                }
            }
            
            // Phase 3: Process selected resources
            currentOperation = "Processing unused resources..."
            optimizationProgress = 0.4
            let resourceResults = try await optimizationService.deleteUnusedResources(
                Array(selectedUnusedResources),
                createBackup: true
            )
            
            // Phase 4: Process selected code
            currentOperation = "Processing unused code..."
            optimizationProgress = 0.7
            let codeResults = try await optimizationService.deleteUnusedCode(
                Array(selectedUnusedCode),
                projectPath: "", // TODO: Get project path from current project
                createBackup: true
            )
            
            // Phase 5: Calculate final results
            currentOperation = "Finalizing optimization..."
            optimizationProgress = 0.9
            let totalOriginalSize = calculateOriginalSize()
            let totalSavedSize = resourceResults.savedSize + codeResults.savedSize
            let totalProcessedFiles = resourceResults.processedFiles + codeResults.processedFiles
            let allFailedFiles = resourceResults.failedFiles + codeResults.failedFiles
            
            optimizationResults = OptimizationResults(
                originalSize: totalOriginalSize,
                optimizedSize: totalOriginalSize - totalSavedSize,
                savedSize: totalSavedSize,
                processedFiles: totalProcessedFiles,
                failedFiles: allFailedFiles,
                backupLocation: backupURL
            )
            
            currentOperation = "Optimization completed"
            optimizationProgress = 1.0
            
        } catch {
            currentOperation = "Optimization failed"
            errorMessage = error.localizedDescription
            throw error
        }
        
        isOptimizing = false
    }
    
    func createBackup() async throws -> URL {
        guard let project = getCurrentProject() else {
            throw AnalysisError.invalidFilePath("No project available for backup")
        }
        
        let backupURL = try await optimizationService.createBackup(for: project)
        backupLocation = backupURL
        return backupURL
    }
    
    func restoreFromBackup(_ backupUrl: URL) async throws {
        try await optimizationService.restoreFromBackup(backupUrl, to: "")
    }
    
    func resetOptimization() {
        isOptimizing = false
        optimizationProgress = 0.0
        currentOperation = ""
        optimizationResults = nil
        errorMessage = nil
    }
    
    func canPerformOptimization() -> Bool {
        return !selectedUnusedResources.isEmpty || !selectedUnusedCode.isEmpty
    }
    
    // MARK: - Private Helper Methods
    
    private func getCurrentProject() -> AnalysisProject? {
        // TODO: Get current project from MainViewModel or dependency injection
        // For now, return nil - this will be properly wired in the integration
        return nil
    }
    
    private func updateSelectionSummary(from project: AnalysisProject) {
        let totalUnusedResources = project.unusedResources.count
        let totalUnusedCode = project.unusedCode.count
        let selectedResourcesCount = selectedUnusedResources.count
        let selectedCodeCount = selectedUnusedCode.count
        
        let selectedResourceSize = selectedUnusedResources.reduce(0) { $0 + $1.resourceSize }
        let selectedCodeSize = selectedUnusedCode.reduce(0) { $0 + $1.codeSize }
        
        selectionSummary = OptimizationSelectionSummary(
            totalUnusedResources: totalUnusedResources,
            selectedUnusedResources: selectedResourcesCount,
            totalUnusedCode: totalUnusedCode,
            selectedUnusedCode: selectedCodeCount,
            selectedResourceSize: selectedResourceSize,
            selectedCodeSize: selectedCodeSize,
            estimatedSavings: selectedResourceSize + selectedCodeSize
        )
    }
    
    private func processImageCompression() async throws {
        // TODO: Implement actual image compression in future tasks
        // For now, simulate the operation
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
    }
    
    private func processUnusedResources() async throws -> (savedSize: Int64, processedFiles: Int, failedFiles: [String]) {
        var savedSize: Int64 = 0
        var processedFiles = 0
        var failedFiles: [String] = []
        
        let totalResources = selectedUnusedResources.count
        
        for (index, resource) in selectedUnusedResources.enumerated() {
            do {
                // Update progress
                let resourceProgress = Double(index) / Double(totalResources) * 0.3 // 30% of total progress
                optimizationProgress = 0.4 + resourceProgress
                currentOperation = "Processing resource: \(resource.fileName)"
                
                // TODO: Implement actual resource deletion in future tasks
                // For now, simulate the operation
                try await simulateFileOperation(for: resource.relativePath)
                savedSize += resource.resourceSize
                processedFiles += 1
            } catch {
                failedFiles.append(resource.relativePath)
            }
        }
        
        return (savedSize, processedFiles, failedFiles)
    }
    
    private func processUnusedCode() async throws -> (savedSize: Int64, processedFiles: Int, failedFiles: [String]) {
        var savedSize: Int64 = 0
        var processedFiles = 0
        var failedFiles: [String] = []
        
        let totalCode = selectedUnusedCode.count
        
        for (index, code) in selectedUnusedCode.enumerated() {
            do {
                // Update progress
                let codeProgress = Double(index) / Double(totalCode) * 0.3 // 30% of total progress
                optimizationProgress = 0.7 + codeProgress
                currentOperation = "Processing code: \(code.fileName)"
                
                // TODO: Implement actual code deletion in future tasks
                // For now, simulate the operation
                try await simulateFileOperation(for: code.relativePath)
                savedSize += code.codeSize
                processedFiles += 1
            } catch {
                failedFiles.append(code.relativePath)
            }
        }
        
        return (savedSize, processedFiles, failedFiles)
    }
    
    private func calculateOriginalSize() -> Int64 {
        let resourceSize = selectedUnusedResources.reduce(0) { $0 + $1.resourceSize }
        let codeSize = selectedUnusedCode.reduce(0) { $0 + $1.codeSize }
        return resourceSize + codeSize
    }
    
    private func simulateFileOperation(for path: String) async throws {
        // Simulate file operation delay
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Simulate occasional failures for demonstration
        if path.contains("critical") {
            throw AnalysisError.insufficientPermissions(path)
        }
    }
    
    private func getResourceType(from fileExtension: String) -> ResourceType {
        switch fileExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp":
            return .image
        case "mp3", "wav", "aac", "m4a", "flac":
            return .audio
        case "mp4", "mov", "avi", "mkv", "webm":
            return .video
        case "json", "xml", "plist", "txt", "csv":
            return .data
        default:
            return .other
        }
    }
    
    private func getRiskLevel(for analysisResult: AnalysisResult) -> RiskLevel {
        // Determine risk based on file characteristics
        let fileExtension = URL(fileURLWithPath: analysisResult.fileName).pathExtension.lowercased()
        
        // High risk files
        if ["swift", "m", "mm", "h", "hpp", "cpp"].contains(fileExtension) {
            return .high
        }
        
        // Medium risk files
        if ["storyboard", "xib", "plist"].contains(fileExtension) {
            return .medium
        }
        
        // Low risk files (resources)
        return .low
    }
    
    // MARK: - Cache Management
    
    func invalidateEstimateCache() {
        cachedEstimate = nil
    }
}

// MARK: - Supporting Data Structures

struct OptimizationSelectionSummary {
    let totalUnusedResources: Int
    let selectedUnusedResources: Int
    let totalUnusedCode: Int
    let selectedUnusedCode: Int
    let selectedResourceSize: Int64
    let selectedCodeSize: Int64
    let estimatedSavings: Int64
}

struct DetailedSavingsBreakdown {
    let originalSize: Int64
    let finalSize: Int64
    let totalSavings: Int64
    let savingsPercentage: Double
    let resourceDeletionSavings: Int64
    let codeDeletionSavings: Int64
    let compressionSavings: Int64
    let affectedResourceFiles: Int
    let affectedCodeFiles: Int
}