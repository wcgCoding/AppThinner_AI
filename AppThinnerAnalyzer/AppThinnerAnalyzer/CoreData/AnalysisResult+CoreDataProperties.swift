import Foundation
import CoreData

extension AnalysisResult {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<AnalysisResult> {
        return NSFetchRequest<AnalysisResult>(entityName: "AnalysisResult")
    }

    @NSManaged public var id: UUID
    @NSManaged public var relativePath: String
    @NSManaged public var fileName: String
    @NSManaged public var fileType: String
    @NSManaged public var codeSize: Int64
    @NSManaged public var resourceSize: Int64
    @NSManaged public var frameworkSize: Int64
    @NSManaged public var isUnusedResource: Bool
    @NSManaged public var isUnusedCode: Bool
    @NSManaged public var isExternallyMarked: Bool
    @NSManaged public var project: AnalysisProject

}

extension AnalysisResult : Identifiable {

}