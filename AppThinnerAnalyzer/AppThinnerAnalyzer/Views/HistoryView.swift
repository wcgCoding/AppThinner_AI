import SwiftUI
import Charts

struct HistoryView: View {
    @StateObject private var viewModel = DependencyContainer.shared.makeHistoryViewModel()
    @State private var selectedTab = 0
    @State private var showingCleanupDialog = false
    @State private var showingExportDialog = false
    
    var body: some View {
        NavigationView {
            VStack {
                // Tab selection
                Picker("History View", selection: $selectedTab) {
                    Text("Timeline").tag(0)
                    Text("Projects").tag(1)
                    Text("Storage").tag(2)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                // Content based on selected tab
                TabView(selection: $selectedTab) {
                    TimelineView(viewModel: viewModel)
                        .tag(0)
                    
                    ProjectHistoryView(viewModel: viewModel)
                        .tag(1)
                    
                    StorageManagementView(viewModel: viewModel)
                        .tag(2)
                }
            }
            .navigationTitle("Analysis History")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Export") {
                        showingExportDialog = true
                    }
                    
                    Button("Cleanup") {
                        showingCleanupDialog = true
                    }
                }
            }
            .sheet(isPresented: $showingCleanupDialog) {
                CleanupDialogView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingExportDialog) {
                ExportDialogView(viewModel: viewModel)
            }
            .task {
                await viewModel.loadHistoricalData()
            }
        }
    }
}

// MARK: - Timeline View

struct TimelineView: View {
    @ObservedObject var viewModel: HistoryViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Size progression chart
                if !viewModel.analysisTimeline.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Size Progression Over Time")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        Chart(viewModel.analysisTimeline, id: \.date) { dataPoint in
                            LineMark(
                                x: .value("Date", dataPoint.date),
                                y: .value("Size", dataPoint.totalSize)
                            )
                            .foregroundStyle(.blue)
                            
                            AreaMark(
                                x: .value("Date", dataPoint.date),
                                y: .value("Size", dataPoint.totalSize)
                            )
                            .foregroundStyle(.blue.opacity(0.3))
                        }
                        .frame(height: 200)
                        .padding(.horizontal)
                    }
                }
                
                // Recent analyses
                VStack(alignment: .leading) {
                    Text("Recent Analyses")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    LazyVStack {
                        ForEach(viewModel.recentAnalyses, id: \.project.id) { analysis in
                            HistoricalAnalysisRow(analysis: analysis)
                        }
                    }
                }
            }
        }
        .refreshable {
            await viewModel.loadHistoricalData()
        }
    }
}

// MARK: - Project History View

struct ProjectHistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel
    @State private var selectedProject: String?
    
    var body: some View {
        NavigationSplitView {
            List(viewModel.projectHistories, id: \.projectName, selection: $selectedProject) { history in
                ProjectHistoryListRow(history: history)
                    .tag(history.projectName)
            }
            .navigationTitle("Projects")
        } detail: {
            if let selectedProject = selectedProject,
               let history = viewModel.projectHistories.first(where: { $0.projectName == selectedProject }) {
                ProjectDetailView(history: history)
            } else {
                ContentUnavailableView(
                    "Select a Project",
                    systemImage: "folder",
                    description: Text("Choose a project to view its analysis history")
                )
            }
        }
    }
}

// MARK: - Storage Management View

struct StorageManagementView: View {
    @ObservedObject var viewModel: HistoryViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Storage statistics
                if let storageUsage = viewModel.storageUsage {
                    StorageUsageCard(storageUsage: storageUsage)
                }
                
                // Storage recommendations
                if !viewModel.storageRecommendations.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Recommendations")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        LazyVStack {
                            ForEach(viewModel.storageRecommendations, id: \.description) { recommendation in
                                StorageRecommendationRow(recommendation: recommendation)
                            }
                        }
                    }
                }
                
                // Cleanup candidates
                if !viewModel.cleanupCandidates.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Cleanup Candidates")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        LazyVStack {
                            ForEach(viewModel.cleanupCandidates, id: \.id) { project in
                                CleanupCandidateRow(
                                    project: project,
                                    isSelected: viewModel.selectedCleanupProjects.contains(project.id)
                                ) {
                                    viewModel.toggleCleanupSelection(project)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Supporting Views

struct HistoricalAnalysisRow: View {
    let analysis: HistoricalAnalysis
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(analysis.project.name)
                    .font(.headline)
                Text(analysis.analysisDate, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing) {
                Text(ByteCountFormatter.string(fromByteCount: analysis.summary.totalSize, countStyle: .file))
                    .font(.subheadline)
                if analysis.summary.potentialSavings > 0 {
                    Text("Savings: \(ByteCountFormatter.string(fromByteCount: analysis.summary.potentialSavings, countStyle: .file))")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

struct ProjectHistoryListRow: View {
    let history: ProjectHistory
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(history.projectName)
                .font(.headline)
            Text("\(history.analyses.count) analyses")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Trend indicator
            HStack {
                Image(systemName: trendIcon(for: history.trends.overallTrend))
                    .foregroundColor(trendColor(for: history.trends.overallTrend))
                Text(trendText(for: history.trends.overallTrend))
                    .font(.caption)
            }
        }
    }
    
    private func trendIcon(for trend: TrendDirection) -> String {
        switch trend {
        case .increasing: return "arrow.up.right"
        case .decreasing: return "arrow.down.right"
        case .stable: return "arrow.right"
        }
    }
    
    private func trendColor(for trend: TrendDirection) -> Color {
        switch trend {
        case .increasing: return .red
        case .decreasing: return .green
        case .stable: return .blue
        }
    }
    
    private func trendText(for trend: TrendDirection) -> String {
        switch trend {
        case .increasing: return "Growing"
        case .decreasing: return "Shrinking"
        case .stable: return "Stable"
        }
    }
}

struct ProjectDetailView: View {
    let history: ProjectHistory
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Project info
                VStack(alignment: .leading) {
                    Text(history.projectName)
                        .font(.largeTitle)
                        .bold()
                    
                    Text("\(history.analyses.count) analyses")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                
                // Size progression chart
                if !history.sizeProgression.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Size Progression")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        Chart(history.sizeProgression, id: \.date) { dataPoint in
                            LineMark(
                                x: .value("Date", dataPoint.date),
                                y: .value("Total Size", dataPoint.totalSize)
                            )
                            .foregroundStyle(.blue)
                            
                            LineMark(
                                x: .value("Date", dataPoint.date),
                                y: .value("Code Size", dataPoint.codeSize)
                            )
                            .foregroundStyle(.green)
                            
                            LineMark(
                                x: .value("Date", dataPoint.date),
                                y: .value("Resource Size", dataPoint.resourceSize)
                            )
                            .foregroundStyle(.orange)
                        }
                        .frame(height: 200)
                        .padding(.horizontal)
                    }
                }
                
                // Trend analysis
                TrendAnalysisView(trends: history.trends)
                
                // Analysis list
                VStack(alignment: .leading) {
                    Text("All Analyses")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    LazyVStack {
                        ForEach(history.analyses, id: \.project.id) { analysis in
                            HistoricalAnalysisRow(analysis: analysis)
                        }
                    }
                }
            }
        }
        .navigationTitle(history.projectName)
        // navigationBarTitleDisplayMode is iOS-only; not used on macOS
    }
}

struct TrendAnalysisView: View {
    let trends: ProjectTrends
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Trend Analysis")
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                TrendRow(title: "Overall", trend: trends.overallTrend)
                TrendRow(title: "Code", trend: trends.codeTrend)
                TrendRow(title: "Resources", trend: trends.resourceTrend)
                TrendRow(title: "Frameworks", trend: trends.frameworkTrend)
                
                if let projectedSize = trends.projectedSize {
                    HStack {
                        Text("Projected Size (30 days):")
                            .font(.subheadline)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: projectedSize, countStyle: .file))
                            .font(.subheadline)
                            .bold()
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)
        }
    }
}

struct TrendRow: View {
    let title: String
    let trend: TrendDirection
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            HStack {
                Image(systemName: trendIcon)
                    .foregroundColor(trendColor)
                Text(trendText)
                    .font(.subheadline)
            }
        }
    }
    
    private var trendIcon: String {
        switch trend {
        case .increasing: return "arrow.up.right"
        case .decreasing: return "arrow.down.right"
        case .stable: return "arrow.right"
        }
    }
    
    private var trendColor: Color {
        switch trend {
        case .increasing: return .red
        case .decreasing: return .green
        case .stable: return .blue
        }
    }
    
    private var trendText: String {
        switch trend {
        case .increasing: return "Growing"
        case .decreasing: return "Shrinking"
        case .stable: return "Stable"
        }
    }
}

struct StorageUsageCard: View {
    let storageUsage: StorageUsage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Storage Usage")
                .font(.headline)
            
            VStack(spacing: 8) {
                StatRow(title: "Total Projects", value: "\(storageUsage.totalProjects)")
                StatRow(title: "Total Results", value: "\(storageUsage.totalAnalysisResults)")
                StatRow(title: "Database Size", value: ByteCountFormatter.string(fromByteCount: storageUsage.estimatedDatabaseSize, countStyle: .file))
                StatRow(title: "Average Project Size", value: ByteCountFormatter.string(fromByteCount: storageUsage.averageProjectSize, countStyle: .file))
                
                if let oldest = storageUsage.oldestProjectDate {
                    StatRow(title: "Oldest Project", value: oldest.formatted(date: .abbreviated, time: .omitted))
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

struct StatRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .bold()
        }
    }
}

struct StorageRecommendationRow: View {
    let recommendation: StorageRecommendation
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: priorityIcon)
                    .foregroundColor(priorityColor)
                Text(recommendation.description)
                    .font(.subheadline)
                Spacer()
            }
            
            Text(recommendation.action)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("Estimated savings: \(ByteCountFormatter.string(fromByteCount: recommendation.estimatedSavings, countStyle: .file))")
                .font(.caption)
                .foregroundColor(.green)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .padding(.horizontal)
    }
    
    private var priorityIcon: String {
        switch recommendation.priority {
        case .low: return "info.circle"
        case .medium: return "exclamationmark.triangle"
        case .high: return "exclamationmark.octagon"
        }
    }
    
    private var priorityColor: Color {
        switch recommendation.priority {
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }
}

struct CleanupCandidateRow: View {
    let project: AnalysisProject
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray)
            }
            
            VStack(alignment: .leading) {
                Text(project.name)
                    .font(.subheadline)
                Text(project.createdAt, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(ByteCountFormatter.string(fromByteCount: project.totalSize, countStyle: .file))
                .font(.caption)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

// MARK: - Dialog Views

struct CleanupDialogView: View {
    @ObservedObject var viewModel: HistoryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var cleanupDays = 90
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Cleanup Old Data")
                    .font(.title2)
                    .bold()
                
                VStack(alignment: .leading) {
                    Text("Delete projects older than:")
                    Stepper("\(cleanupDays) days", value: $cleanupDays, in: 30...365, step: 30)
                }
                
                if !viewModel.selectedCleanupProjects.isEmpty {
                    Text("Selected \(viewModel.selectedCleanupProjects.count) projects for deletion")
                        .foregroundColor(.orange)
                }
                
                Spacer()
                
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("Cleanup") {
                        Task {
                            await viewModel.performCleanup()
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.selectedCleanupProjects.isEmpty)
                }
            }
            .padding()
            // navigationBarHidden is iOS-only; not used on macOS
        }
        .task {
            await viewModel.loadCleanupCandidates(olderThan: cleanupDays)
        }
        .onChange(of: cleanupDays) { _, newValue in
            Task {
                await viewModel.loadCleanupCandidates(olderThan: newValue)
            }
        }
    }
}

struct ExportDialogView: View {
    @ObservedObject var viewModel: HistoryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var exportAll = true
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
    @State private var endDate = Date()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Export Analysis Data")
                    .font(.title2)
                    .bold()
                
                VStack(alignment: .leading) {
                    Toggle("Export all projects", isOn: $exportAll)
                    
                    if !exportAll {
                        DatePicker("From", selection: $startDate, displayedComponents: .date)
                        DatePicker("To", selection: $endDate, displayedComponents: .date)
                    }
                }
                
                Spacer()
                
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("Export") {
                        Task {
                            await viewModel.exportData(all: exportAll, from: startDate, to: endDate)
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            // navigationBarHidden is iOS-only; not used on macOS
        }
    }
}

#Preview {
    HistoryView()
}