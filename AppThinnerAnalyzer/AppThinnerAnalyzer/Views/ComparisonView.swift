import SwiftUI

struct ComparisonView: View {
    let projects: [AnalysisProject]
    @StateObject private var viewModel = DependencyContainer.shared.makeComparisonViewModel()
    @State private var showingExportOptions = false
    @State private var selectedExportFormat: ExportFormat = .html
    
    enum ExportFormat: String, CaseIterable {
        case html = "HTML Report"
        case csv = "CSV Data"
        case json = "JSON Data"
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Project Selection Section - Enhanced for Requirement 6.3
            ProjectSelectionSection(
                projects: projects,
                selectedProjects: $viewModel.selectedProjects,
                onAddProject: { project in
                    viewModel.addProjectToComparison(project)
                },
                onRemoveProject: { project in
                    viewModel.removeProjectFromComparison(project)
                },
                maxSelections: 5
            )
            
            // Comparison Controls
            if viewModel.selectedProjects.count >= 2 {
                ComparisonControlsSection(
                    viewModel: viewModel,
                    showingExportOptions: $showingExportOptions,
                    selectedExportFormat: $selectedExportFormat
                )
            }
            
            // Comparison Results - Enhanced display and trends
            if let comparison = viewModel.comparisonResult {
                ScrollView {
                    ComparisonResultView(
                        comparison: comparison,
                        onExportReport: {
                            showingExportOptions = true
                        },
                        onShowTrends: {
                            // TODO: Implement trend analysis
                        }
                    )
                }
            } else if viewModel.selectedProjects.count < 2 {
                ComparisonEmptyStateView(
                    projectCount: projects.count,
                    selectedCount: viewModel.selectedProjects.count
                )
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Project Comparison")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if viewModel.selectedProjects.count >= 2 {
                    Menu("Export") {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Button(format.rawValue) {
                                selectedExportFormat = format
                                showingExportOptions = true
                            }
                        }
                    }
                    .disabled(viewModel.comparisonResult == nil)
                }
                
                Button("Clear All") {
                    viewModel.clearSelection()
                }
                .disabled(viewModel.selectedProjects.isEmpty)
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .sheet(isPresented: $showingExportOptions) {
            ComparisonExportView(
                viewModel: viewModel,
                selectedFormat: $selectedExportFormat
            )
        }
        .overlay {
            if viewModel.isComparing {
                ComparisonProgressOverlay()
            }
        }
        .keyboardShortcuts(for: .comparison)
        // Comparison-specific keyboard shortcuts
        .keyboardShortcut(KeyboardShortcuts.compareProjects, modifiers: [.command]) {
            if viewModel.selectedProjects.count >= 2 && !viewModel.isComparing {
                Task {
                    do {
                        try await viewModel.performComparison()
                    } catch {
                        // Error handling is done in the view model
                    }
                }
            }
        }
        .keyboardShortcut(KeyboardShortcuts.exportReport, modifiers: [.command]) {
            if viewModel.comparisonResult != nil {
                showingExportOptions = true
            }
        }
        .keyboardShortcut(KeyboardShortcuts.clearSelection, modifiers: []) {
            viewModel.clearSelection()
        }
        .accessibilityKeyboardShortcut("⌘C", description: "Compare selected projects")
        .accessibilityKeyboardShortcut("⌘E", description: "Export comparison report")
        .accessibilityKeyboardShortcut("⌫", description: "Clear project selection")
    }
}

struct ProjectSelectionSection: View {
    let projects: [AnalysisProject]
    @Binding var selectedProjects: [AnalysisProject]
    let onAddProject: (AnalysisProject) -> Void
    let onRemoveProject: (AnalysisProject) -> Void
    let maxSelections: Int
    
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .dateDescending
    
    enum SortOrder: String, CaseIterable {
        case dateDescending = "Date (Newest)"
        case dateAscending = "Date (Oldest)"
        case sizeDescending = "Size (Largest)"
        case sizeAscending = "Size (Smallest)"
        case nameAscending = "Name (A-Z)"
    }
    
    var filteredAndSortedProjects: [AnalysisProject] {
        let filtered = searchText.isEmpty ? projects : projects.filter { project in
            project.name.localizedCaseInsensitiveContains(searchText)
        }
        
        return filtered.sorted { project1, project2 in
            switch sortOrder {
            case .dateDescending:
                return project1.createdAt > project2.createdAt
            case .dateAscending:
                return project1.createdAt < project2.createdAt
            case .sizeDescending:
                return project1.totalSize > project2.totalSize
            case .sizeAscending:
                return project1.totalSize < project2.totalSize
            case .nameAscending:
                return project1.name < project2.name
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Select Projects to Compare")
                    .font(.headline)
                
                Spacer()
                
                if !selectedProjects.isEmpty {
                    Button("Clear Selection") {
                        selectedProjects.forEach { project in
                            onRemoveProject(project)
                        }
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
                }
            }
            
            // Search and Sort Controls
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search projects...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                
                Picker("Sort", selection: $sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }
            
            if projects.isEmpty {
                Text("No analysis projects available")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(filteredAndSortedProjects) { project in
                        ProjectSelectionCard(
                            project: project,
                            isSelected: selectedProjects.contains { $0.id == project.id },
                            isDisabled: !selectedProjects.contains { $0.id == project.id } && selectedProjects.count >= maxSelections,
                            onToggle: {
                                if selectedProjects.contains(where: { $0.id == project.id }) {
                                    onRemoveProject(project)
                                } else if selectedProjects.count < maxSelections {
                                    onAddProject(project)
                                }
                            }
                        )
                    }
                }
            }
            
            // Selection Summary
            HStack {
                Text("Selected: \(selectedProjects.count)/\(maxSelections) project\(selectedProjects.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !searchText.isEmpty {
                    Text("Showing \(filteredAndSortedProjects.count) of \(projects.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct ComparisonControlsSection: View {
    @ObservedObject var viewModel: ComparisonViewModel
    @Binding var showingExportOptions: Bool
    @Binding var selectedExportFormat: ComparisonView.ExportFormat
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button("Compare Projects") {
                    Task {
                        do {
                            try await viewModel.performComparison()
                        } catch {
                            // Error handling is done in the view model
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isComparing)
                
                if viewModel.comparisonResult != nil {
                    Button("Export Results") {
                        showingExportOptions = true
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Show Trends") {
                        // TODO: Implement trend analysis
                    }
                    .buttonStyle(.bordered)
                    .disabled(true) // Will be enabled in future tasks
                }
                
                Spacer()
            }
            
            // Quick comparison info
            if viewModel.selectedProjects.count >= 2 {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    
                    Text("Comparing \(viewModel.selectedProjects.count) projects")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
    }
}

struct ComparisonEmptyStateView: View {
    let projectCount: Int
    let selectedCount: Int
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("Select Projects to Compare")
                .font(.title2)
                .fontWeight(.semibold)
            
            if projectCount == 0 {
                Text("No analysis projects available. Run some analyses first.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else if selectedCount == 0 {
                Text("Choose at least 2 projects from the list above to compare their analysis results")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Select \(2 - selectedCount) more project\(2 - selectedCount == 1 ? "" : "s") to start comparison")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            if projectCount > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Comparison Features:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    ComparisonFeatureRow(icon: "chart.bar", text: "Size change analysis")
                    ComparisonFeatureRow(icon: "doc.text", text: "File-level comparisons")
                    ComparisonFeatureRow(icon: "arrow.up.arrow.down", text: "Trend identification")
                    ComparisonFeatureRow(icon: "square.and.arrow.up", text: "Export reports")
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
        .padding(40)
    }
}

struct ComparisonFeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 16)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct ComparisonExportView: View {
    @ObservedObject var viewModel: ComparisonViewModel
    @Binding var selectedFormat: ComparisonView.ExportFormat
    @Environment(\.dismiss) private var dismiss
    
    @State private var isExporting = false
    @State private var exportProgress: Double = 0.0
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Export Comparison Report")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Export Format")
                    .font(.headline)
                
                Picker("Format", selection: $selectedFormat) {
                    ForEach(ComparisonView.ExportFormat.allCases, id: \.self) { format in
                        VStack(alignment: .leading) {
                            Text(format.rawValue)
                                .font(.subheadline)
                            Text(formatDescription(format))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .tag(format)
                    }
                }
                .pickerStyle(.radioGroup)
            }
            
            if isExporting {
                VStack(spacing: 12) {
                    ProgressView(value: exportProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                    
                    Text("Exporting report...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            HStack {
                Button("Export") {
                    Task {
                        await performExport()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExporting)
                
                Spacer()
            }
        }
        .padding()
        .frame(width: 400, height: 300)
    }
    
    private func formatDescription(_ format: ComparisonView.ExportFormat) -> String {
        switch format {
        case .html:
            return "Interactive HTML report with charts"
        case .csv:
            return "Spreadsheet-compatible data format"
        case .json:
            return "Machine-readable structured data"
        }
    }
    
    private func performExport() async {
        isExporting = true
        exportProgress = 0.0
        
        do {
            // Simulate export progress
            for i in 1...10 {
                exportProgress = Double(i) / 10.0
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
            
            let reportURL = try await viewModel.exportComparisonReport()
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: reportURL.path)
            dismiss()
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
        
        isExporting = false
    }
}

struct ProjectSelectionCard: View {
    let project: AnalysisProject
    let isSelected: Bool
    let isDisabled: Bool
    let onToggle: () -> Void
    
    init(project: AnalysisProject, isSelected: Bool, isDisabled: Bool = false, onToggle: @escaping () -> Void) {
        self.project = project
        self.isSelected = isSelected
        self.isDisabled = isDisabled
        self.onToggle = onToggle
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: onToggle) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundColor(isSelected ? .accentColor : (isDisabled ? .secondary.opacity(0.5) : .secondary))
                }
                .buttonStyle(.borderless)
                .disabled(isDisabled)
                
                Text(project.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundColor(isDisabled ? .secondary.opacity(0.5) : .primary)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Size:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatBytes(project.totalSize))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(isDisabled ? .secondary.opacity(0.5) : .primary)
                    
                    Spacer()
                    
                    Text("Savings:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatBytes(project.potentialSavings))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(isDisabled ? .secondary.opacity(0.5) : .orange)
                }
                
                Text("Created: \(DateFormatter.shortDate.string(from: project.createdAt))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(isSelected ? Color.accentColor.opacity(0.1) : (isDisabled ? Color.gray.opacity(0.05) : Color(NSColor.controlBackgroundColor)))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isDisabled {
                onToggle()
            }
        }
        .opacity(isDisabled ? 0.6 : 1.0)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct ComparisonResultView: View {
    let comparison: ProjectComparison
    let onExportReport: () -> Void
    let onShowTrends: () -> Void
    
    @State private var selectedDetailTab = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with enhanced controls
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Comparison Results")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Comparing \(comparison.projects.count) projects")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button("Show Trends") {
                        onShowTrends()
                    }
                    .buttonStyle(.bordered)
                    .disabled(true) // Will be enabled in future tasks
                    
                    Button("Export Report") {
                        onExportReport()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            
            // Summary Section with enhanced metrics
            ComparisonSummaryView(summary: comparison.summary)
            
            // Detailed Analysis Tabs
            VStack(alignment: .leading, spacing: 16) {
                Picker("Details", selection: $selectedDetailTab) {
                    Text("Size Changes").tag(0)
                    Text("File Changes").tag(1)
                    Text("Project Timeline").tag(2)
                }
                .pickerStyle(.segmented)
                
                switch selectedDetailTab {
                case 0:
                    SizeChangesView(sizeChanges: comparison.sizeChanges)
                case 1:
                    FileChangesView(
                        newFiles: comparison.newFiles,
                        removedFiles: comparison.removedFiles,
                        modifiedFiles: comparison.modifiedFiles
                    )
                case 2:
                    ProjectTimelineView(projects: comparison.projects)
                default:
                    EmptyView()
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct ProjectTimelineView: View {
    let projects: [AnalysisProject]
    
    var sortedProjects: [AnalysisProject] {
        projects.sorted { $0.createdAt < $1.createdAt }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Project Timeline")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(sortedProjects.enumerated()), id: \.element.id) { index, project in
                    TimelineRow(
                        project: project,
                        isFirst: index == 0,
                        isLast: index == sortedProjects.count - 1
                    )
                }
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }
}

struct TimelineRow: View {
    let project: AnalysisProject
    let isFirst: Bool
    let isLast: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Timeline indicator
            VStack(spacing: 0) {
                if !isFirst {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.3))
                        .frame(width: 2, height: 20)
                }
                
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                
                if !isLast {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.3))
                        .frame(width: 2, height: 20)
                }
            }
            
            // Project info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(project.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text(DateFormatter.shortDateTime.string(from: project.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Size: \(formatBytes(project.totalSize))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Savings: \(formatBytes(project.potentialSavings))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct ComparisonSummaryView: View {
    let summary: ComparisonSummary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Summary")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                SummaryMetric(
                    title: "Total Size Change",
                    value: formatBytes(summary.totalSizeChange),
                    systemImage: summary.totalSizeChange >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill",
                    color: summary.totalSizeChange >= 0 ? .red : .green
                )
                
                SummaryMetric(
                    title: "Files Added",
                    value: "\(summary.addedFiles)",
                    systemImage: "plus.circle.fill",
                    color: .blue
                )
                
                SummaryMetric(
                    title: "Files Removed",
                    value: "\(summary.removedFiles)",
                    systemImage: "minus.circle.fill",
                    color: .orange
                )
            }
            
            if !summary.significantChanges.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Significant Changes")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    ForEach(summary.significantChanges, id: \.self) { change in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            
                            Text(change)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct SizeChangesView: View {
    let sizeChanges: [SizeChange]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Size Changes")
                .font(.headline)
            
            VStack(spacing: 8) {
                ForEach(sizeChanges, id: \.category) { change in
                    SizeChangeRow(change: change)
                }
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }
}

struct SizeChangeRow: View {
    let change: SizeChange
    
    var body: some View {
        HStack {
            Text(change.category)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(width: 120, alignment: .leading)
            
            Text(formatBytes(change.oldSize))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(formatBytes(change.newSize))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            
            Spacer()
            
            HStack(spacing: 4) {
                Text(formatBytes(change.change))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(change.change >= 0 ? .red : .green)
                
                Text("(\(String(format: "%.1f", change.changePercentage))%)")
                    .font(.caption)
                    .foregroundColor(change.change >= 0 ? .red : .green)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct FileChangesView: View {
    let newFiles: [String]
    let removedFiles: [String]
    let modifiedFiles: [FileChange]
    
    @State private var selectedSection = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("File Changes")
                .font(.headline)
            
            Picker("File Changes", selection: $selectedSection) {
                Text("Added (\(newFiles.count))").tag(0)
                Text("Removed (\(removedFiles.count))").tag(1)
                Text("Modified (\(modifiedFiles.count))").tag(2)
            }
            .pickerStyle(.segmented)
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    switch selectedSection {
                    case 0:
                        ForEach(newFiles, id: \.self) { file in
                            FileChangeRow(
                                fileName: URL(fileURLWithPath: file).lastPathComponent,
                                filePath: file,
                                changeType: .added,
                                sizeChange: nil
                            )
                        }
                    case 1:
                        ForEach(removedFiles, id: \.self) { file in
                            FileChangeRow(
                                fileName: URL(fileURLWithPath: file).lastPathComponent,
                                filePath: file,
                                changeType: .removed,
                                sizeChange: nil
                            )
                        }
                    case 2:
                        ForEach(modifiedFiles, id: \.filePath) { change in
                            FileChangeRow(
                                fileName: URL(fileURLWithPath: change.filePath).lastPathComponent,
                                filePath: change.filePath,
                                changeType: .modified,
                                sizeChange: change.newSize - change.oldSize
                            )
                        }
                    default:
                        EmptyView()
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }
}

struct FileChangeRow: View {
    let fileName: String
    let filePath: String
    let changeType: ChangeType
    let sizeChange: Int64?
    
    var body: some View {
        HStack {
            Image(systemName: changeTypeIcon)
                .foregroundColor(changeTypeColor)
                .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(fileName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(filePath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            if let sizeChange = sizeChange {
                Text(formatBytes(sizeChange))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(sizeChange >= 0 ? .red : .green)
            }
        }
        .padding(.vertical, 2)
    }
    
    private var changeTypeIcon: String {
        switch changeType {
        case .added:
            return "plus.circle.fill"
        case .removed:
            return "minus.circle.fill"
        case .modified:
            return "pencil.circle.fill"
        case .unchanged:
            return "circle"
        }
    }
    
    private var changeTypeColor: Color {
        switch changeType {
        case .added:
            return .green
        case .removed:
            return .red
        case .modified:
            return .orange
        case .unchanged:
            return .gray
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct ComparisonProgressOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
                    .scaleEffect(2)
                
                Text("Comparing Projects...")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .padding(40)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(16)
            .shadow(radius: 10)
        }
    }
}

#Preview {
    ComparisonView(projects: [])
}