# Candidate — macOS panel

The coordinator lazily owns a nonmodal panel. It captures the rendered
configuration on open, applies two presets to that same binding, saves only from
the Save button, and releases the panel and hosting tree on close.

```swift
struct ToolbarStyle: Codable, Equatable {
    var height: Double
    var cornerRadius: Double
    static let appDefault = Self(height: 44, cornerRadius: 10)
    static let compact = Self(height: 32, cornerRadius: 4)
    static let spacious = Self(height: 56, cornerRadius: 16)
}

struct LabProfile: Codable {
    let schemaVersion = 1
    let name = "default"
    let platform = "macos"
    let container = "NSPanel"
    let scope = ["appearance", "layout"]
    let overrides: ToolbarStyle
    let notes = ""
}

@MainActor
final class FeatureSceneModel: ObservableObject {
    @Published var style = ToolbarStyle.appDefault

    #if DEBUG
    lazy var lab = LabPanelCoordinator(style: Binding(
        get: { [weak self] in self?.style ?? .appDefault },
        set: { [weak self] in self?.style = $0 }
    ))
    #endif
}

#if DEBUG
@MainActor
final class LabPanelCoordinator: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var baseline: ToolbarStyle?
    private let style: Binding<ToolbarStyle>

    init(style: Binding<ToolbarStyle>) { self.style = style }

    func show() {
        if let panel { panel.makeKeyAndOrderFront(nil); return }
        baseline = style.wrappedValue
        let controls = LabPanel(
            style: style,
            reset: { [weak self] in
                guard let self, let baseline = self.baseline else { return }
                self.style.wrappedValue = baseline
            },
            save: { [weak self] in
                guard let self else { return }
                try self.saveProfile()
            }
        )
        let panel = NSPanel(contentRect: .init(x: 0, y: 0, width: 300, height: 250),
                            styleMask: [.titled, .closable, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.animationBehavior = .none
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: controls)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func close() { panel?.close() }

    func windowWillClose(_ notification: Notification) {
        panel?.delegate = nil
        panel?.contentView = nil
        panel = nil
        baseline = nil
    }

    private func saveProfile() throws {
        let profile = LabProfile(overrides: style.wrappedValue)
        let data = try JSONEncoder().encode(profile)
        let directory = URL.applicationSupportDirectory
            .appending(path: ".ui-tuning-lab", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        try data.write(to: directory.appending(path: "default.json"),
                       options: .atomic)
    }
}

private struct LabPanel: View {
    @Binding var style: ToolbarStyle
    let reset: () -> Void
    let save: () throws -> Void
    @State private var error: String?

    var body: some View {
        Form {
            HStack {
                Button("Compact") { style = .compact }
                Button("Spacious") { style = .spacious }
            }
            Slider(value: $style.height, in: 28...64) { Text("Height") }
            Slider(value: $style.cornerRadius, in: 0...24) { Text("Radius") }
            HStack {
                Button("Reset", action: reset)
                Button("Save") {
                    do { try save(); error = nil }
                    catch let saveFailure { error = saveFailure.localizedDescription }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.padding()
    }
}

private struct ShowTuningLabKey: FocusedValueKey {
    typealias Value = () -> Void
}

private extension FocusedValues {
    var showTuningLab: (() -> Void)? {
        get { self[ShowTuningLabKey.self] }
        set { self[ShowTuningLabKey.self] = newValue }
    }
}

private struct TuningLabCommands: Commands {
    @FocusedValue(\.showTuningLab) private var showTuningLab

    var body: some Commands {
        CommandMenu("Development") {
            Button("UI Tuning Lab") { showTuningLab?() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(showTuningLab == nil)
        }
    }
}
#endif

struct FeatureWindow: View {
    @StateObject private var model = FeatureSceneModel()

    var body: some View {
        FeatureView(style: model.style)
            #if DEBUG
            .focusedSceneValue(\.showTuningLab, { model.lab.show() })
            .onDisappear { model.lab.close() }
            #endif
    }
}

@main
struct ExampleApp: App {
    var body: some Scene {
        WindowGroup { FeatureWindow() }
            #if DEBUG
            .commands { TuningLabCommands() }
            #endif
    }
}
```

Each window's `FeatureSceneModel` owns exactly one coordinator; the focused scene
routes the menu and `Command-Shift-L` shortcut to that coordinator. Window
dismissal closes the panel, which releases its hosting tree and baseline. Test
focus return, multiple windows, keyboard navigation, VoiceOver, closed-state
allocations, and the archived Release app before approval.
