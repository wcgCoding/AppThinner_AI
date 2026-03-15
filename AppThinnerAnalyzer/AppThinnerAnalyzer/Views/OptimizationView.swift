import SwiftUI

struct OptimizationView: View {
    let project: AnalysisProject?
    @StateObject private var viewModel = DependencyContainer.shared.makeOptimizationViewModel()
    @State private var showingBackupDialog = false
    @State private var showingBackupLocationPicker = false
    @State private var showingOptimizationSettings = false
    @State private var selectedBackupLocation: URL?
    @State private var didAutoSelectAll = false
    @State private var unusedItemsTab: UnusedItemsTab = .resources
    
    var body: some View {
        VStack(spacing: 0) {
            if let project = project {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Optimization Summary Card - Enhanced for Requirement 4.5
                        OptimizationSummaryCard(
                            estimate: viewModel.estimateOptimizationSavings(),
                            selectionSummary: viewModel.selectionSummary
                        )
                        
                        // Optimization Settings Section
                        OptimizationSettingsSection(
                            compressionLevel: $viewModel.compressionLevel,
                            enableImageCompression: $viewModel.enableImageCompression,
                            enableSafeDelete: $viewModel.enableSafeDelete,
                            showingSettings: $showingOptimizationSettings
                        )
                        
                        // Unused Items Tab (Resources / Code)
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Unused Items", selection: $unusedItemsTab) {
                                Text("Resources").tag(UnusedItemsTab.resources)
                                Text("Code").tag(UnusedItemsTab.code)
                            }
                            .pickerStyle(.segmented)
                            
                            switch unusedItemsTab {
                            case .resources:
                                UnusedResourcesSection(
                                    resources: project.unusedResources,
                                    selectedResources: $viewModel.selectedUnusedResources,
                                    onSelectAll: {
                                        viewModel.selectAllUnusedResources(from: project)
                                    },
                                    onToggleSelection: { resource in
                                        viewModel.toggleResourceSelection(resource, from: project)
                                    },
                                    onShowInFinder: { resource in
                                        showInFinder(for: resource, in: project)
                                    }
                                )
                            case .code:
                                UnusedCodeSection(
                                    code: project.unusedCode,
                                    selectedCode: $viewModel.selectedUnusedCode,
                                    onSelectAll: {
                                        viewModel.selectAllUnusedCode(from: project)
                                    },
                                    onToggleSelection: { code in
                                        viewModel.toggleCodeSelection(code, from: project)
                                    },
                                    onShowInFinder: { codeItem in
                                        showInFinder(for: codeItem, in: project)
                                    }
                                )
                            }
                        }
                        
                        // Optimization Results
                        if let results = viewModel.optimizationResults {
                            OptimizationResultsView(results: results)
                        }
                    }
                    .padding()
                }
                .task {
                    if !didAutoSelectAll {
                        didAutoSelectAll = true
                        viewModel.selectAllUnusedResources(from: project)
                        viewModel.selectAllUnusedCode(from: project)
                    }
                }
                
                // Action Bar - Enhanced for Requirement 4.5
                OptimizationActionBar(
                    viewModel: viewModel,
                    project: project,
                    showingBackupDialog: $showingBackupDialog,
                    showingBackupLocationPicker: $showingBackupLocationPicker,
                    showingOptimizationSettings: $showingOptimizationSettings,
                    selectedBackupLocation: $selectedBackupLocation
                )
                
            } else {
                ContentUnavailableView(
                    "No Analysis Available",
                    systemImage: "wand.and.stars",
                    description: Text("Run an analysis first to see optimization options")
                )
            }
        }
        .navigationTitle("Optimization")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let project = project {
                    Menu("Options") {
                        Button("Optimization Settings") {
                            showingOptimizationSettings = true
                        }
                        
                        Button("Choose Backup Location") {
                            showingBackupLocationPicker = true
                        }
                        
                        Divider()
                        
                        Button("Reset Selection") {
                            viewModel.clearSelection()
                        }
                        .disabled(viewModel.selectedUnusedResources.isEmpty && viewModel.selectedUnusedCode.isEmpty)
                        
                        if let results = viewModel.optimizationResults {
                            Button("Show Backup") {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: results.backupLocation.path)
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                }
            }
        }
        .alert("Create Backup", isPresented: $showingBackupDialog) {
            Button("Create at Default Location") {
                Task {
                    do {
                        try await viewModel.createBackup()
                    } catch {
                        viewModel.errorMessage = error.localizedDescription
                    }
                }
            }
            
            Button("Choose Location") {
                showingBackupLocationPicker = true
            }
            
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("A backup will be created before performing any optimization operations. Choose where to save the backup.")
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
        .fileImporter(
            isPresented: $showingBackupLocationPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                selectedBackupLocation = urls.first
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showingOptimizationSettings) {
            OptimizationSettingsView(viewModel: viewModel)
        }
        .overlay {
            if viewModel.isOptimizing {
                OptimizationProgressOverlay(
                    progress: viewModel.optimizationProgress,
                    currentOperation: viewModel.currentOperation
                )
            }
        }
        .keyboardShortcuts(for: .optimization)
        // Optimization-specific keyboard shortcuts
        .keyboardShortcut(KeyboardShortcuts.selectAll, modifiers: [.command]) {
            if let project = project {
                viewModel.selectAllUnusedResources(from: project)
                viewModel.selectAllUnusedCode(from: project)
            }
        }
        .keyboardShortcut(KeyboardShortcuts.deselectAll, modifiers: [.command, .shift]) {
            viewModel.clearSelection()
        }
        .keyboardShortcut(KeyboardShortcuts.createBackup, modifiers: [.command]) {
            showingBackupDialog = true
        }
        .keyboardShortcut(KeyboardShortcuts.optimizeSelected, modifiers: [.command, .shift]) {
            if viewModel.canPerformOptimization() && !viewModel.isOptimizing {
                Task {
                    do {
                        try await viewModel.performOptimization()
                    } catch {
                        // Error handling is done in the view model
                    }
                }
            }
        }
        .keyboardShortcut(KeyboardShortcuts.clearSelection, modifiers: []) {
            viewModel.clearSelection()
        }
        .accessibilityKeyboardShortcut("⌘A", description: "Select all unused items")
        .accessibilityKeyboardShortcut("⌘⇧D", description: "Deselect all items")
        .accessibilityKeyboardShortcut("⌘B", description: "Create backup")
        .accessibilityKeyboardShortcut("⌘⇧O", description: "Optimize selected items")
        .accessibilityKeyboardShortcut("⌫", description: "Clear selection")
    }

    /// 在 Finder 中选中对应文件（基于项目根路径和 AnalysisResult.relativePath）。
    private func showInFinder(for result: AnalysisResult, in project: AnalysisProject) {
        guard let root = project.projectPath, !root.isEmpty else { return }
        let fullPath = (root as NSString).appendingPathComponent(result.relativePath)
        let url = URL(fileURLWithPath: fullPath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

struct OptimizationSummaryCard: View {
    let estimate: OptimizationEstimate
    let selectionSummary: OptimizationSelectionSummary?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Optimization Summary")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                SummaryMetric(
                    title: "Estimated Savings",
                    value: formatBytes(estimate.estimatedSavings),
                    systemImage: "arrow.down.circle.fill",
                    color: .green
                )
                
                SummaryMetric(
                    title: "Affected Files",
                    value: "\(estimate.affectedFiles)",
                    systemImage: "doc.on.doc",
                    color: .blue
                )
                
                SummaryMetric(
                    title: "Risk Level",
                    value: estimate.riskLevel.description,
                    systemImage: riskLevelIcon(estimate.riskLevel),
                    color: riskLevelColor(estimate.riskLevel)
                )
            }
            
            // Selection Summary
            if let summary = selectionSummary {
                SelectionSummaryView(summary: summary)
            }
            
            if !estimate.recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recommendations")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    ForEach(estimate.recommendations, id: \.self) { recommendation in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.yellow)
                                .font(.caption)
                            
                            Text(recommendation)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func riskLevelIcon(_ riskLevel: RiskLevel) -> String {
        switch riskLevel {
        case .low:
            return "checkmark.shield.fill"
        case .medium:
            return "exclamationmark.shield.fill"
        case .high:
            return "xmark.shield.fill"
        }
    }
    
    private func riskLevelColor(_ riskLevel: RiskLevel) -> Color {
        switch riskLevel {
        case .low:
            return .green
        case .medium:
            return .orange
        case .high:
            return .red
        }
    }
}

struct SelectionSummaryView: View {
    let summary: OptimizationSelectionSummary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selection Summary")
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Resources: \(summary.selectedUnusedResources)/\(summary.totalUnusedResources)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Code: \(summary.selectedUnusedCode)/\(summary.totalUnusedCode)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Resource Size: \(formatBytes(summary.selectedResourceSize))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Code Size: \(formatBytes(summary.selectedCodeSize))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color.accentColor.opacity(0.05))
        .cornerRadius(8)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct OptimizationSettingsSection: View {
    @Binding var compressionLevel: CompressionLevel
    @Binding var enableImageCompression: Bool
    @Binding var enableSafeDelete: Bool
    @Binding var showingSettings: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("执行优化")
                    .font(.headline)
                
                Spacer()
                
                Button("配置") {
                    showingSettings = true
                }
                .buttonStyle(.bordered)
            }
            
            HStack(spacing: 16) {
                SettingToggle(
                    title: "删除所选",
                    isEnabled: $enableSafeDelete,
                    icon: "trash.circle"
                )
                
                SettingToggle(
                    title: "压缩资源",
                    isEnabled: $enableImageCompression,
                    icon: "photo.artframe"
                )
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct SettingToggle: View {
    let title: String
    @Binding var isEnabled: Bool
    let icon: String
    
    var body: some View {
        Button(action: {
            isEnabled.toggle()
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(isEnabled ? .white : .accentColor)
                    .font(.title3)
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isEnabled ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(isEnabled ? .accentColor : .secondary)
    }
}

struct OptimizationActionBar: View {
    @ObservedObject var viewModel: OptimizationViewModel
    let project: AnalysisProject
    @Binding var showingBackupDialog: Bool
    @Binding var showingBackupLocationPicker: Bool
    @Binding var showingOptimizationSettings: Bool
    @Binding var selectedBackupLocation: URL?
    
    var body: some View {
        VStack(spacing: 12) {
            // Progress indicator when optimizing
            if viewModel.isOptimizing {
                HStack {
                    ProgressView(value: viewModel.optimizationProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                    
                    Text("\(Int(viewModel.optimizationProgress * 100))%")
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 40)
                }
                .padding(.horizontal)
            }
            
            // 底部不再提供操作按钮，仅在执行优化时展示进度
        }
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .top
        )
    }
}

struct OptimizationSettingsView: View {
    @ObservedObject var viewModel: OptimizationViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Optimization Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            
            Form {
                Section("Image Compression") {
                    Toggle("Enable Image Compression", isOn: $viewModel.enableImageCompression)
                    
                    if viewModel.enableImageCompression {
                        Picker("Compression Level", selection: $viewModel.compressionLevel) {
                            Text("Conservative (15% savings)").tag(CompressionLevel.conservative)
                            Text("Balanced (30% savings)").tag(CompressionLevel.balanced)
                            Text("Aggressive (50% savings)").tag(CompressionLevel.aggressive)
                        }
                        .pickerStyle(.radioGroup)
                    }
                }
                
                Section("File Operations") {
                    Toggle("Enable Safe Delete", isOn: $viewModel.enableSafeDelete)
                    
                    Text("Safe delete will move files to trash instead of permanently deleting them.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Advanced") {
                    Button("Reset to Defaults") {
                        viewModel.compressionLevel = .balanced
                        viewModel.enableImageCompression = true
                        viewModel.enableSafeDelete = true
                    }
                    .foregroundColor(.red)
                }
            }
            .formStyle(.grouped)
        }
        .padding()
        .frame(width: 500, height: 400)
    }
}

extension RiskLevel {
    var description: String {
        switch self {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        }
    }
}

struct SummaryMetric: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundColor(color)
                .font(.title2)
            
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct UnusedResourcesSection: View {
    let resources: [AnalysisResult]
    @Binding var selectedResources: Set<AnalysisResult>
    let onSelectAll: () -> Void
    let onToggleSelection: (AnalysisResult) -> Void
    let onShowInFinder: (AnalysisResult) -> Void
    
    @State private var sortOption: UnusedResourceSortOption = .sizeDescending
    
    private var sortedResources: [AnalysisResult] {
        switch sortOption {
        case .sizeDescending:
            return resources.sorted { $0.resourceSize > $1.resourceSize }
        case .sizeAscending:
            return resources.sorted { $0.resourceSize < $1.resourceSize }
        case .nameAscending:
            return resources.sorted { $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending }
        case .pathAscending:
            return resources.sorted { $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Unused Resources (\(resources.count))")
                    .font(.headline)
                
                Spacer()
                
                Picker("Sort", selection: $sortOption) {
                    Text("Size ↓").tag(UnusedResourceSortOption.sizeDescending)
                    Text("Size ↑").tag(UnusedResourceSortOption.sizeAscending)
                    Text("Name").tag(UnusedResourceSortOption.nameAscending)
                    Text("Path").tag(UnusedResourceSortOption.pathAscending)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
            
            if resources.isEmpty {
                Text("No unused resources detected")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(sortedResources, id: \.id) { resource in
                        UnusedResourceRow(
                            resource: resource,
                            isSelected: selectedResources.contains(resource),
                            onToggle: {
                                onToggleSelection(resource)
                            },
                            onShowInFinder: {
                                onShowInFinder(resource)
                            }
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

private enum UnusedItemsTab: Hashable {
    case resources
    case code
}

private enum UnusedResourceSortOption: Hashable {
    case sizeDescending
    case sizeAscending
    case nameAscending
    case pathAscending
}

private enum UnusedCodeSortOption: Hashable {
    case sizeDescending
    case sizeAscending
    case nameAscending
    case pathAscending
}

struct UnusedResourceRow: View {
    let resource: AnalysisResult
    let isSelected: Bool
    let onToggle: () -> Void
    let onShowInFinder: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(resource.fileName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(resource.relativePath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatBytes(resource.resourceSize))
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if resource.isExternallyMarked {
                    Text("External")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(4)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
        .contextMenu {
            Button("Show in Finder") {
                onShowInFinder()
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

struct UnusedCodeSection: View {
    let code: [AnalysisResult]
    @Binding var selectedCode: Set<AnalysisResult>
    let onSelectAll: () -> Void
    let onToggleSelection: (AnalysisResult) -> Void
    let onShowInFinder: (AnalysisResult) -> Void
    
    @State private var sortOption: UnusedCodeSortOption = .sizeDescending
    
    private var sortedCode: [AnalysisResult] {
        switch sortOption {
        case .sizeDescending:
            return code.sorted { $0.codeSize > $1.codeSize }
        case .sizeAscending:
            return code.sorted { $0.codeSize < $1.codeSize }
        case .nameAscending:
            return code.sorted { $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending }
        case .pathAscending:
            return code.sorted { $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Unused Code (\(code.count))")
                    .font(.headline)
                
                Spacer()
                Picker("Sort", selection: $sortOption) {
                    Text("Size ↓").tag(UnusedCodeSortOption.sizeDescending)
                    Text("Size ↑").tag(UnusedCodeSortOption.sizeAscending)
                    Text("Name").tag(UnusedCodeSortOption.nameAscending)
                    Text("Path").tag(UnusedCodeSortOption.pathAscending)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
            
            if code.isEmpty {
                Text("No unused code detected")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(sortedCode, id: \.id) { codeItem in
                        UnusedCodeRow(
                            code: codeItem,
                            isSelected: selectedCode.contains(codeItem),
                            onToggle: {
                                onToggleSelection(codeItem)
                            },
                            onShowInFinder: {
                                onShowInFinder(codeItem)
                            }
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct UnusedCodeRow: View {
    let code: AnalysisResult
    let isSelected: Bool
    let onToggle: () -> Void
    let onShowInFinder: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(code.fileName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(code.relativePath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatBytes(code.codeSize))
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack(spacing: 4) {
                    if code.isExternallyMarked {
                        Text("External")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(4)
                    }
                    
                    // Risk indicator (simplified for now)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
        .contextMenu {
            Button("Show in Finder") {
                onShowInFinder()
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

struct OptimizationResultsView: View {
    let results: OptimizationResults
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Optimization Results")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                SummaryMetric(
                    title: "Original Size",
                    value: formatBytes(results.originalSize),
                    systemImage: "doc",
                    color: .gray
                )
                
                SummaryMetric(
                    title: "Optimized Size",
                    value: formatBytes(results.optimizedSize),
                    systemImage: "doc.badge.arrow.up",
                    color: .blue
                )
                
                SummaryMetric(
                    title: "Space Saved",
                    value: formatBytes(results.savedSize),
                    systemImage: "arrow.down.circle.fill",
                    color: .green
                )
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Files Processed: \(results.processedFiles)")
                        .font(.subheadline)
                    
                    if !results.failedFiles.isEmpty {
                        Text("Failed Files: \(results.failedFiles.count)")
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }
                }
                
                Spacer()
                
                Button("Show Backup Location") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: results.backupLocation.path)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct OptimizationProgressOverlay: View {
    let progress: Double
    let currentOperation: String
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView(value: progress)
                    .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
                    .scaleEffect(2)
                
                Text("Optimizing...")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(currentOperation)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Text("\(Int(progress * 100))%")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .monospacedDigit()
            }
            .padding(40)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(16)
            .shadow(radius: 10)
        }
    }
}

#Preview {
    OptimizationView(project: nil)
}