import Foundation
import CoreData

@objc(AnalysisResult)
public class AnalysisResult: NSManagedObject {
    
    // MARK: - Computed Properties
    
    var totalSize: Int64 {
        return codeSize + resourceSize + frameworkSize
    }
    
    var isUnused: Bool {
        return isUnusedResource || isUnusedCode
    }
    
    var fileTypeEnum: FileType {
        return FileType(rawValue: fileType) ?? .other
    }
    
    var unusedSourceEnum: UnusedSource {
        if isExternallyMarked && (isUnusedResource || isUnusedCode) {
            return .externalData
        } else if isExternallyMarked {
            return .externalData
        } else if isUnusedResource || isUnusedCode {
            return .staticAnalysis
        } else {
            return .manual
        }
    }
    
    // MARK: - Helper Methods
    
    func markAsUnusedResource(fromExternal: Bool = false) {
        isUnusedResource = true
        if fromExternal {
            isExternallyMarked = true
        }
    }
    
    func markAsUnusedCode(fromExternal: Bool = false) {
        isUnusedCode = true
        if fromExternal {
            isExternallyMarked = true
        }
    }
    
    func clearUnusedStatus() {
        isUnusedResource = false
        isUnusedCode = false
        isExternallyMarked = false
    }
}
