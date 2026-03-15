import Foundation
import CoreData

// MARK: - 历史数据管理器协议
// 负责管理分析历史记录，提供项目历史查询、版本对比候选推荐、
// 数据清理和存储统计等能力。

protocol HistoricalDataManagerProtocol {
    // 分析历史展示
    func getProjectHistory(for projectName: String) async throws -> ProjectHistory?
    func getAllProjectHistories() async throws -> [ProjectHistory]
    func getRecentAnalyses(limit: Int) async throws -> [HistoricalAnalysis]
    func getAnalysisTimeline() async throws -> [SizeDataPoint]
    
    // 项目对比候选
    func getComparableProjects() async throws -> [AnalysisProject]
    func getProjectVersions(for projectName: String) async throws -> [AnalysisProject]
    func suggestComparisonPairs() async throws -> [(AnalysisProject, AnalysisProject)]
    
    // 数据清理接口
    func getCleanupCandidates(olderThan days: Int) async throws -> [AnalysisProject]
    func getStorageStatistics() async throws -> StorageUsage
    func performCleanup(projects: [AnalysisProject]) async throws -> CleanupResult
    func getOrphanedDataCount() async throws -> Int
    
    // Trend analysis
    func calculateProjectTrends(for projectName: String) async throws -> ProjectTrends
    func identifyConsistentUnusedFiles() async throws -> [String]
    func generateStorageRecommendations() async throws -> [StorageRecommendation]
}

class HistoricalDataManager: HistoricalDataManagerProtocol {
    private let coreDataManager: CoreDataManagerProtocol
    
    init(coreDataManager: CoreDataManagerProtocol = CoreDataManager.shared) {
        self.coreDataManager = coreDataManager
    }
    
    // MARK: - Analysis History Display
    
    func getProjectHistory(for projectName: String) async throws -> ProjectHistory? {
        let projects = try await coreDataManager.fetchAnalysisProjects(withName: projectName)
        guard !projects.isEmpty else { return nil }
        
        let analyses = projects.map { project in
            HistoricalAnalysis(
                project: project,
                analysisDate: project.createdAt,
                summary: createAnalysisSummary(from: project)
            )
        }.sorted { $0.analysisDate < $1.analysisDate }
        
        let sizeProgression = analyses.map { analysis in
            SizeDataPoint(
                date: analysis.analysisDate,
                totalSize: analysis.summary.totalSize,
                codeSize: analysis.summary.codeSize,
                resourceSize: analysis.summary.resourceSize,
                frameworkSize: analysis.summary.frameworkSize
            )
        }
        
        let trends = try await calculateProjectTrends(for: projectName)
        
        return ProjectHistory(
            projectName: projectName,
            analyses: analyses,
            sizeProgression: sizeProgression,
            trends: trends
        )
    }
    
    func getAllProjectHistories() async throws -> [ProjectHistory] {
        let allProjects = try await coreDataManager.fetchAllAnalysisProjects()
        let projectsByName = Dictionary(grouping: allProjects) { $0.name }
        
        var histories: [ProjectHistory] = []
        
        for (projectName, projects) in projectsByName {
            if let history = try await getProjectHistory(for: projectName) {
                histories.append(history)
            }
        }
        
        return histories.sorted { $0.projectName < $1.projectName }
    }
    
    func getRecentAnalyses(limit: Int) async throws -> [HistoricalAnalysis] {
        let allProjects = try await coreDataManager.fetchAllAnalysisProjects()
        let recentProjects = Array(allProjects.prefix(limit))
        
        return recentProjects.map { project in
            HistoricalAnalysis(
                project: project,
                analysisDate: project.createdAt,
                summary: createAnalysisSummary(from: project)
            )
        }
    }
    
    func getAnalysisTimeline() async throws -> [SizeDataPoint] {
        let allProjects = try await coreDataManager.fetchAllAnalysisProjects()
        
        return allProjects.map { project in
            SizeDataPoint(
                date: project.createdAt,
                totalSize: project.totalSize,
                codeSize: project.totalCodeSize,
                resourceSize: project.totalResourceSize,
                frameworkSize: project.totalFrameworkSize
            )
        }.sorted { $0.date < $1.date }
    }
    
    // MARK: - Project Comparison Selection
    
    func getComparableProjects() async throws -> [AnalysisProject] {
        let allProjects = try await coreDataManager.fetchAllAnalysisProjects()
        
        // Filter projects that have sufficient data for comparison
        return allProjects.filter { project in
            project.analysisResultsArray.count > 0 && project.totalSize > 0
        }
    }
    
    func getProjectVersions(for projectName: String) async throws -> [AnalysisProject] {
        let projects = try await coreDataManager.fetchAnalysisProjects(withName: projectName)
        return projects.sorted { $0.createdAt < $1.createdAt }
    }
    
    func suggestComparisonPairs() async throws -> [(AnalysisProject, AnalysisProject)] {
        let projectsByName = Dictionary(grouping: try await getComparableProjects()) { $0.name }
        var suggestions: [(AnalysisProject, AnalysisProject)] = []
        
        for (_, projects) in projectsByName {
            if projects.count >= 2 {
                let sortedProjects = projects.sorted { $0.createdAt < $1.createdAt }
                // Suggest comparing the most recent with the previous version
                if sortedProjects.count >= 2 {
                    let recent = sortedProjects[sortedProjects.count - 1]
                    let previous = sortedProjects[sortedProjects.count - 2]
                    suggestions.append((previous, recent))
                }
            }
        }
        
        return suggestions
    }
    
    // MARK: - Data Cleanup Interface
    
    func getCleanupCandidates(olderThan days: Int) async throws -> [AnalysisProject] {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let oldProjects = try await coreDataManager.fetchAnalysisProjects(createdAfter: Date.distantPast)
        
        return oldProjects.filter { $0.createdAt < cutoffDate }
    }
    
    func getStorageStatistics() async throws -> StorageUsage {
        return try await coreDataManager.calculateStorageUsage()
    }
    
    func performCleanup(projects: [AnalysisProject]) async throws -> CleanupResult {
        var deletedCount = 0
        var failedDeletions: [String] = []
        var freedSpace: Int64 = 0
        
        for project in projects {
            do {
                freedSpace += project.totalSize
                try await coreDataManager.deleteAnalysisProject(project)
                deletedCount += 1
            } catch {
                failedDeletions.append("Failed to delete \(project.name): \(error.localizedDescription)")
            }
        }
        
        // Clean up orphaned data
        let orphanedCount = try await coreDataManager.cleanupOrphanedAnalysisResults()
        
        // Compact database
        try await coreDataManager.compactDatabase()
        
        return CleanupResult(
            deletedProjects: deletedCount,
            orphanedResultsRemoved: orphanedCount,
            estimatedSpaceFreed: freedSpace,
            errors: failedDeletions
        )
    }
    
    func getOrphanedDataCount() async throws -> Int {
        // This would require a custom fetch request to count orphaned results
        // For now, we'll return 0 as the CoreDataManager handles this
        return 0
    }
    
    // MARK: - Trend Analysis
    
    func calculateProjectTrends(for projectName: String) async throws -> ProjectTrends {
        let projects = try await getProjectVersions(for: projectName)
        guard projects.count >= 2 else {
            return ProjectTrends(
                overallTrend: .stable,
                codeTrend: .stable,
                resourceTrend: .stable,
                frameworkTrend: .stable,
                averageGrowthRate: 0.0,
                projectedSize: nil
            )
        }
        
        let sizeData = projects.map { project in
            (
                date: project.createdAt,
                totalSize: project.totalSize,
                codeSize: project.totalCodeSize,
                resourceSize: project.totalResourceSize,
                frameworkSize: project.totalFrameworkSize
            )
        }.sorted { $0.date < $1.date }
        
        let overallTrend = calculateTrend(sizeData.map { $0.totalSize })
        let codeTrend = calculateTrend(sizeData.map { $0.codeSize })
        let resourceTrend = calculateTrend(sizeData.map { $0.resourceSize })
        let frameworkTrend = calculateTrend(sizeData.map { $0.frameworkSize })
        
        let averageGrowthRate = calculateAverageGrowthRate(sizeData.map { $0.totalSize })
        let projectedSize = calculateProjectedSize(sizeData.map { ($0.date, $0.totalSize) })
        
        return ProjectTrends(
            overallTrend: overallTrend,
            codeTrend: codeTrend,
            resourceTrend: resourceTrend,
            frameworkTrend: frameworkTrend,
            averageGrowthRate: averageGrowthRate,
            projectedSize: projectedSize
        )
    }
    
    func identifyConsistentUnusedFiles() async throws -> [String] {
        let allProjects = try await coreDataManager.fetchAllAnalysisProjects()
        var fileUsageCount: [String: (unused: Int, total: Int)] = [:]
        
        for project in allProjects {
            for result in project.analysisResultsArray {
                let filePath = result.relativePath
                let current = fileUsageCount[filePath] ?? (unused: 0, total: 0)
                fileUsageCount[filePath] = (
                    unused: current.unused + (result.isUnused ? 1 : 0),
                    total: current.total + 1
                )
            }
        }
        
        // Return files that are unused in at least 80% of projects
        return fileUsageCount.compactMap { (filePath, counts) in
            let unusedPercentage = Double(counts.unused) / Double(counts.total)
            return unusedPercentage >= 0.8 ? filePath : nil
        }.sorted()
    }
    
    func generateStorageRecommendations() async throws -> [StorageRecommendation] {
        let storageUsage = try await getStorageStatistics()
        var recommendations: [StorageRecommendation] = []
        
        // Recommend cleanup if there are many old projects
        if storageUsage.totalProjects > 50 {
            recommendations.append(StorageRecommendation(
                type: .cleanup,
                priority: .medium,
                description: "Consider cleaning up old analysis projects to free space",
                estimatedSavings: storageUsage.estimatedDatabaseSize / 4,
                action: "Delete projects older than 90 days"
            ))
        }
        
        // Recommend archiving if database is large
        if storageUsage.estimatedDatabaseSize > 100_000_000 { // 100MB
            recommendations.append(StorageRecommendation(
                type: .archive,
                priority: .high,
                description: "Database size is large, consider archiving old data",
                estimatedSavings: storageUsage.estimatedDatabaseSize / 2,
                action: "Export and archive projects older than 6 months"
            ))
        }
        
        // Recommend optimization if there are many small projects
        if storageUsage.averageProjectSize < 1000 && storageUsage.totalProjects > 20 {
            recommendations.append(StorageRecommendation(
                type: .optimization,
                priority: .low,
                description: "Many small projects detected, consider consolidating",
                estimatedSavings: storageUsage.estimatedDatabaseSize / 10,
                action: "Review and consolidate similar small projects"
            ))
        }
        
        return recommendations
    }
    
    // MARK: - Helper Methods
    
    private func createAnalysisSummary(from project: AnalysisProject) -> AnalysisSummary {
        return AnalysisSummary(
            totalSize: project.totalSize,
            codeSize: project.totalCodeSize,
            resourceSize: project.totalResourceSize,
            frameworkSize: project.totalFrameworkSize,
            unusedResourceSize: project.unusedResourceSize,
            unusedCodeSize: project.unusedCodeSize,
            potentialSavings: project.potentialSavings
        )
    }
    
    private func calculateTrend(_ values: [Int64]) -> TrendDirection {
        guard values.count >= 2 else { return .stable }
        
        let first = values.first!
        let last = values.last!
        let change = Double(last - first) / Double(first)
        
        if change > 0.05 { // 5% increase
            return .increasing
        } else if change < -0.05 { // 5% decrease
            return .decreasing
        } else {
            return .stable
        }
    }
    
    private func calculateAverageGrowthRate(_ values: [Int64]) -> Double {
        guard values.count >= 2 else { return 0.0 }
        
        var totalGrowthRate = 0.0
        var validPairs = 0
        
        for i in 1..<values.count {
            let previous = values[i-1]
            let current = values[i]
            
            if previous > 0 {
                let growthRate = Double(current - previous) / Double(previous)
                totalGrowthRate += growthRate
                validPairs += 1
            }
        }
        
        return validPairs > 0 ? totalGrowthRate / Double(validPairs) : 0.0
    }
    
    private func calculateProjectedSize(_ dataPoints: [(Date, Int64)]) -> Int64? {
        guard dataPoints.count >= 3 else { return nil }
        
        // Simple linear projection based on the last 3 data points
        let recentPoints = Array(dataPoints.suffix(3))
        let timeIntervals = recentPoints.enumerated().map { index, point in
            Double(index)
        }
        let sizes = recentPoints.map { Double($0.1) }
        
        // Calculate linear regression
        let n = Double(recentPoints.count)
        let sumX = timeIntervals.reduce(0, +)
        let sumY = sizes.reduce(0, +)
        let sumXY = zip(timeIntervals, sizes).map(*).reduce(0, +)
        let sumXX = timeIntervals.map { $0 * $0 }.reduce(0, +)
        
        let slope = (n * sumXY - sumX * sumY) / (n * sumXX - sumX * sumX)
        let intercept = (sumY - slope * sumX) / n
        
        // Project 30 days into the future
        let futureX = Double(recentPoints.count)
        let projectedSize = slope * futureX + intercept
        
        return Int64(max(0, projectedSize))
    }
}

// MARK: - Supporting Data Structures

struct CleanupResult {
    let deletedProjects: Int
    let orphanedResultsRemoved: Int
    let estimatedSpaceFreed: Int64
    let errors: [String]
}

struct StorageRecommendation {
    let type: RecommendationType
    let priority: RecommendationPriority
    let description: String
    let estimatedSavings: Int64
    let action: String
}

enum RecommendationType {
    case cleanup, archive, optimization
}

enum RecommendationPriority {
    case low, medium, high
}