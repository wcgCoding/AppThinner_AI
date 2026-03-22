import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct AnalysisView: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var showingFilePicker = false
    @State private var filePickerType: FilePickerType = .project
    @State private var showingProgressDetails = false
    @State private var animateProgress = false
    @State private var showingAnalysisConfig = false
    
    enum FilePickerType {
        case project, ipa, linkmap
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Hero Header
                HeroHeaderView()
                
                // File Input Section - Enhanced Card
                FileInputSection(
                    viewModel: viewModel,
                    filePickerType: $filePickerType,
                    showingFilePicker: $showingFilePicker,
                    showingConfigSheet: $showingAnalysisConfig
                )
                
                // External Data Section（直接在主页面展示导入控件）
                ExternalDataSection(viewModel: viewModel)
                
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

// MARK: - Hero Header

struct HeroHeaderView: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Animated Icon
            ZStack {
                // Outer glow rings
                ForEach(0..<3) { index in
                    Circle()
                        .stroke(Color.accentColor.opacity(0.3 - Double(index) * 0.1), lineWidth: 1)
                        .frame(width: 80 + CGFloat(index) * 20, height: 80 + CGFloat(index) * 20)
                        .scaleEffect(isAnimating ? 1.1 : 1.0)
                        .opacity(isAnimating ? 0.5 : 1.0)
                        .animation(
                            .easeInOut(duration: 2.0)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.3),
                            value: isAnimating
                        )
                }
                
                // Main icon container
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.8),
                                Color.accentColor.opacity(0.4)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 70, height: 70)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 20, x: 0, y: 8)
                    .overlay(
                        Image(systemName: "chart.pie.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                    )
            }
            .onAppear {
                isAnimating = true
            }
            
            // Title and subtitle
            VStack(spacing: 6) {
                Text("iOS App Analyzer")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("Professional app size analysis & optimization tool")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

struct FileInputSection: View {
    @ObservedObject var viewModel: MainViewModel
    @Binding var filePickerType: AnalysisView.FilePickerType
    @Binding var showingFilePicker: Bool
    @Binding var showingConfigSheet: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Enhanced Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "doc.badge.plus")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                    
                    Text("Input Files")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                Button {
                    showingConfigSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape.2")
                        Text("配置")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            // File Input Cards
            VStack(spacing: 12) {
                // Project Directory
                ModernFileInputCard(
                    title: "Project Directory",
                    subtitle: "Select the iOS project directory",
                    path: viewModel.selectedProjectPath,
                    icon: "folder.fill",
                    iconColor: .blue,
                    gradientColors: [.blue.opacity(0.3), .cyan.opacity(0.2)],
                    onSelect: {
                        filePickerType = .project
                        showingFilePicker = true
                    },
                    onClear: {
                        viewModel.clearSelectedProjectPath()
                    }
                )
                
                // IPA File
                ModernFileInputCard(
                    title: "IPA File",
                    subtitle: "Select the .ipa file to analyze",
                    path: viewModel.selectedIpaPath,
                    icon: "doc.zipper",
                    iconColor: .purple,
                    gradientColors: [.purple.opacity(0.3), .pink.opacity(0.2)],
                    onSelect: {
                        filePickerType = .ipa
                        showingFilePicker = true
                    },
                    onClear: {
                        viewModel.clearSelectedIpaPath()
                    }
                )
                
                // Linkmap File
                ModernFileInputCard(
                    title: "Linkmap File",
                    subtitle: "Select the linkmap.txt file",
                    path: viewModel.selectedLinkmapPath,
                    icon: "doc.text.fill",
                    iconColor: .orange,
                    gradientColors: [.orange.opacity(0.3), .yellow.opacity(0.2)],
                    onSelect: {
                        filePickerType = .linkmap
                        showingFilePicker = true
                    },
                    onClear: {
                        viewModel.clearSelectedLinkmapPath()
                    }
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
    }
}

struct ModernFileInputCard: View {
    let title: String
    let subtitle: String
    let path: String?
    let icon: String
    let iconColor: Color
    let gradientColors: [Color]
    let onSelect: () -> Void
    let onClear: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon Container
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(iconColor)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                if let path = path {
                    let url = URL(fileURLWithPath: path)
                    HStack(spacing: 6) {
                        Text(url.lastPathComponent)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(iconColor.opacity(0.8))
                            .cornerRadius(6)
                        
                        Text(path)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } else {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 10) {
                if path != nil {
                    Button {
                        onClear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("清除选择")
                }
                
                Button {
                    onSelect()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.badge.plus")
                        Text("选择")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(iconColor)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.textBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isHovered ? iconColor.opacity(0.4) : Color.clear,
                            lineWidth: 1.5
                        )
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
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
                    let url = URL(fileURLWithPath: path)
                    HStack(spacing: 4) {
                        Text(url.lastPathComponent)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .cornerRadius(4)
                        Text(path)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
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
    @ObservedObject var viewModel: MainViewModel
    @State private var showingHelp = false
    @State private var classUsagePlistURL: URL?
    @State private var classUsageCSVURL: URL?
    @State private var resourceUsageCSVURL: URL?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Enhanced Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "cloud.bolt.fill")
                        .font(.title3)
                        .foregroundColor(.teal)
                    
                    Text("External Data")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                
                Button {
                    showingHelp = true
                } label: {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.teal.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("查看外部数据导入格式说明")
                .popover(isPresented: $showingHelp, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("外部数据导入格式说明")
                            .font(.headline)
                        Text("当前版本支持两种模式：1）直接导入简单 TXT/CSV/JSON/Plist 名单；2）从 AppThinnerReporter 上报数据（类映射 plist + 统计 CSV）自动计算无用类和无用资源。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Divider()
                        Group {
                            Text("• 简单模式：无用资源列表（CSV）")
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
                            Text("• 简单模式：无用类列表（CSV）")
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
                        Group {
                            Text("• Reporter 模式：类 & 资源使用数据")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("  - 类：选择 `class_mapping_xxx.plist`（提供 all_class_list）+ 对应的类使用统计 CSV（例如 `UnusedClasses.csv`，包含 `realized_bitmap_base64_gzip` 列），工具会自动按位图 OR 汇总计算未使用类。")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("  - 资源：选择上报平台导出的资源统计 CSV，默认按第一列资源路径导入为外部无用资源名单，如需更精细策略可在平台侧先过滤。")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Divider()
                        Text("简单模式下，额外的列内容会被忽略，仅第一列参与导入；如需更复杂的结构，可考虑使用 JSON / Plist 或 Reporter 模式。")
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
                
                if !viewModel.externalUnusedResources.isEmpty || !viewModel.externalUnusedClasses.isEmpty {
                    HStack(spacing: 12) {
                        if !viewModel.externalUnusedResources.isEmpty {
                            Label("\(viewModel.externalUnusedResources.count) Resources", systemImage: "photo")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.pink.opacity(0.8))
                                .cornerRadius(8)
                        }
                        if !viewModel.externalUnusedClasses.isEmpty {
                            Label("\(viewModel.externalUnusedClasses.count) Classes", systemImage: "curlybraces")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.8))
                                .cornerRadius(8)
                        }
                    }
                }
            }
            
            // Reporter 模式导入区域，直接展示在主页面
            VStack(spacing: 16) {
                // Class Data Card
                ModernGroupCard(
                    title: "类使用数据",
                    subtitle: "Reporter 输出",
                    icon: "curlybraces.square.fill",
                    iconColor: .indigo
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        // Plist Row
                        ModernFileSelectorRow(
                            label: "类映射 plist",
                            isRequired: true,
                            description: "例如 class_mapping_5.97.0_998.plist",
                            selectedURL: classUsagePlistURL ?? viewModel.reporterClassMappingPlistPath.map(URL.init(fileURLWithPath:)),
                            accentColor: .indigo
                        ) {
                            selectFile(allowedExtensions: ["plist"]) { url in
                                classUsagePlistURL = url
                                viewModel.setReporterClassMappingPlist(from: url)
                            }
                        }
                        
                        Divider()
                        
                        // CSV Row
                        ModernFileSelectorRow(
                            label: "类使用统计 CSV",
                            isRequired: true,
                            description: "来自上报平台的聚合表",
                            selectedURL: classUsageCSVURL ?? viewModel.reporterClassUsageCSVPath.map(URL.init(fileURLWithPath:)),
                            accentColor: .purple
                        ) {
                            selectFile(allowedExtensions: ["csv"]) { url in
                                classUsageCSVURL = url
                                viewModel.setReporterClassUsageCSV(from: url)
                            }
                        }
                    }
                }
                
                // Resource Data Card
                ModernGroupCard(
                    title: "资源使用数据",
                    subtitle: "Reporter 输出",
                    icon: "photo.stack.fill",
                    iconColor: .teal
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        ModernFileSelectorRow(
                            label: "资源使用统计 CSV",
                            isRequired: false,
                            description: "按资源聚合后的 CSV，第一列为资源路径",
                            selectedURL: resourceUsageCSVURL ?? viewModel.reporterResourceUsageCSVPath.map(URL.init(fileURLWithPath:)),
                            accentColor: .teal
                        ) {
                            selectFile(allowedExtensions: ["csv"]) { url in
                                resourceUsageCSVURL = url
                                viewModel.setReporterResourceUsageCSV(from: url)
                            }
                        }
                    }
                }
            }
            
            // Footer Actions
            HStack {
                Button {
                    viewModel.clearReporterExternalData()
                    classUsagePlistURL = nil
                    classUsageCSVURL = nil
                    resourceUsageCSVURL = nil
                } label: {
                    Label("清除数据", systemImage: "trash")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red.opacity(0.8))
                
                Spacer()
                
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("开始分析时将自动使用已选择的 Reporter 文件")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
    }
    
    private func selectFile(allowedExtensions: [String], completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedFileTypes = allowedExtensions
        
        if panel.runModal() == .OK, let url = panel.url {
            completion(url)
        }
    }
}

// MARK: - Modern UI Components

struct ModernGroupCard<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(iconColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(iconColor.opacity(0.05))
            
            Divider()
            
            // Content
            content
                .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.textBackgroundColor).opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(iconColor.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

struct ModernFileSelectorRow: View {
    let label: String
    let isRequired: Bool
    let description: String
    let selectedURL: URL?
    let accentColor: Color
    let onSelect: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Status Indicator
            ZStack {
                Circle()
                    .fill(selectedURL != nil ? accentColor.opacity(0.2) : Color.gray.opacity(0.15))
                    .frame(width: 28, height: 28)
                
                Image(systemName: selectedURL != nil ? "checkmark" : "doc")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(selectedURL != nil ? accentColor : .secondary)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(label)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if isRequired {
                        Text("必需")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.7))
                            .cornerRadius(4)
                    }
                }
                
                if let url = selectedURL {
                    HStack(spacing: 6) {
                        Text(url.lastPathComponent)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(accentColor.opacity(0.85))
                            .cornerRadius(6)
                        
                        Text(url.path)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } else {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Select Button
            Button {
                onSelect()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder.badge.plus")
                    Text(selectedURL != nil ? "更换" : "选择")
                }
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(accentColor)
        }
    }
}

struct AnalysisProgressSection: View {
    @ObservedObject var viewModel: MainViewModel
    @Binding var showingDetails: Bool
    @Binding var animateProgress: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            // Header with animated icon
            HStack {
                HStack(spacing: 10) {
                    // Animated spinner
                    ZStack {
                        Circle()
                            .stroke(Color.accentColor.opacity(0.2), lineWidth: 3)
                            .frame(width: 28, height: 28)
                        
                        Circle()
                            .trim(from: 0, to: 0.7)
                            .stroke(
                                LinearGradient(
                                    colors: [.accentColor, .accentColor.opacity(0.5)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .frame(width: 28, height: 28)
                            .rotationEffect(.degrees(animateProgress ? 360 : 0))
                            .animation(
                                .linear(duration: 1.5)
                                .repeatForever(autoreverses: false),
                                value: animateProgress
                            )
                    }
                    
                    Text("Analysis in Progress")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                Button {
                    showingDetails.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text("Details")
                            .font(.subheadline)
                        Image(systemName: showingDetails ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            // Enhanced Progress Bar
            VStack(spacing: 10) {
                HStack {
                    Text(viewModel.currentOperation)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(Int(viewModel.analysisProgress * 100))%")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.accentColor)
                        .monospacedDigit()
                }
                
                // Custom progress bar with gradient
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.15))
                            .frame(height: 12)
                        
                        // Progress
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: [.accentColor.opacity(0.8), .accentColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(geometry.size.width * viewModel.analysisProgress, 12), height: 12)
                            .animation(.easeInOut(duration: 0.3), value: viewModel.analysisProgress)
                        
                        // Shine effect
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.3), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: max(geometry.size.width * viewModel.analysisProgress, 12), height: 6)
                            .offset(y: -3)
                    }
                }
                .frame(height: 12)
            }
            
            // Status Row
            HStack(spacing: 16) {
                // Animated dots
                HStack(spacing: 6) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                            .scaleEffect(animateProgress ? 1.3 : 0.8)
                            .opacity(animateProgress ? 1.0 : 0.5)
                            .animation(
                                .easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.15),
                                value: animateProgress
                            )
                    }
                }
                
                Text("Processing files...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Estimated Time
                if viewModel.analysisProgress > 0.1 {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("~\(estimatedTimeRemaining) remaining")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.08),
                            Color.accentColor.opacity(0.03)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.accentColor.opacity(0.2), lineWidth: 1.5)
                )
        )
    }
    
    private var estimatedTimeRemaining: String {
        let progress = max(viewModel.analysisProgress, 0.01)
        let remainingProgress = 1.0 - progress
        let estimatedSeconds = Int(remainingProgress / progress * 30)
        
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
        VStack(alignment: .leading, spacing: 20) {
            // Enhanced Header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [.green.opacity(0.3), .mint.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.green)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Analysis Results")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(project.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Total size badge
                Text(formatBytes(project.totalSize))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        LinearGradient(
                            colors: [.blue.opacity(0.9), .purple.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(8)
            }
            
            Divider()
            
            // Enhanced Grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 14) {
                ModernSummaryCard(
                    title: "Total Size",
                    value: formatBytes(project.totalSize),
                    systemImage: "doc.fill",
                    gradientColors: [.blue.opacity(0.4), .cyan.opacity(0.3)]
                )
                
                ModernSummaryCard(
                    title: "Code Size",
                    value: formatBytes(project.summaryCodeSize != 0 ? project.summaryCodeSize : project.totalCodeSize),
                    systemImage: "curlybraces",
                    gradientColors: [.green.opacity(0.4), .mint.opacity(0.3)]
                )
                
                ModernSummaryCard(
                    title: "Resources",
                    value: formatBytes(project.summaryResourceSize != 0 ? project.summaryResourceSize : project.totalResourceSize),
                    systemImage: "photo.fill",
                    gradientColors: [.orange.opacity(0.4), .yellow.opacity(0.3)]
                )
                
                ModernSummaryCard(
                    title: "Unused Code",
                    value: formatBytes(project.unusedCodeSize),
                    systemImage: "bolt.slash.fill",
                    gradientColors: [.red.opacity(0.4), .pink.opacity(0.3)]
                )
                
                ModernSummaryCard(
                    title: "Frameworks",
                    value: formatBytes(project.summaryFrameworkSize != 0 ? project.summaryFrameworkSize : project.totalFrameworkSize),
                    systemImage: "building.2.fill",
                    gradientColors: [.purple.opacity(0.4), .indigo.opacity(0.3)]
                )
                
                ModernSummaryCard(
                    title: "Unused Resources",
                    value: formatBytes(project.unusedResourceSize),
                    systemImage: "trash.fill",
                    gradientColors: [.pink.opacity(0.4), .red.opacity(0.2)]
                )
                
                if !project.duplicateCodeGroups.isEmpty {
                    ModernSummaryCard(
                        title: "代码重复",
                        value: "\(project.duplicateCodeGroups.count) 组",
                        systemImage: "doc.on.doc.fill",
                        gradientColors: [.mint.opacity(0.4), .teal.opacity(0.3)]
                    )
                }
                if !project.duplicateResourceGroups.isEmpty {
                    ModernSummaryCard(
                        title: "资源重复",
                        value: "\(project.duplicateResourceGroups.count) 组",
                        systemImage: "photo.on.rectangle.angled",
                        gradientColors: [.cyan.opacity(0.4), .blue.opacity(0.3)]
                    )
                }
                if let pods = project.podsDependencyResult, !pods.pods.isEmpty {
                    ModernSummaryCard(
                        title: "Pods 依赖",
                        value: "\(pods.pods.count) 个",
                        systemImage: "square.stack.3d.up.fill",
                        gradientColors: [.indigo.opacity(0.4), .purple.opacity(0.3)]
                    )
                }
            }
            
            // Additional Info Section
            if !project.duplicateCodeGroups.isEmpty || !project.duplicateResourceGroups.isEmpty || (project.podsDependencyResult != nil && !project.podsDependencyResult!.pods.isEmpty) {
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    if !project.duplicateCodeGroups.isEmpty {
                        InfoRow(
                            icon: "doc.on.doc",
                            iconColor: .mint,
                            title: "代码重复",
                            detail: "\(project.duplicateCodeGroups.count) 组重复代码，涉及 \(project.duplicateCodeGroups.flatMap { $0.entries.map(\.relativePath) }.uniqued().count) 个文件"
                        )
                    }
                    if !project.duplicateResourceGroups.isEmpty {
                        InfoRow(
                            icon: "photo.on.rectangle.angled",
                            iconColor: .cyan,
                            title: "资源重复",
                            detail: "\(project.duplicateResourceGroups.count) 组重复资源，涉及 \(project.duplicateResourceGroups.flatMap { $0.entries.map(\.relativePath) }.uniqued().count) 个文件"
                        )
                    }
                    if let pods = project.podsDependencyResult, !pods.pods.isEmpty {
                        InfoRow(
                            icon: "square.stack.3d.up",
                            iconColor: .indigo,
                            title: "Pods 依赖",
                            detail: "\(pods.pods.count) 个 Pod（来自 \(pods.podfileLockPath ?? "Podfile.lock")）"
                        )
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct ModernSummaryCard: View {
    let title: String
    let value: String
    let systemImage: String
    let gradientColors: [Color]
    
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                
                Image(systemName: systemImage)
                    .font(.system(size: 20))
                    .foregroundColor(gradientColors[0].opacity(2.5))
            }
            
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.textBackgroundColor).opacity(0.4))
        )
    }
}

struct InfoRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let detail: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(iconColor)
                .frame(width: 24, height: 24)
                .background(iconColor.opacity(0.15))
                .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
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

// 预览在 Reporter 导入改造后可按需补充