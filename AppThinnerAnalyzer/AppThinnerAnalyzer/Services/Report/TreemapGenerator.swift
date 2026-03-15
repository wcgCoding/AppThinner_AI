import Foundation
import CoreGraphics

// MARK: - Treemap 生成器协议
// 负责将分析结果转换为 Treemap 可视化数据结构（TreemapNode 树），
// 支持按文件夹层级展开、下钻、「其他」合并等交互模式。

protocol TreemapGeneratorProtocol {
    /// 从分析结果生成 Treemap 根节点（含布局计算）
    func generateTreemap(
        from analysisResults: [AnalysisResult],
        in bounds: CGRect
    ) -> TreemapNode
    
    /// 从 node 起算最多展示 maxDepth 层子块（下钻后仍保持该层数）
    func updateLayout(
        for node: TreemapNode,
        in bounds: CGRect,
        maxDepth: Int
    ) -> TreemapNode
    
    /// 生成每层带「其他」合并的树，供按文件夹展开视图使用，「其他」可展开下钻
    func cappedTreeForFolderDisplay(from node: TreemapNode, maxPerLevel: Int) -> TreemapNode
}

// MARK: - TreemapGenerator Implementation

class TreemapGenerator: TreemapGeneratorProtocol {
    
    /// 每层最多展示的块数量，超出部分合并为「其他」，避免右下角堆积
    private let maxBlocksPerLevel = 48
    
    // MARK: - Public Methods
    
    func generateTreemap(
        from analysisResults: [AnalysisResult],
        in bounds: CGRect
    ) -> TreemapNode {
        print("🗺️ [TreemapGenerator] Input: \(analysisResults.count) results")
        let directoryStructure = buildDirectoryStructure(from: analysisResults)
        let totalInTree = countFilesInDirectoryNode(directoryStructure)
        print("🗺️ [TreemapGenerator] Root children: \(directoryStructure.children.count), total files in tree: \(totalInTree)")
        return createTreemapNode(from: directoryStructure, in: bounds)
    }
    
    func updateLayout(
        for node: TreemapNode,
        in bounds: CGRect,
        maxDepth: Int = 3
    ) -> TreemapNode {
        return updateNodeLayout(node, in: bounds, depth: 0, maxDepth: maxDepth)
    }
    
    // MARK: - Private Helper Methods
    
    private func buildDirectoryStructure(from results: [AnalysisResult]) -> DirectoryNode {
        var directories: [String: DirectoryNode] = [:]
        var rootFiles: [FileNode] = []
        
        // 第一步：预处理静态库文件，检测是否有对应的源码目录
        // 如果 .a 文件路径对应的 Pod 目录已经存在源码文件，则跳过 .a 文件，避免重复
        var staticLibPaths: Set<String> = []
        var sourcePathsUnderPods: Set<String> = []
        
        for result in results {
            let path = result.relativePath
            if path.hasSuffix(".a") {
                staticLibPaths.insert(path)
            }
            // 记录 Pods 下的源码路径
            if path.hasPrefix("Pods/") && (path.hasSuffix(".m") || path.hasSuffix(".mm") || path.hasSuffix(".swift")) {
                // 提取 Pod 模块名（Pods/ModuleName/...）
                let comps = path.components(separatedBy: "/")
                if comps.count >= 2 {
                    let podModule = comps[0] + "/" + comps[1]
                    sourcePathsUnderPods.insert(podModule)
                }
            }
        }

        for result in results {
            let path = result.relativePath
            
            // 过滤：如果 .a 文件所在的 Pod 模块已经有源码文件，则跳过 .a 文件
            if path.hasSuffix(".a") && path.hasPrefix("Pods/") {
                let comps = path.components(separatedBy: "/")
                if comps.count >= 2 {
                    let podModule = comps[0] + "/" + comps[1]
                    if sourcePathsUnderPods.contains(podModule) {
                        print("📁 [TreemapGenerator] 跳过 .a 文件（已有源码）: \(path)")
                        continue
                    }
                }
            }
            
            let pathComponents = result.relativePath.components(separatedBy: "/")
            if pathComponents.count == 1 {
                rootFiles.append(createFileNode(from: result))
            } else {
                addFileToDirectoryStructure(result: result, pathComponents: pathComponents, directories: &directories)
            }
        }

        let flatFileCount = directories.values.reduce(0) { $0 + $1.files.count }
        print("📁 [TreemapGenerator] Flat: \(directories.count) dirs, \(flatFileCount) files in dirs, \(rootFiles.count) root files")

        let nestedDirectories = buildNestedDirectoriesRecursive(from: directories)
        let nestedFileCount = nestedDirectories.reduce(0) { $0 + countFilesInDirectoryNode($1) }
        print("📁 [TreemapGenerator] Tree: \(nestedDirectories.count) top-level, total files in tree: \(nestedFileCount)\(nestedFileCount != flatFileCount ? " ⚠️ mismatch (expected \(flatFileCount))" : "")")
        for child in nestedDirectories.sorted(by: { $0.totalSize > $1.totalSize }).prefix(15) {
            print("   - \(child.name): \(child.totalSize) (\(child.totalSize/1024) KB), files: \(child.files.count), children: \(child.children.count)")
        }
        let rootTotalSize = rootFiles.reduce(0) { $0 + $1.totalSize }
        let rootUnusedSize = rootFiles.filter { $0.isUnused }.reduce(0) { $0 + $1.totalSize }

        return DirectoryNode(
            name: "Root",
            relativePath: "",
            children: nestedDirectories,
            files: rootFiles,
            totalSize: rootTotalSize + nestedDirectories.reduce(0) { $0 + $1.totalSize },
            unusedSize: rootUnusedSize + nestedDirectories.reduce(0) { $0 + $1.unusedSize }
        )
    }
    
    private func createFileNode(from result: AnalysisResult) -> FileNode {
        // 对动态库（.app 内仅以 frameworkSize 体现、codeSize 为 0 的条目）强制视为「有用」，
        // 避免 InMobiSDK 等三方动态库被错误标记为 100% 无用。
        let isDynamicLibrary = result.frameworkSize > 0 && result.codeSize == 0
        let isUnused = isDynamicLibrary ? false : result.isUnused
        
        return FileNode(
            relativePath: result.relativePath,
            fileName: result.fileName,
            codeSize: result.codeSize,
            resourceSize: result.resourceSize,
            frameworkSize: result.frameworkSize,
            isUnused: isUnused,
            unusedSource: result.unusedSourceEnum
        )
    }
    
    private func addFileToDirectoryStructure(
        result: AnalysisResult,
        pathComponents: [String],
        directories: inout [String: DirectoryNode]
    ) {
        let directoryPath = pathComponents.dropLast().joined(separator: "/")
        let fileNode = createFileNode(from: result)
        
        if var directory = directories[directoryPath] {
            var updatedFiles = directory.files
            updatedFiles.append(fileNode)
            directories[directoryPath] = DirectoryNode(
                name: directory.name,
                relativePath: directory.relativePath,
                children: directory.children,
                files: updatedFiles,
                totalSize: directory.totalSize + fileNode.totalSize,
                unusedSize: directory.unusedSize + (fileNode.isUnused ? fileNode.totalSize : 0)
            )
        } else {
            let dirName = pathComponents.dropLast().last ?? (directoryPath as NSString).lastPathComponent
            directories[directoryPath] = DirectoryNode(
                name: dirName,
                relativePath: directoryPath,
                children: [],
                files: [fileNode],
                totalSize: fileNode.totalSize,
                unusedSize: fileNode.isUnused ? fileNode.totalSize : 0
            )
        }
    }
    
    /// 自顶向下从 flat 递归组装树，避免 struct 值类型在「自底向上挂父」时副本不一致导致节点丢失。
    private func buildNestedDirectoriesRecursive(from flatDirectories: [String: DirectoryNode]) -> [DirectoryNode] {
        let topLevelPaths = Set(flatDirectories.keys.flatMap { key -> [String] in
            let comps = key.components(separatedBy: "/")
            return comps.isEmpty ? [] : [comps[0]]
        })
        return topLevelPaths.sorted().map { buildNodeRecursive(path: $0, flatDirectories: flatDirectories) }
    }

    /// 递归统计目录树中的文件总数（用于校验是否丢失）
    private func countFilesInDirectoryNode(_ node: DirectoryNode) -> Int {
        node.files.count + node.children.reduce(0) { $0 + countFilesInDirectoryNode($1) }
    }

    private func buildNodeRecursive(path: String, flatDirectories: [String: DirectoryNode]) -> DirectoryNode {
        let flat = flatDirectories[path]
        let pathPrefix = path.isEmpty ? "" : path + "/"
        // 从所有以 pathPrefix 开头的 key 中提取「直接子路径」：作为 key 或作为 key 的前缀都算，否则会漏掉无直接文件仅有子目录的中间层
        let directChildPaths = Set(flatDirectories.keys.flatMap { key -> [String] in
            guard key.hasPrefix(pathPrefix), key != path, !pathPrefix.isEmpty else { return [] }
            let rest = String(key.dropFirst(pathPrefix.count))
            guard !rest.isEmpty else { return [] }
            if let firstSlash = rest.firstIndex(of: "/") {
                return [pathPrefix + String(rest[..<firstSlash])]
            } else {
                return [pathPrefix + rest]
            }
        }).sorted()
        let children = directChildPaths.map { buildNodeRecursive(path: $0, flatDirectories: flatDirectories) }
        let name = flat?.name ?? (path as NSString).lastPathComponent
        let files = flat?.files ?? []
        let childTotal = children.reduce(0) { $0 + $1.totalSize }
        let childUnused = children.reduce(0) { $0 + $1.unusedSize }
        let fileTotal = files.reduce(0) { $0 + $1.totalSize }
        let fileUnused = files.filter(\.isUnused).reduce(0) { $0 + $1.totalSize }
        return DirectoryNode(
            name: name,
            relativePath: path,
            children: children,
            files: files,
            totalSize: childTotal + fileTotal,
            unusedSize: childUnused + fileUnused
        )
    }

    /// 构建完整树以便支持任意层下钻，不再限制展示深度
    private func createTreemapNode(from directory: DirectoryNode, in bounds: CGRect) -> TreemapNode {
        var children: [TreemapNode] = []
        for childDir in directory.children {
            children.append(createTreemapNodeStructureFull(from: childDir))
        }
        for file in directory.files {
            let fileUnusedRatio = file.isUnused ? 1.0 : 0.0
            children.append(TreemapNode(
                name: file.fileName,
                relativePath: file.relativePath,
                size: file.totalSize,
                children: [],
                isUnused: file.isUnused,
                unusedRatio: fileUnusedRatio,
                fileType: determineFileType(from: file),
                rect: .zero
            ))
        }
        let dirUnusedRatio = directory.totalSize > 0 ? Double(directory.unusedSize) / Double(directory.totalSize) : 0
        let layoutChildren = squarifyLayout(for: children, in: bounds)
        return TreemapNode(
            name: directory.name,
            relativePath: directory.relativePath,
            size: directory.totalSize,
            children: layoutChildren,
            isUnused: directory.unusedSize > 0,
            unusedRatio: dirUnusedRatio,
            fileType: .directory,
            rect: bounds
        )
    }

    /// 递归构建完整树形结构（不限制深度，用于多层下钻）。
    /// 注意：这里不负责具体矩形布局，仅保留目录结构与 size，rect 由上层布局函数统一计算。
    private func createTreemapNodeStructureFull(from directory: DirectoryNode) -> TreemapNode {
        var children: [TreemapNode] = []
        for childDir in directory.children {
            children.append(createTreemapNodeStructureFull(from: childDir))
        }
        for file in directory.files {
            let fileUnusedRatio = file.isUnused ? 1.0 : 0.0
            children.append(TreemapNode(
                name: file.fileName,
                relativePath: file.relativePath,
                size: file.totalSize,
                children: [],
                isUnused: file.isUnused,
                unusedRatio: fileUnusedRatio,
                fileType: determineFileType(from: file),
                rect: .zero
            ))
        }
        let dirUnusedRatio = directory.totalSize > 0 ? Double(directory.unusedSize) / Double(directory.totalSize) : 0
        return TreemapNode(
            name: directory.name,
            relativePath: directory.relativePath,
            size: directory.totalSize,
            children: children,
            isUnused: directory.unusedSize > 0,
            unusedRatio: dirUnusedRatio,
            fileType: .directory,
            rect: .zero
        )
    }
    
    // MARK: - Squarified Treemap 实现
    // 思路与 d3-hierarchy 的 treemap、treemapSquarify 一致：面积 ∝ 体积，按行贪心使长宽比尽量接近 1。
    // 若做 Web 看板，可改用 D3.js (d3-hierarchy) 或 Plotly/Matplotlib+Squarify 做快速原型；本实现为原生 Swift 便于与 App 集成。
    
    /// 使用经典 Squarified Treemap 算法为一批节点在给定矩形内布局。
    /// 核心目标：在保证面积 ∝ size 的前提下，让每个块的长宽比尽量接近 1（“方块化”），避免极端长条。
    private func squarifyLayout(for nodes: [TreemapNode], in bounds: CGRect) -> [TreemapNode] {
        guard !nodes.isEmpty else { return [] }
        
        // 按体积降序，先布大块
        var items = nodes.sorted { $0.size > $1.size }
        let totalWeight = max<Int64>(1, items.reduce(0) { $0 + max($1.size, 0) })
        let areaScale = (bounds.width * bounds.height) / CGFloat(totalWeight)
        
        var result: [TreemapNode] = []
        var row: [TreemapNode] = []
        var currentRect = bounds
        
        func area(for node: TreemapNode) -> CGFloat {
            return CGFloat(max(node.size, 0)) * areaScale
        }
        
        /// 行内最差长宽比：行沿矩形短边排布，每块面积 ∝ size，单块长宽比 = max(w/h, h/w)。
        /// 公式：短边 side，块 i 面积 a_i，则块 i 一边=side、另一边=a_i/side，长宽比 = max(side²/a_i, a_i/side²)。
        func worstAspectRatio(of row: [TreemapNode], in rect: CGRect) -> CGFloat {
            guard !row.isEmpty else { return .infinity }
            let side = min(rect.width, rect.height)
            let areas = row.map { area(for: $0) }
            guard side > 0 else { return .infinity }
            var worst: CGFloat = 0
            for a in areas where a > 0 {
                let r = max((side * side) / a, a / (side * side))
                worst = max(worst, r)
            }
            return worst
        }
        
        func layoutRow(_ row: [TreemapNode], in rect: CGRect) -> (placed: [TreemapNode], remaining: CGRect) {
            let horizontal = rect.width >= rect.height
            let rowArea = row.reduce(0) { $0 + area(for: $1) }
            var placed: [TreemapNode] = []
            var offset: CGFloat = 0
            
            if horizontal {
                let rowHeight = rowArea / rect.width
                for node in row {
                    let nodeArea = area(for: node)
                    let w = nodeArea / rowHeight
                    var updated = node
                    updated.rect = CGRect(
                        x: rect.minX + offset,
                        y: rect.minY,
                        width: w,
                        height: rowHeight
                    )
                    placed.append(updated)
                    offset += w
                }
                let remaining = CGRect(
                    x: rect.minX,
                    y: rect.minY + rowHeight,
                    width: rect.width,
                    height: max(0, rect.height - rowHeight)
                )
                return (placed, remaining)
            } else {
                let rowWidth = rowArea / rect.height
                for node in row {
                    let nodeArea = area(for: node)
                    let h = nodeArea / rowWidth
                    var updated = node
                    updated.rect = CGRect(
                        x: rect.minX,
                        y: rect.minY + offset,
                        width: rowWidth,
                        height: h
                    )
                    placed.append(updated)
                    offset += h
                }
                let remaining = CGRect(
                    x: rect.minX + rowWidth,
                    y: rect.minY,
                    width: max(0, rect.width - rowWidth),
                    height: rect.height
                )
                return (placed, remaining)
            }
        }
        
        while !items.isEmpty {
            let item = items.removeFirst()
            if row.isEmpty {
                row.append(item)
                continue
            }
            
            let currentWorst = worstAspectRatio(of: row, in: currentRect)
            var newRow = row
            newRow.append(item)
            let newWorst = worstAspectRatio(of: newRow, in: currentRect)
            
            if newWorst <= currentWorst {
                row = newRow
            } else {
                let (placed, remaining) = layoutRow(row, in: currentRect)
                result.append(contentsOf: placed)
                currentRect = remaining
                row = [item]
            }
        }
        
        if !row.isEmpty {
            let (placed, _) = layoutRow(row, in: currentRect)
            result.append(contentsOf: placed)
        }
        
        return result
    }
    
    /// 从当前节点起最多展示 maxDepth 层（depth 为当前层深度，0 表示正在布局 node 的直接子节点）。
    /// 若当前为目录且仅有一个子节点，则跳过本层、直接布局该子节点（不展示灰色上级目录），避免父子名称重叠。
    private func updateNodeLayout(_ node: TreemapNode, in bounds: CGRect, depth: Int, maxDepth: Int) -> TreemapNode {
        if node.fileType == .directory && node.children.count == 1 {
            return updateNodeLayout(node.children[0], in: bounds, depth: depth, maxDepth: maxDepth)
        }
        var updatedNode = node
        updatedNode.rect = bounds

        if !node.children.isEmpty {
            let cappedChildren = capChildrenCount(node.children, maxCount: maxBlocksPerLevel)
            let layoutChildren = squarifyLayout(for: cappedChildren, in: bounds)

            let fullyLayoutChildren = layoutChildren.map { child -> TreemapNode in
                let canRecurse = !child.children.isEmpty && (depth + 1 < maxDepth)
                if canRecurse {
                    return updateNodeLayout(child, in: child.rect, depth: depth + 1, maxDepth: maxDepth)
                } else {
                    return child
                }
            }

            updatedNode.children = fullyLayoutChildren
        }

        return updatedNode
    }
    
    /// 每层最多保留 maxCount 个块，其余按体积合并为一个「其他」节点。
    /// 注意：仅为展示合并，总体体积不变——otherSize = sum(rest)，本层总 size = sum(keep) + otherSize = 原 children 总和。
    private func capChildrenCount(_ children: [TreemapNode], maxCount: Int) -> [TreemapNode] {
        guard children.count > maxCount else { return children }
        let sorted = children.sorted { $0.size > $1.size }
        let keep = Array(sorted.prefix(maxCount - 1))
        let rest = sorted.dropFirst(maxCount - 1)
        let otherSize = rest.reduce(0) { $0 + $1.size }
        let otherCount = rest.count
        let otherName = otherCount > 0 ? "其他 (\(otherCount) 项)" : "其他"
        let otherNode = TreemapNode(
            name: otherName,
            relativePath: "",
            size: otherSize,
            children: Array(rest),
            isUnused: false,
            unusedRatio: 0,
            fileType: .other
        )
        return keep + [otherNode]
    }
    
    /// 递归生成每层带「其他」的展示树，供按文件夹展开 Tab 使用
    func cappedTreeForFolderDisplay(from node: TreemapNode, maxPerLevel: Int = 48) -> TreemapNode {
        if node.children.isEmpty {
            return node
        }
        let capped = capChildrenCount(node.children, maxCount: maxPerLevel)
        let newChildren = capped.map { cappedTreeForFolderDisplay(from: $0, maxPerLevel: maxPerLevel) }
        return TreemapNode(
            name: node.name,
            relativePath: node.relativePath,
            size: node.size,
            children: newChildren,
            isUnused: node.isUnused,
            unusedRatio: node.unusedRatio,
            fileType: node.fileType
        )
    }
    
    private func determineFileType(from fileNode: FileNode) -> FileType {
        let fileName = fileNode.fileName.lowercased()
        let pathExtension = URL(fileURLWithPath: fileName).pathExtension
        
        switch pathExtension {
        case "swift", "m", "mm", "h", "hpp", "cpp", "c", "cc":
            return .code
        case "png", "jpg", "jpeg", "gif", "svg", "pdf", "webp", "tiff", "bmp":
            return .resource
        case "framework", "dylib", "a", "so":
            return .framework
        default:
            if fileNode.codeSize > 0 {
                return .code
            } else if fileNode.resourceSize > 0 {
                return .resource
            } else if fileNode.frameworkSize > 0 {
                return .framework
            } else {
                return .other
            }
        }
    }
}

// MARK: - FileNode Extension

extension FileNode {
    var totalSize: Int64 {
        return codeSize + resourceSize + frameworkSize
    }
}
