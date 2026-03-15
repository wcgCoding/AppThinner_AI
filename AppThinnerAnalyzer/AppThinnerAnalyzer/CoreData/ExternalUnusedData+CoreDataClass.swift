import Foundation
import CoreData

@objc(ExternalUnusedData)
public class ExternalUnusedData: NSManagedObject {
    
    // MARK: - Computed Properties
    
    var dataTypeEnum: ExternalDataType {
        return ExternalDataType(rawValue: dataType) ?? .other
    }
    
    // MARK: - Helper Methods
    
    func isResource() -> Bool {
        return dataTypeEnum == .unusedResource
    }
    
    func isCode() -> Bool {
        return dataTypeEnum == .unusedCode
    }
}

// MARK: - Supporting Enums

enum ExternalDataType: String, CaseIterable {
    case unusedResource = "UnusedResource"
    case unusedCode = "UnusedCode"
    case other = "Other"
}