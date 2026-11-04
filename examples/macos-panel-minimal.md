# Candidate — macOS panel

The coordinator lazily owns a nonmodal panel. Its baseline is the declared
default, `ToolbarStyle.appDefault`; presets and sliders edit the scene model's
style, and closing releases the panel and hosting tree. The DEBUG menu command and
Command-Shift-L are the human path and visible fallback; the DEBUG-only
`-UITuningLabOpen 1` launch argument, consumed once in `FeatureWindow.onAppear`, is
the agent path (`references/activation.md`). **Copy values** puts the fields that differ
from the baseline on the pasteboard and logs them as one
`UITUNINGLAB_VALUES {...}` line for landing (`references/landing-protocol.md`).
**Keep as candidate**, the candidates list (Load, Remove), **Compare**, and
**Done** follow `references/candidates.md`. The coordinator owns the
`UITuningLabCandidates` store beside the draft, so candidates and `basedOn`
survive closing the panel; in the default candidate they live in memory and in
the log only, and a name is never reused within a run. Compare shares the Show
baseline stash, and while either shows something other than the draft the
editing controls, Keep, Reset, Copy values, and Load are disabled. Done is
disabled only while Show baseline is on; while Compare shows a candidate, Done
loads it into the draft first, so it is the winner. Closing the panel restores
the draft. The finish hint is pinned below the controls. To reopen a session,
seed the store's `initial:` array; each seeded candidate logs its own
`UITUNINGLAB_CANDIDATE` line. The default candidate has no persistence. Every
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
    @Published var stashedDraft: ToolbarStyle?  // set while the baseline or a candidate is shown
    @Published var comparing: String?           // the candidate Compare shows, nil for the draft
}

@MainActor
final class UITuningLabCoordinator: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private let lab = UITuningLabState()
    // Candidates and basedOn live beside the draft and outlive the panel. To
    // reopen a session, seed the finalists kept in the project here
    // (references/candidates.md).
    private let candidates = UITuningLabCandidates<ToolbarStyle>(baseline: .appDefault, initial: [])
    // The model owns this coordinator, so it always outlives it.
    private unowned let model: FeatureSceneModel

    init(model: FeatureSceneModel) { self.model = model }

    func show() {
        if let panel { panel.makeKeyAndOrderFront(nil); return }
        // The panel observes the model and the lab state, so every change
        // redraws it. The baseline is the declared default, never the value on
        // screen at open: a draft kept from an earlier session must still count.
        let controls = UITuningLabPanel(model: model, lab: lab, candidates: candidates,
                                        baseline: .appDefault)
        let panel = UITuningLabNSPanel(contentRect: .init(x: 0, y: 0, width: 320, height: 420),
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
        lab.comparing = nil
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
    // Owned by the coordinator beside the draft, so candidates and basedOn
    // survive closing and reopening the panel.
    @ObservedObject var candidates: UITuningLabCandidates<ToolbarStyle>
    let baseline: ToolbarStyle
    @State private var status: String?

    private static let compact = ToolbarStyle(height: 32, cornerRadius: 4)
    private static let spacious = ToolbarStyle(height: 56, cornerRadius: 16)

    var body: some View {
        Form {
            Toggle("Show baseline", isOn: showingBaseline)
            if !candidates.all.isEmpty {
                Picker("Compare", selection: comparedCandidate) {
                    Text("Draft").tag(String?.none)
                    ForEach(candidates.all) { Text($0.name).tag(Optional($0.name)) }
                }
            }
            Group {
                HStack {
                    Button("Compact") { model.style = Self.compact; candidates.basedOn = "compact" }
                    Button("Spacious") { model.style = Self.spacious; candidates.basedOn = "spacious" }
                }
                LabeledContent("Height", value: "\(Int(model.style.height)) pt")
                    .accessibilityHidden(true)  // the slider reports its own value
                Slider(value: $model.style.height, in: 28...64, step: 1) { Text("Height") }
                LabeledContent("Radius", value: "\(Int(model.style.cornerRadius)) pt")
                    .accessibilityHidden(true)  // the slider reports its own value
                Slider(value: $model.style.cornerRadius, in: 0...24, step: 1) { Text("Radius") }
                HStack {
                    Button("Reset") { model.style = baseline; candidates.basedOn = "baseline" }
                    Button("Copy values") {
                        status = uiTuningLabCopyValues(from: baseline, to: model.style)
                    }
                }
            }
            .disabled(lab.stashedDraft != nil)
            HStack {
                Button("Keep as candidate", action: keep)
                    .disabled(lab.stashedDraft != nil)
                // While Compare shows a candidate, Done lands that candidate.
                Button("Done", action: done)
                    .disabled(lab.stashedDraft != nil && lab.comparing == nil)
            }
            if !candidates.all.isEmpty {
                Section("Candidates") {
                    ForEach(candidates.all) { candidate in
                        HStack {
                            Text("\(candidate.name), from \(candidate.basedOn)")
                            Spacer()
                            Button("Load") { load(candidate) }
                                .accessibilityLabel("Load \(candidate.name)")
                                .disabled(lab.stashedDraft != nil)
                            Button("Remove") { remove(candidate.name) }
                                .accessibilityLabel("Remove \(candidate.name)")
                        }
                    }
                }
            }
            if let status { Text(status).font(.footnote) }
        }
        // Pinned below the controls, so it shows however long the panel grows.
        .safeAreaInset(edge: .bottom) {
            Text("Finished? Keep the ones you like, then press Done, or tell the agent \"land b\".")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
        }
        .padding()
    }

    /// Shows the baseline in the real feature; turning it off restores the draft.
    private var showingBaseline: Binding<Bool> {
        Binding(
            get: { lab.stashedDraft != nil && lab.comparing == nil },
            set: { show in
                lab.comparing = nil
                if show {
                    if lab.stashedDraft == nil { lab.stashedDraft = model.style }
                    model.style = baseline
                } else if let draft = lab.stashedDraft {
                    model.style = draft
                    lab.stashedDraft = nil
                }
            }
        )
    }

    /// Shows a candidate in the real feature, sharing the baseline's stash;
    /// Draft restores the draft.
    private var comparedCandidate: Binding<String?> {
        Binding(
            get: { lab.comparing },
            set: { name in
                if let name, let candidate = candidates.named(name) {
                    if lab.stashedDraft == nil { lab.stashedDraft = model.style }
                    model.style = candidate.value
                    lab.comparing = name
                } else {
                    if let draft = lab.stashedDraft { model.style = draft }
                    lab.stashedDraft = nil
                    lab.comparing = nil
                }
            }
        )
    }

    private func keep() {
        do {
            let kept = try candidates.keep(model.style)
            status = "Kept \(kept.name)"
        } catch {
            status = error.localizedDescription
        }
    }

    private func done() {
        // The candidate on screen becomes the draft, so it is the winner.
        var draft = model.style
        if let name = lab.comparing, let candidate = candidates.named(name) {
            lab.stashedDraft = nil
            lab.comparing = nil
            load(candidate)
            draft = candidate.value
        }
        status = candidates.done(draft)
    }

    private func load(_ candidate: UITuningLabCandidate<ToolbarStyle>) {
        model.style = candidate.value
        candidates.basedOn = candidate.name
        status = "Loaded \(candidate.name)"
    }

    private func remove(_ name: String) {
        if lab.comparing == name { comparedCandidate.wrappedValue = nil }
        candidates.remove(name)
        status = "Removed \(name)"
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
    try uiTuningLabJSON(uiTuningLabChangedFields(from: baseline, to: draft))
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

/// A finalist kept from the draft (references/candidates.md). It lives in
/// memory, and in storage only when the lab persists it.
struct UITuningLabCandidate<Value: Codable>: Identifiable {
    var name: String
    var basedOn: String  // a preset's kebab-case name, `baseline`, or a candidate's name
    var value: Value
    var id: String { name }
}

/// Why Keep did not add a candidate, worded for the panel's status line.
struct UITuningLabNotKept: LocalizedError {
    let errorDescription: String?
}

/// The candidates list, oldest first, owned beside the draft so it survives
/// closing the lab. Every change logs one line the agent can replay:
/// `UITUNINGLAB_CANDIDATE {...}` and `UITUNINGLAB_CANDIDATE_REMOVED {...}`.
@MainActor
final class UITuningLabCandidates<Value: Codable>: ObservableObject {
    @Published private(set) var all: [UITuningLabCandidate<Value>] = []
    /// Where the draft came from: `baseline` until a preset, Reset, or Load changes it.
    @Published var basedOn = "baseline"
    let baseline: Value
    private var taken: Set<String> = []  // every name issued or reserved this run

    /// Seed with finalists kept in the project to reopen a session; empty by default.
    init(baseline: Value, initial: [UITuningLabCandidate<Value>] = []) {
        self.baseline = baseline
        for candidate in initial { _ = try? adopt(candidate) }
    }

    func named(_ name: String) -> UITuningLabCandidate<Value>? {
        all.first { $0.name == name }
    }

    /// Marks names as used, such as every file in storage, so Keep never issues them.
    func reserve(_ names: some Sequence<String>) { taken.formUnion(names) }

    /// Keeps the draft under a name never used before in this run. A draft that
    /// matches the baseline or an existing candidate is not kept. `store` runs
    /// before the candidate is added; if it throws, nothing is added or logged.
    func keep(_ draft: Value, store: (UITuningLabCandidate<Value>) throws -> Void = { _ in })
        throws -> UITuningLabCandidate<Value> {
        let candidate = UITuningLabCandidate(
            name: uiTuningLabCandidateName(excluding: taken), basedOn: basedOn, value: draft)
        let line = try checked(candidate)
        do { try store(candidate) } catch {
            throw UITuningLabNotKept(errorDescription: "Not kept: \(error.localizedDescription)")
        }
        add(candidate, line: line)
        return candidate
    }

    /// Adds a seeded or stored candidate and logs it. Returns false, silently,
    /// when the name is already in the list; throws when it now matches the
    /// baseline or another candidate.
    @discardableResult
    func adopt(_ candidate: UITuningLabCandidate<Value>) throws -> Bool {
        taken.insert(candidate.name)
        guard named(candidate.name) == nil else { return false }
        add(candidate, line: try checked(candidate))
        return true
    }

    func remove(_ name: String) {
        guard named(name) != nil else { return }
        all.removeAll { $0.name == name }
        uiTuningLabLogLine("UITUNINGLAB_CANDIDATE_REMOVED", ["name": name])
    }

    /// Copies the draft's values like Copy values, then logs the handoff line
    /// `UITUNINGLAB_DONE {...}`. The winner is the candidate the draft matches.
    func done(_ draft: Value) -> String {
        let copied = uiTuningLabCopyValues(from: baseline, to: draft)
        let values: [String: Any]
        let kept: [[String: Any]]
        do {
            values = try uiTuningLabChangedFields(from: baseline, to: draft)
            kept = try all.map { try uiTuningLabCandidateFields($0, baseline: baseline) }
        } catch {
            return "Done not logged: \(error.localizedDescription)"
        }
        let draftValues = try? uiTuningLabJSON(values)
        let winner = all.first { (try? uiTuningLabChangedValues(from: baseline, to: $0.value)) == draftValues }
        var line: [String: Any] = ["candidates": kept, "values": values, "winner": NSNull()]
        if let winner { line["winner"] = winner.name }
        uiTuningLabLogLine("UITUNINGLAB_DONE", line)
        if let winner { return "Done: \(winner.name) is the winner. \(copied)" }
        if all.isEmpty { return "Done. \(copied)" }
        return "Done: the draft matches no candidate, so the agent will ask which to land. \(copied)"
    }

    /// The candidate's log line, or why it cannot join the list.
    private func checked(_ candidate: UITuningLabCandidate<Value>) throws -> [String: Any] {
        let line: [String: Any]
        let values: String
        do {
            line = try uiTuningLabCandidateFields(candidate, baseline: baseline)
            values = try uiTuningLabChangedValues(from: baseline, to: candidate.value)
        } catch {
            throw UITuningLabNotKept(errorDescription: "Not kept: \(error.localizedDescription)")
        }
        if values == "{}" {
            throw UITuningLabNotKept(errorDescription: "Matches the baseline; nothing to keep")
        }
        if let twin = all.first(where: { (try? uiTuningLabChangedValues(from: baseline, to: $0.value)) == values }) {
            throw UITuningLabNotKept(errorDescription: "Same as \(twin.name)")
        }
        return line
    }

    private func add(_ candidate: UITuningLabCandidate<Value>, line: [String: Any]) {
        taken.insert(candidate.name)
        uiTuningLabLogLine("UITUNINGLAB_CANDIDATE", line)
        all.append(candidate)
    }
}

/// `a` to `z`, then `aa`, `ab`, and so on: the first name not in `taken`.
/// Letters only, and never `draft` or `baseline`, which Compare and basedOn use.
func uiTuningLabCandidateName(excluding taken: Set<String>) -> String {
    let used = taken.union(["draft", "baseline"])
    return (0...).lazy.map(uiTuningLabCandidateName(at:)).first { !used.contains($0) }!
}

private func uiTuningLabCandidateName(at index: Int) -> String {
    var remaining = index + 1
    var name = ""
    while remaining > 0 {
        remaining -= 1
        name = String(UnicodeScalar(UInt8(97 + remaining % 26))) + name
        remaining /= 26
    }
    return name
}

/// One candidate as it appears in the log: its values are the diff against the baseline.
private func uiTuningLabCandidateFields<Value: Encodable>(
    _ candidate: UITuningLabCandidate<Value>, baseline: Value
) throws -> [String: Any] {
    ["basedOn": candidate.basedOn, "name": candidate.name,
     "values": try uiTuningLabChangedFields(from: baseline, to: candidate.value)]
}

/// Logs `TAG {...}` with sorted keys at every level, readable outside the debugger.
private func uiTuningLabLogLine(_ tag: String, _ object: [String: Any]) {
    guard let json = try? uiTuningLabJSON(object) else { return }
    uiTuningLabLog.notice("\(tag, privacy: .public) \(json, privacy: .public)")
}

private func uiTuningLabJSON(_ object: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

private func uiTuningLabChangedFields<Value: Encodable>(from baseline: Value, to draft: Value) throws -> [String: Any] {
    let before = try uiTuningLabFields(baseline)
    let after = try uiTuningLabFields(draft)
    var changed: [String: Any] = [:]
    for key in Set(before.keys).union(after.keys)
    where (before[key] as? NSObject) != (after[key] as? NSObject) {
        changed[key] = after[key] ?? NSNull()
    }
    return changed
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

If the user explicitly requests persistence, replace `UITuningLabPanel.swift`
with this version. The app and coordinator files stay unchanged. Each Keep also
writes the candidate as a `schemaVersion` 2 profile, and Remove deletes that
candidate's file and nothing else. Files live under Application Support's
`<bundle-id>/.ui-tuning-lab/candidates/`: a non-sandboxed app shares Application
Support with every other app, so the bundle ID keeps labs apart. Opening the
panel adds every saved candidate to the list, ordered by `savedAt` (which keeps
fractional seconds) and then by name, and logs each one; Load applies its
overrides to the draft, and the baseline stays the declared default, so Reset
still returns to it. Every stored file name stays taken, even for a file that
was skipped. A file that does not decode, has another schema or platform, has a
name that differs from its file or is not kebab-case, or now matches the
baseline is reported in the status line, skipped, and left untouched.

<!-- file: UITuningLabPanel.swift variant=persist -->
```swift
import SwiftUI

#if DEBUG
/// A kept candidate on disk: `<name>.json` in `directory`, `schemaVersion` 2
/// (references/config-schema.md).
struct UITuningLabProfile: Codable {
    var schemaVersion = 2
    var name: String
    var basedOn: String
    var platform = "macos"
    var container = "NSPanel"
    var scope = ["appearance", "layout"]
    var savedAt: String  // ISO-8601 UTC with fractional seconds, ending in Z
    var overrides: ToolbarStyle
    var notes = ""

    /// A non-sandboxed app shares Application Support with every other app, so
    /// the bundle ID keeps labs apart.
    static var directory: URL {
        URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "ui-tuning-lab", directoryHint: .isDirectory)
            .appending(path: ".ui-tuning-lab", directoryHint: .isDirectory)
            .appending(path: "candidates", directoryHint: .isDirectory)
    }

    static func fileURL(_ name: String) -> URL {
        directory.appending(path: "\(name).json")
    }
}

struct UITuningLabProfileMismatch: LocalizedError {
    let errorDescription: String?
}

struct UITuningLabPanel: View {
    @ObservedObject var model: FeatureSceneModel
    @ObservedObject var lab: UITuningLabState
    // Owned by the coordinator beside the draft, so candidates and basedOn
    // survive closing and reopening the panel.
    @ObservedObject var candidates: UITuningLabCandidates<ToolbarStyle>
    let baseline: ToolbarStyle
    @State private var status: String?

    private static let compact = ToolbarStyle(height: 32, cornerRadius: 4)
    private static let spacious = ToolbarStyle(height: 56, cornerRadius: 16)

    var body: some View {
        Form {
            Toggle("Show baseline", isOn: showingBaseline)
            if !candidates.all.isEmpty {
                Picker("Compare", selection: comparedCandidate) {
                    Text("Draft").tag(String?.none)
                    ForEach(candidates.all) { Text($0.name).tag(Optional($0.name)) }
                }
            }
            Group {
                HStack {
                    Button("Compact") { model.style = Self.compact; candidates.basedOn = "compact" }
                    Button("Spacious") { model.style = Self.spacious; candidates.basedOn = "spacious" }
                }
                LabeledContent("Height", value: "\(Int(model.style.height)) pt")
                    .accessibilityHidden(true)  // the slider reports its own value
                Slider(value: $model.style.height, in: 28...64, step: 1) { Text("Height") }
                LabeledContent("Radius", value: "\(Int(model.style.cornerRadius)) pt")
                    .accessibilityHidden(true)  // the slider reports its own value
                Slider(value: $model.style.cornerRadius, in: 0...24, step: 1) { Text("Radius") }
                HStack {
                    Button("Reset") { model.style = baseline; candidates.basedOn = "baseline" }
                    Button("Copy values") {
                        status = uiTuningLabCopyValues(from: baseline, to: model.style)
                    }
                }
            }
            .disabled(lab.stashedDraft != nil)
            HStack {
                Button("Keep as candidate", action: keep)
                    .disabled(lab.stashedDraft != nil)
                // While Compare shows a candidate, Done lands that candidate.
                Button("Done", action: done)
                    .disabled(lab.stashedDraft != nil && lab.comparing == nil)
            }
            if !candidates.all.isEmpty {
                Section("Candidates") {
                    ForEach(candidates.all) { candidate in
                        HStack {
                            Text("\(candidate.name), from \(candidate.basedOn)")
                            Spacer()
                            Button("Load") { load(candidate) }
                                .accessibilityLabel("Load \(candidate.name)")
                                .disabled(lab.stashedDraft != nil)
                            Button("Remove") { remove(candidate.name) }
                                .accessibilityLabel("Remove \(candidate.name)")
                        }
                    }
                }
            }
            if let status { Text(status).font(.footnote) }
        }
        // Pinned below the controls, so it shows however long the panel grows.
        .safeAreaInset(edge: .bottom) {
            Text("Finished? Keep the ones you like, then press Done, or tell the agent \"land b\".")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
        }
        .padding()
        .onAppear(perform: loadSaved)
    }

    /// Shows the baseline in the real feature; turning it off restores the draft.
    private var showingBaseline: Binding<Bool> {
        Binding(
            get: { lab.stashedDraft != nil && lab.comparing == nil },
            set: { show in
                lab.comparing = nil
                if show {
                    if lab.stashedDraft == nil { lab.stashedDraft = model.style }
                    model.style = baseline
                } else if let draft = lab.stashedDraft {
                    model.style = draft
                    lab.stashedDraft = nil
                }
            }
        )
    }

    /// Shows a candidate in the real feature, sharing the baseline's stash;
    /// Draft restores the draft.
    private var comparedCandidate: Binding<String?> {
        Binding(
            get: { lab.comparing },
            set: { name in
                if let name, let candidate = candidates.named(name) {
                    if lab.stashedDraft == nil { lab.stashedDraft = model.style }
                    model.style = candidate.value
                    lab.comparing = name
                } else {
                    if let draft = lab.stashedDraft { model.style = draft }
                    lab.stashedDraft = nil
                    lab.comparing = nil
                }
            }
        )
    }

    private func keep() {
        do {
            let kept = try candidates.keep(model.style, store: save)
            status = "Kept \(kept.name)"
        } catch {
            status = error.localizedDescription
        }
    }

    private func done() {
        // The candidate on screen becomes the draft, so it is the winner.
        var draft = model.style
        if let name = lab.comparing, let candidate = candidates.named(name) {
            lab.stashedDraft = nil
            lab.comparing = nil
            load(candidate)
            draft = candidate.value
        }
        status = candidates.done(draft)
    }

    private func load(_ candidate: UITuningLabCandidate<ToolbarStyle>) {
        model.style = candidate.value
        candidates.basedOn = candidate.name
        status = "Loaded \(candidate.name)"
    }

    private func remove(_ name: String) {
        if lab.comparing == name { comparedCandidate.wrappedValue = nil }
        candidates.remove(name)
        let file = UITuningLabProfile.fileURL(name)
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
            status = "Removed \(name)"
        } catch {
            status = "Removed \(name), file not deleted: \(error.localizedDescription)"
        }
    }

    /// Writes one new candidate atomically, refusing a name storage already holds.
    private func save(_ candidate: UITuningLabCandidate<ToolbarStyle>) throws {
        let file = UITuningLabProfile.fileURL(candidate.name)
        guard !FileManager.default.fileExists(atPath: file.path) else {
            throw UITuningLabProfileMismatch(errorDescription: "\(file.lastPathComponent) already exists")
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let profile = UITuningLabProfile(
            name: candidate.name, basedOn: candidate.basedOn,
            savedAt: formatter.string(from: .now), overrides: candidate.value)
        let data = try JSONEncoder().encode(profile)
        try FileManager.default.createDirectory(
            at: UITuningLabProfile.directory, withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }

    /// Adds every saved candidate to the list, oldest first. Every stored name
    /// stays taken. A file that does not decode, has another schema or platform,
    /// a name that differs from its file or is not kebab-case, or now matches
    /// the baseline is reported and left untouched.
    private func loadSaved() {
        let files = ((try? FileManager.default.contentsOfDirectory(
            at: UITuningLabProfile.directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
        candidates.reserve(files.map { $0.deletingPathExtension().lastPathComponent })
        let kebab = "^[a-z0-9]+(-[a-z0-9]+)*$"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let wholeSeconds = ISO8601DateFormatter()
        var loaded: [(savedAt: Date, profile: UITuningLabProfile)] = []
        var skipped: [String] = []
        for file in files {
            do {
                let profile = try JSONDecoder().decode(
                    UITuningLabProfile.self, from: Data(contentsOf: file))
                guard profile.schemaVersion == 2, profile.platform == "macos" else {
                    throw UITuningLabProfileMismatch(errorDescription: "incompatible schema or platform")
                }
                guard profile.name == file.deletingPathExtension().lastPathComponent,
                      profile.name.range(of: kebab, options: .regularExpression) != nil,
                      profile.basedOn.range(of: kebab, options: .regularExpression) != nil else {
                    throw UITuningLabProfileMismatch(errorDescription: "name or basedOn does not match the file")
                }
                guard let savedAt = formatter.date(from: profile.savedAt)
                        ?? wholeSeconds.date(from: profile.savedAt) else {
                    throw UITuningLabProfileMismatch(errorDescription: "savedAt is not an ISO-8601 time")
                }
                loaded.append((savedAt, profile))
            } catch {
                skipped.append("\(file.lastPathComponent) (\(error.localizedDescription))")
            }
        }
        loaded.sort {
            ($0.savedAt, $0.profile.name.count, $0.profile.name)
                < ($1.savedAt, $1.profile.name.count, $1.profile.name)
        }
        for (_, profile) in loaded {
            do {
                try candidates.adopt(UITuningLabCandidate(
                    name: profile.name, basedOn: profile.basedOn, value: profile.overrides))
            } catch {
                skipped.append("\(profile.name).json (\(error.localizedDescription))")
            }
        }
        if !skipped.isEmpty {
            status = "Skipped \(skipped.joined(separator: ", ")). The files were left unchanged."
        }
    }
}
#endif
```

Keep atomically writes `<name>.json` after checking that the file does not
exist. A write failure refuses the Keep: the status line shows the error, and the
candidate is neither added nor logged.
