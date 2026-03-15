import Foundation
import CoreData

// MARK: - 对比服务协议
// 负责对两个或多个分析项目进行体积对比，生成差异报告、趋势分析，
// 并支持导出对比报告。

protocol ComparisonServiceProtocol {
    /// 对比两个项目，返回文件级差异（新增/删除/修改）
    func compareProjects(
        _ project1: AnalysisProject,
        _ project2: AnalysisProject
    ) async throws -> ProjectComparison
    
    /// 对比多个项目，返回多维度对比结果
    func compareMultipleProjects(
        _ projects: [AnalysisProject]
    ) async throws -> MultiProjectComparison
    
    /// 生成体积趋势分析（按时间排序）
    func generateTrendAnalysis(
        for projects: [AnalysisProject]
    ) async throws -> [SizeTrend]
    
    /// 导出对比报告为 HTML 文件
    func exportComparisonReport(
        _ comparison: ProjectComparison
    ) async throws -> URL
}

// MARK: - 对比服务实现

class ComparisonService: ComparisonServiceProtocol {
    
    private let coreDataManager: CoreDataManagerProtocol
    
    init(coreDataManager: CoreDataManagerProtocol) {
        self.coreDataManager = coreDataManager
    }
    
    // MARK: - Public Methods
    
    func compareProjects(
        _ project1: AnalysisProject,
        _ project2: AnalysisProject
    ) async throws -> ProjectComparison {
        
        let sizeChanges = try await calculateSizeChanges(from: project1, to: project2)
        let fileChanges = try await calculateFileChanges(from: project1, to: project2)
        let newFiles = try await identifyNewFiles(from: project1, to: project2)
        let removedFiles = try await identifyRemovedFiles(from: project1, to: project2)
        let summary = generateComparisonSummary(
            sizeChanges: sizeChanges,
            fileChanges: fileChanges,
            newFiles: newFiles,
            removedFiles: removedFiles
        )
        
        return ProjectComparison(
            projects: [project1, project2],
            sizeChanges: sizeChanges,
            newFiles: newFiles,
            removedFiles: removedFiles,
            modifiedFiles: fileChanges,
            summary: summary
        )
    }
    
    func compareMultipleProjects(
        _ projects: [AnalysisProject]
    ) async throws -> MultiProjectComparison {
        
        guard projects.count >= 2 else {
            throw AnalysisError.invalidFilePath("At least 2 projects required for comparison")
        }
        
        let sortedProjects = projects.sorted { $0.createdAt < $1.createdAt }
        let trends = try await generateTrendAnalysis(for: sortedProjects)
        let consistentUnusedFiles = try await findConsistentUnusedFiles(in: sortedProjects)
        let recommendations = try await generateMultiProjectRecommendations(
            projects: sortedProjects,
            trends: trends,
            consistentUnusedFiles: consistentUnusedFiles
        )
        
        return MultiProjectComparison(
            projects: sortedProjects,
            trends: trends,
            consistentUnusedFiles: consistentUnusedFiles,
            recommendations: recommendations
        )
    }
    
    func generateTrendAnalysis(
        for projects: [AnalysisProject]
    ) async throws -> [SizeTrend] {
        
        guard projects.count >= 2 else {
            return []
        }
        
        let sortedProjects = projects.sorted { $0.createdAt < $1.createdAt }
        
        var trends: [SizeTrend] = []
        
        // Total Size Trend
        let totalSizeDataPoints = sortedProjects.map { ($0.createdAt, $0.totalSize) }
        trends.append(SizeTrend(
            category: "Total Size",
            dataPoints: totalSizeDataPoints,
            trend: calculateTrendDirection(dataPoints: totalSizeDataPoints),
            averageChange: calculateAverageChange(dataPoints: totalSizeDataPoints)
        ))
        
        // Code Size Trend
        let codeSizeDataPoints = try await calculateCategorySizeDataPoints(
            projects: sortedProjects,
            category: "Code"
        )
        trends.append(SizeTrend(
            category: "Code Size",
            dataPoints: codeSizeDataPoints,
            trend: calculateTrendDirection(dataPoints: codeSizeDataPoints),
            averageChange: calculateAverageChange(dataPoints: codeSizeDataPoints)
        ))
        
        // Resource Size Trend
        let resourceSizeDataPoints = try await calculateCategorySizeDataPoints(
            projects: sortedProjects,
            category: "Resource"
        )
        trends.append(SizeTrend(
            category: "Resource Size",
            dataPoints: resourceSizeDataPoints,
            trend: calculateTrendDirection(dataPoints: resourceSizeDataPoints),
            averageChange: calculateAverageChange(dataPoints: resourceSizeDataPoints)
        ))
        
        // Framework Size Trend
        let frameworkSizeDataPoints = try await calculateCategorySizeDataPoints(
            projects: sortedProjects,
            category: "Framework"
        )
        trends.append(SizeTrend(
            category: "Framework Size",
            dataPoints: frameworkSizeDataPoints,
            trend: calculateTrendDirection(dataPoints: frameworkSizeDataPoints),
            averageChange: calculateAverageChange(dataPoints: frameworkSizeDataPoints)
        ))
        
        // Unused Content Trend
        let unusedSizeDataPoints = try await calculateUnusedContentDataPoints(projects: sortedProjects)
        trends.append(SizeTrend(
            category: "Unused Content",
            dataPoints: unusedSizeDataPoints,
            trend: calculateTrendDirection(dataPoints: unusedSizeDataPoints),
            averageChange: calculateAverageChange(dataPoints: unusedSizeDataPoints)
        ))
        
        return trends
    }
    
    func exportComparisonReport(
        _ comparison: ProjectComparison
    ) async throws -> URL {
        // Use a fresh ReportGenerator instance for exporting comparison reports.
        let generator = ReportGenerator()
        return try await generator.generateComparisonReport(comparison)
    }
    
    // MARK: - Private Methods - Size Changes
    
    private func calculateSizeChanges(
        from project1: AnalysisProject,
        to project2: AnalysisProject
    ) async throws -> [SizeChange] {
        
        let results1 = project1.analysisResults?.allObjects as? [AnalysisResult] ?? []
        let results2 = project2.analysisResults?.allObjects as? [AnalysisResult] ?? []
        
        let summary1 = calculateProjectSummary(from: results1)
        let summary2 = calculateProjectSummary(from: results2)
        
        var sizeChanges: [SizeChange] = []
        
        // Total Size Change
        sizeChanges.append(SizeChange(
            category: "Total Size",
            oldSize: summary1.totalSize,
            newSize: summary2.totalSize,
            change: summary2.totalSize - summary1.totalSize,
            changePercentage: calculatePercentageChange(
                from: summary1.totalSize,
                to: summary2.totalSize
            )
        ))
        
        // Code Size Change
        sizeChanges.append(SizeChange(
            category: "Code Size",
            oldSize: summary1.codeSize,
            newSize: summary2.codeSize,
            change: summary2.codeSize - summary1.codeSize,
            changePercentage: calculatePercentageChange(
                from: summary1.codeSize,
                to: summary2.codeSize
            )
        ))
        
        // Resource Size Change
        sizeChanges.append(SizeChange(
            category: "Resource Size",
            oldSize: summary1.resourceSize,
            newSize: summary2.resourceSize,
            change: summary2.resourceSize - summary1.resourceSize,
            changePercentage: calculatePercentageChange(
                from: summary1.resourceSize,
                to: summary2.resourceSize
            )
        ))
        
        // Framework Size Change
        sizeChanges.append(SizeChange(
            category: "Framework Size",
            oldSize: summary1.frameworkSize,
            newSize: summary2.frameworkSize,
            change: summary2.frameworkSize - summary1.frameworkSize,
            changePercentage: calculatePercentageChange(
                from: summary1.frameworkSize,
                to: summary2.frameworkSize
            )
        ))
        
        // Unused Content Change
        sizeChanges.append(SizeChange(
            category: "Unused Content",
            oldSize: summary1.unusedResourceSize + summary1.unusedCodeSize,
            newSize: summary2.unusedResourceSize + summary2.unusedCodeSize,
            change: (summary2.unusedResourceSize + summary2.unusedCodeSize) - 
                   (summary1.unusedResourceSize + summary1.unusedCodeSize),
            changePercentage: calculatePercentageChange(
                from: summary1.unusedResourceSize + summary1.unusedCodeSize,
                to: summary2.unusedResourceSize + summary2.unusedCodeSize
            )
        ))
        
        return sizeChanges
    }
    
    private func calculateFileChanges(
        from project1: AnalysisProject,
        to project2: AnalysisProject
    ) async throws -> [FileChange] {
        
        let results1 = project1.analysisResults?.allObjects as? [AnalysisResult] ?? []
        let results2 = project2.analysisResults?.allObjects as? [AnalysisResult] ?? []
        
        let fileMap1 = Dictionary(uniqueKeysWithValues: results1.map { ($0.relativePath, $0) })
        let fileMap2 = Dictionary(uniqueKeysWithValues: results2.map { ($0.relativePath, $0) })
        
        var fileChanges: [FileChange] = []
        
        // Find modified files
        for (path, result1) in fileMap1 {
            if let result2 = fileMap2[path] {
                let oldSize = result1.codeSize + result1.resourceSize + result1.frameworkSize
                let newSize = result2.codeSize + result2.resourceSize + result2.frameworkSize
                
                if oldSize != newSize {
                    fileChanges.append(FileChange(
                        filePath: path,
                        oldSize: oldSize,
                        newSize: newSize,
                        changeType: .modified
                    ))
                } else {
                    fileChanges.append(FileChange(
                        filePath: path,
                        oldSize: oldSize,
                        newSize: newSize,
                        changeType: .unchanged
                    ))
                }
            } else {
                // File was removed
                let oldSize = result1.codeSize + result1.resourceSize + result1.frameworkSize
                fileChanges.append(FileChange(
                    filePath: path,
                    oldSize: oldSize,
                    newSize: 0,
                    changeType: .removed
                ))
            }
        }
        
        // Find added files
        for (path, result2) in fileMap2 {
            if fileMap1[path] == nil {
                let newSize = result2.codeSize + result2.resourceSize + result2.frameworkSize
                fileChanges.append(FileChange(
                    filePath: path,
                    oldSize: 0,
                    newSize: newSize,
                    changeType: .added
                ))
            }
        }
        
        return fileChanges.sorted { $0.filePath < $1.filePath }
    }
    
    private func identifyNewFiles(
        from project1: AnalysisProject,
        to project2: AnalysisProject
    ) async throws -> [String] {
        
        let results1 = project1.analysisResults?.allObjects as? [AnalysisResult] ?? []
        let results2 = project2.analysisResults?.allObjects as? [AnalysisResult] ?? []
        
        let paths1 = Set(results1.map { $0.relativePath })
        let paths2 = Set(results2.map { $0.relativePath })
        
        return Array(paths2.subtracting(paths1)).sorted()
    }
    
    private func identifyRemovedFiles(
        from project1: AnalysisProject,
        to project2: AnalysisProject
    ) async throws -> [String] {
        
        let results1 = project1.analysisResults?.allObjects as? [AnalysisResult] ?? []
        let results2 = project2.analysisResults?.allObjects as? [AnalysisResult] ?? []
        
        let paths1 = Set(results1.map { $0.relativePath })
        let paths2 = Set(results2.map { $0.relativePath })
        
        return Array(paths1.subtracting(paths2)).sorted()
    }
    
    // MARK: - Private Methods - Multi-Project Analysis
    
    private func findConsistentUnusedFiles(in projects: [AnalysisProject]) async throws -> [String] {
        guard !projects.isEmpty else { return [] }
        
        var unusedFileSets: [Set<String>] = []
        
        for project in projects {
            let results = project.analysisResults?.allObjects as? [AnalysisResult] ?? []
            let unusedFiles = results
                .filter { $0.isUnusedResource || $0.isUnusedCode }
                .map { $0.relativePath }
            unusedFileSets.append(Set(unusedFiles))
        }
        
        // Find intersection of all sets (files that are unused in ALL projects)
        guard let firstSet = unusedFileSets.first else { return [] }
        
        let consistentUnusedFiles = unusedFileSets.dropFirst().reduce(firstSet) { result, set in
            result.intersection(set)
        }
        
        return Array(consistentUnusedFiles).sorted()
    }
    
    private func generateMultiProjectRecommendations(
        projects: [AnalysisProject],
        trends: [SizeTrend],
        consistentUnusedFiles: [String]
    ) async throws -> [String] {
        
        var recommendations: [String] = []
        
        // Analyze trends
        for trend in trends {
            switch trend.trend {
            case .increasing:
                if trend.averageChange > 1_000_000 { // > 1 MB (SI) average increase
                    recommendations.append("⚠️ \(trend.category) is consistently increasing by \(ByteCountFormatter.string(fromByteCount: Int64(trend.averageChange), countStyle: .file)) on average. Consider investigating the cause.")
                }
            case .decreasing:
                if trend.averageChange < -1_000_000 { // > 1 MB (SI) average decrease
                    recommendations.append("✅ \(trend.category) is consistently decreasing by \(ByteCountFormatter.string(fromByteCount: Int64(-trend.averageChange), countStyle: .file)) on average. Good optimization work!")
                }
            case .stable:
                recommendations.append("📊 \(trend.category) remains stable across versions.")
            }
        }
        
        // Analyze consistent unused files
        if !consistentUnusedFiles.isEmpty {
            let totalConsistentFiles = consistentUnusedFiles.count
            recommendations.append("🗑️ Found \(totalConsistentFiles) files that are consistently unused across all analyzed versions. These are safe candidates for removal.")
            
            if totalConsistentFiles > 10 {
                recommendations.append("💡 Consider creating an automated cleanup script to remove the \(totalConsistentFiles) consistently unused files.")
            }
        }
        
        // Analyze project count and frequency
        if projects.count >= 5 {
            let timeSpan = projects.last!.createdAt.timeIntervalSince(projects.first!.createdAt)
            let averageInterval = timeSpan / Double(projects.count - 1)
            let days = Int(averageInterval / (24 * 60 * 60))
            
            if days < 7 {
                recommendations.append("📈 You're analyzing frequently (every \(days) days on average). Consider setting up automated size monitoring.")
            }
        }
        
        // Size growth analysis
        if let totalSizeTrend = trends.first(where: { $0.category == "Total Size" }) {
            let latestProject = projects.last!
            let growthRate = totalSizeTrend.averageChange / Double(latestProject.totalSize) * 100
            
            if growthRate > 5 { // More than 5% growth per version
                recommendations.append("📊 App size is growing at \(String(format: "%.1f", growthRate))% per version. Consider implementing size budgets.")
            }
        }
        
        return recommendations
    }
    
    // MARK: - Private Methods - Trend Analysis
    
    private func calculateCategorySizeDataPoints(
        projects: [AnalysisProject],
        category: String
    ) async throws -> [(Date, Int64)] {
        
        var dataPoints: [(Date, Int64)] = []
        
        for project in projects {
            let results = project.analysisResults?.allObjects as? [AnalysisResult] ?? []
            var categorySize: Int64 = 0
            
            switch category {
            case "Code":
                categorySize = results.reduce(0) { $0 + $1.codeSize }
            case "Resource":
                categorySize = results.reduce(0) { $0 + $1.resourceSize }
            case "Framework":
                categorySize = results.reduce(0) { $0 + $1.frameworkSize }
            default:
                categorySize = 0
            }
            
            dataPoints.append((project.createdAt, categorySize))
        }
        
        return dataPoints
    }
    
    private func calculateUnusedContentDataPoints(
        projects: [AnalysisProject]
    ) async throws -> [(Date, Int64)] {
        
        var dataPoints: [(Date, Int64)] = []
        
        for project in projects {
            let results = project.analysisResults?.allObjects as? [AnalysisResult] ?? []
            let unusedSize = results
                .filter { $0.isUnusedResource || $0.isUnusedCode }
                .reduce(0) { $0 + $1.resourceSize + $1.codeSize }
            
            dataPoints.append((project.createdAt, unusedSize))
        }
        
        return dataPoints
    }
    
    private func calculateTrendDirection(dataPoints: [(Date, Int64)]) -> TrendDirection {
        guard dataPoints.count >= 2 else { return .stable }
        
        let sortedPoints = dataPoints.sorted { $0.0 < $1.0 }
        let firstValue = Double(sortedPoints.first!.1)
        let lastValue = Double(sortedPoints.last!.1)
        
        let changePercentage = abs((lastValue - firstValue) / firstValue * 100)
        
        if changePercentage < 5 { // Less than 5% change is considered stable
            return .stable
        } else if lastValue > firstValue {
            return .increasing
        } else {
            return .decreasing
        }
    }
    
    private func calculateAverageChange(dataPoints: [(Date, Int64)]) -> Double {
        guard dataPoints.count >= 2 else { return 0 }
        
        let sortedPoints = dataPoints.sorted { $0.0 < $1.0 }
        var totalChange: Double = 0
        
        for i in 1..<sortedPoints.count {
            let change = Double(sortedPoints[i].1 - sortedPoints[i-1].1)
            totalChange += change
        }
        
        return totalChange / Double(sortedPoints.count - 1)
    }
    
    // MARK: - Private Methods - Helper Functions
    
    private func calculateProjectSummary(from results: [AnalysisResult]) -> AnalysisSummary {
        let totalSize = results.reduce(0) { $0 + $1.codeSize + $1.resourceSize + $1.frameworkSize }
        let codeSize = results.reduce(0) { $0 + $1.codeSize }
        let resourceSize = results.reduce(0) { $0 + $1.resourceSize }
        let frameworkSize = results.reduce(0) { $0 + $1.frameworkSize }
        let unusedResourceSize = results.filter { $0.isUnusedResource }.reduce(0) { $0 + $1.resourceSize }
        let unusedCodeSize = results.filter { $0.isUnusedCode }.reduce(0) { $0 + $1.codeSize }
        let potentialSavings = unusedResourceSize + unusedCodeSize
        
        return AnalysisSummary(
            totalSize: totalSize,
            codeSize: codeSize,
            resourceSize: resourceSize,
            frameworkSize: frameworkSize,
            unusedResourceSize: unusedResourceSize,
            unusedCodeSize: unusedCodeSize,
            potentialSavings: potentialSavings
        )
    }
    
    private func calculatePercentageChange(from oldValue: Int64, to newValue: Int64) -> Double {
        guard oldValue != 0 else {
            return newValue == 0 ? 0 : 100
        }
        return Double(newValue - oldValue) / Double(oldValue) * 100
    }
    
    private func generateComparisonSummary(
        sizeChanges: [SizeChange],
        fileChanges: [FileChange],
        newFiles: [String],
        removedFiles: [String]
    ) -> ComparisonSummary {
        
        let totalSizeChange = sizeChanges.first { $0.category == "Total Size" }
        let addedFiles = fileChanges.filter { $0.changeType == .added }.count
        let removedFilesCount = fileChanges.filter { $0.changeType == .removed }.count
        let modifiedFiles = fileChanges.filter { $0.changeType == .modified }.count
        
        var significantChanges: [String] = []
        
        // Identify significant changes
        for change in sizeChanges {
            if abs(change.changePercentage) > 10 { // More than 10% change
                let direction = change.change > 0 ? "increased" : "decreased"
                significantChanges.append("\(change.category) \(direction) by \(String(format: "%.1f", abs(change.changePercentage)))%")
            }
        }
        
        if addedFiles > 0 {
            significantChanges.append("\(addedFiles) new files added")
        }
        
        if removedFilesCount > 0 {
            significantChanges.append("\(removedFilesCount) files removed")
        }
        
        return ComparisonSummary(
            totalSizeChange: totalSizeChange?.change ?? 0,
            totalSizeChangePercentage: totalSizeChange?.changePercentage ?? 0,
            addedFiles: addedFiles,
            removedFiles: removedFilesCount,
            modifiedFiles: modifiedFiles,
            significantChanges: significantChanges
        )
    }
}
