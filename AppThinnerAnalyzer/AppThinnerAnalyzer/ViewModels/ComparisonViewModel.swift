import SwiftUI
import Foundation

@MainActor
class ComparisonViewModel: ObservableObject {
    @Published var selectedProjects: [AnalysisProject] = []
    @Published var comparisonResult: ProjectComparison?
    @Published var isComparing = false
    @Published var errorMessage: String?
    
    // MARK: - Dependencies
    
    private let comparisonService: ComparisonServiceProtocol
    
    // MARK: - Initialization
    
    init(comparisonService: ComparisonServiceProtocol) {
        self.comparisonService = comparisonService
    }
    
    // Convenience initializer for backward compatibility
    convenience init() {
        self.init(comparisonService: DependencyContainer.shared.comparisonService)
    }
    
    // MARK: - Project Selection
    
    func addProjectToComparison(_ project: AnalysisProject) {
        guard !selectedProjects.contains(where: { $0.id == project.id }) else { return }
        guard selectedProjects.count < 5 else { return } // Limit to 5 projects for performance
        
        selectedProjects.append(project)
    }
    
    func removeProjectFromComparison(_ project: AnalysisProject) {
        selectedProjects.removeAll { $0.id == project.id }
        
        // Clear comparison result if we have fewer than 2 projects
        if selectedProjects.count < 2 {
            comparisonResult = nil
        }
    }
    
    func clearSelection() {
        selectedProjects.removeAll()
        comparisonResult = nil
    }
    
    // MARK: - Comparison Operations
    
    func performComparison() async throws {
        guard selectedProjects.count >= 2 else {
            throw AnalysisError.invalidFilePath("At least 2 projects are required for comparison")
        }
        
        isComparing = true
        errorMessage = nil
        
        do {
            // Use the comparison service to perform the comparison
            let project1 = selectedProjects[0]
            let project2 = selectedProjects[1]
            
            comparisonResult = try await comparisonService.compareProjects(project1, project2)
            
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
        
        isComparing = false
    }
    
    func exportComparisonReport() async throws -> URL {
        guard let comparison = comparisonResult else {
            throw AnalysisError.invalidFilePath("No comparison result to export")
        }
        
        return try await comparisonService.exportComparisonReport(comparison)
    }
    
    // MARK: - Private Helper Methods
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Extensions

extension DateFormatter {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }()
}