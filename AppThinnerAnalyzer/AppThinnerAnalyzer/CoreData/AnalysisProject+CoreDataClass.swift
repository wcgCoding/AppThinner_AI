import Foundation
import CoreData

@objc(AnalysisProject)
public class AnalysisProject: NSManagedObject {
    
    // MARK: - Computed Properties
    
    var analysisResultsArray: [AnalysisResult] {
        let set = analysisResults as? Set<AnalysisResult> ?? []
        return set.sorted { $0.relativePath < $1.relativePath }
    }
    
    var externalUnusedDataArray: [ExternalUnusedData] {
        let set = externalUnusedData as? Set<ExternalUnusedData> ?? []
        return set.sorted { $0.relativePath < $1.relativePath }
    }
    
    var unusedResources: [AnalysisResult] {
        return analysisResultsArray.filter { $0.isUnusedResource }
    }
    
    var unusedCode: [AnalysisResult] {
        return analysisResultsArray.filter { $0.isUnusedCode }
    }
    
    var totalCodeSize: Int64 {
        return analysisResultsArray.reduce(0) { $0 + $1.codeSize }
    }
    
    var totalResourceSize: Int64 {
        return analysisResultsArray.reduce(0) { $0 + $1.resourceSize }
    }
    
    var totalFrameworkSize: Int64 {
        return analysisResultsArray.reduce(0) { $0 + $1.frameworkSize }
    }
    
    var unusedResourceSize: Int64 {
        return unusedResources.reduce(0) { $0 + $1.resourceSize }
    }
    
    var unusedCodeSize: Int64 {
        return unusedCode.reduce(0) { $0 + $1.codeSize }
    }
    
    var potentialSavings: Int64 {
        return unusedResourceSize + unusedCodeSize
    }
    
    /// 代码重复扫描结果（从 duplicateCodeGroupsData 解码）
    var duplicateCodeGroups: [DuplicateCodeGroup] {
        guard let data = duplicateCodeGroupsData else { return [] }
        return (try? JSONDecoder().decode([DuplicateCodeGroup].self, from: data)) ?? []
    }

    /// 资源重复扫描结果（从 duplicateResourceGroupsData 解码）
    var duplicateResourceGroups: [DuplicateResourceGroup] {
        guard let data = duplicateResourceGroupsData else { return [] }
        return (try? JSONDecoder().decode([DuplicateResourceGroup].self, from: data)) ?? []
    }

    /// Pods 依赖扫描结果（从 podsDependencyData 解码）
    var podsDependencyResult: PodsDependencyResult? {
        guard let data = podsDependencyData else { return nil }
        return try? JSONDecoder().decode(PodsDependencyResult.self, from: data)
    }
    
    // MARK: - Helper Methods
    
    func updateTotalSize() {
        totalSize = totalCodeSize + totalResourceSize + totalFrameworkSize
        updatedAt = Date()
    }
    
    func addAnalysisResult(_ result: AnalysisResult) {
        addToAnalysisResults(result)
        updateTotalSize()
    }
    
    func removeAnalysisResult(_ result: AnalysisResult) {
        removeFromAnalysisResults(result)
        updateTotalSize()
    }
}