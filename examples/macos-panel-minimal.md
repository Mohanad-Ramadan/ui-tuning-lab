# Candidate — macOS panel

The coordinator lazily owns a nonmodal panel. It captures the rendered
configuration on open, applies two presets to that same binding, and releases the
panel and hosting tree on close. The default candidate has no persistence. Every
lab type carries the `UITuningLab` prefix and lives in a file wrapped in
`#if DEBUG`, so `source-gates` can find it and Release builds compile it out.

<!-- file: ExampleApp.swift -->
```swift
import SwiftUI

struct ToolbarStyle: Codable, Equatable {
    var height: Double
    var cornerRadius: Double
    static let appDefault = Self(height: 44, cornerRadius: 10)
}

struct FeatureView: View {
    let style: ToolbarStyle

    var body: some View {
        HStack { Text("Toolbar") }
            .frame(maxWidth: .infinity, minHeight: style.height)
            .background(.bar, in: RoundedRectangle(cornerRadius: style.cornerRadius))
            .padding()
    }
}

@MainActor
final class FeatureSceneModel: ObservableObject {
    @Published var style = ToolbarStyle.appDefault

    #if DEBUG
    lazy var lab = UITuningLabCoordinator(style: Binding(
        get: { [weak self] in self?.style ?? .appDefault },
        set: { [weak self] in self?.style = $0 }
    ))
    #endif
}

struct FeatureWindow: View {
    @StateObject private var model = FeatureSceneModel()

    var body: some View {
        FeatureView(style: model.style)
            #if DEBUG
            .focusedSceneValue(\.showUITuningLab, { model.lab.show() })
            .onDisappear { model.lab.close() }
            #endif
    }
}

@main
struct ExampleApp: App {
    var body: some Scene {
        WindowGroup { FeatureWindow() }
            #if DEBUG
            .commands { UITuningLabCommands() }
            #endif
    }
}
```

<!-- file: UITuningLabCoordinator.swift -->
```swift
import AppKit
import SwiftUI

#if DEBUG
@MainActor
final class UITuningLabCoordinator: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var baseline: ToolbarStyle?
    private let style: Binding<ToolbarStyle>

    init(style: Binding<ToolbarStyle>) { self.style = style }

    func show() {
        if let panel { panel.makeKeyAndOrderFront(nil); return }
        baseline = style.wrappedValue
        let controls = UITuningLabPanel(
            style: style,
            reset: { [weak self] in
                guard let self, let baseline = self.baseline else { return }
                self.style.wrappedValue = baseline
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
}

struct ShowUITuningLabKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var showUITuningLab: (() -> Void)? {
        get { self[ShowUITuningLabKey.self] }
        set { self[ShowUITuningLabKey.self] = newValue }
    }
}

struct UITuningLabCommands: Commands {
    @FocusedValue(\.showUITuningLab) private var showUITuningLab

    var body: some Commands {
        CommandMenu("Development") {
            Button("UI Tuning Lab") { showUITuningLab?() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(showUITuningLab == nil)
        }
    }
}
#endif
```

<!-- file: UITuningLabPanel.swift -->
```swift
import SwiftUI

#if DEBUG
struct UITuningLabPanel: View {
    @Binding var style: ToolbarStyle
    let reset: () -> Void

    private static let compact = ToolbarStyle(height: 32, cornerRadius: 4)
    private static let spacious = ToolbarStyle(height: 56, cornerRadius: 16)

    var body: some View {
        Form {
            HStack {
                Button("Compact") { style = Self.compact }
                Button("Spacious") { style = Self.spacious }
            }
            Slider(value: $style.height, in: 28...64) { Text("Height") }
            Slider(value: $style.cornerRadius, in: 0...24) { Text("Radius") }
            HStack {
                Button("Reset", action: reset)
            }
        }.padding()
    }
}
#endif
```

Each window's `FeatureSceneModel` owns exactly one coordinator; the focused scene
routes the menu and `Command-Shift-L` shortcut to that coordinator. Window
dismissal closes the panel, which releases its hosting tree and baseline. Test
focus return, multiple windows, keyboard navigation, VoiceOver, closed-state
allocations, and the archived Release app before approval.

## Optional persistence, only when requested

If the user explicitly requests saved profiles, replace `UITuningLabPanel.swift`
with this version. The app and coordinator files stay unchanged.

<!-- file: UITuningLabPanel.swift variant=persist -->
```swift
import SwiftUI

#if DEBUG
struct UITuningLabProfile: Codable {
    var schemaVersion = 1
    var name = "default"
    var platform = "macos"
    var container = "NSPanel"
    var scope = ["appearance", "layout"]
    var overrides: ToolbarStyle
    var notes = ""
}

struct UITuningLabPanel: View {
    @Binding var style: ToolbarStyle
    let reset: () -> Void
    @State private var saveError: String?

    private static let compact = ToolbarStyle(height: 32, cornerRadius: 4)
    private static let spacious = ToolbarStyle(height: 56, cornerRadius: 16)

    var body: some View {
        Form {
            HStack {
                Button("Compact") { style = Self.compact }
                Button("Spacious") { style = Self.spacious }
            }
            Slider(value: $style.height, in: 28...64) { Text("Height") }
            Slider(value: $style.cornerRadius, in: 0...24) { Text("Radius") }
            HStack {
                Button("Reset", action: reset)
                Button("Save") {
                    do { try save(); saveError = nil }
                    catch { saveError = error.localizedDescription }
                }
            }
            if let saveError { Text(saveError).foregroundStyle(.red) }
        }.padding()
    }

    private func save() throws {
        let data = try JSONEncoder().encode(UITuningLabProfile(overrides: style))
        let directory = URL.applicationSupportDirectory
            .appending(path: ".ui-tuning-lab", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        try data.write(to: directory.appending(path: "default.json"),
                       options: .atomic)
    }
}
#endif
```

An explicit Save atomically writes `default.json` under Application Support's
`.ui-tuning-lab/`; failures are visible and leave the edited style intact.
