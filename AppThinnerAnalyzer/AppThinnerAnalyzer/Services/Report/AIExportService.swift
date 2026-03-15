import Foundation
import CoreData

// MARK: - AI 优化报告导出

/// 导出给 AI 使用的优化报告数据：包体积分布、无用代码/资源、Pods 依赖，便于 AI 生成可执行的优化建议报告。
enum AIExportService {

    // MARK: - Payload 结构（Codable）

    struct ExportPayload: Encodable {
        let version: String
        let exportedAt: String
        let instructionsForAI: String
        let project: ProjectSummary
        let sizeDistribution: SizeDistributionNode
        let unusedCode: [UnusedCodeEntry]
        let unusedResources: [UnusedResourceEntry]
        let podsDependencies: PodsDependenciesSummary?
    }

    struct ProjectSummary: Encodable {
        let name: String
        let projectPath: String
        let ipaPath: String
        let linkmapPath: String
        let totalSizeBytes: Int64
        let totalSizeKB: Double
        let codeSizeKB: Double
        let resourceSizeKB: Double
        let frameworkSizeKB: Double
        let potentialSavingsBytes: Int64
        let potentialSavingsKB: Double
    }

    struct SizeDistributionNode: Encodable {
        let name: String
        let relativePath: String
        let totalSizeBytes: Int64
        let codeSizeBytes: Int64
        let resourceSizeBytes: Int64
        let frameworkSizeBytes: Int64
        let unusedSizeBytes: Int64
        let unusedRatio: Double
        let children: [SizeDistributionNode]
    }

    struct UnusedCodeEntry: Encodable {
        let relativePath: String
        let fileName: String
        let codeSizeBytes: Int64
        let codeSizeKB: Double
    }

    struct UnusedResourceEntry: Encodable {
        let relativePath: String
        let fileName: String
        let resourceSizeBytes: Int64
        let resourceSizeKB: Double
    }

    struct PodsMainLibSummaryItem: Encodable {
        let name: String
        let version: String
        let sizeBytes: Int64
        let sizeKB: Double
        let unusedSizeBytes: Int64
        let unusedSizeKB: Double
        let unusedRatio: Double
        let dependedByCount: Int
        let dependedByList: [String]
    }

    struct PodsDependenciesSummary: Encodable {
        let podfileLockPath: String?
        let mainLibSummary: [PodsMainLibSummaryItem]
        let tree: [PodsDependencyInfo]
    }

    private static let instructionsForAI = """
        请根据下方 JSON 中的 iOS 工程包体积分析数据，生成一份**可执行的优化报告**。

        数据说明：
        1. **sizeDistribution**：以业务工程目录为基准的包体积分布（树形），含 codeSize/resourceSize/frameworkSize、unusedRatio。可用于定位体积大户与无用占比高的目录。
        2. **unusedCode** / **unusedResources**：可关联到工程路径的无用代码与无用资源列表，含体积。建议按目录或模块归类，并给出删除/下线步骤与风险提示。
        3. **podsDependencies**：Pods 主库维度汇总（mainLibSummary）及依赖树（tree）。可用于评估可下线、可替换或可瘦身的第三方库，并给出可行步骤。

        请输出：
        - 一页总览：总体积、可节约空间、主要问题模块。
        - 按优先级分块的优化方案（如：高价值低风险 / 需评审 / 长期治理）。
        - 每个方案包含：具体步骤、涉及路径或库名、预估收益、注意事项。
        - 若有无用代码/资源，请按业务目录归纳并标注建议操作（删除前需确认引用）。
        """

    // MARK: - 构建导出数据

    /// 从当前分析项目生成供 AI 使用的 JSON 数据。
    static func buildExportData(project: AnalysisProject) throws -> Data {
        let results = project.analysisResultsArray
        var pathAggregates: [String: (code: Int64, resource: Int64, framework: Int64, unused: Int64)] = [:]
        let pathSeparator = "/"

        for r in results {
            let path = r.relativePath
            let comps = path.components(separatedBy: pathSeparator)
            let code = r.codeSize
            let resource = r.resourceSize
            let framework = r.frameworkSize
            let total = code + resource + framework
            let unused = (r.isUnusedCode || r.isUnusedResource) ? total : 0

            for i in 0..<comps.count {
                let prefix = comps[0...i].joined(separator: pathSeparator)
                var cur = pathAggregates[prefix] ?? (0, 0, 0, 0)
                cur.0 += code
                cur.1 += resource
                cur.2 += framework
                cur.3 += unused
                pathAggregates[prefix] = cur
            }
        }

        func directChildPaths(of path: String) -> [String] {
            let prefix = path.isEmpty ? "" : path + pathSeparator
            return pathAggregates.keys
                .compactMap { key in
                    guard key.hasPrefix(prefix) else { return nil }
                    let remaining = String(key.dropFirst(prefix.count))
                    guard !remaining.isEmpty else { return nil }
                    let firstComponent = remaining.split(separator: Character(pathSeparator), maxSplits: 1).first
                    guard let comp = firstComponent else { return nil }
                    let childPath = prefix + String(comp)
                    return childPath
                }
                .uniqued()
                .sorted()
        }

        func buildNode(path: String, name: String) -> SizeDistributionNode {
            let agg = pathAggregates[path] ?? (0, 0, 0, 0)
            let total = agg.0 + agg.1 + agg.2
            let unusedRatio = total > 0 ? Double(agg.3) / Double(total) : 0
            let children = directChildPaths(of: path).map { childPath in
                buildNode(path: childPath, name: (childPath as NSString).lastPathComponent)
            }
            return SizeDistributionNode(
                name: name,
                relativePath: path,
                totalSizeBytes: total,
                codeSizeBytes: agg.0,
                resourceSizeBytes: agg.1,
                frameworkSizeBytes: agg.2,
                unusedSizeBytes: agg.3,
                unusedRatio: unusedRatio,
                children: children.sorted { $0.totalSizeBytes > $1.totalSizeBytes }
            )
        }

        let topLevel = pathAggregates.keys
            .filter { !$0.contains(pathSeparator) }
            .sorted()
        let rootChildren = topLevel.map { buildNode(path: $0, name: $0) }
        let rootTotal = rootChildren.reduce(0) { $0 + $1.totalSizeBytes }
        let rootUnused = rootChildren.reduce(0) { $0 + $1.unusedSizeBytes }
        let rootRatio = rootTotal > 0 ? Double(rootUnused) / Double(rootTotal) : 0
        let sizeDistribution = SizeDistributionNode(
            name: "Root",
            relativePath: "",
            totalSizeBytes: rootTotal,
            codeSizeBytes: rootChildren.reduce(0) { $0 + $1.codeSizeBytes },
            resourceSizeBytes: rootChildren.reduce(0) { $0 + $1.resourceSizeBytes },
            frameworkSizeBytes: rootChildren.reduce(0) { $0 + $1.frameworkSizeBytes },
            unusedSizeBytes: rootUnused,
            unusedRatio: rootRatio,
            children: rootChildren
        )

        let unusedCode = results
            .filter { $0.isUnusedCode && $0.codeSize > 0 }
            .map { r in
                UnusedCodeEntry(
                    relativePath: r.relativePath,
                    fileName: r.fileName,
                    codeSizeBytes: r.codeSize,
                    codeSizeKB: Double(r.codeSize) / 1024.0
                )
            }
        let unusedResources = results
            .filter { $0.isUnusedResource && $0.resourceSize > 0 }
            .map { r in
                UnusedResourceEntry(
                    relativePath: r.relativePath,
                    fileName: r.fileName,
                    resourceSizeBytes: r.resourceSize,
                    resourceSizeKB: Double(r.resourceSize) / 1024.0
                )
            }

        var podsDependencies: PodsDependenciesSummary?
        if let podsResult = project.podsDependencyResult {
            let pods = podsResult.pods
            let mainRows = PodsSummaryBuilder.buildMainLibRows(pods: pods, analysisResults: results)
            let mainLibSummary = mainRows.map { row in
                PodsMainLibSummaryItem(
                    name: row.name,
                    version: row.version,
                    sizeBytes: row.size,
                    sizeKB: Double(row.size) / 1024.0,
                    unusedSizeBytes: row.unusedSize,
                    unusedSizeKB: Double(row.unusedSize) / 1024.0,
                    unusedRatio: row.unusedRatio,
                    dependedByCount: row.dependedByCount,
                    dependedByList: row.dependedByList
                )
            }
            podsDependencies = PodsDependenciesSummary(
                podfileLockPath: podsResult.podfileLockPath,
                mainLibSummary: mainLibSummary,
                tree: pods
            )
        }

        let totalSize = project.totalSize
        let potentialSavings = project.potentialSavings
        let payload = ExportPayload(
            version: "1.0",
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            instructionsForAI: instructionsForAI,
            project: ProjectSummary(
                name: project.name ?? "",
                projectPath: project.projectPath ?? "",
                ipaPath: project.ipaPath ?? "",
                linkmapPath: project.linkmapPath ?? "",
                totalSizeBytes: totalSize,
                totalSizeKB: Double(totalSize) / 1024.0,
                codeSizeKB: Double(project.totalCodeSize) / 1024.0,
                resourceSizeKB: Double(project.totalResourceSize) / 1024.0,
                frameworkSizeKB: Double(project.totalFrameworkSize) / 1024.0,
                potentialSavingsBytes: potentialSavings,
                potentialSavingsKB: Double(potentialSavings) / 1024.0
            ),
            sizeDistribution: sizeDistribution,
            unusedCode: unusedCode,
            unusedResources: unusedResources,
            podsDependencies: podsDependencies
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
