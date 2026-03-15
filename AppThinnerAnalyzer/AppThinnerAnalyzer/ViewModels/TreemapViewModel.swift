import SwiftUI
import CoreData

@MainActor
class TreemapViewModel: ObservableObject {
    @Published var rootNode: TreemapNode?
    @Published var currentNode: TreemapNode?
    @Published var selectedNode: TreemapNode?
    /// Treemap 是否正在后台生成（用于避免主线程卡顿、让前端 WebView 自己展示 loading）
    @Published var isGeneratingTreemap: Bool = false
    @Published var searchText = ""
    /// 为 true 时「按文件夹展开」内的搜索栏请求焦点（如 ⌘F），消费后置为 false
    @Published var focusFolderSearch = false
    @Published var hoveredNode: TreemapNode?
    @Published var navigationHistory: [TreemapNode] = []
    
    private let treemapGenerator: TreemapGeneratorProtocol
    /// 用于复用：核心分析数据未变化时只做布局更新，不重新构造树
    private var cachedProjectIdentity: String?
    private var cachedStructureRoot: TreemapNode?
    /// 按文件夹展开 Tab：基于同一 root 只构造一次并复用
    private var cachedFolderRootSourceId: UUID?
    private var cachedFolderRoot: TreemapNode?
    
    init(treemapGenerator: TreemapGeneratorProtocol = TreemapGenerator()) {
        self.treemapGenerator = treemapGenerator
    }
    
    /// 生成用于缓存的 project 身份（数据未变则一致）
    private func projectIdentity(for project: AnalysisProject) -> String {
        let id = project.objectID.uriRepresentation().absoluteString
        let updated = project.updatedAt.timeIntervalSince1970
        let count = project.analysisResultsArray.count
        let total = project.totalSize
        return "\(id)_\(updated)_\(count)_\(total)"
    }
    
    // MARK: - Treemap Generation
    
    func generateTreemap(from project: AnalysisProject, in bounds: CGRect) {
        let identity = projectIdentity(for: project)
        // 如果核心分析数据未变化，仅做布局更新（成本较低，可直接在主线程完成）
        if identity == cachedProjectIdentity, let cached = cachedStructureRoot {
            rootNode = treemapGenerator.updateLayout(for: cached, in: bounds, maxDepth: 2)
            currentNode = rootNode
            navigationHistory = [rootNode].compactMap { $0 }
            selectLargestChildOfCurrent()
            cachedFolderRootSourceId = nil
            cachedFolderRoot = nil
            return
        }
        
        // 重建 Treemap 树可能较重，放到后台线程计算，主线程只负责状态更新和结果赋值
        isGeneratingTreemap = true
        let generator = treemapGenerator
        let analysisResults = project.analysisResultsArray
        
        Task.detached { [identity] in
            let newRoot = generator.generateTreemap(from: analysisResults, in: bounds)
            await MainActor.run {
                guard let viewModel = self as TreemapViewModel? else { return }
                viewModel.cachedProjectIdentity = identity
                viewModel.cachedStructureRoot = newRoot
                viewModel.rootNode = newRoot
                viewModel.currentNode = newRoot
                viewModel.navigationHistory = [newRoot]
                viewModel.selectLargestChildOfCurrent()
                viewModel.cachedFolderRootSourceId = nil
                viewModel.cachedFolderRoot = nil
                viewModel.isGeneratingTreemap = false
            }
        }
    }
    
    /// 布局时仅展示 2 层深度，下钻后仍为 2 层
    func updateLayout(for bounds: CGRect) {
        guard let root = rootNode else { return }
        let maxDepth = 2
        if currentNode?.id == root.id {
            let updatedRoot = treemapGenerator.updateLayout(for: root, in: bounds, maxDepth: maxDepth)
            rootNode = updatedRoot
            currentNode = updatedRoot
        } else if let current = currentNode {
            currentNode = treemapGenerator.updateLayout(for: current, in: bounds, maxDepth: maxDepth)
        }
        // 布局尺寸变化后，按 id 在最新树中重新找一遍选中节点，避免选中虚线与块位置错位
        if let selected = selectedNode {
            selectedNode = findNodeInTree(root: rootNode ?? currentNode, targetId: selected.id)
        }
    }
    
    // MARK: - Navigation
    
    func drillDown(to node: TreemapNode) {
        guard !node.children.isEmpty else { return }
        
        currentNode = node
        navigationHistory.append(node)
        selectLargestChildOfCurrent()
    }
    
    func drillUp() {
        guard navigationHistory.count > 1 else { return }
        
        navigationHistory.removeLast()
        currentNode = navigationHistory.last
        selectLargestChildOfCurrent()
    }
    
    func navigateToRoot() {
        currentNode = rootNode
        navigationHistory = [rootNode].compactMap { $0 }
        selectLargestChildOfCurrent()
    }

    /// 点击面包屑跳转到某一层：index 为 navigationHistory 的下标（0=Root）
    func navigateToHistoryIndex(_ index: Int) {
        guard index >= 0, index < navigationHistory.count else { return }
        currentNode = navigationHistory[index]
        navigationHistory = Array(navigationHistory.prefix(index + 1))
        selectLargestChildOfCurrent()
    }
    
    // MARK: - Search and Filtering
    
    func search(text: String) {
        searchText = text
        // TODO: Implement search functionality in future tasks
    }
    
    func toggleUnusedFilter() {
        // 仅未使用勾选框已移除，保留空实现避免调用处报错
    }
    
    /// 按文件夹展开 Tab 使用的根节点（每层带「其他」合并，「其他」可展开下钻）；与 rootNode 同源时复用缓存，避免每次切 Tab 重算。
    func displayRootForFolder() -> TreemapNode? {
        guard let root = rootNode else { cachedFolderRootSourceId = nil; cachedFolderRoot = nil; return nil }
        if root.id == cachedFolderRootSourceId, let cached = cachedFolderRoot { return cached }
        let folderRoot = treemapGenerator.cappedTreeForFolderDisplay(from: root, maxPerLevel: 48)
        cachedFolderRootSourceId = root.id
        cachedFolderRoot = folderRoot
        return folderRoot
    }
    
    // MARK: - Node Interaction
    
    /// 悬停时更新 hoveredNode 用于显示 tooltip
    func handleNodeHover(_ node: TreemapNode?) {
        hoveredNode = node
    }
    
    func selectNode(_ node: TreemapNode) {
        selectedNode = node
    }

    /// 根据节点 id 字符串（UUID）选中节点，用于 ECharts treemap 点击回调
    func selectNode(byIdString idString: String) {
        guard let uuid = UUID(uuidString: idString) else { return }
        let root = rootNode ?? currentNode
        if let found = findNodeInTree(root: root, targetId: uuid) {
            selectedNode = found
        }
    }
    
    /// 单击仅选中，下钻通过顶部箭头按钮触发
    func handleNodeTap(_ node: TreemapNode) {
        selectNode(node)
    }
    
    /// 默认选中当前层级中面积最大的一个子节点（首个最大区域模块）
    private func selectLargestChildOfCurrent() {
        guard let current = currentNode, !current.children.isEmpty else {
            selectedNode = nil
            return
        }
        selectedNode = current.children.max(by: { $0.size < $1.size })
    }
    
    // MARK: - Private Helper Methods
    
    private func findNodeInTree(root: TreemapNode?, targetId: UUID) -> TreemapNode? {
        guard let root = root else { return nil }
        
        if root.id == targetId {
            return root
        }
        
        for child in root.children {
            if let found = findNodeInTree(root: child, targetId: targetId) {
                return found
            }
        }
        
        return nil
    }
}
