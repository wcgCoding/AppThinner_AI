#if os(macOS)
import SwiftUI
import WebKit

// MARK: - ECharts 模式

enum EChartsMode {
    case treemap   // 使用 EChartsTreemap.html，注入 setTreemapData(data)
    case graph     // 使用 EChartsGraph.html，注入 setGraphData({ nodes, links })
}

// MARK: - ECharts WebView（加载本地 HTML + CDN ECharts，通过 JS 注入数据）

struct EChartsWebView: NSViewRepresentable {
    let mode: EChartsMode
    /// 注入的 JSON 字符串：treemap 为 [{ name, value, children }]；graph 为 { nodes: [...], links: [...] }
    var dataJSON: String?
    /// 当前展示节点的稳定 id（UUID 字符串），用于判断数据是否真正变化，避免 JSON 序列化顺序不稳定导致误注入
    var displayNodeId: String?
    /// treemap 模式下，节点选中回调（id 为 TreemapNode.id.uuidString）
    var onTreemapNodeSelected: ((String) -> Void)? = nil

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        // 注册 treemap 点击回调
        config.userContentController.add(context.coordinator, name: "treemapNodeSelected")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        return webView
    }

  func updateNSView(_ webView: WKWebView, context: Context) {
    let coordinator = context.coordinator
    // 每次重渲染都同步最新的回调闭包，确保 Swift 侧拿到最新的 ViewModel 引用
    coordinator.parent = self
    if coordinator.lastLoadedMode != mode {
      coordinator.lastLoadedMode = mode
      // 重载 HTML 时才更新 pendingDataJSON，供 didFinish 注入
      coordinator.pendingDataJSON = dataJSON
      coordinator.lastInjectedNodeId = nil
      loadHTML(into: webView)
      return
    }
    // 用稳定的 displayNodeId 判断展示节点是否真正变化，避免 JSON 字符串每次序列化顺序不同导致误注入
    let nodeId = displayNodeId ?? dataJSON
    if let json = dataJSON, !json.isEmpty, nodeId != coordinator.lastInjectedNodeId {
      injectData(into: webView, json: json)
      coordinator.lastInjectedNodeId = nodeId
      coordinator.pendingDataJSON = json
    }
  }

    private func loadHTML(into webView: WKWebView) {
        let fileName = mode == .treemap ? "EChartsTreemap" : "EChartsGraph"
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "html", subdirectory: nil)
            ?? Bundle.main.url(forResource: fileName, withExtension: "html", subdirectory: "Resources") else {
            return
        }
        let bundleRoot = Bundle.main.bundleURL
        webView.loadFileURL(url, allowingReadAccessTo: bundleRoot)
    }

    private func injectData(into webView: WKWebView, json: String) {
        let script = Self.makeInjectionScript(mode: mode, json: json)
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

  private static func makeInjectionScript(mode: EChartsMode, json: String) -> String {
    let escaped = json.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "</script>", with: "<\\/script>")
    switch mode {
    case .treemap:
      return "if (window.setTreemapData) window.setTreemapData(\"\(escaped)\");"
    case .graph:
      return "if (window.setGraphData) window.setGraphData(\"\(escaped)\");"
    }
  }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

  class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var parent: EChartsWebView
    var lastLoadedMode: EChartsMode?
    var pendingDataJSON: String?
    /// 上次注入时的稳定节点 id，用于防止 JSON 序列化顺序不稳定导致误重注入
    var lastInjectedNodeId: String?

    init(parent: EChartsWebView) {
      self.parent = parent
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      guard let mode = lastLoadedMode, let json = pendingDataJSON, !json.isEmpty else { return }
      let script = EChartsWebView.makeInjectionScript(mode: mode, json: json)
      webView.evaluateJavaScript(script, completionHandler: nil)
    }

    // 从 EChartsTreemap.html 收到节点点击事件
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
      guard message.name == "treemapNodeSelected" else { return }
      if let id = message.body as? String {
        parent.onTreemapNodeSelected?(id)
      }
    }
  }
}

// MARK: - Treemap 数据转换（TreemapNode → ECharts hierarchy）

struct EChartsTreemapData {
    static func from(node: TreemapNode) -> [[String: Any]] {
        func toDict(_ n: TreemapNode) -> [String: Any] {
            let sizeValue = max(1, n.size)
            let unused = max(0.0, min(1.0, n.unusedRatio))
            // value[0] 用于面积，value[1] 用于无用比例着色
            var d: [String: Any] = [
                "name": n.name,
                "value": [sizeValue, unused],
                "id": n.id.uuidString,
                "unusedRatio": unused
            ]
            if !n.children.isEmpty {
                d["children"] = n.children.map { toDict($0) }
            }
            return d
        }
        if node.children.isEmpty {
            let sizeValue = max(1, node.size)
            let unused = max(0.0, min(1.0, node.unusedRatio))
            return [[
                "name": node.name,
                "value": [sizeValue, unused],
                "id": node.id.uuidString,
                "unusedRatio": unused
            ]]
        }
        return [toDict(node)]
    }

    static func toJSON(_ node: TreemapNode) -> String? {
        let arr = from(node: node)
        guard let data = try? JSONSerialization.data(withJSONObject: arr),
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }
}

// MARK: - Graph 数据转换（Pods 树 → nodes + links）

struct EChartsGraphData {
    /// 全树节点与边（含子库），用于兼容旧调用
    static func from(pods: [PodsDependencyInfo]) -> (nodes: [[String: Any]], links: [[String: Any]]) {
        var nodes: [[String: Any]] = []
        var links: [[String: Any]] = []
        var seenIds: Set<String> = []
        func add(_ info: PodsDependencyInfo, parentId: String?) {
            let id = "\(info.name)_\(info.version)"
            if !seenIds.contains(id) {
                seenIds.insert(id)
                nodes.append(["id": id, "name": "\(info.name)\n\(info.version)", "symbolSize": 30])
            }
            if let p = parentId { links.append(["source": p, "target": id]) }
            for child in info.children { add(child, parentId: id) }
        }
        for pod in pods { add(pod, parentId: nil) }
        return (nodes, links)
    }

    /// 仅主库颗粒度：节点仅顶层 Pod，边为顶层→顶层（A 依赖 B 则 A→B），保证关系线展示
    static func fromTopLevelOnly(pods: [PodsDependencyInfo]) -> (nodes: [[String: Any]], links: [[String: Any]]) {
        let topNames = Set(pods.map { $0.name })
        func descendantNames(_ info: PodsDependencyInfo) -> Set<String> {
            var s: Set<String> = [info.name]
            for c in info.children { s.formUnion(descendantNames(c)) }
            return s
        }
        var links: [[String: Any]] = []
        for pod in pods {
            let idA = "\(pod.name)_\(pod.version)"
            let deps = descendantNames(pod)
            for name in deps where name != pod.name && topNames.contains(name) {
                guard let target = pods.first(where: { $0.name == name }) else { continue }
                let idB = "\(target.name)_\(target.version)"
                links.append(["source": idA, "target": idB])
            }
        }
        let nodes: [[String: Any]] = pods.map { pod in
            ["id": "\(pod.name)_\(pod.version)", "name": "\(pod.name)\n\(pod.version)", "symbolSize": 36]
        }
        return (nodes, links)
    }

    /// 主仓粒度：节点=主仓名（如 AcrossJCE），边=主仓 A→主仓 B。
    /// - 参数 visibleMainNames: 仅展示这些主仓节点（nil 表示全部主仓）
    /// - 参数 onlyLinksFrom: 仅展示从这些主仓出发的边（nil 表示所有可见主仓）
    /// - 参数 sizeByMain: 主仓 -> 体积（字节），用于控制节点大小（体积越大节点越大）
    /// - 参数 unusedRatioByMain: 主仓 -> 无用占比（0~1），用于 tooltip 展示
    static func fromMainLevelOnly(
        pods: [PodsDependencyInfo],
        mainRepoName: (String) -> String,
        visibleMainNames: Set<String>? = nil,
        onlyLinksFrom: Set<String>? = nil,
        sizeByMain: [String: Int64]? = nil,
        unusedRatioByMain: [String: Double]? = nil
    ) -> (nodes: [[String: Any]], links: [[String: Any]]) {
        let topNames = Set(pods.map { $0.name })
        func descendantNames(_ info: PodsDependencyInfo) -> Set<String> {
            var s: Set<String> = [info.name]
            for c in info.children { s.formUnion(descendantNames(c)) }
            return s
        }
        var mainDeps: [String: Set<String>] = [:]
        for pod in pods {
            let mainA = mainRepoName(pod.name)
            let deps = descendantNames(pod)
            for name in deps where name != pod.name && topNames.contains(name) {
                let mainB = mainRepoName(name)
                if mainB != mainA {
                    mainDeps[mainA, default: []].insert(mainB)
                }
            }
        }
        // 所有主仓：来自所有 Pod 名（包含没有任何依赖关系的独立主仓）
        let allMains = Set(pods.map { mainRepoName($0.name) })
        let visible = visibleMainNames ?? allMains

        // 为了增强大小对比度，基于可见主仓的体积做线性缩放（带 sqrt 强调差异）
        let positiveSizes: [Int64] = visible.compactMap { sizeByMain?[$0] }.filter { $0 > 0 }
        let maxSize = positiveSizes.max() ?? 0
        let minSymbol: Double = 12
        let maxSymbol: Double = 80

        let nodes: [[String: Any]] = visible.sorted().map { main in
            let rawSize = sizeByMain?[main] ?? 0
            let unused = unusedRatioByMain?[main] ?? 0.0
            let symbolSize: Double
            if rawSize <= 0 {
                // size 为 0：使用最小形态
                symbolSize = minSymbol
            } else if maxSize > 0 {
                let normalized = Double(rawSize) / Double(maxSize) // 0~1
                let emphasized = sqrt(normalized)                 // 增强大节点差异
                symbolSize = minSymbol + emphasized * (maxSymbol - minSymbol)
            } else {
                symbolSize = (minSymbol + maxSymbol) / 2.0
            }
            return [
                "id": main,
                "name": main,
                "symbolSize": symbolSize,
                "size": rawSize,
                "unusedRatio": unused
            ]
        }
        var links: [[String: Any]] = []
        for (mainA, targets) in mainDeps {
            guard visible.contains(mainA) else { continue }
            let allowFrom = onlyLinksFrom ?? visible
            guard allowFrom.contains(mainA) else { continue }
            for mainB in targets where visible.contains(mainB) {
                links.append(["source": mainA, "target": mainB])
            }
        }
        return (nodes, links)
    }

    static func toJSON(pods: [PodsDependencyInfo]) -> String? {
        let (nodes, links) = from(pods: pods)
        return toJSONPayload(nodes: nodes, links: links)
    }

    static func toJSONTopLevelOnly(pods: [PodsDependencyInfo]) -> String? {
        let (nodes, links) = fromTopLevelOnly(pods: pods)
        return toJSONPayload(nodes: nodes, links: links)
    }

    static func toJSONMainLevelOnly(
        pods: [PodsDependencyInfo],
        mainRepoName: (String) -> String,
        visibleMainNames: Set<String>? = nil,
        onlyLinksFrom: Set<String>? = nil,
        sizeByMain: [String: Int64]? = nil,
        unusedRatioByMain: [String: Double]? = nil
    ) -> String? {
        let (nodes, links) = fromMainLevelOnly(
            pods: pods,
            mainRepoName: mainRepoName,
            visibleMainNames: visibleMainNames,
            onlyLinksFrom: onlyLinksFrom,
            sizeByMain: sizeByMain,
            unusedRatioByMain: unusedRatioByMain
        )
        return toJSONPayload(nodes: nodes, links: links)
    }

    /// 主仓依赖关系：主仓名 -> 其依赖的主仓名集合（用于搜索时计算两层可见节点）
    static func mainLevelDependencies(pods: [PodsDependencyInfo], mainRepoName: (String) -> String) -> [String: Set<String>] {
        let topNames = Set(pods.map { $0.name })
        func descendantNames(_ info: PodsDependencyInfo) -> Set<String> {
            var s: Set<String> = [info.name]
            for c in info.children { s.formUnion(descendantNames(c)) }
            return s
        }
        var mainDeps: [String: Set<String>] = [:]
        for pod in pods {
            let mainA = mainRepoName(pod.name)
            let deps = descendantNames(pod)
            for name in deps where name != pod.name && topNames.contains(name) {
                let mainB = mainRepoName(name)
                if mainB != mainA {
                    mainDeps[mainA, default: []].insert(mainB)
                }
            }
        }
        return mainDeps
    }

    private static func toJSONPayload(nodes: [[String: Any]], links: [[String: Any]]) -> String? {
        let payload: [String: Any] = ["nodes": nodes, "links": links]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }
}
#endif
