import Foundation
import CoreData

// MARK: - PodsSummaryBuilder

/// 从 Pod 树 + 分析结果按主仓聚合为列表，供 Pods 依赖 Tab 与 AI 导出共用。
enum PodsSummaryBuilder {

    /// 主仓名：取名称第一段，如 "AcrossJCE/comm" -> "AcrossJCE"
    static func mainRepoName(_ podName: String) -> String {
        podName.split(separator: "/").first.map(String.init) ?? podName
    }

    /// 从 Pod 树 + 分析结果按主仓聚合为一行（一个主仓一行，子仓合并）
    static func buildMainLibRows(pods: [PodsDependencyInfo], analysisResults: [AnalysisResult]) -> [PodsMainLibRow] {
        let mainNames = Set(pods.map { mainRepoName($0.name) })
        let mainNamesLower: [String: String] = Dictionary(uniqueKeysWithValues: mainNames.map { ($0.lowercased(), $0) })

        func detectMainName(for result: AnalysisResult) -> String? {
            let path = result.relativePath
            let fileName = result.fileName

            let comps = (path as NSString).pathComponents
            if comps.count >= 2, comps[0] == "Pods" {
                let pod = mainRepoName(comps[1])
                if mainNames.contains(pod) { return pod }
            }

            let parts = path.split(separator: "/").map { String($0) }
            for part in parts {
                let base = ((part as NSString).lastPathComponent as NSString).deletingPathExtension
                let lowered = base.lowercased()
                if lowered.hasPrefix("lib"), lowered.count > 3 {
                    let candidate = String(lowered.dropFirst(3))
                    if let name = mainNamesLower[candidate] { return name }
                }
                if let name = mainNamesLower[lowered] { return name }
            }

            let baseName = ((fileName as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
            if let name = mainNamesLower[baseName] { return name }
            if baseName.hasPrefix("lib"), baseName.count > 3 {
                let candidate = String(baseName.dropFirst(3))
                if let name = mainNamesLower[candidate] { return name }
            }
            return nil
        }

        var sizeByMain: [String: Int64] = [:]
        var unusedSizeByMain: [String: Int64] = [:]
        for r in analysisResults {
            let fileSize = r.codeSize + r.resourceSize + r.frameworkSize
            guard fileSize > 0 else { continue }
            guard let main = detectMainName(for: r) else { continue }
            sizeByMain[main, default: 0] += fileSize
            if r.isUnused {
                unusedSizeByMain[main, default: 0] += fileSize
            }
        }

        func allDescendantNames(_ info: PodsDependencyInfo) -> Set<String> {
            var s: Set<String> = [info.name]
            for c in info.children { s.formUnion(allDescendantNames(c)) }
            return s
        }
        var dependedBy: [String: [String]] = [:]
        for pod in pods {
            let names = allDescendantNames(pod)
            for n in names {
                dependedBy[n, default: []].append(pod.name)
            }
        }

        var byMain: [String: (version: String, size: Int64, unused: Int64, dependedBySet: Set<String>)] = [:]
        for pod in pods {
            let main = mainRepoName(pod.name)
            let list = dependedBy[pod.name] ?? []
            let depMainNames = Set(list).filter { $0 != pod.name }.map(mainRepoName)
            if var cur = byMain[main] {
                cur.dependedBySet.formUnion(depMainNames)
                if cur.version != pod.version { cur.version = "多个" }
                byMain[main] = cur
            } else {
                byMain[main] = (
                    version: pod.version,
                    size: sizeByMain[main] ?? 0,
                    unused: unusedSizeByMain[main] ?? 0,
                    dependedBySet: Set(depMainNames).subtracting([main])
                )
            }
        }
        return byMain.map { main, val in
            let list = Array(val.dependedBySet.subtracting([main])).sorted()
            let unused = max(0, val.unused)
            let ratio = val.size > 0 ? Double(unused) / Double(val.size) : 0
            return PodsMainLibRow(
                name: main,
                version: val.version,
                size: val.size,
                unusedSize: unused,
                unusedRatio: ratio,
                dependedByCount: list.count,
                dependedByList: list
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
