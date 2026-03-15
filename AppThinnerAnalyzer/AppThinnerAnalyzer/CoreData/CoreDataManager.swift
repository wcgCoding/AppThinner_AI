import CoreData
import Foundation

protocol CoreDataManagerProtocol {
    var container: NSPersistentContainer { get }
    func save() throws
    /// 供异步调用方批量写入后触发的保存（与 save() 等价，便于在 async 流程中按批调用）。
    func saveContext() async throws
    func createAnalysisProject(name: String, projectPath: String?, ipaPath: String?, linkmapPath: String?) -> AnalysisProject
    func createAnalysisProject(name: String, projectPath: String?, ipaPath: String?, linkmapPath: String?, totalSize: Int64, summaryCodeSize: Int64, summaryResourceSize: Int64, summaryFrameworkSize: Int64) async throws -> AnalysisProject
    func createAnalysisResult(for project: AnalysisProject, relativePath: String, fileName: String, fileType: String) -> AnalysisResult
    func createAnalysisResult(for project: AnalysisProject, relativePath: String, fileName: String, fileType: String, codeSize: Int64, resourceSize: Int64, frameworkSize: Int64, isUnusedResource: Bool, isUnusedCode: Bool, isExternallyMarked: Bool) async throws
    func fetch<T: NSManagedObject>(_ request: NSFetchRequest<T>) throws -> [T]
    func delete(_ object: NSManagedObject) throws
    func fetchAllAnalysisProjects() async throws -> [AnalysisProject]
    func deleteAnalysisProject(_ project: AnalysisProject) async throws
    func exportAnalysisProject(_ project: AnalysisProject) async throws -> Data
    func importAnalysisProject(from data: Data) async throws -> AnalysisProject
    
    // Enhanced CRUD operations
    func updateAnalysisProject(_ project: AnalysisProject) async throws
    func fetchAnalysisProject(by id: UUID) async throws -> AnalysisProject?
    func fetchAnalysisProjects(createdAfter date: Date) async throws -> [AnalysisProject]
    func fetchAnalysisProjects(withName name: String) async throws -> [AnalysisProject]
    func fetchAnalysisProjects() async throws -> [AnalysisProject]
    
    // Storage cleanup functionality
    func cleanupOldAnalysisProjects(olderThan days: Int) async throws -> Int
    func calculateStorageUsage() async throws -> StorageUsage
    func cleanupOrphanedAnalysisResults() async throws -> Int
    func compactDatabase() async throws
    
    // Enhanced export/import functionality
    func exportAllAnalysisProjects() async throws -> Data
    func exportAnalysisProjectsInDateRange(from startDate: Date, to endDate: Date) async throws -> Data
    func importAnalysisProjects(from data: Data, replaceExisting: Bool) async throws -> [AnalysisProject]
    func validateImportData(_ data: Data) async throws -> ImportValidationResult
}

/// Core Data 的 viewContext 与主队列绑定，所有访问必须在主线程；使用 @MainActor 避免在后台 Task 中调用时 EXC_BAD_ACCESS。
@MainActor
class CoreDataManager: CoreDataManagerProtocol, ObservableObject {
    static let shared = CoreDataManager()
    
    lazy var container: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "DataModel")
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Core Data failed to load: \(error.localizedDescription)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }()
    
    private init() {}
    
    func save() throws {
        let context = container.viewContext
        if context.hasChanges {
            try context.save()
        }
    }

    func saveContext() async throws {
        try save()
    }
    
    func createAnalysisProject(name: String, projectPath: String?, ipaPath: String?, linkmapPath: String?) -> AnalysisProject {
        let context = container.viewContext
        let project = AnalysisProject(context: context)
        project.id = UUID()
        project.name = name
        project.projectPath = projectPath
        project.ipaPath = ipaPath
        project.linkmapPath = linkmapPath
        project.createdAt = Date()
        project.updatedAt = Date()
        project.totalSize = 0
        return project
    }
    
    func createAnalysisProject(name: String, projectPath: String?, ipaPath: String?, linkmapPath: String?, totalSize: Int64, summaryCodeSize: Int64 = 0, summaryResourceSize: Int64 = 0, summaryFrameworkSize: Int64 = 0) async throws -> AnalysisProject {
        let context = container.viewContext
        let project = AnalysisProject(context: context)
        project.id = UUID()
        project.name = name
        project.projectPath = projectPath
        project.ipaPath = ipaPath
        project.linkmapPath = linkmapPath
        project.createdAt = Date()
        project.updatedAt = Date()
        project.totalSize = totalSize
        project.summaryCodeSize = summaryCodeSize
        project.summaryResourceSize = summaryResourceSize
        project.summaryFrameworkSize = summaryFrameworkSize
        try save()
        return project
    }
    
    func createAnalysisResult(for project: AnalysisProject, relativePath: String, fileName: String, fileType: String) -> AnalysisResult {
        let context = container.viewContext
        let result = AnalysisResult(context: context)
        result.id = UUID()
        result.relativePath = relativePath
        result.fileName = fileName
        result.fileType = fileType
        result.codeSize = 0
        result.resourceSize = 0
        result.frameworkSize = 0
        result.isUnusedResource = false
        result.isUnusedCode = false
        result.isExternallyMarked = false
        result.project = project
        return result
    }
    
    func createAnalysisResult(
        for project: AnalysisProject,
        relativePath: String,
        fileName: String,
        fileType: String,
        codeSize: Int64,
        resourceSize: Int64,
        frameworkSize: Int64,
        isUnusedResource: Bool,
        isUnusedCode: Bool,
        isExternallyMarked: Bool
    ) async throws {
        let context = container.viewContext
        let result = AnalysisResult(context: context)
        result.id = UUID()
        result.relativePath = relativePath
        result.fileName = fileName
        result.fileType = fileType
        result.codeSize = codeSize
        result.resourceSize = resourceSize
        result.frameworkSize = frameworkSize
        result.isUnusedResource = isUnusedResource
        result.isUnusedCode = isUnusedCode
        result.isExternallyMarked = isExternallyMarked
        result.project = project
        // 不再逐条 save，由调用方按批调用 saveContext() 以提升性能
    }
    
    func fetch<T: NSManagedObject>(_ request: NSFetchRequest<T>) throws -> [T] {
        let context = container.viewContext
        return try context.fetch(request)
    }
    
    func delete(_ object: NSManagedObject) throws {
        let context = container.viewContext
        context.delete(object)
        try save()
    }
    
    func fetchAllAnalysisProjects() async throws -> [AnalysisProject] {
        let context = container.viewContext
        let request: NSFetchRequest<AnalysisProject> = AnalysisProject.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \AnalysisProject.updatedAt, ascending: false)]
        return try context.fetch(request)
    }
    
    func deleteAnalysisProject(_ project: AnalysisProject) async throws {
        let context = container.viewContext
        context.delete(project)
        try save()
    }
    
    func exportAnalysisProject(_ project: AnalysisProject) async throws -> Data {
        // For now, return a simple JSON representation
        // In a full implementation, this would serialize the project and all its results
        let exportData = [
            "id": project.id.uuidString,
            "name": project.name,
            "projectPath": project.projectPath ?? "",
            "ipaPath": project.ipaPath ?? "",
            "linkmapPath": project.linkmapPath ?? "",
            "totalSize": project.totalSize,
            "summaryCodeSize": project.summaryCodeSize,
            "summaryResourceSize": project.summaryResourceSize,
            "summaryFrameworkSize": project.summaryFrameworkSize,
            "createdAt": project.createdAt.timeIntervalSince1970,
            "updatedAt": project.updatedAt.timeIntervalSince1970
        ] as [String: Any]
        
        return try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
    }
    
    func importAnalysisProject(from data: Data) async throws -> AnalysisProject {
        // For now, create a basic project from JSON data
        // In a full implementation, this would deserialize the complete project structure
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String else {
            throw AnalysisError.coreDataError("Invalid import data format")
        }
        
        let projectPath = json["projectPath"] as? String
        let ipaPath = json["ipaPath"] as? String
        let linkmapPath = json["linkmapPath"] as? String
        let totalSize = json["totalSize"] as? Int64 ?? 0
        
        return try await createAnalysisProject(
            name: name,
            projectPath: projectPath,
            ipaPath: ipaPath,
            linkmapPath: linkmapPath,
            totalSize: totalSize,
            summaryCodeSize: json["summaryCodeSize"] as? Int64 ?? 0,
            summaryResourceSize: json["summaryResourceSize"] as? Int64 ?? 0,
            summaryFrameworkSize: json["summaryFrameworkSize"] as? Int64 ?? 0
        )
    }
    
    // MARK: - Enhanced CRUD Operations
    
    func updateAnalysisProject(_ project: AnalysisProject) async throws {
        project.updatedAt = Date()
        try save()
    }
    
    func fetchAnalysisProject(by id: UUID) async throws -> AnalysisProject? {
        let context = container.viewContext
        let request: NSFetchRequest<AnalysisProject> = AnalysisProject.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        
        let results = try context.fetch(request)
        return results.first
    }
    
    func fetchAnalysisProjects(createdAfter date: Date) async throws -> [AnalysisProject] {
        let context = container.viewContext
        let request: NSFetchRequest<AnalysisProject> = AnalysisProject.fetchRequest()
        request.predicate = NSPredicate(format: "createdAt >= %@", date as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \AnalysisProject.createdAt, ascending: false)]
        
        return try context.fetch(request)
    }
    
    func fetchAnalysisProjects(withName name: String) async throws -> [AnalysisProject] {
        let context = container.viewContext
        let request: NSFetchRequest<AnalysisProject> = AnalysisProject.fetchRequest()
        request.predicate = NSPredicate(format: "name CONTAINS[cd] %@", name)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \AnalysisProject.updatedAt, ascending: false)]
        
        return try context.fetch(request)
    }
    
    func fetchAnalysisProjects() async throws -> [AnalysisProject] {
        let context = container.viewContext
        let request: NSFetchRequest<AnalysisProject> = AnalysisProject.fetchRequest()
//        request.predicate = NSPredicate(format: "name CONTAINS[cd] %@", name)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \AnalysisProject.updatedAt, ascending: false)]
        
        return try context.fetch(request)
    }
    
    // MARK: - Storage Cleanup Functionality
    
    func cleanupOldAnalysisProjects(olderThan days: Int) async throws -> Int {
        let context = container.viewContext
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        
        let request: NSFetchRequest<AnalysisProject> = AnalysisProject.fetchRequest()
        request.predicate = NSPredicate(format: "createdAt < %@", cutoffDate as CVarArg)
        
        let oldProjects = try context.fetch(request)
        let deletedCount = oldProjects.count
        
        for project in oldProjects {
            context.delete(project)
        }
        
        try save()
        return deletedCount
    }
    
    func calculateStorageUsage() async throws -> StorageUsage {
        let context = container.viewContext
        
        // Fetch all projects
        let projectRequest: NSFetchRequest<AnalysisProject> = AnalysisProject.fetchRequest()
        let projects = try context.fetch(projectRequest)
        
        // Fetch all analysis results
        let resultRequest: NSFetchRequest<AnalysisResult> = AnalysisResult.fetchRequest()
        let results = try context.fetch(resultRequest)
        
        // Calculate statistics
        let totalProjects = projects.count
        let totalAnalysisResults = results.count
        
        let oldestProject = projects.min(by: { $0.createdAt < $1.createdAt })
        let totalSize = projects.reduce(0) { $0 + $1.totalSize }
        let averageProjectSize = totalProjects > 0 ? totalSize / Int64(totalProjects) : 0
        let estimatedDatabaseSize = Int64(totalProjects * 1024 + totalAnalysisResults * 512) // Rough estimate
        
        return StorageUsage(
            totalProjects: totalProjects,
            totalAnalysisResults: totalAnalysisResults,
            estimatedDatabaseSize: estimatedDatabaseSize,
            oldestProjectDate: oldestProject?.createdAt,
            averageProjectSize: averageProjectSize
        )
    }
    
    func cleanupOrphanedAnalysisResults() async throws -> Int {
        let context = container.viewContext
        
        // Find analysis results without a project
        let request: NSFetchRequest<AnalysisResult> = AnalysisResult.fetchRequest()
        request.predicate = NSPredicate(format: "project == nil")
        
        let orphanedResults = try context.fetch(request)
        let deletedCount = orphanedResults.count
        
        for result in orphanedResults {
            context.delete(result)
        }
        
        try save()
        return deletedCount
    }
    
    func compactDatabase() async throws {
        let context = container.viewContext
        
        // Perform a save to ensure all changes are persisted
        try save()
        
        // Reset the context to free up memory
        context.reset()
        
        // Note: In a production app, you might want to implement more sophisticated
        // database compaction using NSPersistentStore migration or vacuum operations
    }
    
    // MARK: - Enhanced Export/Import Functionality
    
    func exportAllAnalysisProjects() async throws -> Data {
        let projects = try await fetchAllAnalysisProjects()
        return try await exportMultipleProjects(projects)
    }
    
    func exportAnalysisProjectsInDateRange(from startDate: Date, to endDate: Date) async throws -> Data {
        let context = container.viewContext
        let request: NSFetchRequest<AnalysisProject> = AnalysisProject.fetchRequest()
        request.predicate = NSPredicate(format: "createdAt >= %@ AND createdAt <= %@", startDate as CVarArg, endDate as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \AnalysisProject.createdAt, ascending: true)]
        
        let projects = try context.fetch(request)
        return try await exportMultipleProjects(projects)
    }
    
    private func exportMultipleProjects(_ projects: [AnalysisProject]) async throws -> Data {
        var exportData: [[String: Any]] = []
        
        for project in projects {
            let projectData = try await exportProjectToDict(project)
            exportData.append(projectData)
        }
        
        let finalExportData = [
            "version": "1.0",
            "exportDate": Date().timeIntervalSince1970,
            "projectCount": projects.count,
            "projects": exportData
        ] as [String: Any]
        
        return try JSONSerialization.data(withJSONObject: finalExportData, options: .prettyPrinted)
    }
    
    private func exportProjectToDict(_ project: AnalysisProject) async throws -> [String: Any] {
        let analysisResults = project.analysisResultsArray.map { result in
            [
                "id": result.id.uuidString,
                "relativePath": result.relativePath,
                "fileName": result.fileName,
                "fileType": result.fileType,
                "codeSize": result.codeSize,
                "resourceSize": result.resourceSize,
                "frameworkSize": result.frameworkSize,
                "isUnusedResource": result.isUnusedResource,
                "isUnusedCode": result.isUnusedCode,
                "isExternallyMarked": result.isExternallyMarked
            ] as [String: Any]
        }
        
        return [
            "id": project.id.uuidString,
            "name": project.name,
            "projectPath": project.projectPath ?? "",
            "ipaPath": project.ipaPath ?? "",
            "linkmapPath": project.linkmapPath ?? "",
            "totalSize": project.totalSize,
            "summaryCodeSize": project.summaryCodeSize,
            "summaryResourceSize": project.summaryResourceSize,
            "summaryFrameworkSize": project.summaryFrameworkSize,
            "createdAt": project.createdAt.timeIntervalSince1970,
            "updatedAt": project.updatedAt.timeIntervalSince1970,
            "analysisResults": analysisResults
        ]
    }
    
    func importAnalysisProjects(from data: Data, replaceExisting: Bool) async throws -> [AnalysisProject] {
        let validation = try await validateImportData(data)
        guard validation.isValid else {
            throw AnalysisError.coreDataError("Import validation failed: \(validation.errors.joined(separator: ", "))")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let projects = json["projects"] as? [[String: Any]] else {
            throw AnalysisError.coreDataError("Invalid import data format")
        }
        
        var importedProjects: [AnalysisProject] = []
        
        for projectData in projects {
            let project = try await importSingleProject(from: projectData, replaceExisting: replaceExisting)
            importedProjects.append(project)
        }
        
        return importedProjects
    }
    
    private func importSingleProject(from projectData: [String: Any], replaceExisting: Bool) async throws -> AnalysisProject {
        guard let name = projectData["name"] as? String,
              let idString = projectData["id"] as? String,
              let id = UUID(uuidString: idString) else {
            throw AnalysisError.coreDataError("Invalid project data in import")
        }
        
        // Check if project already exists
        if let existingProject = try await fetchAnalysisProject(by: id) {
            if replaceExisting {
                try await deleteAnalysisProject(existingProject)
            } else {
                throw AnalysisError.coreDataError("Project with ID \(id) already exists")
            }
        }
        
        let projectPath = projectData["projectPath"] as? String
        let ipaPath = projectData["ipaPath"] as? String
        let linkmapPath = projectData["linkmapPath"] as? String
        let totalSize = projectData["totalSize"] as? Int64 ?? 0
        
        let project = try await createAnalysisProject(
            name: name,
            projectPath: projectPath,
            ipaPath: ipaPath,
            linkmapPath: linkmapPath,
            totalSize: totalSize,
            summaryCodeSize: projectData["summaryCodeSize"] as? Int64 ?? 0,
            summaryResourceSize: projectData["summaryResourceSize"] as? Int64 ?? 0,
            summaryFrameworkSize: projectData["summaryFrameworkSize"] as? Int64 ?? 0
        )
        
        // Set the original ID and dates
        project.id = id
        if let createdAtTimestamp = projectData["createdAt"] as? TimeInterval {
            project.createdAt = Date(timeIntervalSince1970: createdAtTimestamp)
        }
        if let updatedAtTimestamp = projectData["updatedAt"] as? TimeInterval {
            project.updatedAt = Date(timeIntervalSince1970: updatedAtTimestamp)
        }
        
        // Import analysis results
        if let analysisResults = projectData["analysisResults"] as? [[String: Any]] {
            for resultData in analysisResults {
                try await importAnalysisResult(resultData, for: project)
            }
        }
        
        try await updateAnalysisProject(project)
        return project
    }
    
    private func importAnalysisResult(_ resultData: [String: Any], for project: AnalysisProject) async throws {
        guard let relativePath = resultData["relativePath"] as? String,
              let fileName = resultData["fileName"] as? String,
              let fileType = resultData["fileType"] as? String else {
            throw AnalysisError.coreDataError("Invalid analysis result data in import")
        }
        
        let codeSize = resultData["codeSize"] as? Int64 ?? 0
        let resourceSize = resultData["resourceSize"] as? Int64 ?? 0
        let frameworkSize = resultData["frameworkSize"] as? Int64 ?? 0
        let isUnusedResource = resultData["isUnusedResource"] as? Bool ?? false
        let isUnusedCode = resultData["isUnusedCode"] as? Bool ?? false
        let isExternallyMarked = resultData["isExternallyMarked"] as? Bool ?? false
        
        try await createAnalysisResult(
            for: project,
            relativePath: relativePath,
            fileName: fileName,
            fileType: fileType,
            codeSize: codeSize,
            resourceSize: resourceSize,
            frameworkSize: frameworkSize,
            isUnusedResource: isUnusedResource,
            isUnusedCode: isUnusedCode,
            isExternallyMarked: isExternallyMarked
        )
    }
    
    func validateImportData(_ data: Data) async throws -> ImportValidationResult {
        var errors: [String] = []
        var warnings: [String] = []
        var projectCount = 0
        var estimatedSize: Int64 = 0
        
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                errors.append("Invalid JSON format")
                return ImportValidationResult(isValid: false, projectCount: 0, errors: errors, warnings: warnings, estimatedImportSize: 0)
            }
            
            let version = json["version"] as? String
            if version == nil {
                errors.append("Missing version information")
            } else if version != "1.0" {
                warnings.append("Import data version (\(version ?? "unknown")) may not be fully compatible")
            }
            
            guard let projects = json["projects"] as? [[String: Any]] else {
                errors.append("Missing or invalid projects data")
                return ImportValidationResult(isValid: false, projectCount: 0, errors: errors, warnings: warnings, estimatedImportSize: 0)
            }
            
            projectCount = projects.count
            
            for (index, projectData) in projects.enumerated() {
                let projectErrors = validateProjectData(projectData, index: index)
                errors.append(contentsOf: projectErrors)
                
                if let totalSize = projectData["totalSize"] as? Int64 {
                    estimatedSize += totalSize
                }
            }
            
        } catch {
            errors.append("Failed to parse JSON: \(error.localizedDescription)")
        }
        
        return ImportValidationResult(
            isValid: errors.isEmpty,
            projectCount: projectCount,
            errors: errors,
            warnings: warnings,
            estimatedImportSize: estimatedSize
        )
    }
    
    private func validateProjectData(_ projectData: [String: Any], index: Int) -> [String] {
        var errors: [String] = []
        
        if projectData["name"] as? String == nil {
            errors.append("Project \(index): Missing name")
        }
        
        if projectData["id"] as? String == nil {
            errors.append("Project \(index): Missing ID")
        } else if let idString = projectData["id"] as? String, UUID(uuidString: idString) == nil {
            errors.append("Project \(index): Invalid ID format")
        }
        
        return errors
    }
}
