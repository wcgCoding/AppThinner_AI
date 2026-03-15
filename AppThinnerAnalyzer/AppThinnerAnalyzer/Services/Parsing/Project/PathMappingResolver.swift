import Foundation

// MARK: - PathMappingResolver 协议
// 负责将工程目录中的源文件路径与 IPA 包内文件路径进行匹配，
// 构建「工程路径 → 包内路径」的映射表，并解决路径冲突。

protocol PathMappingResolverProtocol {
    /// 解析项目路径与 IPA 内路径的映射。若传入已扫描的 projectResources 则不再重复扫描项目目录。
    func resolvePathMappings(
        projectPath: String,
        packageFiles: [PackageFileInfo],
        linkmapSymbols: [SymbolInfo],
        projectResources: [ProjectFileEntry]?
    ) async throws -> PathMappingResult
    
    func resolveConflicts(
        _ conflicts: [PathMappingConflict]
    ) async throws -> [PathMappingResolution]
}

// MARK: - PathMappingResolver 实现

class PathMappingResolver: PathMappingResolverProtocol {
    
    // MARK: - 公共方法
    
    func resolvePathMappings(
        projectPath: String,
        packageFiles: [PackageFileInfo],
        linkmapSymbols: [SymbolInfo],
        projectResources: [ProjectFileEntry]? = nil
    ) async throws -> PathMappingResult {
        
        guard !projectPath.isEmpty else {
            throw AnalysisError.pathMappingFailed("Project path cannot be empty")
        }
        
        // Step 1: 若有已扫描的项目资源则直接建表，避免二次扫描项目目录
        let initialMappingTable: PathMappingTable
        if let resources = projectResources, !resources.isEmpty {
            initialMappingTable = buildInitialMappingTable(projectResources: resources, packageFiles: packageFiles)
        } else {
            let resourceScanner = ProjectResourceScanner()
            initialMappingTable = try await resourceScanner.buildPathMappingTable(
                projectPath: projectPath,
                packageFiles: packageFiles
            )
        }
        
        // Step 2: Enhance mapping with linkmap symbol information
        let enhancedMappingTable = try await enhanceMappingWithSymbols(
            mappingTable: initialMappingTable,
            symbols: linkmapSymbols,
            projectPath: projectPath
        )
        
        // Step 3: 并行解析冲突
        let resolutions = try await resolveConflicts(enhancedMappingTable.conflicts)
        
        // Step 4: Generate comprehensive accuracy report
        let accuracyReport = generateMappingAccuracyReport(
            mappingTable: enhancedMappingTable,
            resolutions: resolutions,
            projectPath: projectPath
        )
        
        return PathMappingResult(
            mappingTable: enhancedMappingTable,
            resolutions: resolutions,
            accuracyReport: accuracyReport
        )
    }
    
    func resolveConflicts(
        _ conflicts: [PathMappingConflict]
    ) async throws -> [PathMappingResolution] {
        try await withThrowingTaskGroup(of: PathMappingResolution.self) { group in
            for conflict in conflicts {
                group.addTask { try await self.resolveIndividualConflict(conflict) }
            }
            var resolutions: [PathMappingResolution] = []
            for try await resolution in group { resolutions.append(resolution) }
            return resolutions
        }
    }
    
    // MARK: - Private Methods
    
    /// 用已扫描的项目资源与 IPA 文件列表在内存中建映射表，避免再次扫描磁盘
    func buildInitialMappingTable(
        projectResources: [ProjectFileEntry],
        packageFiles: [PackageFileInfo]
    ) -> PathMappingTable {
        let packageFilesByName = Dictionary(grouping: packageFiles) { $0.fileName }
        var mappings: [String: String] = [:]
        var conflicts: [PathMappingConflict] = []
        var unmappedFiles: [String] = []
        for resource in projectResources {
            let fileName = resource.fileName
            guard let matches = packageFilesByName[fileName] else {
                unmappedFiles.append(resource.relativePath)
                continue
            }
            if matches.count == 1 {
                mappings[resource.relativePath] = matches[0].relativePath
            } else {
                let candidates = matches.map { $0.relativePath }
                let best = candidates.max { a, b in
                    calculatePathStructureSimilarity(resource.relativePath, a) < calculatePathStructureSimilarity(resource.relativePath, b)
                } ?? candidates[0]
                conflicts.append(PathMappingConflict(
                    projectPath: resource.relativePath,
                    candidatePackagePaths: candidates,
                    recommendedResolution: best
                ))
                mappings[resource.relativePath] = best
            }
        }
        let total = projectResources.count
        let accuracy = total > 0 ? Double(mappings.count) / Double(total) : 0.0
        return PathMappingTable(
            mappings: mappings,
            conflicts: conflicts,
            unmappedFiles: unmappedFiles,
            accuracy: accuracy
        )
    }
    
    private func enhanceMappingWithSymbols(
        mappingTable: PathMappingTable,
        symbols: [SymbolInfo],
        projectPath: String
    ) async throws -> PathMappingTable {
        
        var enhancedMappings = mappingTable.mappings
        var enhancedConflicts = mappingTable.conflicts
        var enhancedUnmappedFiles = mappingTable.unmappedFiles
        
        // Create symbol-to-file mapping from linkmap data
        let symbolFileMapping = createSymbolFileMapping(symbols: symbols)
        
        // Try to resolve unmapped files using symbol information
        var resolvedFiles: [String] = []
        
        for unmappedFile in mappingTable.unmappedFiles {
            if let resolvedPath = try await resolveUsingSymbols(
                projectFile: unmappedFile,
                symbolMapping: symbolFileMapping,
                projectPath: projectPath
            ) {
                enhancedMappings[unmappedFile] = resolvedPath
                resolvedFiles.append(unmappedFile)
            }
        }
        
        // Remove resolved files from unmapped list
        enhancedUnmappedFiles.removeAll { resolvedFiles.contains($0) }
        
        // Recalculate accuracy
        let totalFiles = enhancedMappings.count + enhancedUnmappedFiles.count
        let mappedFiles = enhancedMappings.count
        let accuracy = totalFiles > 0 ? Double(mappedFiles) / Double(totalFiles) : 0.0
        
        return PathMappingTable(
            mappings: enhancedMappings,
            conflicts: enhancedConflicts,
            unmappedFiles: enhancedUnmappedFiles,
            accuracy: accuracy
        )
    }
    
    private func createSymbolFileMapping(symbols: [SymbolInfo]) -> [String: [SymbolInfo]] {
        return Dictionary(grouping: symbols) { symbol in
            // Extract base filename from symbol fileName
            let fileName = URL(fileURLWithPath: symbol.fileName).lastPathComponent
            return fileName
        }
    }
    
    private func resolveUsingSymbols(
        projectFile: String,
        symbolMapping: [String: [SymbolInfo]],
        projectPath: String
    ) async throws -> String? {
        
        let fileName = URL(fileURLWithPath: projectFile).lastPathComponent
        let baseName = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        
        // Try exact filename match first
        if let symbols = symbolMapping[fileName] {
            return symbols.first?.fileName
        }
        
        // Try base name match (without extension)
        if let symbols = symbolMapping[baseName + ".o"] ?? symbolMapping[baseName + ".m"] ?? symbolMapping[baseName + ".swift"] {
            return symbols.first?.fileName
        }
        return nil
    }
    
    private func resolveIndividualConflict(
        _ conflict: PathMappingConflict
    ) async throws -> PathMappingResolution {
        
        let projectPath = conflict.projectPath
        let candidates = conflict.candidatePackagePaths
        
        // Algorithm 1: Path structure similarity
        let structureSimilarityScores = candidates.map { candidate in
            (candidate, calculatePathStructureSimilarity(projectPath, candidate))
        }
        
        // Algorithm 2: File size correlation (if available)
        let sizeCorrelationScores = candidates.map { candidate in
            (candidate, calculateSizeCorrelation(projectPath, candidate))
        }
        
        // Algorithm 3: Directory context matching
        let contextScores = candidates.map { candidate in
            (candidate, calculateDirectoryContextScore(projectPath, candidate))
        }
        
        // Combine scores with weights
        var combinedScores: [(String, Double)] = []
        
        for candidate in candidates {
            let structureScore = structureSimilarityScores.first { $0.0 == candidate }?.1 ?? 0.0
            let sizeScore = sizeCorrelationScores.first { $0.0 == candidate }?.1 ?? 0.0
            let contextScore = contextScores.first { $0.0 == candidate }?.1 ?? 0.0
            
            // Weighted combination
            let combinedScore = (structureScore * 0.5) + (sizeScore * 0.3) + (contextScore * 0.2)
            combinedScores.append((candidate, combinedScore))
        }
        
        // Select best match
        let bestMatch = combinedScores.max { $0.1 < $1.1 }
        let selectedPath = bestMatch?.0 ?? conflict.recommendedResolution
        let confidence = bestMatch?.1 ?? 0.5
        
        // Generate reasoning
        let reasoning = generateResolutionReasoning(
            projectPath: projectPath,
            selectedPath: selectedPath,
            confidence: confidence,
            alternatives: candidates.filter { $0 != selectedPath }
        )
        
        return PathMappingResolution(
            conflict: conflict,
            selectedPath: selectedPath,
            confidence: confidence,
            reasoning: reasoning
        )
    }
    
    private func calculatePathStructureSimilarity(_ path1: String, _ path2: String) -> Double {
        let components1 = path1.components(separatedBy: "/")
        let components2 = path2.components(separatedBy: "/")
        
        let maxLength = max(components1.count, components2.count)
        guard maxLength > 0 else { return 0.0 }
        
        var matchingComponents = 0
        let minLength = min(components1.count, components2.count)
        
        // Compare from the end (filename is most important)
        for i in 1...minLength {
            let comp1 = components1[components1.count - i]
            let comp2 = components2[components2.count - i]
            
            if comp1 == comp2 {
                matchingComponents += i // Weight later components more heavily
            } else {
                break
            }
        }
        
        return Double(matchingComponents) / Double(maxLength * (maxLength + 1) / 2)
    }
    
    private func calculateSizeCorrelation(_ projectPath: String, _ packagePath: String) -> Double {
        // This would require actual file size information
        // For now, return a neutral score
        // In a real implementation, you would compare file sizes if available
        return 0.5
    }
    
    private func calculateDirectoryContextScore(_ projectPath: String, _ packagePath: String) -> Double {
        let projectDir = URL(fileURLWithPath: projectPath).deletingLastPathComponent().lastPathComponent
        let packageDir = URL(fileURLWithPath: packagePath).deletingLastPathComponent().lastPathComponent
        
        // Check if directories have similar names or purposes
        let commonDirectoryNames = [
            ("Resources", "Resources"),
            ("Images", "Images"),
            ("Assets", "Assets"),
            ("Sounds", "Audio"),
            ("Videos", "Video"),
            ("Data", "Data"),
            ("Localization", "Localized"),
            ("Strings", "Localized")
        ]
        
        for (projPattern, pkgPattern) in commonDirectoryNames {
            if projectDir.contains(projPattern) && packageDir.contains(pkgPattern) {
                return 1.0
            }
        }
        
        // Fallback to string similarity
        return calculateStringSimilarity(projectDir, packageDir)
    }
    
    private func calculateStringSimilarity(_ str1: String, _ str2: String) -> Double {
        let longer = str1.count > str2.count ? str1 : str2
        let shorter = str1.count > str2.count ? str2 : str1
        
        guard longer.count > 0 else { return 1.0 }
        
        let editDistance = levenshteinDistance(shorter, longer)
        return (Double(longer.count) - Double(editDistance)) / Double(longer.count)
    }
    
    private func levenshteinDistance(_ str1: String, _ str2: String) -> Int {
        let arr1 = Array(str1)
        let arr2 = Array(str2)
        
        var matrix = Array(repeating: Array(repeating: 0, count: arr2.count + 1), count: arr1.count + 1)
        
        for i in 0...arr1.count {
            matrix[i][0] = i
        }
        
        for j in 0...arr2.count {
            matrix[0][j] = j
        }
        
        for i in 1...arr1.count {
            for j in 1...arr2.count {
                let cost = arr1[i-1] == arr2[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,      // deletion
                    matrix[i][j-1] + 1,      // insertion
                    matrix[i-1][j-1] + cost  // substitution
                )
            }
        }
        
        return matrix[arr1.count][arr2.count]
    }
    
    private func generateResolutionReasoning(
        projectPath: String,
        selectedPath: String,
        confidence: Double,
        alternatives: [String]
    ) -> String {
        var reasoning = "Selected '\(selectedPath)' for '\(projectPath)' "
        
        if confidence > 0.8 {
            reasoning += "with high confidence (\(String(format: "%.1f", confidence * 100))%) "
            reasoning += "based on strong path structure similarity and directory context matching."
        } else if confidence > 0.6 {
            reasoning += "with moderate confidence (\(String(format: "%.1f", confidence * 100))%) "
            reasoning += "based on partial path similarity."
        } else {
            reasoning += "with low confidence (\(String(format: "%.1f", confidence * 100))%). "
            reasoning += "Manual review recommended."
        }
        
        if !alternatives.isEmpty {
            reasoning += " Alternative candidates: \(alternatives.joined(separator: ", "))."
        }
        
        return reasoning
    }
    
    private func generateMappingAccuracyReport(
        mappingTable: PathMappingTable,
        resolutions: [PathMappingResolution],
        projectPath: String
    ) -> MappingAccuracyReport {
        
        let totalFiles = mappingTable.mappings.count + mappingTable.unmappedFiles.count
        let mappedFiles = mappingTable.mappings.count
        let conflictedFiles = mappingTable.conflicts.count
        let unmappedFiles = mappingTable.unmappedFiles.count
        
        let overallAccuracy = totalFiles > 0 ? Double(mappedFiles) / Double(totalFiles) : 0.0
        
        // Generate recommendations based on analysis results
        var recommendations: [String] = []
        
        if overallAccuracy < 0.7 {
            recommendations.append("Low mapping accuracy detected. Consider providing additional data sources or manual verification.")
        }
        
        if conflictedFiles > totalFiles / 4 {
            recommendations.append("High number of path conflicts detected. Review project structure and package organization.")
        }
        
        if unmappedFiles > totalFiles / 3 {
            recommendations.append("Many files could not be mapped. Verify that all data sources are from the same project version.")
        }
        
        let lowConfidenceResolutions = resolutions.filter { $0.confidence < 0.6 }
        if !lowConfidenceResolutions.isEmpty {
            recommendations.append("Manual review recommended for \(lowConfidenceResolutions.count) low-confidence path mappings.")
        }
        
        if recommendations.isEmpty {
            recommendations.append("Path mapping completed successfully with good accuracy.")
        }
        
        return MappingAccuracyReport(
            totalFiles: totalFiles,
            mappedFiles: mappedFiles,
            conflictedFiles: conflictedFiles,
            unmappedFiles: unmappedFiles,
            overallAccuracy: overallAccuracy,
            recommendations: recommendations
        )
    }
}

