import Foundation

// MARK: - Pods 依赖扫描服务协议
// 解析工程根目录下的 Podfile.lock，构建 Pod 依赖树（含子依赖关系），
// 用于分析各 Pod 的被依赖情况和潜在的冗余依赖。

protocol PodsDependencyScanServiceProtocol {
    /// 解析工程根目录下的 Podfile.lock，返回依赖树（含子依赖）
    func scanPodsDependencies(projectPath: String) async throws -> PodsDependencyResult?
}

// MARK: - Pods 依赖扫描服务实现

/// 解析 Podfile.lock（类 YAML），按缩进构建 PODS 树，便于计算被依赖关系。
final class PodsDependencyScanService: PodsDependencyScanServiceProtocol {

    func scanPodsDependencies(projectPath: String) async throws -> PodsDependencyResult? {
        let podfileLockURL = URL(fileURLWithPath: projectPath).appendingPathComponent(
            "Podfile.lock")
        guard FileManager.default.fileExists(atPath: podfileLockURL.path) else { return nil }
        let content: String
        do {
            content = try String(contentsOf: podfileLockURL, encoding: .utf8)
        } catch {
            return nil
        }
        let pods = parsePodfileLockTree(content)
        return PodsDependencyResult(pods: pods, podfileLockPath: "Podfile.lock")
    }

    private struct PodLockItem {
        let level: Int
        let name: String
        let version: String
    }

    /// 解析 PODS 段：按行首空格数识别层级，构建树（顶层 = 主库，子节点 = 子依赖）
    private func parsePodfileLockTree(_ content: String) -> [PodsDependencyInfo] {
        let lines = content.components(separatedBy: .newlines)
        var inPods = false
        var items: [PodLockItem] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "PODS:" {
                inPods = true
                continue
            }
            if inPods {
                if trimmed.hasPrefix("DEPENDENCIES:") || trimmed.hasPrefix("SPEC REPOS:")
                    || trimmed.hasPrefix("EXTERNAL SOURCES:")
                {
                    break
                }
                // 只关心包含 "-" 的行（PODS 段的声明行和依赖行），按缩进算层级
                guard line.contains("- ") else { continue }
                let spaceCount = line.prefix(while: { $0 == " " }).count
                let level = spaceCount / 2
                let rest = String(line.dropFirst(spaceCount))
                guard let (name, version) = parsePodLine(rest), !name.isEmpty else { continue }
                items.append(PodLockItem(level: level, name: name, version: version))
            }
        }

        return buildTree(from: items)
    }

    private func buildTree(from items: [PodLockItem]) -> [PodsDependencyInfo] {
        struct MutableNode {
            let level: Int
            let name: String
            let version: String
            var children: [MutableNode] = []
        }
        var stack: [MutableNode] = []
        var roots: [MutableNode] = []

        for item in items {
            while let last = stack.last, last.level >= item.level {
                stack.removeLast()
                if stack.isEmpty {
                    roots.append(last)
                } else {
                    var parent = stack.removeLast()
                    parent.children.append(last)
                    stack.append(parent)
                }
            }
            stack.append(
                MutableNode(level: item.level, name: item.name, version: item.version, children: [])
            )
        }
        roots.append(contentsOf: stack.reversed())
        func toInfo(_ n: MutableNode) -> PodsDependencyInfo {
            PodsDependencyInfo(
                name: n.name,
                version: n.version,
                subspecs: [],
                children: n.children.map(toInfo),
                estimatedSize: 0
            )
        }
        return roots.map(toInfo).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// 解析 Podfile.lock 中一行：
    /// - "- Foo (1.2.3):"     -> ("Foo", "1.2.3")
    /// - "- Foo/Bar"          -> ("Foo/Bar", "")
    /// - "- Foo/Bar:"         -> ("Foo/Bar", "")
    private func parsePodLine(_ value: String) -> (String, String)? {
        guard value.contains("- ") else { return nil }
        // 去掉行首缩进，只保留从 "-" 开始的部分
        guard let dashRange = value.range(of: "- ") else { return nil }
        let afterDash = value[dashRange.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !afterDash.isEmpty else { return nil }

        // 尝试解析带版本号的形式 "Name (x.y.z):"
        if let open = afterDash.firstIndex(of: "("),
            let close = afterDash[open...].firstIndex(of: ")")
        {
            let namePart = afterDash[..<open]
            let versionPart = afterDash[afterDash.index(after: open)..<close]
            let name = namePart.trimmingCharacters(in: .whitespaces)
            let version = versionPart.trimmingCharacters(in: .whitespaces)
            return (name, version)
        }

        // 无版本号：依赖行只写名称，例如 "KSBasicUI/Kuikly" 或 "KSBasicUI/Kuikly:"
        var name = afterDash
        if name.hasSuffix(":") {
            name = String(name.dropLast())
        }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return nil }
        return (trimmedName, "")
    }
}
