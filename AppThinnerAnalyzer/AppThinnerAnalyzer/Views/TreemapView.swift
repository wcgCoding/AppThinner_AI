import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// 统一将字节数显示为 KB（保留两位小数；≥1024 KB 时显示为 MB）
private func formatSizeInKB(_ bytes: Int64) -> String {
    let kb = Double(bytes) / 1024.0
    if kb >= 1024 {
        let mb = kb / 1024.0
        return String(format: "%.1f MB", mb)
    }
    return String(format: "%.2f KB", kb)
}

/// 用于导出 JSON 的可编码节点结构
private struct TreemapNodeExport: Encodable {
    let id: String
    let name: String
    let relativePath: String
    let size: Int64
    let isUnused: Bool
    let unusedRatio: Double
    let fileType: String
    let childrenCount: Int
    let children: [TreemapNodeExport]

    init(from node: TreemapNode) {
        id = node.id.uuidString
        name = node.name
        relativePath = node.relativePath
        size = node.size
        isUnused = node.isUnused
        unusedRatio = node.unusedRatio
        fileType = node.fileType.rawValue
        childrenCount = node.children.count
        children = node.children.map { TreemapNodeExport(from: $0) }
    }
}

/// 底部信息面板固定高度，避免选中不同节点时 treemap 区域高度变化
private let bottomPanelFixedHeight: CGFloat = 160

struct TreemapView: View {
    let project: AnalysisProject?
    @StateObject private var viewModel = DependencyContainer.shared.makeTreemapViewModel()
    @State private var viewBounds: CGRect = .zero
    @State private var selectedVizTab: VisualizationTab = .treemap
    @State private var isExportingAIReport: Bool = false
    
    enum VisualizationTab: String, CaseIterable {
        case treemap
        case groupedByFolder
        case duplicate
        case podsDependency
    }
    
    var body: some View {
        VStack {
            if let project = project {
                Picker("", selection: $selectedVizTab) {
                    Text("Treemap").tag(VisualizationTab.treemap)
                    Text("按文件夹展开").tag(VisualizationTab.groupedByFolder)
                    Text("重复度").tag(VisualizationTab.duplicate)
                    Text("Pods依赖").tag(VisualizationTab.podsDependency)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 16)
                
                switch selectedVizTab {
                case .treemap:
                    VStack(spacing: 0) {
                        // Treemap 主视图：面积 + 颜色 用于发现「垃圾最多的区域」
                        let displayNode = viewModel.currentNode ?? viewModel.rootNode
                        EChartsWebView(
                            mode: .treemap,
                            dataJSON: displayNode.flatMap { EChartsTreemapData.toJSON($0) },
                            displayNodeId: displayNode?.id.uuidString,
                            onTreemapNodeSelected: { nodeId in
                                viewModel.selectNode(byIdString: nodeId)
                            }
                        )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onAppear {
                                viewBounds = CGRect(x: 0, y: 0, width: 800, height: 600)
                                viewModel.generateTreemap(from: project, in: viewBounds)
                            }
                            .onChange(of: project.id) { _, _ in
                                viewModel.generateTreemap(from: project, in: viewBounds)
                            }
                        
                        // 底部 info 面板：固定高度，展示当前区域无用情况，并提供二级列表入口
                        let infoNode = viewModel.selectedNode ?? viewModel.currentNode ?? viewModel.rootNode
                        if let infoNode {
                            NodeInfoPanel(
                                node: infoNode,
                                onShowUnusedDetails: { node in
                                    #if os(macOS)
                                    UnusedItemsWindowManager.shared.open(for: node, projectRoot: project.projectPath)
                                    #endif
                                }
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: bottomPanelFixedHeight)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: bottomPanelFixedHeight)
                        }
                    }
                    
                case .groupedByFolder:
                    GroupedByFolderView(
                        rootNode: viewModel.displayRootForFolder(),
                        projectRoot: project.projectPath,
                        searchText: $viewModel.searchText,
                        requestSearchFocus: $viewModel.focusFolderSearch
                    )
                
                case .duplicate:
                    DuplicateTabView(project: project)
                
                case .podsDependency:
                    PodsDependencyTabView(project: project)
                }
            } else {
                ContentUnavailableView(
                    "No Analysis Available",
                    systemImage: "chart.pie",
                    description: Text("Run an analysis first to see the treemap visualization")
                )
            }
        }
        .navigationTitle("Treemap Visualization")
        .toolbar {
            if project != nil, viewModel.rootNode != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        exportAIOptimizationReport(project: project)
                    } label: {
                        HStack(spacing: 6) {
                            if isExportingAIReport {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(isExportingAIReport ? "正在导出 AI 报告…" : "导出 AI 可分析数据")
                        }
                    }
                    .disabled(isExportingAIReport)
                    .help("导出供 AI 生成优化建议的 JSON（体积分布、无用代码/资源、Pods 依赖）")
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.selectedNode)
        .keyboardShortcuts(for: .treemap)
        // Treemap-specific keyboard shortcuts
        .keyboardShortcut(.leftArrow, modifiers: []) {
            viewModel.drillUp()
        }
        .keyboardShortcut(.rightArrow, modifiers: []) {
            if let selectedNode = viewModel.selectedNode, !selectedNode.children.isEmpty {
                viewModel.drillDown(to: selectedNode)
            }
        }
        .keyboardShortcut(.upArrow, modifiers: []) {
            viewModel.navigateToRoot()
        }
        .keyboardShortcut(.downArrow, modifiers: []) {
            if let currentNode = viewModel.currentNode, !currentNode.children.isEmpty {
                let firstChild = currentNode.children.first!
                viewModel.selectNode(firstChild)
            }
        }
        .keyboardShortcut(.escape, modifiers: []) {
            viewModel.selectedNode = nil
        }
        .keyboardShortcut(KeyEquivalent("f"), modifiers: [.command]) {
            // 仅在「按文件夹展开」时聚焦搜索栏，由 GroupedByFolderView 通过 focus 处理
            if selectedVizTab == .groupedByFolder {
                viewModel.focusFolderSearch = true
            }
        }
        .accessibilityKeyboardShortcut("←", description: "Navigate back")
        .accessibilityKeyboardShortcut("→", description: "Drill down into selected item")
        .accessibilityKeyboardShortcut("↑", description: "Navigate to root")
        .accessibilityKeyboardShortcut("↓", description: "Select first child")
        .accessibilityKeyboardShortcut("⎋", description: "Clear selection")
        .accessibilityKeyboardShortcut("⌘F", description: "Focus search")
    }

    /// 导出供 AI 生成优化报告的数据（体积分布、无用代码/资源、Pods 依赖），弹出保存面板
    private func exportAIOptimizationReport(project: AnalysisProject?) {
        guard let project, !isExportingAIReport else { return }
        isExportingAIReport = true
        Task {
            do {
                // 在后台线程构建导出数据，避免阻塞主线程
                let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            let result = try AIExportService.buildExportData(project: project)
                            continuation.resume(returning: result)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
                #if os(macOS)
                await MainActor.run {
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.json]
                    let safeName = (project.name ?? "project").filter { $0.isLetter || $0.isNumber || $0 == "_" }
                    panel.nameFieldStringValue = "ai-optimization-report-\(safeName).json"
                    panel.begin { response in
                        guard response == .OK, let url = panel.url else { return }
                        try? data.write(to: url)
                    }
                }
                #endif
            } catch {
                #if os(macOS)
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "导出失败"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
                #endif
            }
            await MainActor.run {
                isExportingAIReport = false
            }
        }
    }

    /// 导出可视化结果为 JSON 文件，弹出保存面板
    private func exportVisualizationToJSON(projectName: String, rootNode: TreemapNode?) {
        guard let root = rootNode else { return }
        let payload = VisualizationExportPayload(
            projectName: projectName,
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            root: TreemapNodeExport(from: root)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return }
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "treemap-\(projectName.filter { $0.isLetter || $0.isNumber }).json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url)
        }
        #endif
    }
}

private struct VisualizationExportPayload: Encodable {
    let projectName: String
    let exportedAt: String
    let root: TreemapNodeExport
}

struct TreemapControlsView: View {
    @ObservedObject var viewModel: TreemapViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    Button(action: viewModel.navigateToRoot) {
                        Image(systemName: "house")
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.navigationHistory.count <= 1)
                    
                    Button(action: viewModel.drillUp) {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.navigationHistory.count <= 1)
                    
                    Button(action: {
                        if let sel = viewModel.selectedNode, !sel.children.isEmpty {
                            viewModel.drillDown(to: sel)
                        }
                    }) {
                        Image(systemName: "arrow.right")
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.selectedNode == nil || (viewModel.selectedNode?.children.isEmpty ?? true))
                    .help("下钻到选中项")
                }
                
                Text("·")
                    .foregroundColor(.secondary)
                
                Text(viewModel.currentNode?.name ?? "Root")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))
            
            // 可点击的面包屑目录条
            if viewModel.navigationHistory.count > 0 {
                HStack(spacing: 4) {
                    ForEach(Array(viewModel.navigationHistory.enumerated()), id: \.element.id) { index, node in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Button(action: { viewModel.navigateToHistoryIndex(index) }) {
                            Text(index == 0 ? "Root" : node.name)
                                .font(.subheadline)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(index == viewModel.navigationHistory.count - 1 ? .primary : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            index == viewModel.navigationHistory.count - 1
                                ? Color.primary.opacity(0.08)
                                : Color.clear
                        )
                        .cornerRadius(4)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
            }
        }
    }
}

struct TreemapCanvas: View {
    let node: TreemapNode?
    let selectedNode: TreemapNode?
    let hoveredNode: TreemapNode?
    let onNodeTap: (TreemapNode) -> Void
    let onNodeHover: (TreemapNode?) -> Void
    
    @State private var mouseLocation: CGPoint = .zero
    @State private var hoveredAdjustedLocation: CGPoint = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Canvas { context, size in
            guard let node = node else { return }
            
            // Apply transformations
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: dragOffset.width, y: dragOffset.height)
            
            drawTreemapNode(context: context, node: node, in: size)
        }
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.15 : 0.3), lineWidth: 0.8)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap(at: mouseLocation)
        }
        .onContinuousHover { phase in
            handleHover(phase: phase)
        }
        .gesture(
            SimultaneousGesture(
                // Pan gesture for navigation
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.3)) {
                            dragOffset = .zero
                        }
                    },
                
                // Magnification gesture for zoom
                MagnificationGesture()
                    .onChanged { value in
                        scale = max(0.5, min(3.0, value))
                    }
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.3)) {
                            scale = 1.0
                        }
                    }
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Treemap visualization")
        .accessibilityHint("Click to select; use arrow button to drill down")
        .overlay(alignment: .topLeading) {
            GeometryReader { geo in
                if let hovered = hoveredNode, hovered.rect.width > 2, hovered.rect.height > 2 {
                    let spacing: CGFloat = 16
                    let tipW: CGFloat = 160
                    let tipH: CGFloat = 48
                    let x = max(8, min(mouseLocation.x + spacing, geo.size.width - tipW - 8))
                    let y = max(8, min(mouseLocation.y + spacing, geo.size.height - tipH - 8))
                    TreemapHoverTooltip(node: hovered)
                        .frame(maxWidth: tipW, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: true)
                        .position(x: x + tipW/2, y: y + tipH/2)
                        .allowsHitTesting(false)
                }
            }
        }
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.2) : Color.white.opacity(0.8)
    }
    
    private func handleTap(at location: CGPoint) {
        let adjusted = CGPoint(
            x: (location.x - dragOffset.width) / scale,
            y: (location.y - dragOffset.height) / scale
        )
        if let tappedNode = findNode(at: adjusted, in: node) {
            let impactFeedback = NSHapticFeedbackManager.defaultPerformer
            impactFeedback.perform(.alignment, performanceTime: .now)
            onNodeTap(tappedNode)
        }
    }
    
    private func handleHover(phase: HoverPhase) {
        switch phase {
        case .active(let location):
            mouseLocation = location
            hoveredAdjustedLocation = CGPoint(
                x: (location.x - dragOffset.width) / scale,
                y: (location.y - dragOffset.height) / scale
            )
            let hoveredNode = findNode(at: hoveredAdjustedLocation, in: node)
            onNodeHover(hoveredNode)
        case .ended:
            onNodeHover(nil)
        }
    }
    
    private func drawTreemapNode(
        context: GraphicsContext,
        node: TreemapNode,
        in size: CGSize
    ) {
        // Draw current node's children（顶层按索引分配不同颜色）
        for (index, child) in node.children.enumerated() {
            drawSingleNode(context: context, node: child, topLevelIndex: index)
        }
        
        // Draw selection overlay only（不随鼠标滑动高亮，仅单击选中）
        if let selected = selectedNode {
            drawSelectionOverlay(context: context, node: selected)
        }
    }
    
    private func drawSingleNode(
        context: GraphicsContext,
        node: TreemapNode,
        topLevelIndex: Int? = nil
    ) {
        let rect = node.rect
        guard rect.width > 1 && rect.height > 1 else { return }
        
        let fillColor = colorForNode(node, topLevelIndex: topLevelIndex)
        let strokeColor = strokeColorForNode(node)
        
        let cornerRadius: CGFloat = min(3, min(rect.width, rect.height) * 0.15)
        let path = Path(roundedRect: rect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        
        // 填充颜色（根据 unusedRatio 控制透明度），不再叠加斜纹
        context.fill(path, with: .color(fillColor))
        
        // 白色细边框，提升分块可读性
        let strokeWidth = strokeWidthForNode(node)
        context.stroke(path, with: .color(strokeColor), lineWidth: strokeWidth)
        
        // 所有块均在块中间展示：名称居中，大小在名称下方（展示不下则忽略大小）
        drawNodeLabelAndSize(context: context, node: node, rect: rect)
        
        for child in node.children {
            drawSingleNode(context: context, node: child, topLevelIndex: nil)
        }
    }
    
    // 斜纹与额外警告图标已移除，保留函数占位以便后续需要时扩展（目前不再调用）
    
    /// 块中间展示：名称居中，大小在名称下方；展示不下则只画名称或忽略
    private func drawNodeLabelAndSize(context: GraphicsContext, node: TreemapNode, rect: CGRect) {
        if node.name == "Root" { return }
        // 只有空间足够时才渲染文本
        guard rect.width > 48 && rect.height > 24 else { return }
        
        let nameFontSize = min(12, max(8, rect.height / 6))
        let maxNameWidth = rect.width - 8
        let displayName = truncatedName(node.name, maxWidth: maxNameWidth, fontSize: nameFontSize, context: context)
        let nameText = Text(displayName)
            .font(.system(size: nameFontSize, weight: .medium))
            .foregroundColor(textColorForNode(node))
        let resolvedName = context.resolve(nameText)
        let nameBounds = resolvedName.measure(in: rect.size)
        guard nameBounds.width < rect.width - 8 else { return }
        
        let sizeFontSize: CGFloat = 9
        let sizeStr = formatSizeInKB(node.size)
        let sizeText = Text(sizeStr)
            .font(.system(size: sizeFontSize, weight: .medium))
            .foregroundColor(textColorForNode(node).opacity(0.85))
        let resolvedSize = context.resolve(sizeText)
        let sizeBounds = resolvedSize.measure(in: rect.size)
        let spacing: CGFloat = 2
        let totalHeight = nameBounds.height + spacing + sizeBounds.height
        let canShowSize = totalHeight < rect.height - 6 && sizeBounds.width < rect.width - 8
        
        let contentHeight = canShowSize ? totalHeight : nameBounds.height
        let startY = rect.midY - contentHeight / 2
        
        // 使用 anchor: .center 确保文案在块内水平、垂直都按中心对齐（避免默认 at 语义导致“右边线居中”）
        let nameCenterY = startY + nameBounds.height / 2
        context.draw(resolvedName, at: CGPoint(x: rect.midX, y: nameCenterY), anchor: .center)
        
        if canShowSize {
            let sizeCenterY = startY + nameBounds.height + spacing + sizeBounds.height / 2
            context.draw(resolvedSize, at: CGPoint(x: rect.midX, y: sizeCenterY), anchor: .center)
        }
    }
    
    private func truncatedName(_ name: String, maxWidth: CGFloat, fontSize: CGFloat, context: GraphicsContext) -> String {
        guard maxWidth > 20 else { return "…" }
        let measureSize = CGSize(width: 2000, height: 40)
        let fullText = Text(name).font(.system(size: fontSize, weight: .semibold))
        let fullBounds = context.resolve(fullText).measure(in: measureSize)
        if fullBounds.width <= maxWidth { return name }
        let suffix = "…"
        for drop in 1..<name.count {
            let candidate = String(name.prefix(name.count - drop)) + suffix
            let candidateText = Text(candidate).font(.system(size: fontSize, weight: .semibold))
            if context.resolve(candidateText).measure(in: measureSize).width <= maxWidth {
                return candidate
            }
        }
        return suffix
    }
    
    private func drawNodeLabel(context: GraphicsContext, node: TreemapNode, rect: CGRect) {
        if node.name == "Root" { return }
        guard rect.width > 52 && rect.height > 24 else { return }
        
        let fontSize = min(12, max(8, rect.height / 6))
        let text = Text(node.name)
            .font(.system(size: fontSize, weight: .medium))
            .foregroundColor(textColorForNode(node))
        
        let textBounds = context.resolve(text).measure(in: rect.size)
        guard textBounds.width < rect.width - 8 && textBounds.height < rect.height - 4 else { return }
        
        let textPosition = CGPoint(
            x: rect.midX - textBounds.width / 2,
            y: rect.midY - textBounds.height / 2
        )
        context.draw(text, at: textPosition)
    }
    
    private func drawSizeIndicator(context: GraphicsContext, node: TreemapNode, rect: CGRect) {
        if node.name == "Root" { return }
        guard rect.width > 28 && rect.height > 18 else { return }
        
        let sizeText = Text(formatSizeInKB(node.size))
            .font(.system(size: 8, weight: .medium))
            .foregroundColor(.primary)
        
        context.draw(sizeText, at: CGPoint(x: rect.midX, y: rect.midY))
    }
    
    private func drawSelectionOverlay(context: GraphicsContext, node: TreemapNode) {
        let rect = node.rect
        let cornerRadius: CGFloat = min(3, min(rect.width, rect.height) * 0.15)
        let overlayPath = Path(roundedRect: rect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        
        // Draw selection highlight
        context.stroke(
            overlayPath,
            with: .color(.accentColor),
            style: StrokeStyle(lineWidth: 3, dash: [5, 3])
        )
        
        // Draw selection corners
        let cornerSize: CGFloat = 8
        let corners = [
            CGRect(x: rect.minX - 2, y: rect.minY - 2, width: cornerSize, height: cornerSize),
            CGRect(x: rect.maxX - cornerSize + 2, y: rect.minY - 2, width: cornerSize, height: cornerSize),
            CGRect(x: rect.minX - 2, y: rect.maxY - cornerSize + 2, width: cornerSize, height: cornerSize),
            CGRect(x: rect.maxX - cornerSize + 2, y: rect.maxY - cornerSize + 2, width: cornerSize, height: cornerSize)
        ]
        
        for corner in corners {
            context.fill(Path(corner), with: .color(.accentColor))
        }
    }
    
    /// 顶层块冷色调 (r,g,b)；按无用占比 unusedRatio 向暖色/红插值
    private static let topLevelPaletteRGB: [(r: Double, g: Double, b: Double)] = [
        (0.25, 0.45, 0.85), (0.30, 0.55, 0.82), (0.28, 0.62, 0.72), (0.35, 0.52, 0.78),
        (0.32, 0.68, 0.65), (0.40, 0.58, 0.88), (0.38, 0.72, 0.58), (0.45, 0.50, 0.75),
        (0.42, 0.65, 0.70), (0.30, 0.60, 0.55), (0.35, 0.48, 0.82), (0.33, 0.70, 0.62),
        (0.28, 0.55, 0.68), (0.40, 0.62, 0.72), (0.36, 0.58, 0.65), (0.32, 0.65, 0.58),
    ]
    private static let topLevelPalette: [Color] = topLevelPaletteRGB.map { Color(red: $0.r, green: $0.g, blue: $0.b) }
    
    /// 冷色基调（按类型）(r,g,b)；无用占比越高越向红色插值
    private static let coldColorByType: [FileType: (r: Double, g: Double, b: Double)] = [
        .code: (0.28, 0.48, 0.82),
        .resource: (0.22, 0.58, 0.62),
        .framework: (0.35, 0.52, 0.72),
        .directory: (0.40, 0.45, 0.52),
        .other: (0.38, 0.42, 0.58),
    ]
    private static let warmRGB = (r: 0.9, g: 0.2, b: 0.25)
    
    private func colorForNode(_ node: TreemapNode, topLevelIndex: Int? = nil) -> Color {
        // 统一以蓝色为基础色，当存在无用内容时向红色过渡；透明度由 unusedRatio 控制。
        let baseRGB = (r: 0.16, g: 0.30, b: 0.78)
        let warmRGB = Self.warmRGB
        
        let ratio = max(0.0, min(1.0, node.unusedRatio))
        
        let r = baseRGB.r + (warmRGB.r - baseRGB.r) * ratio
        let g = baseRGB.g + (warmRGB.g - baseRGB.g) * ratio
        let b = baseRGB.b + (warmRGB.b - baseRGB.b) * ratio
        let baseColor = Color(red: r, green: g, blue: b)
        
        let minOpacity: Double = colorScheme == .dark ? 0.45 : 0.4
        let maxOpacity: Double = colorScheme == .dark ? 0.9  : 0.85
        let opacity = minOpacity + (maxOpacity - minOpacity) * ratio
        
        return baseColor.opacity(opacity)
    }
    
    private func strokeColorForNode(_ node: TreemapNode) -> Color {
        // 统一使用白色细边框，选中时略亮
        if selectedNode?.id == node.id {
            return Color.white.opacity(0.95)
        } else {
            return Color.white.opacity(colorScheme == .dark ? 0.7 : 0.8)
        }
    }
    
    private func strokeWidthForNode(_ node: TreemapNode) -> CGFloat {
        // 选中节点边框略粗，其余保持极细
        if selectedNode?.id == node.id {
            return 2.0
        } else {
            return 0.8
        }
    }
    
    private func textColorForNode(_ node: TreemapNode) -> Color {
        // 文本始终使用高对比色，避免因颜色变化影响可读性
        return colorScheme == .dark ? .white : .black
    }
    
    private func findNode(at location: CGPoint, in rootNode: TreemapNode?) -> TreemapNode? {
        guard let rootNode = rootNode else { return nil }
        
        // Check children first (they're on top) - depth-first search
        for child in rootNode.children.reversed() { // Reversed for proper hit testing
            if child.rect.contains(location) {
                // If this child has children, recursively search
                if !child.children.isEmpty {
                    if let found = findNode(at: location, in: child) {
                        return found
                    }
                }
                return child
            }
        }
        
        return nil
    }
    
}

/// 悬停时显示的块名称与大小
struct TreemapHoverTooltip: View {
    let node: TreemapNode
    @Environment(\.colorScheme) private var colorScheme
    
    private var sizePercentString: String {
        let pct = max(0, min(1, node.unusedRatio)) * 100
        return String(format: "%.1f%%", pct)
    }
    
    private var fileCountText: String {
        let stats = fileCountStats(for: node)
        guard stats.total > 0, stats.unused > 0 else { return "" }
        return "Unused files: \(stats.unused) / \(stats.total)"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(node.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .primary)
                .lineLimit(2)
            Text(formatSizeInKB(node.size))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            if node.unusedRatio > 0 {
                Text("Unused: \(sizePercentString) of size")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            let countText = fileCountText
            if !countText.isEmpty {
                Text(countText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(colorScheme == .dark ? Color.black.opacity(0.85) : Color.white.opacity(0.95))
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - 按文件夹展开
// OutlineGroup 的 children 参数要求 KeyPath 指向 [Element]?，TreemapNode.children 是 [TreemapNode]，故用包装类型。

private struct OutlineFolderItem: Identifiable {
    let id: UUID
    let name: String
    let size: Int64
    let relativePath: String
    /// 当前节点无用占比（0~1），来源于 TreemapNode.unusedRatio
    let unusedRatio: Double
    /// 无子节点时为 nil，满足 OutlineGroup 的 KeyPath<_, [Self]?> 要求
    let children: [OutlineFolderItem]?
    
    init(from node: TreemapNode) {
        id = node.id
        name = node.name
        size = node.size
        relativePath = node.relativePath
        unusedRatio = node.unusedRatio
        children = node.children.isEmpty ? nil : node.children.map { OutlineFolderItem(from: $0) }
    }
    
    /// 用于搜索过滤后重建子树（保留匹配节点及其祖先）
    init(id: UUID, name: String, size: Int64, relativePath: String, unusedRatio: Double, children: [OutlineFolderItem]?) {
        self.id = id
        self.name = name
        self.size = size
        self.relativePath = relativePath
        self.unusedRatio = unusedRatio
        self.children = children
    }
}

/// 按文件夹展开列表排序维度
private enum FolderListSortKey {
    case name
    case size
    case unusedRatio
}

struct GroupedByFolderView: View {
    let rootNode: TreemapNode?
    let projectRoot: String?
    @Binding var searchText: String
    @Binding var requestSearchFocus: Bool
    @FocusState private var isSearchFocused: Bool
    @State private var folderSortKey: FolderListSortKey = .name
    @State private var folderSortAscending: Bool = true
    
    init(rootNode: TreemapNode?, projectRoot: String?, searchText: Binding<String>, requestSearchFocus: Binding<Bool> = .constant(false)) {
        self.rootNode = rootNode
        self.projectRoot = projectRoot
        _searchText = searchText
        _requestSearchFocus = requestSearchFocus
    }
    
    private var totalSize: Int64 {
        rootNode?.size ?? 1
    }
    
    /// 转为 OutlineFolderItem 树，供 OutlineGroup 使用（children 为可选）
    private var outlineItems: [OutlineFolderItem] {
        (rootNode?.children ?? []).map { OutlineFolderItem(from: $0) }
    }
    
    /// 按搜索关键词过滤树：保留名称或路径包含关键词的节点及其祖先，子节点递归过滤
    private func filteredOutlineItems(roots: [OutlineFolderItem], query: String) -> [OutlineFolderItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return roots }
        return roots.flatMap { filterItem($0, query: q) }
    }
    
    private func filterItem(_ item: OutlineFolderItem, query: String) -> [OutlineFolderItem] {
        let matchSelf = item.name.localizedCaseInsensitiveContains(query)
            || item.relativePath.localizedCaseInsensitiveContains(query)
        if matchSelf { return [item] }
        guard let children = item.children else { return [] }
        let filteredChildren = children.flatMap { filterItem($0, query: query) }
        if filteredChildren.isEmpty { return [] }
        return [OutlineFolderItem(
            id: item.id,
            name: item.name,
            size: item.size,
            relativePath: item.relativePath,
            unusedRatio: item.unusedRatio,
            children: filteredChildren
        )]
    }
    
    private var displayedOutlineItems: [OutlineFolderItem] {
        let filtered = filteredOutlineItems(roots: outlineItems, query: searchText)
        return sortOutlineItems(filtered)
    }
    
    /// 按当前排序规则对各层节点进行排序
    private func sortOutlineItems(_ items: [OutlineFolderItem]) -> [OutlineFolderItem] {
        let sortedThisLevel: [OutlineFolderItem]
        switch folderSortKey {
        case .name:
            sortedThisLevel = items.sorted {
                folderSortAscending
                    ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending
            }
        case .size:
            sortedThisLevel = items.sorted {
                folderSortAscending ? $0.size < $1.size : $0.size > $1.size
            }
        case .unusedRatio:
            sortedThisLevel = items.sorted {
                folderSortAscending ? $0.unusedRatio < $1.unusedRatio : $0.unusedRatio > $1.unusedRatio
            }
        }
        // 递归对 children 排序
        return sortedThisLevel.map { item in
            if let children = item.children {
                return OutlineFolderItem(
                    id: item.id,
                    name: item.name,
                    size: item.size,
                    relativePath: item.relativePath,
                    unusedRatio: item.unusedRatio,
                    children: sortOutlineItems(children)
                )
            } else {
                return item
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 搜索栏（仅在此 Tab 展示）
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("按名称或路径搜索…", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .onChange(of: requestSearchFocus) { _, newValue in
                if newValue {
                    isSearchFocused = true
                    requestSearchFocus = false
                }
            }
            
            // 表头（每列居左），支持按 Size / 无用占比排序
            HStack(alignment: .center, spacing: 0) {
                Text("Name")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.headline)
                Button {
                    if folderSortKey == .size {
                        folderSortAscending.toggle()
                    } else {
                        folderSortKey = .size
                        folderSortAscending = false
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text("Size (KB)")
                        if folderSortKey == .size {
                            Image(systemName: folderSortAscending ? "arrow.up" : "arrow.down")
                                .font(.caption2)
                        }
                    }
                    .frame(width: 100, alignment: .leading)
                }
                .buttonStyle(.plain)
                .font(.headline)
                Text("Percent")
                    .frame(width: 70, alignment: .leading)
                    .font(.headline)
                Button {
                    if folderSortKey == .unusedRatio {
                        folderSortAscending.toggle()
                    } else {
                        folderSortKey = .unusedRatio
                        folderSortAscending = false
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text("无用占比")
                        if folderSortKey == .unusedRatio {
                            Image(systemName: folderSortAscending ? "arrow.up" : "arrow.down")
                                .font(.caption2)
                        }
                    }
                    .frame(width: 80, alignment: .leading)
                }
                .buttonStyle(.plain)
                .font(.headline)
            }
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.06))
            
            List {
                OutlineGroup(displayedOutlineItems, id: \.id, children: \.children) { item in
                    HStack(alignment: .center, spacing: 0) {
                        Text(item.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(formatSizeInKB(item.size))
                            .frame(width: 100, alignment: .leading)
                            .monospacedDigit()
                        Text(percentString(size: item.size))
                            .frame(width: 70, alignment: .leading)
                            .monospacedDigit()
                        Text(unusedPercentString(ratio: item.unusedRatio))
                            .frame(width: 80, alignment: .leading)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button("Copy Name") {
                            #if os(macOS)
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(item.name, forType: .string)
                            #endif
                        }
                        if let projectRoot, !item.relativePath.isEmpty {
                            Button("Show in Finder") {
                                #if os(macOS)
                                let fullPath = (projectRoot as NSString).appendingPathComponent(item.relativePath)
                                NSWorkspace.shared.selectFile(
                                    fullPath,
                                    inFileViewerRootedAtPath: (projectRoot as NSString).deletingLastPathComponent
                                )
                                #endif
                            }
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }
    
    private func percentString(size: Int64) -> String {
        guard totalSize > 0 else { return "0" }
        let pct = Double(size) / Double(totalSize) * 100
        return String(format: "%.2f%%", pct)
    }
    
    private func unusedPercentString(ratio: Double) -> String {
        let clamped = max(0.0, min(1.0, ratio))
        guard clamped > 0 else { return "—" }
        let pct = clamped * 100
        return String(format: "%.1f%%", pct)
    }
    
}

// MARK: - 重复度 Tab（代码重复 + 资源重复）

struct DuplicateTabView: View {
    let project: AnalysisProject?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if project == nil {
                ContentUnavailableView(
                    "无分析数据",
                    systemImage: "doc.on.doc",
                    description: Text("请先完成分析并开启代码/资源重复扫描")
                )
                Spacer()
            } else if (project?.duplicateCodeGroups.isEmpty ?? true) && (project?.duplicateResourceGroups.isEmpty ?? true) {
                // 未开启重复扫描或扫描结果为空时的默认展示（与 Pods 依赖风格一致）
                ContentUnavailableView(
                    "暂无重复度数据",
                    systemImage: "doc.on.doc",
                    description: Text("未检测到代码/资源重复，或尚未在分析配置中开启重复扫描。请在左侧分析配置中打开「代码重复扫描」「资源重复扫描」后重新分析。")
                )
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        codeDuplicateSection
                        resourceDuplicateSection
                    }
                    .padding()
                }
            }
        }
    }
    
    @ViewBuilder private var codeDuplicateSection: some View {
        let groups = project?.duplicateCodeGroups ?? []
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("代码重复")
                    .font(.headline)
                Text("\(groups.count) 组")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if groups.isEmpty {
                Text("未检测到重复代码，或未开启代码重复扫描")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                DisclosureGroup("代码重复组列表") {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(groups) { group in
                            DisclosureGroup(content: {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(Array(group.entries.enumerated()), id: \.offset) { _, entry in
                                        Text(entry.relativePath)
                                            .font(.caption)
                                            .textSelection(.enabled)
                                    }
                                }
                                .padding(.leading, 8)
                            }, label: {
                                HStack {
                                    Text("\(group.count) 份 · 相似度 \(String(format: "%.0f%%", group.similarity * 100))")
                                        .font(.subheadline)
                                }
                            })
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    @ViewBuilder private var resourceDuplicateSection: some View {
        let groups = project?.duplicateResourceGroups ?? []
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("资源重复")
                    .font(.headline)
                Text("\(groups.count) 组")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if groups.isEmpty {
                Text("未检测到重复资源，或未开启资源重复扫描")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                DisclosureGroup("资源重复组列表") {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(groups) { group in
                            DisclosureGroup(content: {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(Array(group.entries.enumerated()), id: \.offset) { _, entry in
                                        HStack {
                                            Text(entry.relativePath)
                                                .font(.caption)
                                                .textSelection(.enabled)
                                            Text(formatSizeInKB(entry.size))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .padding(.leading, 8)
                            }, label: {
                                HStack {
                                    Text("\(group.count) 份 · 共 \(formatSizeInKB(group.totalSize))")
                                        .font(.subheadline)
                                }
                            })
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Pods 依赖 Tab（主仓粒度：仅展示如 AcrossJCE，不展示子仓 AcrossJCE/comm）

/// 主仓名：取名称第一段，委托给 PodsSummaryBuilder 供列表与关系图共用
private func mainRepoName(_ podName: String) -> String {
    PodsSummaryBuilder.mainRepoName(podName)
}

/// 从 Pod 树 + 分析结果按主仓聚合为一行（委托给 PodsSummaryBuilder）
private func buildPodsMainLibRows(pods: [PodsDependencyInfo], analysisResults: [AnalysisResult]) -> [PodsMainLibRow] {
    PodsSummaryBuilder.buildMainLibRows(pods: pods, analysisResults: analysisResults)
}

/// 列表排序维度
private enum PodsListSortKey: String, CaseIterable {
    case size = "体积"
    case unusedRatio = "无用占比"
    case dependedByCount = "被依赖库数量"
}

struct PodsDependencyTabView: View {
    let project: AnalysisProject?
    @State private var showPodsGraph: Bool = false
    @State private var expandedIds: Set<String> = []
    @State private var sortKey: PodsListSortKey = .size
    @State private var sortAscending: Bool = false
    @State private var podsSearchText: String = ""

    private var podsResult: PodsDependencyResult? {
        project?.podsDependencyResult
    }

    /// 仅主库（顶层 Pod），不包含子库
    private var pods: [PodsDependencyInfo] {
        podsResult?.pods ?? []
    }

    private var mainLibRows: [PodsMainLibRow] {
        guard !pods.isEmpty, let proj = project else { return [] }
        return buildPodsMainLibRows(pods: pods, analysisResults: proj.analysisResultsArray)
    }

    /// 按当前排序规则排序后的主库行（仅主库粒度，无子库结构）
    private var sortedMainLibRows: [PodsMainLibRow] {
        switch sortKey {
        case .size:
            return mainLibRows.sorted { sortAscending ? $0.size < $1.size : $0.size > $1.size }
        case .unusedRatio:
            return mainLibRows.sorted {
                sortAscending ? $0.unusedRatio < $1.unusedRatio : $0.unusedRatio > $1.unusedRatio
            }
        case .dependedByCount:
            return mainLibRows.sorted { sortAscending ? $0.dependedByCount < $1.dependedByCount : $0.dependedByCount > $1.dependedByCount }
        }
    }

    /// 按搜索关键词过滤后的主库（列表与关系图共用）
    private var filteredPods: [PodsDependencyInfo] {
        let q = podsSearchText.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return pods }
        return pods.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.version.localizedCaseInsensitiveContains(q)
        }
    }

    /// 按搜索过滤后的主库行（列表用）
    private var filteredSortedMainLibRows: [PodsMainLibRow] {
        let q = podsSearchText.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return sortedMainLibRows }
        return sortedMainLibRows.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.version.localizedCaseInsensitiveContains(q)
        }
    }

    /// 关系图用 JSON：主仓粒度；有搜索时仅展示匹配主仓 + 其依赖的主仓（两层），并按主仓体积调整节点大小
    private var podsGraphJSON: String? {
        // 主仓 -> 体积（字节） & 无用占比，来自已计算的主库行
        let sizeByMain = Dictionary(uniqueKeysWithValues: mainLibRows.map { ($0.name, $0.size) })
        let unusedRatioByMain = Dictionary(uniqueKeysWithValues: mainLibRows.map { ($0.name, $0.unusedRatio) })
        let q = podsSearchText.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            return EChartsGraphData.toJSONMainLevelOnly(
                pods: pods,
                mainRepoName: mainRepoName,
                visibleMainNames: nil,
                onlyLinksFrom: nil,
                sizeByMain: sizeByMain,
                unusedRatioByMain: unusedRatioByMain
            )
        }
        let matchingMains = Set(filteredPods.map { mainRepoName($0.name) })
        let mainDeps = EChartsGraphData.mainLevelDependencies(pods: pods, mainRepoName: mainRepoName)
        let dependencyMains = matchingMains.flatMap { mainDeps[$0] ?? [] }
        let visibleMains = matchingMains.union(dependencyMains)
        return EChartsGraphData.toJSONMainLevelOnly(
            pods: pods,
            mainRepoName: mainRepoName,
            visibleMainNames: visibleMains,
            onlyLinksFrom: matchingMains,
            sizeByMain: sizeByMain,
            unusedRatioByMain: unusedRatioByMain
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if project == nil || podsResult == nil || pods.isEmpty {
                ContentUnavailableView(
                    "无 Pods 依赖数据",
                    systemImage: "square.stack.3d.up",
                    description: Text("请先完成分析并开启 Pods 库依赖扫描，且工程根目录存在 Podfile.lock")
                )
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if let path = podsResult?.podfileLockPath {
                        Text("来源: \(path)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField("搜索 Pod 名称或版本", text: $podsSearchText)
                                .textFieldStyle(.roundedBorder)
                        }
                        .frame(maxWidth: 280)
                        Picker("", selection: $showPodsGraph) {
                            Text("列表").tag(false)
                            Text("关系图").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .help("关系图使用 ECharts 力导向图展示依赖关系（需网络加载 CDN）")
                        if !podsSearchText.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text("\(filteredSortedMainLibRows.count) / \(mainLibRows.count) 个主仓")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 30)
                    if showPodsGraph {
                        EChartsWebView(mode: .graph, dataJSON: podsGraphJSON)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        HStack(alignment: .center, spacing: 0) {
                            Text("Pod 名称")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .font(.headline)
                            Text("版本")
                                .frame(width: 160, alignment: .leading)
                                .font(.headline)
                            Button {
                                sortKey = .size
                                sortAscending = (sortKey == .size ? !sortAscending : false)
                            } label: {
                                HStack(spacing: 2) {
                                    Text("体积")
                                    if sortKey == .size {
                                        Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                                            .font(.caption2)
                                    }
                                }
                                .frame(width: 88, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .font(.headline)
                            Button {
                                sortKey = .unusedRatio
                                sortAscending = (sortKey == .unusedRatio ? !sortAscending : false)
                            } label: {
                                HStack(spacing: 2) {
                                    Text("无用占比")
                                    if sortKey == .unusedRatio {
                                        Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                                            .font(.caption2)
                                    }
                                }
                                .frame(width: 88, alignment: .trailing)
                            }
                            .buttonStyle(.plain)
                            .font(.headline)
                            Button {
                                sortKey = .dependedByCount
                                sortAscending = (sortKey == .dependedByCount ? !sortAscending : false)
                            } label: {
                                HStack(spacing: 2) {
                                    Text("被依赖库数量")
                                    if sortKey == .dependedByCount {
                                        Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                                            .font(.caption2)
                                    }
                                }
                                .frame(width: 100, alignment: .trailing)
                            }
                            .buttonStyle(.plain)
                            .font(.headline)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.primary.opacity(0.06))
                        List {
                            ForEach(filteredSortedMainLibRows) { row in
                                DisclosureGroup(isExpanded: Binding(
                                    get: { expandedIds.contains(row.id) },
                                    set: { if $0 { expandedIds.insert(row.id) } else { expandedIds.remove(row.id) } }
                                )) {
                                    if !row.dependedByList.isEmpty {
                                        VStack(alignment: .leading, spacing: 4) {
                                            ForEach(row.dependedByList, id: \.self) { name in
                                                Text("• \(name)")
                                                    .font(.subheadline)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .padding(.vertical, 4)
                                        .padding(.leading, 8)
                                    } else {
                                        Text("无")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .padding(.vertical, 4)
                                            .padding(.leading, 8)
                                    }
                                } label: {
                                    HStack(alignment: .center, spacing: 0) {
                                        Text(row.name)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .lineLimit(1)
                                        Text(row.version)
                                            .frame(width: 160, alignment: .leading)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                        Text(row.size > 0 ? formatSizeInKB(row.size) : "—")
                                            .frame(width: 88, alignment: .leading)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                        let ratioValue = max(0.0, min(1.0, row.unusedRatio)) * 100
                                        let ratioText = (row.size > 0 && row.unusedSize > 0)
                                            ? String(format: "%.1f%%", ratioValue)
                                            : "—"
                                        Text(ratioText)
                                            .frame(width: 88, alignment: .trailing)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                        Text("\(row.dependedByCount)")
                                            .frame(width: 100, alignment: .trailing)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    .frame(minHeight: 30, alignment: .center)
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                        .listStyle(.inset(alternatesRowBackgrounds: true))
                    }
                }
            }
        }
    }
}

/// 展示某个 Treemap 节点下所有无用文件的详情列表（Name / Size / Percent），样式参考按文件夹展开视图。
struct UnusedItemsListView: View {
    let rootNode: TreemapNode
    let projectRoot: String?

    private enum ItemTab: String, CaseIterable {
        case resource = "Resource"
        case code = "Code"
    }
    @State private var selectedTab: ItemTab = .resource

    private var totalSize: Int64 {
        max(rootNode.size, 1)
    }

    private var allUnusedLeaves: [TreemapNode] {
        var result: [TreemapNode] = []
        collectUnusedLeaves(from: rootNode, into: &result)
        return result.sorted { $0.size > $1.size }
    }

    private var unusedLeaves: [TreemapNode] {
        let typeFilter: FileType = selectedTab == .code ? .code : .resource
        return allUnusedLeaves.filter { $0.fileType == typeFilter }
    }

    private var codeCount: Int {
        allUnusedLeaves.filter { $0.fileType == .code }.count
    }

    private var resourceCount: Int {
        allUnusedLeaves.filter { $0.fileType == .resource }.count
    }

    /// 用于 Unused Items 列表展示的尺寸：优先使用工程物理文件大小，找不到时回退 Treemap 节点 size。
    private func displaySize(for node: TreemapNode) -> Int64 {
        guard let projectRoot, !node.relativePath.isEmpty else { return node.size }
        let fullPath = (projectRoot as NSString).appendingPathComponent(node.relativePath)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath),
           let fileSize = attrs[.size] as? NSNumber {
            return fileSize.int64Value
        }
        return node.size
    }

    private var totalUnusedDisplaySize: Int64 {
        unusedLeaves.reduce(0) { $0 + displaySize(for: $1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部标题 + 切换 Tab
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Unused Name")
                            .font(.headline)
                        Text("Total Unused Size: \(formatSizeInKB(totalUnusedDisplaySize))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Size (KB)")
                        .frame(width: 100, alignment: .leading)
                        .font(.headline)
                    Text("Percent")
                        .frame(width: 70, alignment: .leading)
                        .font(.headline)

                    // 导出 CSV 按钮
                    Button(action: exportCSV) {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .padding(.leading, 12)
                }

                Picker("", selection: $selectedTab) {
                    Text("Resource (\(resourceCount))").tag(ItemTab.resource)
                    Text("Code (\(codeCount))").tag(ItemTab.code)
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.primary.opacity(0.06))

            if unusedLeaves.isEmpty {
                VStack {
                    Spacer()
                    Text("No unused \(selectedTab.rawValue.lowercased()) files detected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .italic()
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(unusedLeaves, id: \.id) { node in
                        HStack(alignment: .center, spacing: 0) {
                            Text(node.name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(formatSizeInKB(displaySize(for: node)))
                                .frame(width: 100, alignment: .leading)
                                .monospacedDigit()
                            Text(percentString(size: node.size))
                                .frame(width: 70, alignment: .leading)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 2)
                        .help(node.relativePath)
                        .contextMenu {
                            Button("Copy Name") {
                                #if os(macOS)
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.setString(node.name, forType: .string)
                                #endif
                            }
                            if let projectRoot, !node.relativePath.isEmpty {
                                Button("Show in Finder") {
                                    #if os(macOS)
                                    let fullPath = (projectRoot as NSString).appendingPathComponent(node.relativePath)
                                    NSWorkspace.shared.selectFile(
                                        fullPath,
                                        inFileViewerRootedAtPath: (projectRoot as NSString).deletingLastPathComponent
                                    )
                                    #endif
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    private func percentString(size: Int64) -> String {
        let pct = Double(size) / Double(totalSize) * 100
        return String(format: "%.2f%%", pct)
    }

    /// 将当前 Tab 的无用文件列表导出为 CSV 文件
    private func exportCSV() {
        #if os(macOS)
        // 构建 CSV 内容
        var lines: [String] = ["Name,Size (Bytes),Size (KB),Percent,Relative Path"]
        for node in unusedLeaves {
            let size = displaySize(for: node)
            let sizeKB = formatSizeInKB(size)
            let pct = percentString(size: node.size)
            // 对含逗号或引号的字段做 CSV 转义
            let escapedName = node.name.contains(",") ? "\"\(node.name)\"" : node.name
            let escapedPath = node.relativePath.contains(",") ? "\"\(node.relativePath)\"" : node.relativePath
            lines.append("\(escapedName),\(size),\(sizeKB),\(pct),\(escapedPath)")
        }
        let csvString = lines.joined(separator: "\n")

        // 弹出保存面板
        let panel = NSSavePanel()
        panel.title = "Export Unused \(selectedTab.rawValue) Items"
        panel.nameFieldStringValue = "unused_\(selectedTab.rawValue.lowercased())_items.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try csvString.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Export Failed"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
        #endif
    }
}

// MARK: - Shared Helpers & Windows

/// 递归统计某个节点下叶子文件总数与无用文件数（按 isUnused 标记）
private func fileCountStats(for node: TreemapNode) -> (total: Int, unused: Int) {
    if node.children.isEmpty {
        return (1, node.isUnused ? 1 : 0)
    }
    var total = 0
    var unused = 0
    for child in node.children {
        let stats = fileCountStats(for: child)
        total += stats.total
        unused += stats.unused
    }
    return (total, unused)
}

/// 收集某个节点子树中的所有无用叶子节点（文件）
private func collectUnusedLeaves(from node: TreemapNode, into array: inout [TreemapNode]) {
    if node.children.isEmpty {
        if node.isUnused {
            array.append(node)
        }
        return
    }
    for child in node.children {
        collectUnusedLeaves(from: child, into: &array)
    }
}

#if os(macOS)
/// 管理「Unused Items」独立窗口，避免被 SwiftUI 视图释放。
final class UnusedItemsWindowManager {
    static let shared = UnusedItemsWindowManager()
    private var windows: [NSWindow] = []
    
    func open(for node: TreemapNode, projectRoot: String?) {
        let controller = NSHostingController(rootView: UnusedItemsListView(rootNode: node, projectRoot: projectRoot))
        let window = NSWindow(contentViewController: controller)
        window.title = "Unused Items – \(node.name)"
        window.setContentSize(NSSize(width: 520, height: 360))
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        windows.append(window)
    }
}
#endif

struct NodeInfoPanel: View {
    let node: TreemapNode
    /// 点击查看当前块下的无用文件详情
    var onShowUnusedDetails: ((TreemapNode) -> Void)? = nil
    
    private var sizePercentString: String {
        let pct = max(0, min(1, node.unusedRatio)) * 100
        return String(format: "%.1f%%", pct)
    }
    
    private var fileStats: (total: Int, unused: Int) {
        fileCountStats(for: node)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImageForFileType(node.fileType))
                    .foregroundColor(colorForFileType(node.fileType))
                
                Text(node.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Path: \(node.relativePath)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Size: \(formatSizeInKB(node.size))")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("Type: \(node.fileType.rawValue)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if node.unusedRatio > 0 {
                    Text("Unused size: \(sizePercentString)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .fontWeight(.medium)
                }
                
                let stats = fileStats
                if stats.total > 0 {
                    Text("Unused items: \(stats.unused) / \(stats.total)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text("Contains \(node.children.count) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let onShowUnusedDetails, fileStats.unused > 0 {
                    Button("View unused items…") {
                        onShowUnusedDetails(node)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: 4)
        .padding()
    }
    
    private func systemImageForFileType(_ fileType: FileType) -> String {
        switch fileType {
        case .code:
            return "curlybraces"
        case .resource:
            return "photo"
        case .framework:
            return "building.2"
        case .directory:
            return "folder"
        case .other:
            return "doc"
        }
    }
    
    private func colorForFileType(_ fileType: FileType) -> Color {
        switch fileType {
        case .code:
            return .blue
        case .resource:
            return .green
        case .framework:
            return .orange
        case .directory:
            return .gray
        case .other:
            return .purple
        }
    }
    
}

#Preview {
    TreemapView(project: nil)
}

struct TreemapLegendView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Legend")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                // File Type Legend
                Text("File Types")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                VStack(alignment: .leading, spacing: 6) {
                    LegendItem(
                        color: .blue.opacity(colorScheme == .dark ? 0.8 : 0.7),
                        icon: "curlybraces",
                        title: "Code Files",
                        description: "Swift, Objective-C, C++"
                    )
                    
                    LegendItem(
                        color: .green.opacity(colorScheme == .dark ? 0.8 : 0.7),
                        icon: "photo",
                        title: "Resources",
                        description: "Images, Audio, Data"
                    )
                    
                    LegendItem(
                        color: .orange.opacity(colorScheme == .dark ? 0.8 : 0.7),
                        icon: "building.2",
                        title: "Frameworks",
                        description: "Libraries, Dependencies"
                    )
                    
                    LegendItem(
                        color: .gray.opacity(colorScheme == .dark ? 0.8 : 0.7),
                        icon: "folder",
                        title: "Directories",
                        description: "Folder containers"
                    )
                }
                
                Divider()
                
                // Unused Content 说明：无无用=蓝，有用=红+透明度
                Text("Unused Content")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.blue.opacity(colorScheme == .dark ? 0.75 : 0.65))
                            .frame(width: 16, height: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("无无用")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("块内无未使用内容时显示蓝色")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    HStack(spacing: 8) {
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.red.opacity(0.4),
                                Color.red.opacity(0.9)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 36, height: 14)
                        .cornerRadius(3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("存在无用")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("红色表示，透明度随无用占比升高")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Divider()
                
                // Interaction Legend
                Text("Interactions")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.tap.fill")
                            .foregroundColor(.accentColor)
                            .frame(width: 20)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Click to select, arrow button to drill down")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("Navigate into folders")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Image(systemName: "cursorarrow")
                            .foregroundColor(.primary)
                            .frame(width: 20)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hover for name & size")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("Tooltip on block")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.primary)
                            .frame(width: 20)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pinch to zoom")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("Zoom in/out view")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct LegendItem: View {
    let color: Color
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Rectangle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .cornerRadius(2)
                
                Image(systemName: icon)
                    .foregroundColor(color)
                    .frame(width: 12)
            }
            .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}
