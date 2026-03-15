import SwiftUI

// MARK: - Keyboard Shortcuts Helper

struct KeyboardShortcuts {
    // File operations
    static let openFiles = KeyEquivalent("o")
    static let saveExport = KeyEquivalent("s")
    static let refresh = KeyEquivalent("r")

    // Analysis operations
    static let startAnalysis: KeyEquivalent = .return
    static let stopAnalysis: KeyEquivalent = .escape

    // Navigation
    static let tab1 = KeyEquivalent("1")
    static let tab2 = KeyEquivalent("2")
    static let tab3 = KeyEquivalent("3")
    static let tab4 = KeyEquivalent("4")

    // Selection operations
    static let selectAll = KeyEquivalent("a")
    static let deselectAll: KeyEquivalent = KeyEquivalent("d")
    static let clearSelection: KeyEquivalent = .delete

    // View operations
    static let toggleSidebar = KeyEquivalent("s")
    static let showHelp = KeyEquivalent("/")
    static let showAbout = KeyEquivalent("i")

    // Optimization operations
    static let createBackup = KeyEquivalent("b")
    static let optimizeSelected = KeyEquivalent("o")

    // Comparison operations
    static let compareProjects = KeyEquivalent("c")
    static let exportReport = KeyEquivalent("e")
}

// MARK: - Keyboard Shortcut Modifiers

extension View {
    func keyboardShortcuts(for context: KeyboardShortcutContext) -> some View {
        self.modifier(KeyboardShortcutModifier(context: context))
    }
}

// Global keyboard shortcut helpers using hidden buttons
extension View {
    func keyboardShortcut(_ key: Character, modifiers: EventModifiers = .command, perform action: @escaping () -> Void) -> some View {
        self.background(
            Button("", action: action)
                .keyboardShortcut(KeyEquivalent(key), modifiers: modifiers)
                .hidden()
        )
    }
    
    func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command, perform action: @escaping () -> Void) -> some View {
        self.background(
            Button("", action: action)
                .keyboardShortcut(key, modifiers: modifiers)
                .hidden()
        )
    }
}

enum KeyboardShortcutContext {
    case main
    case analysis
    case optimization
    case comparison
    case treemap
}

struct KeyboardShortcutModifier: ViewModifier {
    let context: KeyboardShortcutContext

    func body(content: Content) -> some View {
        content
            .overlay(
                KeyboardShortcutHandler(context: context)
                    .allowsHitTesting(false)
                    .opacity(0)
            )
    }
}

struct KeyboardShortcutHandler: View {
    let context: KeyboardShortcutContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch context {
            case .main:
                mainShortcuts
            case .analysis:
                analysisShortcuts
            case .optimization:
                optimizationShortcuts
            case .comparison:
                comparisonShortcuts
            case .treemap:
                treemapShortcuts
            }
        }
    }

    @ViewBuilder
    private var mainShortcuts: some View {
        // Main shortcuts are handled in MainView
        EmptyView()
    }

    @ViewBuilder
    private var analysisShortcuts: some View {
        Button("") {}
            .keyboardShortcut(KeyboardShortcuts.refresh, modifiers: [.command])
            .hidden()

        Button("") {}
            .keyboardShortcut(KeyboardShortcuts.showHelp, modifiers: [.command])
            .hidden()
    }

    @ViewBuilder
    private var optimizationShortcuts: some View {
        Button("") {}
            .keyboardShortcut(KeyboardShortcuts.selectAll, modifiers: [.command])
            .hidden()

        Button("") {}
            .keyboardShortcut(KeyboardShortcuts.deselectAll, modifiers: [.command, .shift])
            .hidden()

        Button("") {}
            .keyboardShortcut(KeyboardShortcuts.createBackup, modifiers: [.command])
            .hidden()

        Button("") {}
            .keyboardShortcut(KeyboardShortcuts.optimizeSelected, modifiers: [.command, .shift])
            .hidden()
    }

    @ViewBuilder
    private var comparisonShortcuts: some View {
        Button("") {}
            .keyboardShortcut(KeyboardShortcuts.compareProjects, modifiers: [.command])
            .hidden()

        Button("") {}
            .keyboardShortcut(KeyboardShortcuts.exportReport, modifiers: [.command])
            .hidden()

        Button("") {}
            .keyboardShortcut(KeyboardShortcuts.clearSelection, modifiers: [])
            .hidden()
    }

    @ViewBuilder
    private var treemapShortcuts: some View {
        Button("") {}
            .keyboardShortcut(.leftArrow, modifiers: [])
            .hidden()

        Button("") {}
            .keyboardShortcut(.rightArrow, modifiers: [])
            .hidden()

        Button("") {}
            .keyboardShortcut(.upArrow, modifiers: [])
            .hidden()

        Button("") {}
            .keyboardShortcut(.downArrow, modifiers: [])
            .hidden()
    }
}

// MARK: - Keyboard Shortcut Help View

struct KeyboardShortcutHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ShortcutSection(
                        title: "File Operations",
                        shortcuts: [
                            ("⌘O", "Open Files"),
                            ("⌘S", "Export Results"),
                            ("⌘R", "Refresh History"),
                        ]
                    )

                    ShortcutSection(
                        title: "Navigation",
                        shortcuts: [
                            ("⌘1", "Analysis Tab"),
                            ("⌘2", "Visualization Tab"),
                            ("⌘3", "Optimization Tab"),
                            ("⌘4", "Comparison Tab"),
                        ]
                    )

                    ShortcutSection(
                        title: "Analysis",
                        shortcuts: [
                            ("⌘↩", "Start Analysis"),
                            ("⌘/", "Show Help"),
                            ("⌘I", "About"),
                        ]
                    )

                    ShortcutSection(
                        title: "Optimization",
                        shortcuts: [
                            ("⌘A", "Select All"),
                            ("⌘⇧D", "Deselect All"),
                            ("⌘B", "Create Backup"),
                            ("⌘⇧O", "Optimize Selected"),
                            ("⌫", "Clear Selection"),
                        ]
                    )

                    ShortcutSection(
                        title: "Comparison",
                        shortcuts: [
                            ("⌘C", "Compare Projects"),
                            ("⌘E", "Export Report"),
                            ("⌫", "Clear Selection"),
                        ]
                    )

                    ShortcutSection(
                        title: "Treemap Navigation",
                        shortcuts: [
                            ("←", "Navigate Back"),
                            ("→", "Drill Down"),
                            ("↑", "Parent Directory"),
                            ("↓", "Child Directory"),
                        ]
                    )
                }
            }
        }
        .padding()
        .frame(width: 500, height: 600)
    }
}

struct ShortcutSection: View {
    let title: String
    let shortcuts: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(shortcuts, id: \.0) { shortcut, description in
                    HStack {
                        Text(shortcut)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .leading)

                        Text(description)
                            .font(.body)
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Accessibility Support

extension View {
    func accessibilityKeyboardShortcut(_ shortcut: String, description: String) -> some View {
        self.accessibilityHint("Keyboard shortcut: \(shortcut). \(description)")
    }
}

// MARK: - Visual Feedback for Shortcuts

struct ShortcutFeedbackView: View {
    let shortcut: String
    let description: String
    @State private var isVisible = false

    var body: some View {
        VStack(spacing: 8) {
            Text(shortcut)
                .font(.system(.title2, design: .monospaced))
                .fontWeight(.semibold)

            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: 4)
        .scaleEffect(isVisible ? 1.0 : 0.8)
        .opacity(isVisible ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.2)) {
                isVisible = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isVisible = false
                }
            }
        }
    }
}

// MARK: - Shortcut Manager

@MainActor
class ShortcutManager: ObservableObject {
    @Published var showingFeedback = false
    @Published var currentShortcut = ""
    @Published var currentDescription = ""

    static let shared = ShortcutManager()

    private init() {}

    func showFeedback(shortcut: String, description: String) {
        currentShortcut = shortcut
        currentDescription = description
        showingFeedback = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.showingFeedback = false
        }
    }
}
