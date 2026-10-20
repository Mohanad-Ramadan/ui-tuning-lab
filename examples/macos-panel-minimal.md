# Candidate — macOS panel

The coordinator lazily owns a nonmodal panel. It captures the rendered
configuration on open, applies two presets to that same binding, and releases the
panel and hosting tree on close. **Copy values** puts the fields that differ from
the baseline on the pasteboard and logs them as one `UITUNINGLAB_VALUES {...}`
line for landing (`references/landing-protocol.md`). The default candidate has no persistence. Every
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
    lazy var uiTuningLab = UITuningLabCoordinator(style: Binding(
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
            .focusedSceneValue(\.showUITuningLab, { model.uiTuningLab.show() })
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

<!-- file: UITuningLabCoordinator.swift -->
```swift
import AppKit
import SwiftUI

#if DEBUG
@MainActor
final class UITuningLabCoordinator: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private let style: Binding<ToolbarStyle>

    init(style: Binding<ToolbarStyle>) { self.style = style }

    func show() {
        if let panel { panel.makeKeyAndOrderFront(nil); return }
        // The panel keeps this captured value for Reset and Copy values.
        let controls = UITuningLabPanel(style: style, baseline: style.wrappedValue)
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
    let baseline: ToolbarStyle
    @State private var status: String?

    private static let compact = ToolbarStyle(height: 32, cornerRadius: 4)
    private static let spacious = ToolbarStyle(height: 56, cornerRadius: 16)

    var body: some View {
        Form {
            HStack {
                Button("Compact") { style = Self.compact }
                Button("Spacious") { style = Self.spacious }
            }
            Slider(value: $style.height, in: 28...64, step: 1) { Text("Height") }
            Slider(value: $style.cornerRadius, in: 0...24, step: 1) { Text("Radius") }
            HStack {
                Button("Reset") { style = baseline }
                Button("Copy values") {
                    status = uiTuningLabCopyValues(from: baseline, to: style)
                }
            }
            if let status { Text(status).font(.footnote) }
        }.padding()
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
routes the menu and `Command-Shift-L` shortcut to that coordinator. Window
dismissal closes the panel, which releases its hosting tree and captured baseline. Test
focus return, multiple windows, keyboard navigation, VoiceOver, closed-state
allocations, and the archived Release app before approval.

## Optional persistence, only when requested

If the user explicitly requests saved profiles, replace `UITuningLabPanel.swift`
with this version. The app and coordinator files stay unchanged. Load saved
applies the stored overrides to the draft; the baseline stays as captured, so
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
    @Binding var style: ToolbarStyle
    let baseline: ToolbarStyle
    @State private var status: String?

    private static let compact = ToolbarStyle(height: 32, cornerRadius: 4)
    private static let spacious = ToolbarStyle(height: 56, cornerRadius: 16)

    var body: some View {
        Form {
            HStack {
                Button("Compact") { style = Self.compact }
                Button("Spacious") { style = Self.spacious }
            }
            Slider(value: $style.height, in: 28...64, step: 1) { Text("Height") }
            Slider(value: $style.cornerRadius, in: 0...24, step: 1) { Text("Radius") }
            HStack {
                Button("Reset") { style = baseline }
                Button("Copy values") {
                    status = uiTuningLabCopyValues(from: baseline, to: style)
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
            if let status { Text(status).font(.footnote) }
        }.padding()
    }

    private func save() throws {
        let data = try JSONEncoder().encode(UITuningLabProfile(overrides: style))
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
        style = profile.overrides
    }
}
#endif
```

An explicit Save atomically writes `default.json` under Application Support's
`.ui-tuning-lab/`; failures are visible and leave the edited style intact.
