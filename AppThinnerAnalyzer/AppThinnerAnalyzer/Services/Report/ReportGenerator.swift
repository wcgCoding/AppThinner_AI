import Foundation
import CoreData

// MARK: - 报告生成器协议
// 负责将分析结果导出为 HTML 格式的可视化报告，支持三种报告类型：
//   - 单项目分析报告：含 Treemap、无用资源/代码列表、优化建议
//   - 多项目对比报告：体积变化趋势、新增/删除/修改文件统计
//   - 优化操作报告：压缩/删除操作结果汇总

protocol ReportGeneratorProtocol {
    /// 为指定分析项目生成 HTML 报告
    func generateHTMLReport(for project: AnalysisProject) async throws -> URL
    /// 生成两个项目的对比报告
    func generateComparisonReport(_ comparison: ProjectComparison) async throws -> URL
    /// 生成优化操作结果报告
    func generateOptimizationReport(_ results: OptimizationResults) async throws -> URL
}

// MARK: - 报告生成器实现

class ReportGenerator: ReportGeneratorProtocol {
    
    private let fileManager = FileManager.default
    
    // MARK: - 公共方法
    
    func generateHTMLReport(for project: AnalysisProject) async throws -> URL {
        let template = try await loadHTMLTemplate()
        let treemapData = try await generateTreemapJSON(from: project)
        let unusedResourcesHTML = try await generateUnusedResourcesTable(from: project)
        let unusedCodeHTML = try await generateUnusedCodeTable(from: project)
        let summaryHTML = try await generateSummarySection(from: project)
        let optimizationHTML = try await generateOptimizationSection(from: project)
        
        let finalHTML = template
            .replacingOccurrences(of: "{{PROJECT_NAME}}", with: project.name)
            .replacingOccurrences(of: "{{GENERATION_DATE}}", with: DateFormatter.reportDate.string(from: Date()))
            .replacingOccurrences(of: "{{TREEMAP_DATA}}", with: treemapData)
            .replacingOccurrences(of: "{{SUMMARY_SECTION}}", with: summaryHTML)
            .replacingOccurrences(of: "{{UNUSED_RESOURCES}}", with: unusedResourcesHTML)
            .replacingOccurrences(of: "{{UNUSED_CODE}}", with: unusedCodeHTML)
            .replacingOccurrences(of: "{{OPTIMIZATION_RECOMMENDATIONS}}", with: optimizationHTML)
        
        return try await saveHTMLReport(finalHTML, for: project)
    }
    
    func generateComparisonReport(_ comparison: ProjectComparison) async throws -> URL {
        let template = try await loadComparisonTemplate()
        let summaryHTML = try await generateComparisonSummary(comparison)
        let changesHTML = try await generateChangesTable(comparison)
        let trendsHTML = try await generateTrendsSection(comparison)
        
        let projectNames = comparison.projects.map { $0.name }.joined(separator: " vs ")
        
        let finalHTML = template
            .replacingOccurrences(of: "{{PROJECT_NAMES}}", with: projectNames)
            .replacingOccurrences(of: "{{GENERATION_DATE}}", with: DateFormatter.reportDate.string(from: Date()))
            .replacingOccurrences(of: "{{COMPARISON_SUMMARY}}", with: summaryHTML)
            .replacingOccurrences(of: "{{CHANGES_TABLE}}", with: changesHTML)
            .replacingOccurrences(of: "{{TRENDS_SECTION}}", with: trendsHTML)
        
        return try await saveComparisonReport(finalHTML, for: comparison)
    }
    
    func generateOptimizationReport(_ results: OptimizationResults) async throws -> URL {
        let template = try await loadOptimizationTemplate()
        let summaryHTML = try await generateOptimizationSummary(results)
        let detailsHTML = try await generateOptimizationDetails(results)
        
        let finalHTML = template
            .replacingOccurrences(of: "{{GENERATION_DATE}}", with: DateFormatter.reportDate.string(from: Date()))
            .replacingOccurrences(of: "{{OPTIMIZATION_SUMMARY}}", with: summaryHTML)
            .replacingOccurrences(of: "{{OPTIMIZATION_DETAILS}}", with: detailsHTML)
        
        return try await saveOptimizationReport(finalHTML, for: results)
    }
    
    // MARK: - Private Methods - Template Loading
    
    private func loadHTMLTemplate() async throws -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>iOS App Analysis Report - {{PROJECT_NAME}}</title>
            <style>
                \(getReportCSS())
            </style>
            <script src="https://d3js.org/d3.v7.min.js"></script>
        </head>
        <body>
            <div class="container">
                <header class="report-header">
                    <h1>iOS App Analysis Report</h1>
                    <h2>{{PROJECT_NAME}}</h2>
                    <p class="generation-date">Generated on {{GENERATION_DATE}}</p>
                </header>
                
                <section class="summary-section">
                    <h3>Analysis Summary</h3>
                    {{SUMMARY_SECTION}}
                </section>
                
                <section class="treemap-section">
                    <h3>Size Distribution Treemap</h3>
                    <div id="treemap-container"></div>
                </section>
                
                <section class="unused-resources-section">
                    <h3>Unused Resources</h3>
                    {{UNUSED_RESOURCES}}
                </section>
                
                <section class="unused-code-section">
                    <h3>Unused Code</h3>
                    {{UNUSED_CODE}}
                </section>
                
                <section class="optimization-section">
                    <h3>Optimization Recommendations</h3>
                    {{OPTIMIZATION_RECOMMENDATIONS}}
                </section>
                
                <footer class="report-footer">
                    <p>Generated by iOS App Analyzer</p>
                </footer>
            </div>
            
            <script>
                \(getTreemapScript())
                
                // Initialize treemap with data
                const treemapData = {{TREEMAP_DATA}};
                renderTreemap(treemapData);
            </script>
        </body>
        </html>
        """
    }
    
    private func loadComparisonTemplate() async throws -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Project Comparison Report - {{PROJECT_NAMES}}</title>
            <style>
                \(getReportCSS())
                \(getComparisonCSS())
            </style>
        </head>
        <body>
            <div class="container">
                <header class="report-header">
                    <h1>Project Comparison Report</h1>
                    <h2>{{PROJECT_NAMES}}</h2>
                    <p class="generation-date">Generated on {{GENERATION_DATE}}</p>
                </header>
                
                <section class="comparison-summary">
                    <h3>Comparison Summary</h3>
                    {{COMPARISON_SUMMARY}}
                </section>
                
                <section class="changes-section">
                    <h3>Detailed Changes</h3>
                    {{CHANGES_TABLE}}
                </section>
                
                <section class="trends-section">
                    <h3>Size Trends</h3>
                    {{TRENDS_SECTION}}
                </section>
                
                <footer class="report-footer">
                    <p>Generated by iOS App Analyzer</p>
                </footer>
            </div>
        </body>
        </html>
        """
    }
    
    private func loadOptimizationTemplate() async throws -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Optimization Report</title>
            <style>
                \(getReportCSS())
                \(getOptimizationCSS())
            </style>
        </head>
        <body>
            <div class="container">
                <header class="report-header">
                    <h1>Optimization Report</h1>
                    <p class="generation-date">Generated on {{GENERATION_DATE}}</p>
                </header>
                
                <section class="optimization-summary">
                    <h3>Optimization Summary</h3>
                    {{OPTIMIZATION_SUMMARY}}
                </section>
                
                <section class="optimization-details">
                    <h3>Optimization Details</h3>
                    {{OPTIMIZATION_DETAILS}}
                </section>
                
                <footer class="report-footer">
                    <p>Generated by iOS App Analyzer</p>
                </footer>
            </div>
        </body>
        </html>
        """
    }
    
    // MARK: - Private Methods - Data Generation
    
    private func generateTreemapJSON(from project: AnalysisProject) async throws -> String {
        guard let analysisResults = project.analysisResults?.allObjects as? [AnalysisResult] else {
            return "{}"
        }
        
        let treemapData = buildTreemapHierarchy(from: analysisResults)
        let jsonData = try JSONSerialization.data(withJSONObject: treemapData, options: .prettyPrinted)
        return String(data: jsonData, encoding: .utf8) ?? "{}"
    }
    
    private func buildTreemapHierarchy(from results: [AnalysisResult]) -> [String: Any] {
        var hierarchy: [String: Any] = [
            "name": "Root",
            "children": []
        ]
        
        var directoryMap: [String: [String: Any]] = [:]
        
        for result in results {
            let pathComponents = result.relativePath.components(separatedBy: "/")
            var currentPath = ""
            
            for (index, component) in pathComponents.enumerated() {
                if index == pathComponents.count - 1 {
                    // This is a file
                    let fileData: [String: Any] = [
                        "name": result.fileName,
                        "size": result.codeSize + result.resourceSize + result.frameworkSize,
                        "type": result.fileType,
                        "isUnused": result.isUnusedResource || result.isUnusedCode
                    ]
                    
                    if directoryMap[currentPath] == nil {
                        directoryMap[currentPath] = [
                            "name": currentPath.isEmpty ? "Root" : String(currentPath.split(separator: "/").last ?? ""),
                            "children": []
                        ]
                    }
                    
                    var children = directoryMap[currentPath]?["children"] as? [[String: Any]] ?? []
                    children.append(fileData)
                    directoryMap[currentPath]?["children"] = children
                } else {
                    // This is a directory
                    currentPath += (currentPath.isEmpty ? "" : "/") + component
                    
                    if directoryMap[currentPath] == nil {
                        directoryMap[currentPath] = [
                            "name": component,
                            "children": []
                        ]
                    }
                }
            }
        }
        
        // Build the final hierarchy
        hierarchy["children"] = Array(directoryMap.values)
        return hierarchy
    }
    
    private func generateSummarySection(from project: AnalysisProject) async throws -> String {
        guard let analysisResults = project.analysisResults?.allObjects as? [AnalysisResult] else {
            return "<p>No analysis data available</p>"
        }
        
        let summary = calculateSummary(from: analysisResults)
        
        return """
        <div class="summary-grid">
            <div class="summary-card">
                <h4>Total Size</h4>
                <p class="size-value">\(ByteCountFormatter.string(fromByteCount: summary.totalSize, countStyle: .file))</p>
            </div>
            <div class="summary-card">
                <h4>Code Size</h4>
                <p class="size-value">\(ByteCountFormatter.string(fromByteCount: summary.codeSize, countStyle: .file))</p>
            </div>
            <div class="summary-card">
                <h4>Resource Size</h4>
                <p class="size-value">\(ByteCountFormatter.string(fromByteCount: summary.resourceSize, countStyle: .file))</p>
            </div>
            <div class="summary-card">
                <h4>Framework Size</h4>
                <p class="size-value">\(ByteCountFormatter.string(fromByteCount: summary.frameworkSize, countStyle: .file))</p>
            </div>
            <div class="summary-card highlight">
                <h4>Potential Savings</h4>
                <p class="size-value">\(ByteCountFormatter.string(fromByteCount: summary.potentialSavings, countStyle: .file))</p>
            </div>
            <div class="summary-card highlight">
                <h4>Unused Content</h4>
                <p class="size-value">\(ByteCountFormatter.string(fromByteCount: summary.unusedResourceSize + summary.unusedCodeSize, countStyle: .file))</p>
            </div>
        </div>
        """
    }
    
    private func generateUnusedResourcesTable(from project: AnalysisProject) async throws -> String {
        guard let analysisResults = project.analysisResults?.allObjects as? [AnalysisResult] else {
            return "<p>No unused resources found</p>"
        }
        
        let unusedResources = analysisResults.filter { $0.isUnusedResource }
        
        if unusedResources.isEmpty {
            return "<p>No unused resources found</p>"
        }
        
        var tableHTML = """
        <table class="data-table">
            <thead>
                <tr>
                    <th>File Name</th>
                    <th>Path</th>
                    <th>Size</th>
                    <th>Type</th>
                    <th>Detection Method</th>
                </tr>
            </thead>
            <tbody>
        """
        
        for resource in unusedResources.sorted(by: { $0.resourceSize > $1.resourceSize }) {
            tableHTML += """
                <tr>
                    <td>\(resource.fileName)</td>
                    <td>\(resource.relativePath)</td>
                    <td>\(ByteCountFormatter.string(fromByteCount: resource.resourceSize, countStyle: .file))</td>
                    <td>\(resource.fileType)</td>
                    <td>\(resource.isExternallyMarked ? "External Data" : "Static Analysis")</td>
                </tr>
            """
        }
        
        tableHTML += """
            </tbody>
        </table>
        """
        
        return tableHTML
    }
    
    private func generateUnusedCodeTable(from project: AnalysisProject) async throws -> String {
        guard let analysisResults = project.analysisResults?.allObjects as? [AnalysisResult] else {
            return "<p>No unused code found</p>"
        }
        
        let unusedCode = analysisResults.filter { $0.isUnusedCode }
        
        if unusedCode.isEmpty {
            return "<p>No unused code found</p>"
        }
        
        var tableHTML = """
        <table class="data-table">
            <thead>
                <tr>
                    <th>File Name</th>
                    <th>Path</th>
                    <th>Estimated Size</th>
                    <th>Detection Method</th>
                </tr>
            </thead>
            <tbody>
        """
        
        for code in unusedCode.sorted(by: { $0.codeSize > $1.codeSize }) {
            tableHTML += """
                <tr>
                    <td>\(code.fileName)</td>
                    <td>\(code.relativePath)</td>
                    <td>\(ByteCountFormatter.string(fromByteCount: code.codeSize, countStyle: .file))</td>
                    <td>\(code.isExternallyMarked ? "External Data" : "Static Analysis")</td>
                </tr>
            """
        }
        
        tableHTML += """
            </tbody>
        </table>
        """
        
        return tableHTML
    }
    
    private func generateOptimizationSection(from project: AnalysisProject) async throws -> String {
        guard let analysisResults = project.analysisResults?.allObjects as? [AnalysisResult] else {
            return "<p>No optimization recommendations available</p>"
        }
        
        let unusedResources = analysisResults.filter { $0.isUnusedResource }
        let unusedCode = analysisResults.filter { $0.isUnusedCode }
        
        let totalUnusedSize = unusedResources.reduce(0) { $0 + $1.resourceSize } +
                             unusedCode.reduce(0) { $0 + $1.codeSize }
        
        return """
        <div class="optimization-recommendations">
            <div class="recommendation-card">
                <h4>Remove Unused Resources</h4>
                <p>Found \(unusedResources.count) unused resource files</p>
                <p class="savings">Potential savings: \(ByteCountFormatter.string(fromByteCount: unusedResources.reduce(0) { $0 + $1.resourceSize }, countStyle: .file))</p>
                <p class="risk low">Risk Level: Low</p>
            </div>
            
            <div class="recommendation-card">
                <h4>Remove Unused Code</h4>
                <p>Found \(unusedCode.count) unused code files</p>
                <p class="savings">Potential savings: \(ByteCountFormatter.string(fromByteCount: unusedCode.reduce(0) { $0 + $1.codeSize }, countStyle: .file))</p>
                <p class="risk medium">Risk Level: Medium</p>
            </div>
            
            <div class="recommendation-card highlight">
                <h4>Total Optimization Potential</h4>
                <p class="total-savings">\(ByteCountFormatter.string(fromByteCount: totalUnusedSize, countStyle: .file))</p>
                <p>Percentage of total app size: \(String(format: "%.1f", Double(totalUnusedSize) / Double(project.totalSize) * 100))%</p>
            </div>
        </div>
        """
    }
    
    // MARK: - Comparison Report Methods
    
    private func generateComparisonSummary(_ comparison: ProjectComparison) async throws -> String {
        let summary = comparison.summary
        
        return """
        <div class="comparison-summary-grid">
            <div class="summary-card">
                <h4>Total Size Change</h4>
                <p class="size-change \(summary.totalSizeChange >= 0 ? "increase" : "decrease")">
                    \(summary.totalSizeChange >= 0 ? "+" : "")\(ByteCountFormatter.string(fromByteCount: summary.totalSizeChange, countStyle: .file))
                </p>
                <p class="percentage">(\(String(format: "%.1f", summary.totalSizeChangePercentage))%)</p>
            </div>
            <div class="summary-card">
                <h4>Files Added</h4>
                <p class="count">\(summary.addedFiles)</p>
            </div>
            <div class="summary-card">
                <h4>Files Removed</h4>
                <p class="count">\(summary.removedFiles)</p>
            </div>
            <div class="summary-card">
                <h4>Files Modified</h4>
                <p class="count">\(summary.modifiedFiles)</p>
            </div>
        </div>
        """
    }
    
    private func generateChangesTable(_ comparison: ProjectComparison) async throws -> String {
        var tableHTML = """
        <table class="data-table">
            <thead>
                <tr>
                    <th>Category</th>
                    <th>Old Size</th>
                    <th>New Size</th>
                    <th>Change</th>
                    <th>Change %</th>
                </tr>
            </thead>
            <tbody>
        """
        
        for change in comparison.sizeChanges {
            let changeClass = change.change >= 0 ? "increase" : "decrease"
            tableHTML += """
                <tr>
                    <td>\(change.category)</td>
                    <td>\(ByteCountFormatter.string(fromByteCount: change.oldSize, countStyle: .file))</td>
                    <td>\(ByteCountFormatter.string(fromByteCount: change.newSize, countStyle: .file))</td>
                    <td class="\(changeClass)">\(change.change >= 0 ? "+" : "")\(ByteCountFormatter.string(fromByteCount: change.change, countStyle: .file))</td>
                    <td class="\(changeClass)">\(String(format: "%.1f", change.changePercentage))%</td>
                </tr>
            """
        }
        
        tableHTML += """
            </tbody>
        </table>
        """
        
        return tableHTML
    }
    
    private func generateTrendsSection(_ comparison: ProjectComparison) async throws -> String {
        return """
        <div class="trends-container">
            <p>Trend analysis shows the evolution of your app size over time.</p>
            <div class="trend-insights">
                <h4>Key Insights:</h4>
                <ul>
        """ + comparison.summary.significantChanges.map { "<li>\($0)</li>" }.joined() + """
                </ul>
            </div>
        </div>
        """
    }
    
    // MARK: - Optimization Report Methods
    
    private func generateOptimizationSummary(_ results: OptimizationResults) async throws -> String {
        let savingsPercentage = Double(results.savedSize) / Double(results.originalSize) * 100
        
        return """
        <div class="optimization-summary-grid">
            <div class="summary-card">
                <h4>Original Size</h4>
                <p class="size-value">\(ByteCountFormatter.string(fromByteCount: results.originalSize, countStyle: .file))</p>
            </div>
            <div class="summary-card">
                <h4>Optimized Size</h4>
                <p class="size-value">\(ByteCountFormatter.string(fromByteCount: results.optimizedSize, countStyle: .file))</p>
            </div>
            <div class="summary-card highlight">
                <h4>Space Saved</h4>
                <p class="size-value">\(ByteCountFormatter.string(fromByteCount: results.savedSize, countStyle: .file))</p>
                <p class="percentage">(\(String(format: "%.1f", savingsPercentage))%)</p>
            </div>
            <div class="summary-card">
                <h4>Files Processed</h4>
                <p class="count">\(results.processedFiles)</p>
            </div>
        </div>
        """
    }
    
    private func generateOptimizationDetails(_ results: OptimizationResults) async throws -> String {
        var detailsHTML = """
        <div class="optimization-details">
            <div class="backup-info">
                <h4>Backup Information</h4>
                <p>Backup created at: <code>\(results.backupLocation.path)</code></p>
            </div>
        """
        
        if !results.failedFiles.isEmpty {
            detailsHTML += """
            <div class="failed-files">
                <h4>Failed Operations</h4>
                <ul>
            """ + results.failedFiles.map { "<li>\($0)</li>" }.joined() + """
                </ul>
            </div>
            """
        }
        
        detailsHTML += "</div>"
        return detailsHTML
    }
    
    // MARK: - Helper Methods
    
    private func calculateSummary(from results: [AnalysisResult]) -> AnalysisSummary {
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
    
    private func saveHTMLReport(_ html: String, for project: AnalysisProject) async throws -> URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let reportsDirectory = documentsPath.appendingPathComponent("iOS App Analyzer Reports")
        
        try fileManager.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
        
        let fileName = "\(project.name)_Report_\(DateFormatter.fileDate.string(from: Date())).html"
        let fileURL = reportsDirectory.appendingPathComponent(fileName)
        
        try html.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
    
    private func saveComparisonReport(_ html: String, for comparison: ProjectComparison) async throws -> URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let reportsDirectory = documentsPath.appendingPathComponent("iOS App Analyzer Reports")
        
        try fileManager.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
        
        let projectNames = comparison.projects.map { $0.name }.joined(separator: "_vs_")
        let fileName = "Comparison_\(projectNames)_\(DateFormatter.fileDate.string(from: Date())).html"
        let fileURL = reportsDirectory.appendingPathComponent(fileName)
        
        try html.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
    
    private func saveOptimizationReport(_ html: String, for results: OptimizationResults) async throws -> URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let reportsDirectory = documentsPath.appendingPathComponent("iOS App Analyzer Reports")
        
        try fileManager.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
        
        let fileName = "Optimization_Report_\(DateFormatter.fileDate.string(from: Date())).html"
        let fileURL = reportsDirectory.appendingPathComponent(fileName)
        
        try html.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}

// MARK: - CSS and JavaScript

extension ReportGenerator {
    
    private func getReportCSS() -> String {
        return """
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            color: #333;
            background-color: #f8f9fa;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
            background-color: white;
            box-shadow: 0 0 20px rgba(0,0,0,0.1);
        }
        
        .report-header {
            text-align: center;
            margin-bottom: 40px;
            padding-bottom: 20px;
            border-bottom: 2px solid #007AFF;
        }
        
        .report-header h1 {
            color: #007AFF;
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        
        .report-header h2 {
            color: #666;
            font-weight: normal;
            margin-bottom: 10px;
        }
        
        .generation-date {
            color: #999;
            font-size: 0.9em;
        }
        
        section {
            margin-bottom: 40px;
        }
        
        h3 {
            color: #333;
            font-size: 1.5em;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 1px solid #eee;
        }
        
        .summary-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .summary-card {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 8px;
            text-align: center;
            border: 1px solid #e9ecef;
        }
        
        .summary-card.highlight {
            background: #e3f2fd;
            border-color: #007AFF;
        }
        
        .summary-card h4 {
            color: #666;
            font-size: 0.9em;
            text-transform: uppercase;
            letter-spacing: 1px;
            margin-bottom: 10px;
        }
        
        .size-value {
            font-size: 1.8em;
            font-weight: bold;
            color: #333;
        }
        
        .data-table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 20px;
        }
        
        .data-table th,
        .data-table td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }
        
        .data-table th {
            background-color: #f8f9fa;
            font-weight: 600;
            color: #333;
        }
        
        .data-table tr:hover {
            background-color: #f5f5f5;
        }
        
        #treemap-container {
            width: 100%;
            height: 500px;
            border: 1px solid #ddd;
            border-radius: 8px;
            overflow: hidden;
        }
        
        .optimization-recommendations {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
        }
        
        .recommendation-card {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 8px;
            border-left: 4px solid #007AFF;
        }
        
        .recommendation-card h4 {
            color: #333;
            margin-bottom: 10px;
        }
        
        .savings {
            font-weight: bold;
            color: #28a745;
        }
        
        .risk {
            font-size: 0.9em;
            font-weight: bold;
        }
        
        .risk.low { color: #28a745; }
        .risk.medium { color: #ffc107; }
        .risk.high { color: #dc3545; }
        
        .total-savings {
            font-size: 2em;
            font-weight: bold;
            color: #28a745;
        }
        
        .report-footer {
            text-align: center;
            margin-top: 40px;
            padding-top: 20px;
            border-top: 1px solid #eee;
            color: #999;
        }
        
        @media print {
            body { background-color: white; }
            .container { box-shadow: none; }
            #treemap-container { height: 400px; }
        }
        """
    }
    
    private func getComparisonCSS() -> String {
        return """
        .comparison-summary-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .size-change {
            font-size: 1.5em;
            font-weight: bold;
        }
        
        .size-change.increase { color: #dc3545; }
        .size-change.decrease { color: #28a745; }
        
        .percentage {
            font-size: 0.9em;
            color: #666;
        }
        
        .count {
            font-size: 1.8em;
            font-weight: bold;
            color: #333;
        }
        
        .increase { color: #dc3545; }
        .decrease { color: #28a745; }
        
        .trends-container {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 8px;
        }
        
        .trend-insights {
            margin-top: 20px;
        }
        
        .trend-insights ul {
            margin-left: 20px;
        }
        
        .trend-insights li {
            margin-bottom: 5px;
        }
        """
    }
    
    private func getOptimizationCSS() -> String {
        return """
        .optimization-summary-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .optimization-details {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 8px;
        }
        
        .backup-info {
            margin-bottom: 20px;
        }
        
        .backup-info code {
            background: #e9ecef;
            padding: 2px 6px;
            border-radius: 4px;
            font-family: 'Monaco', 'Menlo', monospace;
        }
        
        .failed-files {
            background: #fff3cd;
            padding: 15px;
            border-radius: 8px;
            border-left: 4px solid #ffc107;
        }
        
        .failed-files ul {
            margin-left: 20px;
        }
        """
    }
    
    private func getTreemapScript() -> String {
        return """
        function renderTreemap(data) {
            const container = d3.select("#treemap-container");
            const width = container.node().getBoundingClientRect().width;
            const height = 500;
            
            const svg = container.append("svg")
                .attr("width", width)
                .attr("height", height);
            
            const root = d3.hierarchy(data)
                .sum(d => d.size || 0)
                .sort((a, b) => b.value - a.value);
            
            const treemap = d3.treemap()
                .size([width, height])
                .padding(1);
            
            treemap(root);
            
            const color = d3.scaleOrdinal()
                .domain(['Code', 'Resource', 'Framework', 'Directory'])
                .range(['#007AFF', '#34C759', '#FF9500', '#8E8E93']);
            
            const leaf = svg.selectAll("g")
                .data(root.leaves())
                .enter().append("g")
                .attr("transform", d => `translate(${d.x0},${d.y0})`);
            
            leaf.append("rect")
                .attr("width", d => d.x1 - d.x0)
                .attr("height", d => d.y1 - d.y0)
                .attr("fill", d => d.data.isUnused ? "#FF3B30" : color(d.data.type))
                .attr("opacity", d => d.data.isUnused ? 0.8 : 0.6)
                .attr("stroke", "#fff")
                .attr("stroke-width", 1);
            
            leaf.append("text")
                .attr("x", 4)
                .attr("y", 14)
                .text(d => d.data.name)
                .attr("font-size", "10px")
                .attr("fill", "white")
                .attr("font-weight", "bold");
            
            leaf.append("title")
                .text(d => `${d.data.name}\\nSize: ${formatBytes(d.value)}\\nType: ${d.data.type}${d.data.isUnused ? '\\nStatus: Unused' : ''}`);
        }
        
        function formatBytes(bytes) {
            if (bytes === 0) return '0 Bytes';
            const k = 1000; // SI: 1 KB = 1000 B, 1 MB = 1e6 B (App Store / Finder 标准)
            const sizes = ['Bytes', 'KB', 'MB', 'GB'];
            const i = Math.min(Math.floor(Math.log(Math.max(bytes, 1)) / Math.log(k)), sizes.length - 1);
            return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
        }
        """
    }
}

// MARK: - Date Formatters

extension DateFormatter {
    static let reportDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter
    }()
    
    static let fileDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}