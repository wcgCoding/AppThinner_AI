import SwiftUI
import UniformTypeIdentifiers

struct AnalysisView: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var showingFilePicker = false
    @State private var showingExternalDataImporter = false
    @State private var filePickerType: FilePickerType = .project
    @State private var showingProgressDetails = false
    @State private var animateProgress = false
    @State private var showingAnalysisConfig = false
    
    enum FilePickerType {
        case project, ipa, linkmap
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // File Input Section
                FileInputSection(
                    viewModel: viewModel,
                    filePickerType: $filePickerType,
                    showingFilePicker: $showingFilePicker,
                    showingConfigSheet: $showingAnalysisConfig
                )
                
                // External Data Section
                ExternalDataSection(
                    showingImporter: $showingExternalDataImporter,
                    viewModel: viewModel
                )
                
                // Analysis Progress Section - Enhanced for Requirement 7.3
                if viewModel.isAnalyzing {
                    AnalysisProgressSection(
                        viewModel: viewModel,
                        showingDetails: $showingProgressDetails,
                        animateProgress: $animateProgress
                    )
                    .onAppear {
                        animateProgress = true
                    }
                }
                
                // Analysis Results Summary
                if let project = viewModel.currentProject {
                    AnalysisSummaryView(project: project)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
                
            }
            .padding()
        }
        .navigationTitle("iOS App Analysis")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if viewModel.isAnalyzing {
                    Button("Show Details") {
                        showingProgressDetails.toggle()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Start Analysis") {
                        Task {
                            await viewModel.startAnalysis()
                        }
                    }
                    .disabled(!viewModel.hasValidInput)
                    .buttonStyle(.borderedProminent)
                    .help("Start analyzing the selected files (⌘↩)")
                }
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
        .sheet(isPresented: $showingAnalysisConfig) {
            AnalysisOptionsSheetView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingExternalDataImporter) {
            ExternalDataImporterView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingProgressDetails) {
            AnalysisProgressDetailView(viewModel: viewModel)
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isAnalyzing)
        .animation(.easeInOut(duration: 0.3), value: viewModel.currentProject != nil)
        .keyboardShortcuts(for: .analysis)
        // Analysis-specific keyboard shortcuts
        .keyboardShortcut(KeyboardShortcuts.refresh, modifiers: [.command]) {
            Task {
                await viewModel.loadAnalysisHistory()
            }
        }
        .keyboardShortcut(KeyboardShortcuts.showHelp, modifiers: [.command]) {
            // TODO: Show help in future tasks
        }
        .accessibilityKeyboardShortcut("⌘R", description: "Refresh analysis history")
        .accessibilityKeyboardShortcut("⌘/", description: "Show help")
    }
    
    private var allowedContentTypes: [UTType] {
        switch filePickerType {
        case .project:
            return [.folder]
        case .ipa:
            return [UTType(filenameExtension: "ipa") ?? .data]
        case .linkmap:
            return [.plainText]
        }
    }
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            // 通过 ViewModel 设置路径，会保存 security-scoped bookmark 并写入缓存
            switch filePickerType {
            case .project:
                viewModel.setSelectedProjectPath(from: url)
            case .ipa:
                viewModel.setSelectedIpaPath(from: url)
            case .linkmap:
                viewModel.setSelectedLinkmapPath(from: url)
            }
            
        case .failure(let error):
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

struct FileInputSection: View {
    @ObservedObject var viewModel: MainViewModel
    @Binding var filePickerType: AnalysisView.FilePickerType
    @Binding var showingFilePicker: Bool
    @Binding var showingConfigSheet: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Input Files")
                    .font(.headline)
                Spacer()
                Button("配置") {
                    showingConfigSheet = true
                }
                .buttonStyle(.bordered)
            }
            
            // Project Directory
            FileInputRow(
                title: "Project Directory",
                subtitle: "Select the iOS project directory",
                path: viewModel.selectedProjectPath,
                systemImage: "folder",
                onSelect: {
                    filePickerType = .project
                    showingFilePicker = true
                },
                onClear: {
                    viewModel.clearSelectedProjectPath()
                }
            )
            
            // IPA File
            FileInputRow(
                title: "IPA File",
                subtitle: "Select the .ipa file to analyze",
                path: viewModel.selectedIpaPath,
                systemImage: "doc.zipper",
                onSelect: {
                    filePickerType = .ipa
                    showingFilePicker = true
                },
                onClear: {
                    viewModel.clearSelectedIpaPath()
                }
            )
            
            // Linkmap File
            FileInputRow(
                title: "Linkmap File",
                subtitle: "Select the linkmap.txt file",
                path: viewModel.selectedLinkmapPath,
                systemImage: "doc.text",
                onSelect: {
                    filePickerType = .linkmap
                    showingFilePicker = true
                },
                onClear: {
                    viewModel.clearSelectedLinkmapPath()
                }
            )
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct FileInputRow: View {
    let title: String
    let subtitle: String
    let path: String?
    let systemImage: String
    let onSelect: () -> Void
    let onClear: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundColor(.accentColor)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if let path = path {
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.primary)
                    Text(path)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                if path != nil {
                    Button("Clear") {
                        onClear()
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
                }
                
                Button("Select") {
                    onSelect()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 8)
    }
}

/// 分析配置弹窗（二级页面），由「输入文件」右上角「配置」按钮打开
struct AnalysisOptionsSheetView: View {
    @ObservedObject var viewModel: MainViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题区
            VStack(alignment: .leading, spacing: 4) {
                Text("分析配置")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("选择分析时启用的扩展扫描项，开启后将增加分析时间。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            // 配置项列表（居中、限制最大宽度，避免右侧大片空白）
            VStack(spacing: 0) {
                AnalysisConfigRow(
                    icon: "doc.on.doc",
                    iconColor: .mint,
                    title: "代码重复扫描",
                    subtitle: "基于源码归一化哈希检测重复代码",
                    isOn: Binding(
                        get: { viewModel.analysisOptions.enableCodeDuplicateScan },
                        set: { viewModel.setEnableCodeDuplicateScan($0) }
                    )
                )
                Divider()
                    .padding(.leading, 52)
                AnalysisConfigRow(
                    icon: "photo.on.rectangle.angled",
                    iconColor: .cyan,
                    title: "资源重复扫描",
                    subtitle: "基于文件内容哈希检测重复图片等资源",
                    isOn: Binding(
                        get: { viewModel.analysisOptions.enableResourceDuplicateScan },
                        set: { viewModel.setEnableResourceDuplicateScan($0) }
                    )
                )
                Divider()
                    .padding(.leading, 52)
                AnalysisConfigRow(
                    icon: "square.stack.3d.up",
                    iconColor: .indigo,
                    title: "Pods 库依赖扫描",
                    subtitle: "解析 Podfile.lock 展示依赖列表",
                    isOn: Binding(
                        get: { viewModel.analysisOptions.enablePodsDependencyScan },
                        set: { viewModel.setEnablePodsDependencyScan($0) }
                    )
                )
                Divider()
                    .padding(.leading, 52)
                AnalysisConfigRow(
                    icon: "curlybraces",
                    iconColor: .orange,
                    title: "无用代码扫描",
                    subtitle: "检测未被引用的类/方法（耗时长，默认关）",
                    isOn: Binding(
                        get: { viewModel.analysisOptions.enableUnusedCodeScan },
                        set: { viewModel.setEnableUnusedCodeScan($0) }
                    )
                )
                Divider()
                    .padding(.leading, 52)
                AnalysisConfigRow(
                    icon: "photo",
                    iconColor: .pink,
                    title: "无用资源扫描",
                    subtitle: "检测未被引用的图片等资源（耗时长，默认关）",
                    isOn: Binding(
                        get: { viewModel.analysisOptions.enableUnusedResourceScan },
                        set: { viewModel.setEnableUnusedResourceScan($0) }
                    )
                )
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
            )
            .padding(.horizontal, 20)
            
            Spacer(minLength: 24)
            
            // 底部按钮区
            HStack {
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .padding(.top, 12)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 420, minHeight: 320)
    }
}

private struct AnalysisConfigRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 28, height: 28, alignment: .center)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.vertical, 10)
    }
}

struct ExternalDataSection: View {
    @Binding var showingImporter: Bool
    @ObservedObject var viewModel: MainViewModel
    @State private var showingHelp = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("External Data")
                    .font(.headline)
                
                Button {
                    showingHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("查看外部 CSV 数据格式说明")
                .popover(isPresented: $showingHelp, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("外部数据 CSV 格式说明")
                            .font(.headline)
                        Text("当前版本支持从 TXT / CSV / JSON / Plist 导入「无用类」和「无用资源」名单，这里是 CSV 的推荐格式：")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Divider()
                        Group {
                            Text("• 无用资源列表（CSV）")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("  - 第一列：资源相对路径或完整路径，例如 `Resources/Images/legacy/live_entry_icon.png`")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("  - 可选表头：首行包含 `Path` 字样时会被自动跳过")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Divider()
                        Group {
                            Text("• 无用类列表（CSV）")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("  - 第一列：类名，例如 `LiveHomeViewController`")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("  - 可选表头：首行包含 `Class` 字样时会被自动跳过")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Divider()
                        Text("额外的列内容会被忽略，仅第一列参与导入；如需更复杂的结构，可考虑使用 JSON / Plist 格式。")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Spacer()
                            Button("关闭") { showingHelp = false }
                                .keyboardShortcut(.cancelAction)
                        }
                        .padding(.top, 4)
                    }
                    .padding(16)
                    .frame(minWidth: 380)
                }
                
                Spacer()
                
                Button("Import") {
                    showingImporter = true
                }
                .buttonStyle(.bordered)
            }
            
            if !viewModel.externalUnusedResources.isEmpty || !viewModel.externalUnusedClasses.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if !viewModel.externalUnusedResources.isEmpty {
                        Text("Unused Resources: \(viewModel.externalUnusedResources.count) items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if !viewModel.externalUnusedClasses.isEmpty {
                        Text("Unused Classes: \(viewModel.externalUnusedClasses.count) items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Clear External Data") {
                        viewModel.externalUnusedResources.removeAll()
                        viewModel.externalUnusedClasses.removeAll()
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
                    .font(.caption)
                }
            } else {
                Text("No external data imported")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct AnalysisProgressSection: View {
    @ObservedObject var viewModel: MainViewModel
    @Binding var showingDetails: Bool
    @Binding var animateProgress: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Analysis in Progress")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    showingDetails.toggle()
                }) {
                    Image(systemName: showingDetails ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderless)
            }
            
            // Main Progress Bar
            VStack(spacing: 8) {
                HStack {
                    Text(viewModel.currentOperation)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(Int(viewModel.analysisProgress * 100))%")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
                
                ProgressView(value: viewModel.analysisProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                    .scaleEffect(y: 2)
                    .animation(.easeInOut(duration: 0.3), value: viewModel.analysisProgress)
            }
            
            // Animated Activity Indicator
            HStack(spacing: 12) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animateProgress ? 1.2 : 0.8)
                        .animation(
                            .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                            value: animateProgress
                        )
                }
                
                Text("Processing files...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Estimated Time Remaining
            if viewModel.analysisProgress > 0.1 {
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                    
                    Text("Estimated time remaining: \(estimatedTimeRemaining)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color.accentColor.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(12)
    }
    
    private var estimatedTimeRemaining: String {
        let progress = max(viewModel.analysisProgress, 0.01)
        let remainingProgress = 1.0 - progress
        let estimatedSeconds = Int(remainingProgress / progress * 30) // Rough estimate
        
        if estimatedSeconds < 60 {
            return "\(estimatedSeconds)s"
        } else {
            let minutes = estimatedSeconds / 60
            let seconds = estimatedSeconds % 60
            return "\(minutes)m \(seconds)s"
        }
    }
}

/// 进度阶段定义（与 AnalysisService 上报的 stageId 一致）
private let progressStageOrder: [(id: String, title: String)] = [
    ("fileParsing", "File Parsing"),
    ("dataIntegration", "Data Integration"),
    ("unusedScan", "Unused code/resource scan"),
    ("codeDuplicate", "Code duplicate scan"),
    ("resourceDuplicate", "Resource duplicate scan"),
    ("podsDependency", "Pods dependency scan"),
    ("analysisGeneration", "Analysis generation"),
]

struct AnalysisProgressDetailView: View {
    @ObservedObject var viewModel: MainViewModel
    @Environment(\.dismiss) private var dismiss
    
    /// 根据分析配置只展示已开启的扫描阶段，其它核心阶段（解析/整合/生成）始终展示
    private var visibleStages: [(id: String, title: String)] {
        let options = viewModel.analysisOptions
        return progressStageOrder.filter { stage in
            switch stage.id {
            case "codeDuplicate":
                return options.enableCodeDuplicateScan
            case "resourceDuplicate":
                return options.enableResourceDuplicateScan
            case "podsDependency":
                return options.enablePodsDependencyScan
            case "unusedScan":
                return options.enableUnusedCodeScan || options.enableUnusedResourceScan
            default:
                return true
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Analysis Progress Details")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            
            ProgressDetailRow(
                title: "Overall Progress",
                progress: viewModel.analysisProgress,
                status: viewModel.currentOperation
            )
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(visibleStages.enumerated()), id: \.element.id) { index, stage in
                        stageStatusRow(stageId: stage.id, title: stage.title, index: index)
                    }
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding()
        .frame(minWidth: 420, maxWidth: 420, minHeight: 320)
    }
    
    private func stageStatusRow(stageId: String, title: String, index: Int) -> some View {
        let completed = viewModel.completedProgressStages.contains(stageId)
        let previousAllCompleted = visibleStages.prefix(index).allSatisfy { viewModel.completedProgressStages.contains($0.id) }
        let inProgress = !completed && previousAllCompleted && viewModel.isAnalyzing
        let status: String = completed ? "Completed" : (inProgress ? "In Progress" : "Waiting")
        let progress: Double = completed ? 1.0 : (inProgress ? 0.5 : 0)
        return ProgressDetailRow(title: title, progress: progress, status: status)
    }
}

struct ProgressDetailRow: View {
    let title: String
    let progress: Double
    let status: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text(status)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle())
        }
    }
}

struct AnalysisSummaryView: View {
    let project: AnalysisProject
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Analysis Results")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                SummaryCard(
                    title: "Total Size",
                    value: formatBytes(project.totalSize),
                    systemImage: "doc",
                    color: .blue
                )
                
                SummaryCard(
                    title: "Code Size",
                    value: formatBytes(project.summaryCodeSize != 0 ? project.summaryCodeSize : project.totalCodeSize),
                    systemImage: "curlybraces",
                    color: .green
                )
                
                SummaryCard(
                    title: "Resources",
                    value: formatBytes(project.summaryResourceSize != 0 ? project.summaryResourceSize : project.totalResourceSize),
                    systemImage: "photo",
                    color: .orange
                )
                
                SummaryCard(
                    title: "Unused Code",
                    value: formatBytes(project.unusedCodeSize),
                    systemImage: "bolt.slash",
                    color: .red
                )
                
                SummaryCard(
                    title: "Frameworks",
                    value: formatBytes(project.summaryFrameworkSize != 0 ? project.summaryFrameworkSize : project.totalFrameworkSize),
                    systemImage: "building.2",
                    color: .purple
                )
                
                SummaryCard(
                    title: "Unused Resources",
                    value: formatBytes(project.unusedResourceSize),
                    systemImage: "trash",
                    color: .pink
                )
                
                if !project.duplicateCodeGroups.isEmpty {
                    SummaryCard(
                        title: "代码重复",
                        value: "\(project.duplicateCodeGroups.count) 组",
                        systemImage: "doc.on.doc",
                        color: .mint
                    )
                }
                if !project.duplicateResourceGroups.isEmpty {
                    SummaryCard(
                        title: "资源重复",
                        value: "\(project.duplicateResourceGroups.count) 组",
                        systemImage: "photo.on.rectangle.angled",
                        color: .cyan
                    )
                }
                if let pods = project.podsDependencyResult, !pods.pods.isEmpty {
                    SummaryCard(
                        title: "Pods 依赖",
                        value: "\(pods.pods.count) 个",
                        systemImage: "square.stack.3d.up",
                        color: .indigo
                    )
                }
            }
            
            if !project.duplicateCodeGroups.isEmpty {
                Divider()
                Text("代码重复")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("共 \(project.duplicateCodeGroups.count) 组重复代码，涉及 \(project.duplicateCodeGroups.flatMap { $0.entries.map(\.relativePath) }.uniqued().count) 个文件。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if !project.duplicateResourceGroups.isEmpty {
                Divider()
                Text("资源重复")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("共 \(project.duplicateResourceGroups.count) 组重复资源，涉及 \(project.duplicateResourceGroups.flatMap { $0.entries.map(\.relativePath) }.uniqued().count) 个文件。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let pods = project.podsDependencyResult, !pods.pods.isEmpty {
                Divider()
                Text("Pods 依赖")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("共 \(pods.pods.count) 个 Pod（来自 \(pods.podfileLockPath ?? "Podfile.lock")）。")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

struct SummaryCard: View {
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

struct ExternalDataImporterView: View {
    @ObservedObject var viewModel: MainViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Import External Data")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Import lists of unused resources and classes from external tools")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            // TODO: Implement actual file import functionality
            VStack(spacing: 16) {
                Button("Import Unused Resources List") {
                    // TODO: Implement in future tasks
                }
                .buttonStyle(.bordered)
                
                Button("Import Unused Classes List") {
                    // TODO: Implement in future tasks
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400, height: 300)
    }
}

#Preview {
    AnalysisView(viewModel: MainViewModel())
}