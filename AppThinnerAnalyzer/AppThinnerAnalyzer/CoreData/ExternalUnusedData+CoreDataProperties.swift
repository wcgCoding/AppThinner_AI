import Foundation
import CoreData

extension ExternalUnusedData {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ExternalUnusedData> {
        return NSFetchRequest<ExternalUnusedData>(entityName: "ExternalUnusedData")
    }

    @NSManaged public var id: UUID
    @NSManaged public var relativePath: String
    @NSManaged public var fileName: String
    @NSManaged public var dataType: String
    @NSManaged public var importedAt: Date
    @NSManaged public var project: AnalysisProject

}

extension ExternalUnusedData : Identifiable {

}