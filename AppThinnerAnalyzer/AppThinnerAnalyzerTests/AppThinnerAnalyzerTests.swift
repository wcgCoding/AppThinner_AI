import Testing
import Foundation
import CoreData
@testable import AppThinnerAnalyzer

// MARK: - Basic Swift Testing Setup

@Test("CoreDataManager initialization")
func testCoreDataManagerInitialization() {
    let manager = CoreDataManager.shared
    #expect(manager.container.name == "DataModel")
}

@Test("AnalysisProject creation")
func testAnalysisProjectCreation() {
    let manager = CoreDataManager.shared
    let project = manager.createAnalysisProject(
        name: "Test Project",
        projectPath: "/test/path",
        ipaPath: "/test/app.ipa",
        linkmapPath: "/test/linkmap.txt"
    )
    
    #expect(project.name == "Test Project")
    #expect(project.projectPath == "/test/path")
    #expect(project.ipaPath == "/test/app.ipa")
    #expect(project.linkmapPath == "/test/linkmap.txt")
    #expect(project.totalSize == 0)
    #expect(project.analysisResultsArray.isEmpty)
}

@Test("AnalysisResult creation")
func testAnalysisResultCreation() {
    let manager = CoreDataManager.shared
    let project = manager.createAnalysisProject(
        name: "Test Project",
        projectPath: nil,
        ipaPath: nil,
        linkmapPath: nil
    )
    let result = manager.createAnalysisResult(
        for: project,
        relativePath: "Sources/Test.swift",
        fileName: "Test.swift",
        fileType: "Code"
    )
    
    #expect(result.relativePath == "Sources/Test.swift")
    #expect(result.fileName == "Test.swift")
    #expect(result.fileType == "Code")
    #expect(result.codeSize == 0)
    #expect(result.resourceSize == 0)
    #expect(result.frameworkSize == 0)
    #expect(result.isUnusedResource == false)
    #expect(result.isUnusedCode == false)
    #expect(result.project == project)
}

@Test("FileType enum functionality")
func testFileTypeEnum() {
    #expect(FileType.code.rawValue == "Code")
    #expect(FileType.resource.rawValue == "Resource")
    #expect(FileType.framework.rawValue == "Framework")
    #expect(FileType.directory.rawValue == "Directory")
    #expect(FileType.other.rawValue == "Other")
}

@Test("TreemapNode creation")
func testTreemapNodeCreation() {
    let node = TreemapNode(
        name: "TestNode",
        relativePath: "test/path",
        size: 1024,
        children: [],
        isUnused: false,
        unusedRatio: 0,
        fileType: .code
    )
    
    #expect(node.name == "TestNode")
    #expect(node.relativePath == "test/path")
    #expect(node.size == 1024)
    #expect(node.children.isEmpty)
    #expect(node.isUnused == false)
    #expect(node.fileType == .code)
}

@Test("MainViewModel initialization")
@MainActor
func testMainViewModelInitialization() async {
    let viewModel = MainViewModel()
    
    #expect(viewModel.currentProject == nil)
    #expect(viewModel.analysisHistory.isEmpty)
    #expect(viewModel.isAnalyzing == false)
    #expect(viewModel.analysisProgress == 0.0)
    #expect(viewModel.hasValidInput == false)
}

@Test("TreemapViewModel initialization")
@MainActor
func testTreemapViewModelInitialization() async {
    let viewModel = TreemapViewModel()
    
    #expect(viewModel.rootNode == nil)
    #expect(viewModel.currentNode == nil)
    #expect(viewModel.selectedNode == nil)
    #expect(viewModel.searchText.isEmpty)
    #expect(viewModel.hoveredNode == nil)
    #expect(viewModel.navigationHistory.isEmpty)
}

@Test("OptimizationViewModel initialization")
@MainActor
func testOptimizationViewModelInitialization() async {
    let viewModel = OptimizationViewModel()
    
    #expect(viewModel.selectedUnusedResources.isEmpty)
    #expect(viewModel.selectedUnusedCode.isEmpty)
    #expect(viewModel.isOptimizing == false)
    #expect(viewModel.optimizationProgress == 0.0)
    #expect(viewModel.optimizationResults == nil)
    #expect(viewModel.backupLocation == nil)
}

@Test("ComparisonViewModel initialization")
@MainActor
func testComparisonViewModelInitialization() async {
    let viewModel = ComparisonViewModel()
    
    #expect(viewModel.selectedProjects.isEmpty)
    #expect(viewModel.comparisonResult == nil)
    #expect(viewModel.isComparing == false)
}

// MARK: - Property-Based Testing

// Feature: ios-app-analyzer, Property 16: Data Persistence Round-trip Integrity
// Validates: Requirements 6.1, 6.4

@Suite("Property 16: Data Persistence Round-trip Integrity")
struct DataPersistenceRoundTripTests {
    
    // Test data generator for property-based testing
    struct TestProjectData {
        let name: String
        let projectPath: String?
        let ipaPath: String?
        let linkmapPath: String?
        let resultsCount: Int
        let resultData: [(relativePath: String, fileName: String, fileType: String, codeSize: Int64, resourceSize: Int64, frameworkSize: Int64, isUnusedResource: Bool, isUnusedCode: Bool)]
    }
    
    // Generate diverse test cases to simulate property-based testing
    static let testCases: [TestProjectData] = [
        // Case 1: Minimal project with no results
        TestProjectData(
            name: "Minimal Project",
            projectPath: nil,
            ipaPath: nil,
            linkmapPath: nil,
            resultsCount: 0,
            resultData: []
        ),
        // Case 2: Project with all paths and single result
        TestProjectData(
            name: "Complete Project",
            projectPath: "/Users/test/MyApp",
            ipaPath: "/Users/test/MyApp.ipa",
            linkmapPath: "/Users/test/linkmap.txt",
            resultsCount: 1,
            resultData: [
                ("Sources/Main.swift", "Main.swift", "Code", 1024, 0, 0, false, false)
            ]
        ),
        // Case 3: Project with multiple results and mixed data
        TestProjectData(
            name: "Complex Project",
            projectPath: "/Users/test/ComplexApp",
            ipaPath: "/Users/test/ComplexApp.ipa",
            linkmapPath: "/Users/test/complex_linkmap.txt",
            resultsCount: 5,
            resultData: [
                ("Sources/AppDelegate.swift", "AppDelegate.swift", "Code", 2048, 0, 0, false, false),
                ("Resources/icon.png", "icon.png", "Resource", 0, 4096, 0, false, false),
                ("Frameworks/MyFramework.framework", "MyFramework.framework", "Framework", 0, 0, 8192, false, false),
                ("Resources/unused_image.png", "unused_image.png", "Resource", 0, 2048, 0, true, false),
                ("Sources/UnusedClass.swift", "UnusedClass.swift", "Code", 512, 0, 0, false, true)
            ]
        ),
        // Case 4: Project with special characters in paths
        TestProjectData(
            name: "Special Chars Project 中文",
            projectPath: "/Users/test/My App (2024)",
            ipaPath: "/Users/test/My App.ipa",
            linkmapPath: "/Users/test/linkmap-v2.txt",
            resultsCount: 2,
            resultData: [
                ("Sources/File With Spaces.swift", "File With Spaces.swift", "Code", 1536, 0, 0, false, false),
                ("Resources/图片.png", "图片.png", "Resource", 0, 3072, 0, false, false)
            ]
        ),
        // Case 5: Large project with many results
        TestProjectData(
            name: "Large Project",
            projectPath: "/Users/test/LargeApp",
            ipaPath: "/Users/test/LargeApp.ipa",
            linkmapPath: "/Users/test/large_linkmap.txt",
            resultsCount: 10,
            resultData: [
                ("Sources/File1.swift", "File1.swift", "Code", 1000, 0, 0, false, false),
                ("Sources/File2.swift", "File2.swift", "Code", 2000, 0, 0, false, false),
                ("Sources/File3.swift", "File3.swift", "Code", 3000, 0, 0, false, false),
                ("Resources/image1.png", "image1.png", "Resource", 0, 1500, 0, false, false),
                ("Resources/image2.png", "image2.png", "Resource", 0, 2500, 0, false, false),
                ("Resources/image3.png", "image3.png", "Resource", 0, 3500, 0, true, false),
                ("Frameworks/Framework1.framework", "Framework1.framework", "Framework", 0, 0, 10000, false, false),
                ("Frameworks/Framework2.framework", "Framework2.framework", "Framework", 0, 0, 20000, false, false),
                ("Sources/UnusedFile1.swift", "UnusedFile1.swift", "Code", 500, 0, 0, false, true),
                ("Sources/UnusedFile2.swift", "UnusedFile2.swift", "Code", 750, 0, 0, false, true)
            ]
        ),
        // Case 6: Project with only unused content
        TestProjectData(
            name: "Unused Only Project",
            projectPath: "/Users/test/UnusedApp",
            ipaPath: nil,
            linkmapPath: nil,
            resultsCount: 3,
            resultData: [
                ("Resources/unused1.png", "unused1.png", "Resource", 0, 1024, 0, true, false),
                ("Resources/unused2.png", "unused2.png", "Resource", 0, 2048, 0, true, false),
                ("Sources/UnusedCode.swift", "UnusedCode.swift", "Code", 512, 0, 0, false, true)
            ]
        ),
        // Case 7: Project with maximum size values
        TestProjectData(
            name: "Max Size Project",
            projectPath: "/Users/test/MaxSizeApp",
            ipaPath: "/Users/test/MaxSizeApp.ipa",
            linkmapPath: "/Users/test/max_linkmap.txt",
            resultsCount: 3,
            resultData: [
                ("Sources/LargeFile.swift", "LargeFile.swift", "Code", Int64.max / 4, 0, 0, false, false),
                ("Resources/LargeResource.bin", "LargeResource.bin", "Resource", 0, Int64.max / 4, 0, false, false),
                ("Frameworks/LargeFramework.framework", "LargeFramework.framework", "Framework", 0, 0, Int64.max / 4, false, false)
            ]
        ),
        // Case 8: Project with empty strings (edge case)
        TestProjectData(
            name: "",
            projectPath: "",
            ipaPath: "",
            linkmapPath: "",
            resultsCount: 1,
            resultData: [
                ("", "", "Code", 0, 0, 0, false, false)
            ]
        )
    ]
    
    @Test("Round-trip persistence preserves project data", arguments: testCases)
    func testProjectRoundTripPersistence(testData: TestProjectData) throws {
        let manager = CoreDataManager.shared
        let context = manager.container.viewContext
        
        // Create original project
        let originalProject = manager.createAnalysisProject(
            name: testData.name,
            projectPath: testData.projectPath,
            ipaPath: testData.ipaPath,
            linkmapPath: testData.linkmapPath
        )
        
        // Add analysis results
        for resultData in testData.resultData {
            let result = manager.createAnalysisResult(
                for: originalProject,
                relativePath: resultData.relativePath,
                fileName: resultData.fileName,
                fileType: resultData.fileType
            )
            result.codeSize = resultData.codeSize
            result.resourceSize = resultData.resourceSize
            result.frameworkSize = resultData.frameworkSize
            result.isUnusedResource = resultData.isUnusedResource
            result.isUnusedCode = resultData.isUnusedCode
        }
        
        originalProject.updateTotalSize()
        
        // Save to CoreData
        try manager.save()
        
        // Fetch the project back
        let fetchRequest: NSFetchRequest<AnalysisProject> = AnalysisProject.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", originalProject.id as CVarArg)
        
        let fetchedProjects = try manager.fetch(fetchRequest)
        
        // Verify project was saved and fetched
        #expect(fetchedProjects.count == 1, "Should fetch exactly one project")
        
        guard let loadedProject = fetchedProjects.first else {
            Issue.record("Failed to fetch saved project")
            return
        }
        
        // Property: All project attributes should be preserved
        #expect(loadedProject.id == originalProject.id, "Project ID should be preserved")
        #expect(loadedProject.name == originalProject.name, "Project name should be preserved")
        #expect(loadedProject.projectPath == originalProject.projectPath, "Project path should be preserved")
        #expect(loadedProject.ipaPath == originalProject.ipaPath, "IPA path should be preserved")
        #expect(loadedProject.linkmapPath == originalProject.linkmapPath, "Linkmap path should be preserved")
        #expect(loadedProject.totalSize == originalProject.totalSize, "Total size should be preserved")
        #expect(loadedProject.createdAt.timeIntervalSince1970 == originalProject.createdAt.timeIntervalSince1970, "Created date should be preserved")
        
        // Property: All analysis results should be preserved
        #expect(loadedProject.analysisResultsArray.count == testData.resultsCount, "Should have correct number of results")
        
        // Property: Each result's data should be preserved
        let originalResults = originalProject.analysisResultsArray
        let loadedResults = loadedProject.analysisResultsArray
        
        for (index, originalResult) in originalResults.enumerated() {
            let loadedResult = loadedResults[index]
            
            #expect(loadedResult.id == originalResult.id, "Result ID should be preserved at index \(index)")
            #expect(loadedResult.relativePath == originalResult.relativePath, "Relative path should be preserved at index \(index)")
            #expect(loadedResult.fileName == originalResult.fileName, "File name should be preserved at index \(index)")
            #expect(loadedResult.fileType == originalResult.fileType, "File type should be preserved at index \(index)")
            #expect(loadedResult.codeSize == originalResult.codeSize, "Code size should be preserved at index \(index)")
            #expect(loadedResult.resourceSize == originalResult.resourceSize, "Resource size should be preserved at index \(index)")
            #expect(loadedResult.frameworkSize == originalResult.frameworkSize, "Framework size should be preserved at index \(index)")
            #expect(loadedResult.isUnusedResource == originalResult.isUnusedResource, "Unused resource flag should be preserved at index \(index)")
            #expect(loadedResult.isUnusedCode == originalResult.isUnusedCode, "Unused code flag should be preserved at index \(index)")
            #expect(loadedResult.project.id == loadedProject.id, "Result should maintain relationship to project at index \(index)")
        }
        
        // Property: Computed properties should be consistent
        #expect(loadedProject.totalCodeSize == originalProject.totalCodeSize, "Total code size should be consistent")
        #expect(loadedProject.totalResourceSize == originalProject.totalResourceSize, "Total resource size should be consistent")
        #expect(loadedProject.totalFrameworkSize == originalProject.totalFrameworkSize, "Total framework size should be consistent")
        #expect(loadedProject.unusedResourceSize == originalProject.unusedResourceSize, "Unused resource size should be consistent")
        #expect(loadedProject.unusedCodeSize == originalProject.unusedCodeSize, "Unused code size should be consistent")
        #expect(loadedProject.potentialSavings == originalProject.potentialSavings, "Potential savings should be consistent")
        
        // Cleanup
        try manager.delete(loadedProject)
    }
    
    @Test("Multiple save-load cycles preserve data integrity")
    func testMultipleSaveLoadCycles() throws {
        let manager = CoreDataManager.shared
        
        // Create a project with complex data
        let originalProject = manager.createAnalysisProject(
            name: "Multi-Cycle Test Project",
            projectPath: "/test/path",
            ipaPath: "/test/app.ipa",
            linkmapPath: "/test/linkmap.txt"
        )
        
        // Add multiple results
        for i in 0..<5 {
            let result = manager.createAnalysisResult(
                for: originalProject,
                relativePath: "Sources/File\(i).swift",
                fileName: "File\(i).swift",
                fileType: "Code"
            )
            result.codeSize = Int64(i * 1000)
            result.resourceSize = Int64(i * 500)
        }
        
        originalProject.updateTotalSize()
        let originalTotalSize = originalProject.totalSize
        let originalResultCount = originalProject.analysisResultsArray.count
        
        // Perform multiple save-load cycles
        for cycle in 1...5 {
            try manager.save()
            
            let fetchRequest: NSFetchRequest<AnalysisProject> = AnalysisProject.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", originalProject.id as CVarArg)
            let fetchedProjects = try manager.fetch(fetchRequest)
            
            #expect(fetchedProjects.count == 1, "Should fetch project in cycle \(cycle)")
            
            guard let loadedProject = fetchedProjects.first else {
                Issue.record("Failed to fetch project in cycle \(cycle)")
                return
            }
            
            // Property: Data should remain consistent across multiple cycles
            #expect(loadedProject.totalSize == originalTotalSize, "Total size should remain consistent in cycle \(cycle)")
            #expect(loadedProject.analysisResultsArray.count == originalResultCount, "Result count should remain consistent in cycle \(cycle)")
        }
        
        // Cleanup
        let fetchRequest: NSFetchRequest<AnalysisProject> = AnalysisProject.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", originalProject.id as CVarArg)
        if let project = try manager.fetch(fetchRequest).first {
            try manager.delete(project)
        }
    }
    
    @Test("Concurrent save operations maintain data integrity")
    func testConcurrentSaveOperations() async throws {
        let manager = CoreDataManager.shared
        
        // Create multiple projects concurrently
        await withTaskGroup(of: AnalysisProject.self) { group in
            for i in 0..<10 {
                group.addTask {
                    let project = manager.createAnalysisProject(
                        name: "Concurrent Project \(i)",
                        projectPath: "/test/path\(i)",
                        ipaPath: "/test/app\(i).ipa",
                        linkmapPath: "/test/linkmap\(i).txt"
                    )
                    
                    let result = manager.createAnalysisResult(
                        for: project,
                        relativePath: "Sources/File\(i).swift",
                        fileName: "File\(i).swift",
                        fileType: "Code"
                    )
                    result.codeSize = Int64(i * 1000)
                    
                    project.updateTotalSize()
                    
                    return project
                }
            }
        }
        
        // Save all changes
        try manager.save()
        
        // Verify all projects were saved correctly
        let fetchRequest: NSFetchRequest<AnalysisProject> = AnalysisProject.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "name BEGINSWITH %@", "Concurrent Project")
        let fetchedProjects = try manager.fetch(fetchRequest)
        
        // Property: All concurrently created projects should be persisted
        #expect(fetchedProjects.count == 10, "All concurrent projects should be saved")
        
        // Property: Each project should have correct data
        for project in fetchedProjects {
            #expect(project.name.hasPrefix("Concurrent Project"), "Project name should be correct")
            #expect(project.analysisResultsArray.count == 1, "Each project should have one result")
            #expect(project.totalSize > 0, "Total size should be calculated")
        }
        
        // Cleanup
        for project in fetchedProjects {
            try manager.delete(project)
        }
    }
    
    @Test("Delete and recreate maintains data independence")
    func testDeleteAndRecreate() throws {
        let manager = CoreDataManager.shared
        
        // Create first project
        let project1 = manager.createAnalysisProject(
            name: "First Project",
            projectPath: "/test/first",
            ipaPath: nil,
            linkmapPath: nil
        )
        let result1 = manager.createAnalysisResult(
            for: project1,
            relativePath: "Sources/First.swift",
            fileName: "First.swift",
            fileType: "Code"
        )
        result1.codeSize = 1000
        project1.updateTotalSize()
        
        try manager.save()
        let firstProjectId = project1.id
        
        // Delete first project
        try manager.delete(project1)
        
        // Create second project with same name but different data
        let project2 = manager.createAnalysisProject(
            name: "First Project",
            projectPath: "/test/second",
            ipaPath: nil,
            linkmapPath: nil
        )
        let result2 = manager.createAnalysisResult(
            for: project2,
            relativePath: "Sources/Second.swift",
            fileName: "Second.swift",
            fileType: "Code"
        )
        result2.codeSize = 2000
        project2.updateTotalSize()
        
        try manager.save()
        
        // Verify second project is independent
        let fetchRequest: NSFetchRequest<AnalysisProject> = AnalysisProject.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "name == %@", "First Project")
        let fetchedProjects = try manager.fetch(fetchRequest)
        
        // Property: Only the new project should exist
        #expect(fetchedProjects.count == 1, "Should have only one project with the name")
        
        guard let loadedProject = fetchedProjects.first else {
            Issue.record("Failed to fetch recreated project")
            return
        }
        
        // Property: New project should have different ID and data
        #expect(loadedProject.id != firstProjectId, "New project should have different ID")
        #expect(loadedProject.projectPath == "/test/second", "New project should have new path")
        #expect(loadedProject.totalSize == 2000, "New project should have new size")
        #expect(loadedProject.analysisResultsArray.first?.fileName == "Second.swift", "New project should have new results")
        
        // Cleanup
        try manager.delete(loadedProject)
    }
}

// MARK: - Integration Test Placeholders

@Test("Integration test placeholder")
func testIntegrationPlaceholder() {
    // TODO: Implement integration tests in future tasks
    // These will test the interaction between multiple components
    #expect(true) // Placeholder assertion
}

// MARK: - Helper Functions for Testing

extension AnalysisProject {
    static func createTestProject() -> AnalysisProject {
        let manager = CoreDataManager.shared
        return manager.createAnalysisProject(
            name: "Test Project",
            projectPath: "/test/project",
            ipaPath: "/test/app.ipa",
            linkmapPath: "/test/linkmap.txt"
        )
    }
}

extension AnalysisResult {
    static func createTestResult(for project: AnalysisProject) -> AnalysisResult {
        let manager = CoreDataManager.shared
        return manager.createAnalysisResult(
            for: project,
            relativePath: "Sources/TestFile.swift",
            fileName: "TestFile.swift",
            fileType: "Code"
        )
    }
}