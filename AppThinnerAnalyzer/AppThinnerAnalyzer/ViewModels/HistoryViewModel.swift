import Foundation
import SwiftUI

@MainActor
class HistoryViewModel: ObservableObject {
    @Published var projectHistories: [ProjectHistory] = []
    @Published var recentAnalyses: [HistoricalAnalysis] = []
    @Published var analysisTimeline: [SizeDataPoint] = []
    @Published var storageUsage: StorageUsage?
    @Published var storageRecommendations: [StorageRecommendation] = []
    @Published var cleanupCandidates: [AnalysisProject] = []
    @Published var selectedCleanupProjects: Set<UUID> = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastCleanupResult: CleanupResult?
    
    // MARK: - Dependencies
    
    private let historicalDataManager: HistoricalDataManagerProtocol
    private let coreDataManager: CoreDataManagerProtocol
    
    // MARK: - Initialization
    
    init(
        historicalDataManager: HistoricalDataManagerProtocol,
        coreDataManager: CoreDataManagerProtocol
    ) {
        self.historicalDataManager = historicalDataManager
        self.coreDataManager = coreDataManager
    }
    
    // Convenience initializer for backward compatibility
    convenience init() {
        let container = DependencyContainer.shared
        self.init(
            historicalDataManager: container.historicalDataManager,
            coreDataManager: container.coreDataManager
        )
    }
    
    // MARK: - Data Loading
    
    func loadHistoricalData() async {
        isLoading = true
        errorMessage = nil
        
        do {
            async let histories = historicalDataManager.getAllProjectHistories()
            async let recent = historicalDataManager.getRecentAnalyses(limit: 10)
            async let timeline = historicalDataManager.getAnalysisTimeline()
            async let storage = historicalDataManager.getStorageStatistics()
            async let recommendations = historicalDataManager.generateStorageRecommendations()
            
            projectHistories = try await histories
            recentAnalyses = try await recent
            analysisTimeline = try await timeline
            storageUsage = try await storage
            storageRecommendations = try await recommendations
            
        } catch {
            errorMessage = "Failed to load historical data: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func loadProjectHistory(for projectName: String) async -> ProjectHistory? {
        do {
            return try await historicalDataManager.getProjectHistory(for: projectName)
        } catch {
            errorMessage = "Failed to load project history: \(error.localizedDescription)"
            return nil
        }
    }
    
    func loadCleanupCandidates(olderThan days: Int) async {
        do {
            cleanupCandidates = try await historicalDataManager.getCleanupCandidates(olderThan: days)
        } catch {
            errorMessage = "Failed to load cleanup candidates: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Cleanup Management
    
    func toggleCleanupSelection(_ project: AnalysisProject) {
        if selectedCleanupProjects.contains(project.id) {
            selectedCleanupProjects.remove(project.id)
        } else {
            selectedCleanupProjects.insert(project.id)
        }
    }
    
    func selectAllCleanupCandidates() {
        selectedCleanupProjects = Set(cleanupCandidates.map { $0.id })
    }
    
    func clearCleanupSelection() {
        selectedCleanupProjects.removeAll()
    }
    
    func performCleanup() async {
        let projectsToDelete = cleanupCandidates.filter { selectedCleanupProjects.contains($0.id) }
        
        guard !projectsToDelete.isEmpty else {
            errorMessage = "No projects selected for cleanup"
            return
        }
        
        isLoading = true
        
        do {
            let result = try await historicalDataManager.performCleanup(projects: projectsToDelete)
            lastCleanupResult = result
            
            // Refresh data after cleanup
            await loadHistoricalData()
            await loadCleanupCandidates(olderThan: 90) // Refresh with default value
            
            selectedCleanupProjects.removeAll()
            
        } catch {
            errorMessage = "Cleanup failed: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    // MARK: - Export Functionality
    
    func exportData(all: Bool, from startDate: Date, to endDate: Date) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let data: Data
            if all {
                data = try await coreDataManager.exportAllAnalysisProjects()
            } else {
                data = try await coreDataManager.exportAnalysisProjectsInDateRange(from: startDate, to: endDate)
            }
            
            // Save to file
            let fileName = all ? "all_projects_export.json" : "projects_export_\(startDate.formatted(date: .abbreviated, time: .omitted))_to_\(endDate.formatted(date: .abbreviated, time: .omitted)).json"
            await saveExportData(data, fileName: fileName)
            
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func saveExportData(_ data: Data, fileName: String) async {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL)
            // In a real app, you might want to show a save panel or share sheet
            print("Export saved to: \(fileURL.path)")
        } catch {
            errorMessage = "Failed to save export file: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Comparison Helpers
    
    func getComparableProjects() async -> [AnalysisProject] {
        do {
            return try await historicalDataManager.getComparableProjects()
        } catch {
            errorMessage = "Failed to load comparable projects: \(error.localizedDescription)"
            return []
        }
    }
    
    func getProjectVersions(for projectName: String) async -> [AnalysisProject] {
        do {
            return try await historicalDataManager.getProjectVersions(for: projectName)
        } catch {
            errorMessage = "Failed to load project versions: \(error.localizedDescription)"
            return []
        }
    }
    
    func getSuggestedComparisons() async -> [(AnalysisProject, AnalysisProject)] {
        do {
            return try await historicalDataManager.suggestComparisonPairs()
        } catch {
            errorMessage = "Failed to load suggested comparisons: \(error.localizedDescription)"
            return []
        }
    }
    
    // MARK: - Trend Analysis
    
    func getProjectTrends(for projectName: String) async -> ProjectTrends? {
        do {
            return try await historicalDataManager.calculateProjectTrends(for: projectName)
        } catch {
            errorMessage = "Failed to calculate project trends: \(error.localizedDescription)"
            return nil
        }
    }
    
    func getConsistentUnusedFiles() async -> [String] {
        do {
            return try await historicalDataManager.identifyConsistentUnusedFiles()
        } catch {
            errorMessage = "Failed to identify consistent unused files: \(error.localizedDescription)"
            return []
        }
    }
    
    // MARK: - Storage Management
    
    func refreshStorageStatistics() async {
        do {
            storageUsage = try await historicalDataManager.getStorageStatistics()
            storageRecommendations = try await historicalDataManager.generateStorageRecommendations()
        } catch {
            errorMessage = "Failed to refresh storage statistics: \(error.localizedDescription)"
        }
    }
    
    func compactDatabase() async {
        isLoading = true
        
        do {
            try await coreDataManager.compactDatabase()
            await refreshStorageStatistics()
        } catch {
            errorMessage = "Failed to compact database: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    // MARK: - Utility Methods
    
    func clearError() {
        errorMessage = nil
    }
    
    func formatFileSize(_ bytes: Int64) -> String {
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    
    func formatDate(_ date: Date) -> String {
        return date.formatted(date: .abbreviated, time: .shortened)
    }
    
    func formatPercentage(_ value: Double) -> String {
        return String(format: "%.1f%%", value * 100)
    }
    
    // MARK: - Search and Filtering
    
    func searchProjects(query: String) -> [ProjectHistory] {
        guard !query.isEmpty else { return projectHistories }
        
        return projectHistories.filter { history in
            history.projectName.localizedCaseInsensitiveContains(query)
        }
    }
    
    func filterProjectsByDateRange(from startDate: Date, to endDate: Date) -> [ProjectHistory] {
        return projectHistories.filter { history in
            let latestAnalysis = history.analyses.max(by: { $0.analysisDate < $1.analysisDate })
            guard let latest = latestAnalysis else { return false }
            return latest.analysisDate >= startDate && latest.analysisDate <= endDate
        }
    }
    
    func filterProjectsByTrend(_ trendDirection: TrendDirection) -> [ProjectHistory] {
        return projectHistories.filter { history in
            history.trends.overallTrend == trendDirection
        }
    }
    
    // MARK: - Statistics
    
    func calculateTotalSavingsPotential() -> Int64 {
        return recentAnalyses.reduce(0) { total, analysis in
            total + analysis.summary.potentialSavings
        }
    }
    
    func calculateAverageProjectSize() -> Int64 {
        guard !recentAnalyses.isEmpty else { return 0 }
        
        let totalSize = recentAnalyses.reduce(0) { total, analysis in
            total + analysis.summary.totalSize
        }
        
        return totalSize / Int64(recentAnalyses.count)
    }
    
    func getMostActiveProject() -> String? {
        let projectCounts = Dictionary(grouping: recentAnalyses) { $0.project.name }
            .mapValues { $0.count }
        
        return projectCounts.max(by: { $0.value < $1.value })?.key
    }
    
    func getLargestProject() -> HistoricalAnalysis? {
        return recentAnalyses.max(by: { $0.summary.totalSize < $1.summary.totalSize })
    }
}