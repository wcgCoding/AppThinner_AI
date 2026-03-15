import Foundation

// MARK: - Assets.car 解析器
// 负责解析 .app 包内的 Assets.car 文件，提取各 asset 的体积信息，
// 并将其匹配到项目中对应的 .xcassets 路径。

final class AssetsCatalogParser {

    // MARK: - 常量

    /// 未匹配到项目路径的 .car 内容的虚拟文件名（用于 Treemap 中展示）
    static let carUnmatchedVirtualFileName = "Assets.car（未匹配-Packed）"

    // MARK: - 公共方法

    /// 并发解析所有 .car 文件，将 asset 体积匹配到项目路径。
    /// - Parameters:
    ///   - carFiles: .app 包内所有 Assets.car 文件列表
    ///   - appBundlePath: .app 在磁盘上的根路径
    ///   - assetNameToPaths: asset 名称 → 项目路径列表的映射（由 buildAssetNameToProjectPaths 构建）
    /// - Returns: (路径→追加体积, 已分配的 .car 相对路径集合, 各 .car 未匹配体积)
    func parseAndAssign(
        carFiles: [PackageFileInfo],
        appBundlePath: String,
        assetNameToPaths: [String: [String]]
    ) async -> (pathAdditions: [String: Int64], assignedCarPaths: Set<String>, unmatchedByCar: [String: Int64]) {
        let appRoot = (appBundlePath as NSString).standardizingPath

        // 并发解析每个 .car 文件（assetutil 是独立子进程，CoreUI 在 TaskGroup 中各自独立）
        typealias CarParseItem = (carRelPath: String, assetSizes: [(String, Int64)]?, failureReason: String?)
        let parseItems: [CarParseItem] = await withTaskGroup(of: CarParseItem.self) { group in
            for car in carFiles {
                let fullPath = (appRoot as NSString).appendingPathComponent(car.relativePath)
                let carRelPath = car.relativePath
                group.addTask { [self] in
                    guard FileManager.default.fileExists(atPath: fullPath) else {
                        return (carRelPath, nil, "文件不存在: \(fullPath)")
                    }
                    let r = self.parseContentsWithDiagnostics(at: fullPath)
                    return (carRelPath, r.assetSizes, r.failureReason)
                }
            }
            var items: [CarParseItem] = []
            for await item in group { items.append(item) }
            return items
        }

        // 顺序汇总（字典写入不能并发）
        var pathAdditions: [String: Int64] = [:]
        var assignedCarPaths: Set<String> = []
        var unmatchedByCar: [String: Int64] = [:]
        var sandboxErrorLogged = false

        // 使用并行任务组处理 .car 文件匹配，大幅提升大项目性能
        await withTaskGroup(of: (pathAdditions: [String: Int64], matchedSize: Int64, carRelPath: String).self) { group in
            for item in parseItems {
                guard let assetSizes = item.assetSizes else {
                    let reason = item.failureReason ?? "解析失败"
                    let isSandbox = reason.contains("App Sandbox") || reason.contains("cannot be used within")
                    if isSandbox && !sandboxErrorLogged {
                        sandboxErrorLogged = true
                        print("📐 [AssetsCatalogParser] Assets.car 跳过(\(item.carRelPath)): 沙盒限制，将按整文件匹配。")
                    } else if !isSandbox {
                        print("📐 [AssetsCatalogParser] Assets.car 跳过(\(item.carRelPath)): \(reason)")
                    }
                    continue
                }

                group.addTask { [self] in
                    let scope = self.carScope(fromCarRelativePath: item.carRelPath)
                    var localPathAdditions: [String: Int64] = [:]
                    var localMatchedSize: Int64 = 0

                    // 批量处理 asset 匹配，减少字典操作开销
                    for (assetName, size) in assetSizes {
                        var candidates = assetNameToPaths[assetName]
                        if candidates == nil || candidates!.isEmpty, (assetName as NSString).pathExtension.count > 0 {
                            candidates = assetNameToPaths[(assetName as NSString).deletingPathExtension]
                        }
                        guard let list = candidates, !list.isEmpty else { continue }

                        let path: String = list.count == 1 ? list[0] :
                            (list.max { self.scopeScore(path: $0, scope: scope) < self.scopeScore(path: $1, scope: scope) } ?? list[0])
                        localPathAdditions[path, default: 0] += size
                        localMatchedSize += size
                    }

                    return (localPathAdditions, localMatchedSize, item.carRelPath)
                }
            }

            // 收集所有并行任务的结果
            for await result in group {
                // 合并路径追加
                for (path, size) in result.pathAdditions {
                    pathAdditions[path, default: 0] += size
                }

                // 处理未匹配体积
                let totalInCar = parseItems.first { $0.carRelPath == result.carRelPath }?.assetSizes?.reduce(0) { $0 + $1.1 } ?? 0
                let unmatchedSize = totalInCar - result.matchedSize
                if unmatchedSize > 0 { unmatchedByCar[result.carRelPath] = unmatchedSize }
                assignedCarPaths.insert(result.carRelPath)
            }
        }
        return (pathAdditions, assignedCarPaths, unmatchedByCar)
    }

    /// 从项目路径中提取 .xcassets 下的 asset 名 → 对应项目路径列表的映射。
    /// 同时将 .imageset 内图片文件名的逻辑名（如 c_bg@2x.png → c_bg）加入映射，
    /// 与 .car 内按图片名命名的 asset 对齐；不依赖读 Contents.json。
    func buildAssetNameToProjectPaths(projectFileEntries: [ProjectFileEntry], projectPath: String? = nil) -> [String: [String]] {
        let suffixes = [".imageset", ".colorset", ".dataset"]
        var map: [String: [String]] = [:]
        // 用 Set 跟踪各 key 已加入的路径，避免 O(N) list.contains 重复检测
        var addedPaths: [String: Set<String>] = [:]
        for entry in projectFileEntries {
            let path = entry.relativePath
            for suffix in suffixes {
                guard path.contains(suffix), let range = path.range(of: suffix) else { continue }
                let name = (String(path[..<range.lowerBound]) as NSString).lastPathComponent
                if !name.isEmpty {
                    map[name, default: []].append(path)
                }
                if suffix == ".imageset", path.contains(".imageset/") {
                    let fileName = (path as NSString).lastPathComponent
                    let logicalName = assetLogicalName(fromImageFilename: fileName)
                    let ext = (fileName as NSString).pathExtension
                    let nameWithExt = ext.isEmpty ? logicalName : "\(logicalName).\(ext)"
                    for key in [logicalName, nameWithExt] where !key.isEmpty && key != name {
                        if addedPaths[key, default: []].insert(path).inserted {
                            map[key, default: []].append(path)
                        }
                    }
                }
                break
            }
        }
        return map
    }

    /// 从 .app 内 .bundle 路径取出三方库名（最后一段去掉 .bundle），用于挂到 Pods/<库名>/ 下。
    static func libraryNameFromBundlePath(_ bundlePath: String) -> String {
        let last = (bundlePath as NSString).lastPathComponent
        if last.hasSuffix(".bundle") { return String(last.dropLast(7)) }
        return last
    }

    // MARK: - 私有方法

    /// 带诊断的解析：优先 assetutil；若失败（如沙盒）则尝试进程内 CoreUI 解析。
    /// 该方法无实例状态写入，可安全在并发 TaskGroup 中调用。
    private func parseContentsWithDiagnostics(at path: String) -> (assetSizes: [(String, Int64)]?, failureReason: String?) {
        let (fromUtil, utilReason) = parseViaAssetutil(at: path)
        if let list = fromUtil { return (list, nil) }
        let (fromCoreUI, coreUIReason) = parseViaCoreUI(at: path)
        if let list = fromCoreUI { return (list, nil) }
        return (nil, utilReason ?? coreUIReason ?? "解析失败")
    }

    /// 通过 xcrun assetutil -I 解析 .car 文件，返回 [(asset 逻辑名, SizeOnDisk)]。
    /// 同一 asset 多 rendition 按逻辑名聚合后求和。
    private func parseViaAssetutil(at path: String) -> ([(String, Int64)]?, String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["assetutil", "-I", path]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (nil, "启动 assetutil 失败: \(error.localizedDescription)")
        }
        let exitCode = process.terminationStatus
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard exitCode == 0 else {
            return (nil, "assetutil 退出码 \(exitCode)\(errStr.map { "; \($0)" } ?? "")")
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return (nil, "JSON 解析失败（stdout 非合法 JSON）")
        }
        let renditions = collectRenditionDictionaries(from: json)
        guard !renditions.isEmpty else {
            return (nil, "JSON 中未找到 Renditions/Images 数组或为空")
        }
        return (extractAssetSizes(fromRenditions: renditions), nil)
    }

    /// 进程内解析 .car（CoreUI），沙盒下可用；参考 https://github.com/insidegui/AssetCatalogTinkerer
    private func parseViaCoreUI(at path: String) -> ([(String, Int64)]?, String?) {
        var err: NSError?
        guard let list = CARParserParseCARAtPath(path, &err) as? [[String: Any]], !list.isEmpty else {
            return (nil, err?.localizedDescription ?? "CoreUI 解析无结果")
        }
        var result: [(String, Int64)] = []
        for item in list {
            guard let name = item["name"] as? String,
                  let sizeNum = item["size"] as? NSNumber else { continue }
            result.append((name, sizeNum.int64Value))
        }
        return result.isEmpty ? (nil, "CoreUI 解析无有效 name/size") : (result, nil)
    }

    /// 递归收集 JSON 中的 Renditions/Images 数组
    private func collectRenditionDictionaries(from json: Any) -> [[String: Any]] {
        if let arr = json as? [[String: Any]] { return arr }
        if let obj = json as? [String: Any] {
            if let r = obj["Renditions"] as? [[String: Any]] { return r }
            if let r = obj["Images"] as? [[String: Any]] { return r }
            for (_, v) in obj {
                let nested = collectRenditionDictionaries(from: v)
                if !nested.isEmpty { return nested }
            }
        }
        return []
    }

    /// 从 rendition 字典列表中提取 (asset 基名, 体积) 列表，同名 rendition 聚合求和
    private func extractAssetSizes(fromRenditions renditions: [[String: Any]]) -> [(String, Int64)] {
        var byBaseName: [String: Int64] = [:]
        for r in renditions {
            let name = (r["Name"] as? String) ?? (r["RenditionName"] as? String) ?? ""
            let size: Int64
            if let n = r["SizeOnDisk"] as? NSNumber { size = n.int64Value }
            else if let i = r["SizeOnDisk"] as? Int { size = Int64(i) }
            else { size = 0 }
            if name.isEmpty || size <= 0 { continue }
            let base = assetBaseName(from: name)
            byBaseName[base, default: 0] += size
        }
        return byBaseName.map { ($0.key, $0.value) }
    }

    /// 从 rendition 名称提取 asset 基名：去掉 @2x/@3x 等分辨率后缀和 dash 变体
    private func assetBaseName(from renditionName: String) -> String {
        if let at = renditionName.firstIndex(of: "@") { return String(renditionName[..<at]) }
        if let dash = renditionName.firstIndex(of: "-") { return String(renditionName[..<dash]) }
        return renditionName
    }

    /// 从 imageset 内图片文件名得到 .car 中使用的逻辑名：去掉 @1x/@2x/@3x 和扩展名
    /// 例："c_bg@2x.png" → "c_bg"
    private func assetLogicalName(fromImageFilename filename: String) -> String {
        var base = (filename as NSString).deletingPathExtension
        for suffix in ["@3x", "@2x", "@1x"] {
            if base.lowercased().hasSuffix(suffix) {
                base = String(base.dropLast(suffix.count))
                break
            }
        }
        return base.trimmingCharacters(in: .whitespaces)
    }

    /// 从 .car 相对路径提取 scope（用于多候选路径时优先匹配同 bundle 下的项目路径）
    private func carScope(fromCarRelativePath carPath: String) -> String {
        let comps = carPath.components(separatedBy: "/")
        if comps.count >= 2, comps[0].hasSuffix(".bundle") { return comps[0] }
        if comps.count >= 1 { return (comps[0] as NSString).deletingPathExtension }
        return ""
    }

    /// 计算 .car scope 与项目路径的匹配得分，得分越高越优先
    private func scopeScore(path: String, scope: String) -> Int {
        guard !scope.isEmpty else { return 0 }
        let lower = path.lowercased()
        let scopeLower = scope.lowercased()
        if lower.contains(scopeLower) { return scopeLower.count }
        return 0
    }
}
