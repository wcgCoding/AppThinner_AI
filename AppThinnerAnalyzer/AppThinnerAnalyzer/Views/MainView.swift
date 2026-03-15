import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct MainView: View {
    @StateObject private var mainViewModel = DependencyContainer.shared.makeMainViewModel()
    @State private var selectedTab = 0
    @State private var isDragTargeted = false
    @State private var showingFileImporter = false
    @State private var showingAbout = false
    
    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: mainViewModel)
                .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
        } detail: {
            MainContentView(
                mainViewModel: mainViewModel,
                selectedTab: $selectedTab,
                isDragTargeted: $isDragTargeted,
                showingFileImporter: $showingFileImporter,
                showingAbout: $showingAbout
            )
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            handleDroppedFiles(providers)
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.folder, .data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                mainViewModel.handleDroppedFiles(urls)
            case .failure(let error):
                mainViewModel.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .alert("Error", isPresented: Binding<Bool>(
            get: { mainViewModel.errorMessage != nil },
            set: { _ in mainViewModel.errorMessage = nil }
        )) {
            Button("OK") {
                mainViewModel.errorMessage = nil
            }
        } message: {
            if let errorMessage = mainViewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .handleErrors() // Use centralized error handling
    }
    
    private func handleDroppedFiles(_ providers: [NSItemProvider]) -> Bool {
        let urls = providers.compactMap { provider in
            var url: URL?
            let semaphore = DispatchSemaphore(value: 0)
            
            _ = provider.loadObject(ofClass: URL.self) { loadedURL, _ in
                url = loadedURL
                semaphore.signal()
            }
            
            semaphore.wait()
            return url
        }
        
        mainViewModel.handleDroppedFiles(urls)
        return !urls.isEmpty
    }
}

struct MainContentView: View {
    @ObservedObject var mainViewModel: MainViewModel
    @Binding var selectedTab: Int
    @Binding var isDragTargeted: Bool
    @Binding var showingFileImporter: Bool
    @Binding var showingAbout: Bool
    
    var body: some View {
        TabView(selection: $selectedTab) {
            AnalysisView(viewModel: mainViewModel)
                .tabItem {
                    Label("Analysis", systemImage: "chart.pie")
                }
                .tag(0)
            
            TreemapView(project: mainViewModel.currentProject)
                .tabItem {
                    Label("Visualization", systemImage: "square.grid.3x3")
                }
                .tag(1)
            
            OptimizationView(project: mainViewModel.currentProject)
                .tabItem {
                    Label("Optimization", systemImage: "wand.and.stars")
                }
                .tag(2)
        }
        .overlay(alignment: .center) {
            if isDragTargeted {
                DragTargetOverlay()
            }
        }
        // Keyboard shortcuts for Requirements 7.5
        .keyboardShortcut(KeyEquivalent("o"), modifiers: [.command]) {
            showingFileImporter = true
        }
        .keyboardShortcut(KeyEquivalent("s"), modifiers: [.command]) {
            if let project = mainViewModel.currentProject {
                Task {
                    do {
                        try await mainViewModel.exportProject(project)
                    } catch {
                        mainViewModel.errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .keyboardShortcut(.return, modifiers: [.command]) {
            if selectedTab == 0 && mainViewModel.hasValidInput && !mainViewModel.isAnalyzing {
                Task {
                    await mainViewModel.startAnalysis()
                }
            }
        }
        .keyboardShortcut(KeyEquivalent("1"), modifiers: [.command]) {
            selectedTab = 0
        }
        .keyboardShortcut(KeyEquivalent("2"), modifiers: [.command]) {
            selectedTab = 1
        }
        .keyboardShortcut(KeyEquivalent("3"), modifiers: [.command]) {
            selectedTab = 2
        }
        .keyboardShortcut(KeyEquivalent("r"), modifiers: [.command]) {
            Task {
                await mainViewModel.loadAnalysisHistory()
            }
        }
        .keyboardShortcut(KeyEquivalent("/"), modifiers: [.command]) {
            // Show keyboard shortcuts help
            showingAbout = true
        }
        .accessibilityKeyboardShortcut("⌘O", description: "Open files")
        .accessibilityKeyboardShortcut("⌘S", description: "Export results")
        .accessibilityKeyboardShortcut("⌘↩", description: "Start analysis")
        .accessibilityKeyboardShortcut("⌘1-4", description: "Switch between tabs")
        .accessibilityKeyboardShortcut("⌘R", description: "Refresh analysis history")
        .accessibilityKeyboardShortcut("⌘/", description: "Show keyboard shortcuts")
    }
}

// MARK: - Supporting Views

struct DragTargetOverlay: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentColor.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10]))
                )
            
            VStack(spacing: 16) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
                
                Text("Drop files here to analyze")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
                
                Text("Supported: .ipa files, linkmap.txt, project directories")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(40)
        .animation(.easeInOut(duration: 0.2), value: true)
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingKeyboardShortcuts = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            
            Text("iOS App Analyzer")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Version 1.0.0")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Professional iOS app size analysis tool for macOS")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            VStack(spacing: 12) {
                Button("View Keyboard Shortcuts") {
                    showingKeyboardShortcuts = true
                }
                .buttonStyle(.bordered)
                
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
        .frame(width: 400)
        .sheet(isPresented: $showingKeyboardShortcuts) {
            KeyboardShortcutHelpView()
        }
    }
}

struct SidebarView: View {
    @ObservedObject var viewModel: MainViewModel
    /// 与 currentProject 同步，用于 List 的 selection 绑定；选中即加载
    @State private var selectedProjectId: UUID?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Current Project Section
            if let currentProject = viewModel.currentProject {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Project")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    ProjectSummaryCard(project: currentProject)
                }
            }
            
            // Analysis History Section（支持选中加载：选中项即设为 currentProject）
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Analysis History")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button(action: {
                        Task {
                            await viewModel.loadAnalysisHistory()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                }
                
                if viewModel.analysisHistory.isEmpty {
                    Text("No previous analyses")
                        .foregroundColor(Color.secondary.opacity(0.6))
                        .italic()
                } else {
                    List(selection: $selectedProjectId) {
                        ForEach(viewModel.analysisHistory) { project in
                            ProjectHistoryRow(
                                project: project,
                                isSelected: viewModel.currentProject?.id == project.id,
                                onSelect: {
                                    viewModel.currentProject = project
                                },
                                onDelete: {
                                    Task {
                                        await viewModel.deleteProject(project)
                                    }
                                }
                            )
                            .tag(project.id)
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("iOS App Analyzer")
        .onChange(of: selectedProjectId) { _, newId in
            guard let id = newId,
                  let project = viewModel.analysisHistory.first(where: { $0.id == id }) else { return }
            viewModel.currentProject = project
        }
        .onChange(of: viewModel.currentProject?.id) { _, newId in
            selectedProjectId = newId
        }
        .onChange(of: viewModel.analysisHistory.count) { _, _ in
            if let sid = selectedProjectId,
               !viewModel.analysisHistory.contains(where: { $0.id == sid }) {
                selectedProjectId = viewModel.currentProject?.id
            }
        }
        .task {
            await viewModel.loadAnalysisHistory()
        }
        .onAppear {
            selectedProjectId = viewModel.currentProject?.id
        }
    }
}

struct ProjectSummaryCard: View {
    let project: AnalysisProject
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(project.name)
                .font(.title3)
                .fontWeight(.semibold)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Size")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatBytes(project.totalSize))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Spacer()
            }
            
            Text("Updated: \(DateFormatter.shortDateTime.string(from: project.updatedAt))")
                .font(.caption)
                .foregroundColor(Color.secondary.opacity(0.6))
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct ProjectHistoryRow: View {
    let project: AnalysisProject
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                
                Text(formatBytes(project.totalSize))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(DateFormatter.shortDateTime.string(from: project.createdAt))
                    .font(.caption2)
                    .foregroundColor(Color.secondary.opacity(0.6))
            }
            
            Spacer()
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(6)
        .onTapGesture {
            onSelect()
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

#Preview {
    MainView()
}