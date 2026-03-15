import Foundation

// MARK: - Linkmap 路径兜底解析（pbxproj + 一次索引构建，避免逐条枚举）

/// 对未命中 direct 的 linkmap 路径做解析：XCFrameworkIntermediates → xcframework 路径、.a(Obj.o) → 优先源码路径、否则 .a/.framework 索引查找；初始化时一次性构建索引，resolve 仅做查表。
final class LinkmapPathFallbackResolver {
    private let projectRoot: String
    /// 文件名小写 → 项目相对路径（pbxproj）
    private let pbxprojLookup: [String: String]
    /// framework 名（小写，如 pagadsdk）→ xcframework 内 .framework 目录路径（如 Pods/Ads-Global/SDK/PAGAdSDK.xcframework/ios-arm64/PAGAdSDK.framework）
    private let xcframeworkDirByFwName: [String: String]
    /// 文件名小写 → 项目相对路径（.a / .framework，一次枚举构建）
    private let filePathByFileName: [String: String]
    /// 仅 resolve 时用：pod 根路径 | 对象基名 → 源码路径（.m/.mm），避免重复枚举同一 pod
    private var sourcePathCache: [String: String] = [:]
    private let queue = DispatchQueue(label: "AppThinner.LinkmapPathFallbackResolver.cache")

    init?(projectPath: String?) {
        guard let projectPath = projectPath, !projectPath.isEmpty else { return nil }
        let root: String
        if projectPath.hasSuffix(".xcodeproj") {
            root = (projectPath as NSString).deletingLastPathComponent
        } else {
            root = projectPath
        }
        self.projectRoot = root
        self.pbxprojLookup = Self.parsePbxprojFileRefs(projectPath: projectPath, projectRoot: root)
        let (xcDirs, byFileName) = Self.buildOneTimeIndexes(projectRoot: root)
        self.xcframeworkDirByFwName = xcDirs
        self.filePathByFileName = byFileName
    }

    private static func parsePbxprojFileRefs(projectPath: String, projectRoot: String) -> [String: String] {
        let pbxPath: String
        if projectPath.hasSuffix(".xcodeproj") {
            pbxPath = (projectPath as NSString).appendingPathComponent("project.pbxproj")
        } else {
            let fm = FileManager.default
            guard let contents = try? fm.contentsOfDirectory(atPath: projectRoot),
                  let xc = contents.first(where: { $0.hasSuffix(".xcodeproj") }) else { return [:] }
            let candidate = (projectRoot as NSString).appendingPathComponent((xc as NSString).appendingPathComponent("project.pbxproj"))
            guard fm.fileExists(atPath: candidate) else { return [:] }
            pbxPath = candidate
        }
        guard let content = try? String(contentsOfFile: pbxPath, encoding: .utf8) else { return [:] }
        var lookup: [String: String] = [:]
        let pattern = #"path\s*=\s*"([^"]+\.(?:a|framework))";"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let range = NSRange(content.startIndex..., in: content)
        regex.enumerateMatches(in: content, options: [], range: range) { match, _, _ in
            guard let m = match, m.numberOfRanges >= 2,
                  let r = Range(m.range(at: 1), in: content) else { return }
            let path = String(content[r])
            let fileName = (path as NSString).lastPathComponent
            let key = fileName.lowercased()
            if lookup[key] == nil { lookup[key] = path }
        }
        return lookup
    }

    /// 一次性枚举项目根，构建 xcframework 路径表 + .a/.framework 文件名索引，后续 resolve 仅查表。
    private static func buildOneTimeIndexes(projectRoot: String) -> (xcframeworkDirs: [String: String], pathByFileName: [String: String]) {
        var xcDirs: [String: String] = [:]
        var byFileName: [String: String] = [:]
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: projectRoot) else { return (xcDirs, byFileName) }
        while let sub = enumerator.nextObject() as? String {
            let lower = sub.lowercased()
            if lower.contains(".xcframework/") && lower.contains("ios-arm64") && lower.hasSuffix(".framework") {
                let fwName = ((sub as NSString).lastPathComponent as NSString).deletingPathExtension
                if !fwName.isEmpty && xcDirs[fwName.lowercased()] == nil {
                    xcDirs[fwName.lowercased()] = sub
                }
            }
            let last = (sub as NSString).lastPathComponent.lowercased()
            if last.hasSuffix(".a") || last.hasSuffix(".framework") {
                if byFileName[last] == nil { byFileName[last] = sub }
            }
        }
        return (xcDirs, byFileName)
    }

    /// 解析 linkmap 路径：XCFrameworkIntermediates → xcframework；.a(Obj.o) → 优先同 pod 下源码；否则 .framework/.a 查表。
    func resolve(linkmapObjectPath path: String, fileName: String) -> String? {
        // 1) XCFrameworkIntermediates/.../PAGAdSDK.framework/PAGAdSDK(Obj.o) → Pods/.../PAGAdSDK.xcframework/ios-arm64/PAGAdSDK.framework/PAGAdSDK/Obj.o
        if path.contains("XCFrameworkIntermediates"), path.contains(".framework/") {
            if let fwName = LinkmapPathAdapter.frameworkName(fromLinkmapPath: path),
               let fwDir = xcframeworkDirByFwName[fwName] {
                if let range = path.range(of: ".framework/") {
                    let after = String(path[range.upperBound...])
                    let component = after.split(separator: "/").first.map(String.init) ?? after
                    if component.contains("("), let open = component.firstIndex(of: "("), let close = component.firstIndex(of: ")") {
                        let binaryName = String(component[..<open])
                        let objName = String(component[component.index(after: open)..<close])
                        return fwDir + "/" + binaryName + "/" + objName
                    }
                    return fwDir + "/" + component + "/" + fileName
                }
                return fwDir
            }
        }
        // 2) 静态库：优先映射到源码路径（同 pod 下 .m/.mm），否则返回 .a 路径
        if let libName = LinkmapPathAdapter.staticLibName(fromLinkmapPath: path) {
            let baseName = LinkmapPathAdapter.objectBaseName(fromLinkmapPath: path, fileName: fileName) ?? ""
            let keys = ["lib\(libName).a", "\(libName).a"].map { $0.lowercased() }
            var aPath: String?
            for key in keys {
                aPath = pbxprojLookup[key] ?? filePathByFileName[key]
                if aPath != nil { break }
            }
            if let aPath = aPath {
                var podRoot = extractPodRootFromPath(aPath)
                if podRoot.isEmpty, aPath.contains("Build") || aPath.contains("Release-iphoneos") {
                    podRoot = "Pods/\(libName)"
                }
                if !baseName.isEmpty, !podRoot.isEmpty {
                    let cacheKey = podRoot + "|" + baseName.lowercased()
                    if let cached = queue.sync(execute: { sourcePathCache[cacheKey] }) {
                        if !cached.isEmpty { return cached }
                        return aPath
                    }
                    let sourcePath = findSourceUnderPod(podRoot: podRoot, baseName: baseName)
                    queue.sync { sourcePathCache[cacheKey] = sourcePath ?? "" }
                    if let sp = sourcePath { return sp }
                }
                if !baseName.isEmpty {
                    let cacheKey = "global|" + baseName.lowercased()
                    if let cached = queue.sync(execute: { sourcePathCache[cacheKey] }), !cached.isEmpty { return cached }
                    if let sourcePath = findSourceInProject(baseName: baseName) {
                        queue.sync { sourcePathCache[cacheKey] = sourcePath }
                        return sourcePath
                    }
                    queue.sync { sourcePathCache[cacheKey] = "" }
                }
                return aPath
            }
            if !baseName.isEmpty {
                let cacheKey = "global|" + baseName.lowercased()
                if let cached = queue.sync(execute: { sourcePathCache[cacheKey] }), !cached.isEmpty { return cached }
                if let sourcePath = findSourceInProject(baseName: baseName) {
                    queue.sync { sourcePathCache[cacheKey] = sourcePath }
                    return sourcePath
                }
                queue.sync { sourcePathCache[cacheKey] = "" }
            }
        }
        // 3) Framework：.framework/Name(Obj.o) → 项目内 .framework 目录 + 组件
        if let fwName = LinkmapPathAdapter.frameworkName(fromLinkmapPath: path) {
            let key = "\(fwName).framework"
            let fwDir = pbxprojLookup[key] ?? filePathByFileName[key]
            if let fwDir = fwDir {
                if let range = path.range(of: ".framework/") {
                    let after = String(path[range.upperBound...])
                    let component = after.split(separator: "/").first.map(String.init) ?? String(after)
                    return fwDir + "/" + component
                }
                return fwDir
            }
        }
        // 4) 普通 .o（主 Target 或 DerivedData 下的编译单元，如 GlobalCommon.pb.o）：
        //    提取对象基名后，在整个项目中搜索同名源码文件（.m/.mm/.swift 等）。
        //    例：.../Objects-normal/arm64/GlobalCommon.pb.o → baseName = "GlobalCommon.pb"
        //        → 匹配项目中 Library/PB_OC/JXPBCode/Classes/PB/GlobalCommon.pb.m
        let baseName = LinkmapPathAdapter.objectBaseName(fromLinkmapPath: path, fileName: fileName) ?? ""
        if !baseName.isEmpty {
            let cacheKey = "global|" + baseName.lowercased()
            if let cached = queue.sync(execute: { sourcePathCache[cacheKey] }), !cached.isEmpty { return cached }
            if let sourcePath = findSourceInProject(baseName: baseName) {
                return sourcePath
            }
        }
        return nil
    }

    /// 从 .a 路径提取 Pod 根目录（改进版）
    /// 例：Pods/WSLaunchModule/WSLaunchModule/Classes/WeSingOnly/Hook/libWSLaunchModule.a → Pods/WSLaunchModule
    /// 例：Pods/AFNetworking/AFNetworking.framework → Pods/AFNetworking
    private func extractPodRootFromPath(_ path: String) -> String {
        let comps = path.components(separatedBy: "/")
        guard let podsIdx = comps.firstIndex(where: { $0 == "Pods" }),
              podsIdx + 1 < comps.count else {
            // 如果路径不以 Pods 开头，返回原逻辑
            return podRootFromPath(path)
        }
        // 返回 Pods/ModuleName
        return comps[podsIdx...podsIdx+1].joined(separator: "/")
    }

    /// 从 .a 路径得到 pod 根，如 Pods/WSLaunchModule/.../libX.a → Pods/WSLaunchModule
    private func podRootFromPath(_ path: String) -> String {
        let comps = path.split(separator: "/").map(String.init)
        guard let podsIdx = comps.firstIndex(where: { $0.lowercased() == "pods" }),
              podsIdx + 1 < comps.count else { return "" }
        return comps[podsIdx...podsIdx+1].joined(separator: "/")
    }

    /// 在整个项目中查找源码文件（全局搜索，只执行一次）
    private func findSourceInProject(baseName: String) -> String? {
        let lower = baseName.lowercased()
        let cacheKey = "project_search_done"
        if let done = queue.sync(execute: { sourcePathCache[cacheKey] }), done == "yes" {
            let key = "global|" + lower
            if let cached = queue.sync(execute: { sourcePathCache[key] }), !cached.isEmpty { return cached }
            return nil
        }
        var sourceIndex: [String: String] = [:]
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: projectRoot) else { return nil }
        while let sub = enumerator.nextObject() as? String {
            let last = (sub as NSString).lastPathComponent
            let base = (last as NSString).deletingPathExtension
            let ext = (last as NSString).pathExtension.lowercased()
            guard ["m", "mm", "swift", "c", "cc", "cpp", "cxx"].contains(ext) else { continue }
            let key = base.lowercased()
            if sourceIndex[key] == nil { sourceIndex[key] = sub }
        }
        queue.sync {
            for (key, path) in sourceIndex {
                sourcePathCache["global|\(key)"] = path
            }
            sourcePathCache[cacheKey] = "yes"
        }
        return sourceIndex[lower]
    }

    /// 在 pod 根目录下查找 baseName.m 或 baseName.mm
    private func findSourceUnderPod(podRoot: String, baseName: String) -> String? {
        let fullPath = (projectRoot as NSString).appendingPathComponent(podRoot)
        guard let enumerator = FileManager.default.enumerator(atPath: fullPath) else { return nil }
        let lower = baseName.lowercased()
        while let sub = enumerator.nextObject() as? String {
            let last = (sub as NSString).lastPathComponent
            let base = (last as NSString).deletingPathExtension
            let ext = (last as NSString).pathExtension.lowercased()
            guard ["m", "mm", "swift", "c", "cc", "cpp", "cxx"].contains(ext) else { continue }
            if base.lowercased() == lower {
                return podRoot + "/" + sub
            }
        }
        return nil
    }
}
