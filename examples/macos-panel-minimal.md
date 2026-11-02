# Candidate — macOS panel

The coordinator lazily owns a nonmodal panel. Its baseline is the declared
default, `ToolbarStyle.appDefault`; presets and sliders edit the scene model's
style, and closing releases the panel and hosting tree. The DEBUG menu command and
Command-Shift-L are the human path and visible fallback; the DEBUG-only
`-UITuningLabOpen 1` launch argument, consumed once in `FeatureWindow.onAppear`, is
the agent path (`references/activation.md`). **Copy values** puts the fields that differ
from the baseline on the pasteboard and logs them as one
`UITUNINGLAB_VALUES {...}` line for landing (`references/landing-protocol.md`).
The default candidate has no persistence. Every
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
    lazy var uiTuningLab = UITuningLabCoordinator(model: self)
    #endif
}

struct FeatureWindow: View {
    @StateObject private var model = FeatureSceneModel()

    var body: some View {
        FeatureView(style: model.style)
            #if DEBUG
            .focusedSceneValue(\.showUITuningLab, { model.uiTuningLab.show() })
            // The agent path opens one panel, in the first window, once per launch.
            .onAppear { if UITuningLabLaunch.consumeRequest() { model.uiTuningLab.show() } }
            .onDisappear { model.uiTuningLab.close() }
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

<!-- file: UITuningLabLaunch.swift -->
```swift
import Foundation

#if DEBUG
/// The agent path: a DEBUG-only launch argument, honored once per launch.
/// Launch with `open ExampleApp.app --args -UITuningLabOpen 1`.
@MainActor
enum UITuningLabLaunch {
    // Launch arguments land in the volatile argument domain, so the value
    // counts: `-UITuningLabOpen 0` keeps the lab closed.
    private static var pending = UserDefaults.standard.bool(forKey: "UITuningLabOpen")

    /// True only the first time it is read, so a second window or a reappearing
    /// window does not open another panel.
    static func consumeRequest() -> Bool {
        defer { pending = false }
        return pending
    }
}
#endif
```

<!-- file: UITuningLabCoordinator.swift -->
```swift
import AppKit
import SwiftUI

#if DEBUG
/// Lab-only state the panel observes; the coordinator owns it so closing the
/// panel can always restore the draft.
@MainActor
final class UITuningLabState: ObservableObject {
    @Published var stashedDraft: ToolbarStyle?  // set while the baseline is shown
}

@MainActor
final class UITuningLabCoordinator: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private let lab = UITuningLabState()
    // The model owns this coordinator, so it always outlives it.
    private unowned let model: FeatureSceneModel

    init(model: FeatureSceneModel) { self.model = model }

    func show() {
        if let panel { panel.makeKeyAndOrderFront(nil); return }
        // The panel observes the model and the lab state, so every change
        // redraws it. The baseline is the declared default, never the value on
        // screen at open: a draft kept from an earlier session must still count.
        let controls = UITuningLabPanel(model: model, lab: lab, baseline: .appDefault)
        let panel = UITuningLabNSPanel(contentRect: .init(x: 0, y: 0, width: 300, height: 250),
                            styleMask: [.titled, .closable, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.animationBehavior = .none
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: controls)
        // Beside the feature window, never over it.
        if let window = NSApp.keyWindow {
            panel.setFrameTopLeftPoint(NSPoint(x: window.frame.maxX + 12, y: window.frame.maxY))
        } else {
            panel.center()
        }
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func close() { panel?.close() }

    func windowWillClose(_ notification: Notification) {
        if let draft = lab.stashedDraft { model.style = draft }
        lab.stashedDraft = nil
        panel?.delegate = nil
        panel?.contentView = nil
        panel = nil
    }
}

/// A utility panel that also closes on Escape.
final class UITuningLabNSPanel: NSPanel {
    override func cancelOperation(_ sender: Any?) { close() }
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
    @ObservedObject var model: FeatureSceneModel
    @ObservedObject var lab: UITuningLabState
    let baseline: ToolbarStyle
    @State private var status: String?

    private static let compact = ToolbarStyle(height: 32, cornerRadius: 4)
    private static let spacious = ToolbarStyle(height: 56, cornerRadius: 16)

    var body: some View {
        Form {
            Toggle("Show baseline", isOn: showingBaseline)
            Group {
                HStack {
                    Button("Compact") { model.style = Self.compact }
                    Button("Spacious") { model.style = Self.spacious }
                }
                LabeledContent("Height", value: "\(Int(model.style.height)) pt")
                    .accessibilityHidden(true)  // the slider reports its own value
                Slider(value: $model.style.height, in: 28...64, step: 1) { Text("Height") }
                LabeledContent("Radius", value: "\(Int(model.style.cornerRadius)) pt")
                    .accessibilityHidden(true)  // the slider reports its own value
                Slider(value: $model.style.cornerRadius, in: 0...24, step: 1) { Text("Radius") }
                HStack {
                    Button("Reset") { model.style = baseline }
                    Button("Copy values") {
                        status = uiTuningLabCopyValues(from: baseline, to: model.style)
                    }
                }
            }
            .disabled(lab.stashedDraft != nil)
            if let status { Text(status).font(.footnote) }
        }.padding()
    }

    /// Shows the baseline in the real feature; turning it off restores the draft.
    private var showingBaseline: Binding<Bool> {
        Binding(
            get: { lab.stashedDraft != nil },
            set: { show in
                if show {
                    lab.stashedDraft = model.style
                    model.style = baseline
                } else if let draft = lab.stashedDraft {
                    model.style = draft
                    lab.stashedDraft = nil
                }
            }
        )
    }
}
#endif
```

<!-- file: UITuningLabValues.swift -->
```swift
import Foundation
import os
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

#if DEBUG
private let uiTuningLabLog = Logger(subsystem: "ui-tuning-lab", category: "values")

struct UITuningLabValuesError: LocalizedError {
    var errorDescription: String? { "the configuration does not encode as a JSON object" }
}

/// The draft fields that differ from the baseline, as one line of sorted JSON.
/// Floating-point numbers are rounded to three decimals at any depth, so slider
/// noise is not reported. A field the draft cleared to nil is reported as null.
func uiTuningLabChangedValues<Value: Encodable>(from baseline: Value, to draft: Value) throws -> String {
    let before = try uiTuningLabFields(baseline)
    let after = try uiTuningLabFields(draft)
    var changed: [String: Any] = [:]
    for key in Set(before.keys).union(after.keys)
    where (before[key] as? NSObject) != (after[key] as? NSObject) {
        changed[key] = after[key] ?? NSNull()
    }
    let data = try JSONSerialization.data(withJSONObject: changed, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

/// Copies the changed values and logs them on one line the agent can find:
/// `UITUNINGLAB_VALUES {...}`. Returns a status message for the panel.
func uiTuningLabCopyValues<Value: Encodable>(from baseline: Value, to draft: Value) -> String {
    let values: String
    do { values = try uiTuningLabChangedValues(from: baseline, to: draft) }
    catch { return "Values not copied: \(error.localizedDescription)" }
    #if canImport(UIKit)
    UIPasteboard.general.string = values
    #elseif canImport(AppKit)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(values, forType: .string)
    #endif
    uiTuningLabLog.notice("UITUNINGLAB_VALUES \(values, privacy: .public)")
    return values == "{}" ? "No changes from baseline" : "Copied \(values)"
}

private func uiTuningLabFields<Value: Encodable>(_ value: Value) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw UITuningLabValuesError()
    }
    return object.mapValues(uiTuningLabNormalized)
}

/// Numbers become decimals so they print in their shortest form (0.35, not
/// 0.34999999999999998): floats rounded to three places, integers kept exact.
private func uiTuningLabNormalized(_ field: Any) -> Any {
    switch field {
    case let array as [Any]:
        return array.map(uiTuningLabNormalized)
    case let object as [String: Any]:
        return object.mapValues(uiTuningLabNormalized)
    case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID():
        guard CFNumberIsFloatType(number) else { return NSDecimalNumber(string: number.stringValue) }
        let rounded = (number.doubleValue * 1000).rounded() / 1000
        return NSDecimalNumber(string: "\(rounded)")
    default:
        return field
    }
}
#endif
```

Each window's `FeatureSceneModel` owns exactly one coordinator; the focused scene
routes the menu and `Command-Shift-L` shortcut to that coordinator, and the launch
argument opens one panel, in the first window to appear, for the agent. Window
dismissal closes the panel, which releases its hosting tree. Test focus return,
multiple windows, keyboard navigation, VoiceOver, closed-state allocations, and
the archived Release app before approval.

## Optional persistence, only when requested

If the user explicitly requests saved profiles, replace `UITuningLabPanel.swift`
with this version. The app and coordinator files stay unchanged. Load saved
applies the stored overrides to the draft; the baseline stays the declared default, so
Reset still returns to it. An unreadable or incompatible file is reported and
left untouched.

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

    static var fileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: ".ui-tuning-lab", directoryHint: .isDirectory)
            .appending(path: "default.json")
    }
}

struct UITuningLabProfileMismatch: LocalizedError {
    var errorDescription: String? { "the saved profile has an incompatible schema or platform" }
}

struct UITuningLabPanel: View {
    @ObservedObject var model: FeatureSceneModel
    @ObservedObject var lab: UITuningLabState
    let baseline: ToolbarStyle
    @State private var status: String?

    private static let compact = ToolbarStyle(height: 32, cornerRadius: 4)
    private static let spacious = ToolbarStyle(height: 56, cornerRadius: 16)

    var body: some View {
        Form {
            Toggle("Show baseline", isOn: showingBaseline)
            Group {
                HStack {
                    Button("Compact") { model.style = Self.compact }
                    Button("Spacious") { model.style = Self.spacious }
                }
                LabeledContent("Height", value: "\(Int(model.style.height)) pt")
                    .accessibilityHidden(true)  // the slider reports its own value
                Slider(value: $model.style.height, in: 28...64, step: 1) { Text("Height") }
                LabeledContent("Radius", value: "\(Int(model.style.cornerRadius)) pt")
                    .accessibilityHidden(true)  // the slider reports its own value
                Slider(value: $model.style.cornerRadius, in: 0...24, step: 1) { Text("Radius") }
                HStack {
                    Button("Reset") { model.style = baseline }
                    Button("Copy values") {
                        status = uiTuningLabCopyValues(from: baseline, to: model.style)
                    }
                    Button("Save") {
                        do { try save(); status = "Saved" }
                        catch { status = "Save failed: \(error.localizedDescription)" }
                    }
                    Button("Load saved") {
                        do { try loadSaved(); status = "Loaded saved values" }
                        catch {
                            status = "Saved profile not loaded: \(error.localizedDescription). The file was left unchanged."
                        }
                    }
                }
            }
            .disabled(lab.stashedDraft != nil)
            if let status { Text(status).font(.footnote) }
        }.padding()
    }

    /// Shows the baseline in the real feature; turning it off restores the draft.
    private var showingBaseline: Binding<Bool> {
        Binding(
            get: { lab.stashedDraft != nil },
            set: { show in
                if show {
                    lab.stashedDraft = model.style
                    model.style = baseline
                } else if let draft = lab.stashedDraft {
                    model.style = draft
                    lab.stashedDraft = nil
                }
            }
        )
    }

    private func save() throws {
        let data = try JSONEncoder().encode(UITuningLabProfile(overrides: model.style))
        try FileManager.default.createDirectory(
            at: UITuningLabProfile.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try data.write(to: UITuningLabProfile.fileURL, options: .atomic)
    }

    private func loadSaved() throws {
        let data = try Data(contentsOf: UITuningLabProfile.fileURL)
        let profile = try JSONDecoder().decode(UITuningLabProfile.self, from: data)
        guard profile.schemaVersion == 1, profile.platform == "macos" else {
            throw UITuningLabProfileMismatch()
        }
        model.style = profile.overrides
    }
}
#endif
```

An explicit Save atomically writes `default.json` under Application Support's
`.ui-tuning-lab/`; failures are visible and leave the edited style intact.
