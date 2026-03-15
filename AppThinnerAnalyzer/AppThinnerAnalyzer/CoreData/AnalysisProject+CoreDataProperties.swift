import Foundation
import CoreData

extension AnalysisProject {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<AnalysisProject> {
        return NSFetchRequest<AnalysisProject>(entityName: "AnalysisProject")
    }

    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var projectPath: String?
    @NSManaged public var duplicateCodeGroupsData: Data?
    @NSManaged public var duplicateResourceGroupsData: Data?
    @NSManaged public var podsDependencyData: Data?
    @NSManaged public var ipaPath: String?
    @NSManaged public var linkmapPath: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var totalSize: Int64
    @NSManaged public var summaryCodeSize: Int64
    @NSManaged public var summaryResourceSize: Int64
    @NSManaged public var summaryFrameworkSize: Int64
    @NSManaged public var analysisResults: NSSet?
    @NSManaged public var externalUnusedData: NSSet?

}

// MARK: Generated accessors for analysisResults
extension AnalysisProject {

    @objc(addAnalysisResultsObject:)
    @NSManaged public func addToAnalysisResults(_ value: AnalysisResult)

    @objc(removeAnalysisResultsObject:)
    @NSManaged public func removeFromAnalysisResults(_ value: AnalysisResult)

    @objc(addAnalysisResults:)
    @NSManaged public func addToAnalysisResults(_ values: NSSet)

    @objc(removeAnalysisResults:)
    @NSManaged public func removeFromAnalysisResults(_ values: NSSet)

}

// MARK: Generated accessors for externalUnusedData
extension AnalysisProject {

    @objc(addExternalUnusedDataObject:)
    @NSManaged public func addToExternalUnusedData(_ value: ExternalUnusedData)

    @objc(removeExternalUnusedDataObject:)
    @NSManaged public func removeFromExternalUnusedData(_ value: ExternalUnusedData)

    @objc(addExternalUnusedData:)
    @NSManaged public func addToExternalUnusedData(_ values: NSSet)

    @objc(removeExternalUnusedData:)
    @NSManaged public func removeFromExternalUnusedData(_ values: NSSet)

}

extension AnalysisProject : Identifiable {

}