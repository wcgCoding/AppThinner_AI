import Foundation

// MARK: - 数据整合服务
// 负责将 IPA 包文件、工程目录扫描结果、LinkMap 代码体积三路数据整合为
// 统一的 IntegratedAnalysisData，供后续 CoreData 写入和 Treemap 展示使用。

final class DataIntegrationService {

    // MARK: - 依赖

    private let assetsCatalogParser: AssetsCatalogParser

    // MARK: - 初始化

    init(assetsCatalogParser: AssetsCatalogParser = AssetsCatalogParser()) {
        self.assetsCatalogParser = assetsCatalogParser
    }

    // MARK: - 核心整合方法

    /// 核心分析：IPA 资源与 linkmap 代码通过路径匹配写入各条目体积，过滤无体积条目后构建 TreeMap 用数据。
    /// - Total Size：解压后 Payload（.app 内容）总大小
    /// - Code Size：.app 内主二进制大小
    /// - Framework Size：.app/Frameworks 内动态库总大小
    /// - Resource Size：.app 内除主二进制和 Frameworks 外的资源大小
    /// - appBundlePath：.app 在磁盘上的路径；非 nil 且为 .app 时会对 Assets.car 调用 assetutil 解析出原始资源再按 asset 名匹配
    func buildIntegratedData(
        projectFileEntries: [ProjectFileEntry],
        packageFiles: [PackageFileInfo],
        codeSizeInfo: [CodeSizeInfo],
        appBundlePath: String? = nil,
        projectPath: String? = nil
    ) async -> IntegratedAnalysisData {
        let tTotal = Date()
        func e(_ t: Date) -> String { String(format: "%.2f", Date().timeIntervalSince(t)) }

        let resourcePackageFiles = packageFiles.filter { !$0.relativePath.hasPrefix("Frameworks/") && !$0.isMainExecutable }
        // .app Frameworks/ 内仅保留「以 .framework 为后缀」的 bundle 聚合列表（动态库不参与 linkmap，真实体积即 .app 内该 framework 总大小）
        let frameworkBundleToSize = buildFrameworkBundleToSize(from: packageFiles)

        let tRes = Date()
        let (pathToResourceSize, assignedResourcePackagePaths, carUnmatchedEntries) = await buildPathToResourceSize(
            projectFileEntries: projectFileEntries,
            resourcePackageFiles: resourcePackageFiles,
            appBundlePath: appBundlePath,
            projectPath: projectPath
        )
        print("⏱️ [TIMING]   资源体积分配（含 .car 解析）: \(e(tRes))s")

        let tFw = Date()
        let (pathToFrameworkSize, _) = buildPathToFrameworkSize(
            projectFileEntries: projectFileEntries,
            frameworkBundleToSize: frameworkBundleToSize
        )
        print("⏱️ [TIMING]   Framework 体积分配: \(e(tFw))s")

        // 将 codeSizeInfo 按「是否为 .framework/.a 下的虚拟 .o 节点」分组：
        //   - virtualObjectEntries：relativePath 含 "(" 的条目（如 Pods/X.framework/X(Foo.o)），展开为虚拟子节点，不参与聚合
        //   - realCodeEntries：普通源文件编译单元，按现有逻辑映射到 projectFileEntries
        let virtualObjectEntries = codeSizeInfo.filter { AnalysisService.isVirtualObjectPath($0.relativePath) }
        let realCodeEntries = codeSizeInfo.filter { !AnalysisService.isVirtualObjectPath($0.relativePath) }

        // 收集已有虚拟子节点覆盖的 framework/静态库容器路径，用于将容器条目的 frameworkSize 置零
        // （体积完全由虚拟 .o 子节点承载，避免重复计算）
        var containerPathsCoveredByVirtual: Set<String> = []
        for info in virtualObjectEntries {
            // 截取容器路径：Pods/X.framework/X(Foo.o) → Pods/X.framework
            if let openParen = info.relativePath.firstIndex(of: "(") {
                var container = String(info.relativePath[..<openParen])
                // 去掉末尾斜线（如 Pods/X.framework/X 末尾的二进制名，退回到 .framework 目录本身）
                if let lastSlash = container.lastIndex(of: "/") {
                    container = String(container[..<lastSlash])
                }
                containerPathsCoveredByVirtual.insert(container)
            }
        }

        var pathToCodeSize: [String: Int64] = [:]
        for info in realCodeEntries {
            pathToCodeSize[info.relativePath, default: 0] += info.totalSize
        }
        // 仅对「普通源文件」路径做聚合（.framework/X(Foo.o) 已单独处理，不再 aggregate）
        pathToCodeSize = aggregateFrameworkObjectPathsToBinary(pathToCodeSize)

        // 动态库：以 .app 内实际大小为准，不使用 linkmap。凡已分配 framework 体积的条目均将 codeSize 置 0。
        // 同时：被虚拟 .o 节点覆盖的静态 framework 容器条目 frameworkSize 也置 0，避免体积重复。
        let enriched = projectFileEntries.map { entry -> (entry: ProjectFileEntry, resourceSize: Int64, codeSize: Int64, frameworkSize: Int64) in
            let resourceSize = pathToResourceSize[entry.relativePath] ?? 0
            var codeSize = pathToCodeSize[entry.relativePath] ?? 0
            var frameworkSize = pathToFrameworkSize[entry.relativePath] ?? 0
            if frameworkSize > 0 { codeSize = 0 }
            // 若该 framework 容器已有虚拟 .o 节点，体积由子节点承载，容器自身不重复计入
            let entryPath = entry.relativePath
            let isCoveredByVirtual = containerPathsCoveredByVirtual.contains(entryPath)
                || containerPathsCoveredByVirtual.contains(where: { entryPath.hasPrefix($0) })
            if isCoveredByVirtual { frameworkSize = 0 }
            return (entry, resourceSize, codeSize, frameworkSize)
        }
        let withRealSize = enriched.filter { $0.resourceSize + $0.codeSize + $0.frameworkSize > 0 }

        var files: [IntegratedFileInfo] = withRealSize.map { item in
            let fileType = item.entry.isSourceCode ? FileType.code : (item.entry.resourceType.flatMap { $0.toFileType() } ?? .other)
            return IntegratedFileInfo(
                relativePath: item.entry.relativePath,
                fileName: item.entry.fileName,
                fileType: fileType,
                resourceSize: item.resourceSize,
                codeSize: item.codeSize,
                frameworkSize: item.frameworkSize,
                hasPackageData: item.resourceSize > 0 || item.frameworkSize > 0,
                hasProjectData: true,
                hasLinkmapData: item.codeSize > 0
            )
        }

        // 将虚拟 .o 节点追加到 files 列表，每个条目对应 linkmap 中 .framework/.a 下的一个编译单元
        let virtualNodes = buildVirtualObjectFileNodes(from: virtualObjectEntries)
        files.append(contentsOf: virtualNodes)

        // linkmap 快速路径下未匹配到工程路径的 code 路径：单独加入树，便于 Treemap 按路径层级展示
        let assignedPaths = Set(files.map(\.relativePath))
        for (path, size) in pathToCodeSize where size > 0 && !assignedPaths.contains(path) {
            let fileName = (path as NSString).lastPathComponent
            files.append(IntegratedFileInfo(
                relativePath: path,
                fileName: fileName,
                fileType: .code,
                resourceSize: 0,
                codeSize: size,
                frameworkSize: 0,
                hasPackageData: false,
                hasProjectData: false,
                hasLinkmapData: true
            ))
        }

        for item in carUnmatchedEntries {
            files.append(IntegratedFileInfo(
                relativePath: item.virtualPath,
                fileName: AssetsCatalogParser.carUnmatchedVirtualFileName,
                fileType: .resource,
                resourceSize: item.size,
                codeSize: 0,
                frameworkSize: 0,
                hasPackageData: true,
                hasProjectData: false,
                hasLinkmapData: false
            ))
        }
        print("📦 [DataIntegrationService] 虚拟 .o 节点: \(virtualNodes.count) 个（来自 .framework/.a 编译单元）")

        let summary = calculateSummaryFromPackageAndFiles(packageFiles: packageFiles, integratedFiles: files)
        logIntegratedDataSummary(packageFiles: packageFiles, summary: summary, fileCount: files.count)

        let unmappedCount = resourcePackageFiles.filter { !assignedResourcePackagePaths.contains($0.relativePath) }.count
        if unmappedCount > 0 {
            print("📐 [DataIntegrationService] 未映射到工程路径的 .app 资源: \(unmappedCount) 个")
        }
        print("⏱️ [TIMING]   buildIntegratedData 合计: \(e(tTotal))s  (整合文件:\(files.count))")

        return IntegratedAnalysisData(files: files, summary: summary)
    }

    // MARK: - 汇总计算

    /// 从 .app 包解析结果计算汇总：Total=Payload 总大小，Code=主二进制，Frameworks=.app/Frameworks 总大小，Resources=其余资源。
    func calculateSummaryFromPackageAndFiles(
        packageFiles: [PackageFileInfo],
        integratedFiles: [IntegratedFileInfo]
    ) -> AnalysisSummary {
        guard !packageFiles.isEmpty else {
            return calculateAnalysisSummary(from: integratedFiles)
        }
        let totalPayloadSize = packageFiles.reduce(0) { $0 + $1.size }
        let frameworkTotalSize = packageFiles
            .filter { $0.relativePath.hasPrefix("Frameworks/") }
            .reduce(0) { $0 + $1.size }
        let mainBinarySize: Int64 = {
            if let main = packageFiles.first(where: { $0.isMainExecutable }) {
                return main.size
            }
            let rootFiles = packageFiles.filter { $0.relativePath.components(separatedBy: "/").count == 1 }
            if rootFiles.count == 1, let main = rootFiles.first { return main.size }
            if let main = rootFiles.first(where: { $0.fileType == .code }) { return main.size }
            return rootFiles.first?.size ?? 0
        }()
        let resourceTotalSize = totalPayloadSize - mainBinarySize - frameworkTotalSize
        if resourceTotalSize < 0 {
            print("⚠️ [DataIntegrationService] Summary size mismatch: total=\(totalPayloadSize) code=\(mainBinarySize) framework=\(frameworkTotalSize) resource would be \(resourceTotalSize)")
        }
        return AnalysisSummary(
            totalSize: totalPayloadSize,
            codeSize: mainBinarySize,
            resourceSize: max(0, resourceTotalSize),
            frameworkSize: frameworkTotalSize,
            unusedResourceSize: 0,
            unusedCodeSize: 0,
            potentialSavings: 0
        )
    }

    // MARK: - 私有辅助方法

    /// 输出集成结果汇总日志，便于排查可视化数据问题
    private func logIntegratedDataSummary(packageFiles: [PackageFileInfo], summary: AnalysisSummary, fileCount: Int) {
        let mainBinary = packageFiles.first(where: { $0.isMainExecutable })
        let frameworkCount = packageFiles.filter { $0.relativePath.hasPrefix("Frameworks/") }.count
        print("📐 [DataIntegrationService] Integrated summary: Total=\(summary.totalSize) Code=\(summary.codeSize) Resource=\(summary.resourceSize) Framework=\(summary.frameworkSize)")
        print("   - Main binary (CFBundleExecutable): \(mainBinary.map { "\($0.relativePath) \($0.size)" } ?? "none") | Framework entries: \(frameworkCount) | Integrated files: \(fileCount)")
    }

    /// .app 内 Frameworks/ 下按「.framework」bundle 聚合：返回 bundle 相对路径 → 该 bundle 内所有文件大小之和。
    private func buildFrameworkBundleToSize(from packageFiles: [PackageFileInfo]) -> [String: Int64] {
        let underFrameworks = packageFiles.filter { $0.relativePath.hasPrefix("Frameworks/") && $0.relativePath.contains(".framework") }
        var bundleToSize: [String: Int64] = [:]
        for pkg in underFrameworks {
            guard let range = pkg.relativePath.range(of: ".framework") else { continue }
            let bundlePath = String(pkg.relativePath[..<range.upperBound])
            bundleToSize[bundlePath, default: 0] += pkg.size
        }
        return bundleToSize
    }

    /// 项目路径 → framework 体积：每个 .framework bundle 的 .app 内总大小只计入「一个」代表条目，避免同目录下多文件重复累加导致 Treemap 显示成 N×真实大小；动态库真实体积以 .app/Frameworks/ 为准，不再叠加 linkmap codeSize。
    /// 匹配使用不区分大小写，避免 .app 内为 light.framework、项目路径为 LightSDKDynamic/.../Light.framework 时匹配失败导致体积偏小。
    /// 返回 (pathToFrameworkSize, 已分配过的 bundle 路径集合)，便于调用方打印未匹配的 framework。
    private func buildPathToFrameworkSize(projectFileEntries: [ProjectFileEntry], frameworkBundleToSize: [String: Int64]) -> ([String: Int64], Set<String>) {
        let sortedBundles = frameworkBundleToSize.sorted {
            ($0.key as NSString).lastPathComponent.count > ($1.key as NSString).lastPathComponent.count
        }
        var pathToFrameworkSize: [String: Int64] = [:]
        var assignedBundlePaths: Set<String> = []
        let entryPathLower: [String: String] = Dictionary(uniqueKeysWithValues: projectFileEntries.map {
            ($0.relativePath, $0.relativePath.lowercased())
        })
        for entry in projectFileEntries {
            let pathLower = entryPathLower[entry.relativePath] ?? entry.relativePath.lowercased()
            for (bundlePath, size) in sortedBundles {
                let bundleName = (bundlePath as NSString).lastPathComponent
                guard pathLower.contains(bundleName.lowercased()) else { continue }
                if assignedBundlePaths.contains(bundlePath) {
                    pathToFrameworkSize[entry.relativePath] = 0
                } else {
                    pathToFrameworkSize[entry.relativePath] = size
                    assignedBundlePaths.insert(bundlePath)
                }
                break
            }
        }
        return (pathToFrameworkSize, assignedBundlePaths)
    }

    /// 将 linkmap 中「.framework/Name(Obj.o)」形式的 per-object 路径聚合到 framework 二进制路径「.framework/Name」上，
    /// 以便 project 中只有二进制文件路径时也能拿到整份 codeSize。
    private func aggregateFrameworkObjectPathsToBinary(_ pathToCodeSize: [String: Int64]) -> [String: Int64] {
        var merged: [String: Int64] = [:]
        for (path, size) in pathToCodeSize {
            if path.contains(".framework/"), let open = path.firstIndex(of: "(") {
                let canonical = String(path[..<open])
                merged[canonical, default: 0] += size
            } else {
                merged[path, default: 0] += size
            }
        }
        return merged
    }

    /// 资源体积分配：非 Assets.car 按文件名+路径相似度匹配；Assets.car 在提供 appBundlePath 时并发解析再按 asset 名匹配到项目 .xcassets。
    private func buildPathToResourceSize(
        projectFileEntries: [ProjectFileEntry],
        resourcePackageFiles: [PackageFileInfo],
        appBundlePath: String?,
        projectPath: String? = nil
    ) async -> (pathToResourceSize: [String: Int64], assignedResourcePackagePaths: Set<String>, carUnmatchedEntries: [(virtualPath: String, size: Int64)]) {
        let carFiles = resourcePackageFiles.filter { $0.fileName == "Assets.car" }
        let nonCarFiles = resourcePackageFiles.filter { $0.fileName != "Assets.car" }
        let assetNameToPaths = assetsCatalogParser.buildAssetNameToProjectPaths(projectFileEntries: projectFileEntries, projectPath: projectPath)
        var pathToResourceSize: [String: Int64] = [:]
        var assignedResourcePackagePaths: Set<String> = []
        var carUnmatchedEntries: [(virtualPath: String, size: Int64)] = []
        if let appRoot = appBundlePath, !appRoot.isEmpty, !carFiles.isEmpty {
            let tCar = Date()
            let (fromCar, assignedCars, unmatchedByCar) = await assetsCatalogParser.parseAndAssign(
                carFiles: carFiles,
                appBundlePath: appRoot,
                assetNameToPaths: assetNameToPaths
            )
            print("⏱️ [TIMING]     .car 并发解析+匹配 (\(carFiles.count) 个): \(String(format: "%.2f", Date().timeIntervalSince(tCar)))s")
            for (path, size) in fromCar { pathToResourceSize[path, default: 0] += size }
            assignedResourcePackagePaths.formUnion(assignedCars)
            if !assignedCars.isEmpty {
                let totalFromCar = fromCar.values.reduce(0, +)
                print("📐 [DataIntegrationService] Assets.car 解析匹配: \(assignedCars.count) 个 .car，合计 \(totalFromCar/1024) KB")
            }
            for (carPath, size) in unmatchedByCar where size > 0 {
                let bundleDir = (carPath as NSString).deletingLastPathComponent
                let libraryName = AssetsCatalogParser.libraryNameFromBundlePath(bundleDir)
                let virtualPath = "Pods/\(libraryName)/\(AssetsCatalogParser.carUnmatchedVirtualFileName)"
                pathToResourceSize[virtualPath, default: 0] += size
                carUnmatchedEntries.append((virtualPath: virtualPath, size: size))
            }
        }
        let remainingFiles = nonCarFiles + carFiles.filter { !assignedResourcePackagePaths.contains($0.relativePath) }
        let (fromFiles, assignedFiles) = buildPathToPackageSize(projectFileEntries: projectFileEntries, packageFiles: remainingFiles)
        for (path, size) in fromFiles { pathToResourceSize[path, default: 0] += size }
        assignedResourcePackagePaths.formUnion(assignedFiles)
        return (pathToResourceSize, assignedResourcePackagePaths, carUnmatchedEntries)
    }

    /// 项目路径 → IPA 包内大小的映射（按 fileName 匹配）。
    /// 采用「按 .app 路径驱动」：同名时先处理更具体的 .app 路径（如 WSResources.bundle/Assets.car），
    /// 再为其挑选包含该 scope 的项目路径，避免多候选时只匹配一条导致大量未匹配。
    private func buildPathToPackageSize(projectFileEntries: [ProjectFileEntry], packageFiles: [PackageFileInfo]) -> ([String: Int64], Set<String>) {
        let packageByFileName = Dictionary(grouping: packageFiles) { $0.fileName }
        let projectEntriesByFileName = Dictionary(grouping: projectFileEntries) { $0.fileName }

        var pathToPackageSize: [String: Int64] = [:]
        var assignedPackagePaths: Set<String> = []
        var assignedProjectPaths: Set<String> = []
        for (fileName, packages) in packageByFileName {
            let sortedPackages = packages.sorted { $0.relativePath.count > $1.relativePath.count }
            guard let projectEntries = projectEntriesByFileName[fileName], !projectEntries.isEmpty else { continue }
            for pkg in sortedPackages {
                let pkgPath = pkg.relativePath
                let availableProjects = projectEntries.filter { !assignedProjectPaths.contains($0.relativePath) }
                guard let best = availableProjects.max(by: { a, b in
                    self.packageToProjectScore(packagePath: pkgPath, projectPath: a.relativePath) < self.packageToProjectScore(packagePath: pkgPath, projectPath: b.relativePath)
                }) else { continue }
                pathToPackageSize[best.relativePath] = pkg.size
                assignedPackagePaths.insert(pkgPath)
                assignedProjectPaths.insert(best.relativePath)
            }
        }
        return (pathToPackageSize, assignedPackagePaths)
    }

    /// .app 路径 P 与项目路径 Q 的匹配得分：路径尾部相似度 + 若 Q 包含 P 的 scope（首段，如 WSResources.bundle）则加大分
    private func packageToProjectScore(packagePath: String, projectPath: String) -> Int {
        let pComps = packagePath.components(separatedBy: "/")
        let qComps = projectPath.components(separatedBy: "/")
        var score = pathSimilarity(pComps, qComps)
        if let scope = pComps.first, !scope.isEmpty, projectPath.contains(scope) {
            score += 1000
        }
        return score
    }

    /// 路径尾部相似度：从末尾逐段比较，每匹配一段得分加权
    private func pathSimilarity(_ a: [String], _ b: [String]) -> Int {
        let minLen = min(a.count, b.count)
        var score = 0
        for i in 1...minLen where a[a.count - i] == b[b.count - i] { score += i }
        return score
    }

    /// 从 integratedFiles 计算汇总（无 packageFiles 时的兜底方案）
    private func calculateAnalysisSummary(from files: [IntegratedFileInfo]) -> AnalysisSummary {
        let totalSize = files.reduce(0) { $0 + $1.resourceSize + $1.codeSize + $1.frameworkSize }
        let codeSize = files.reduce(0) { $0 + $1.codeSize }
        let resourceSize = files.reduce(0) { $0 + $1.resourceSize }
        let frameworkSize = files.reduce(0) { $0 + $1.frameworkSize }

        return AnalysisSummary(
            totalSize: totalSize,
            codeSize: codeSize,
            resourceSize: resourceSize,
            frameworkSize: frameworkSize,
            unusedResourceSize: 0,
            unusedCodeSize: 0,
            potentialSavings: 0
        )
    }

    // MARK: - 虚拟 .o 节点辅助方法

    /// 从 virtualObjectEntries 构建 IntegratedFileInfo 虚拟节点列表。
    /// relativePath 保持原始值（含括号），作为 Treemap 中该编译单元的唯一路径。
    /// fileName 取括号内 .o 文件名（如 SDImageCache.o），便于 UI 展示。
    private func buildVirtualObjectFileNodes(from entries: [CodeSizeInfo]) -> [IntegratedFileInfo] {
        entries.compactMap { info -> IntegratedFileInfo? in
            guard info.totalSize > 0 else { return nil }
            // 从路径中提取 .o 文件名：X(Foo.o) → Foo.o
            let displayName: String
            if let openParen = info.relativePath.lastIndex(of: "("),
               let closeParen = info.relativePath.lastIndex(of: ")"),
               openParen < closeParen {
                displayName = String(info.relativePath[info.relativePath.index(after: openParen)..<closeParen])
            } else {
                displayName = info.fileName
            }
            return IntegratedFileInfo(
                relativePath: info.relativePath,
                fileName: displayName,
                fileType: .code,
                resourceSize: 0,
                codeSize: info.totalSize,
                frameworkSize: 0,
                hasPackageData: false,
                hasProjectData: false,
                hasLinkmapData: true
            )
        }
    }
}
