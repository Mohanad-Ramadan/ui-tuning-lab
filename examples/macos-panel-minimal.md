# Candidate — macOS panel

The coordinator lazily owns a nonmodal panel. Its baseline is the declared
default, `ToolbarStyle.appDefault`; presets and sliders edit the scene model's
style, and closing releases the panel and hosting tree. The DEBUG menu command and
Command-Shift-L are the human path and visible fallback; the DEBUG-only
`-UITuningLabOpen 1` launch argument, consumed once in `FeatureWindow.onAppear`, is
the agent path (`references/activation.md`). **Copy values** puts the fields that differ
from the baseline on the pasteboard and logs them as one
`UITUNINGLAB_VALUES {...}` line for landing (`references/landing-protocol.md`).
The chips, **Duplicate**, **Choose**, and the **⋯** menu (Copy values) follow
`references/candidates.md`. The chip row shows Shipped and each pin; the
selected chip is outlined, and the toolbar always shows it, so switching chips is
the comparison. The controls edit the selected pin in place; on Shipped, which is
read-only, they start a new pin named after the preset or `tweak`. **Duplicate**
branches the selected pin. **Choose** picks the selected chip, logs
`UITUNINGLAB_DONE`, writes Application Support
`<bundle-id>/.ui-tuning-lab/result.json`, copies `land <name>`, and collapses
the panel to a `Chosen:` bar whose Change button reopens it. The coordinator
owns the `UITuningLabCandidates` store, so the pins and the selection survive
closing the panel; in the default candidate they live in memory and in the log,
and a name is never reused within a run. To reopen a session, seed the store's
`initial:` array; each seeded pin logs its own `UITUNINGLAB_CANDIDATE` line. The
default candidate saves no pins.

The panel is a plain stack, never a `Form`: on macOS a `Form` lays its rows out
in two columns, which pushes the controls right and shows each label twice. The
header and chips sit at the top, the controls scroll, and the actions and hint
are pinned at the bottom. The panel carries its own fixed size, because the
window follows its content: without it the panel comes back from the result bar
only as tall as its header and chips. Every lab type carries the `UITuningLab` prefix and lives in a file wrapped in
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
/// Lab-only state the panel observes; the coordinator owns it beside the pins.
@MainActor
final class UITuningLabState: ObservableObject {
    @Published var sent: String?  // the last pick; set, the panel is one bar
}

@MainActor
final class UITuningLabCoordinator: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private let lab = UITuningLabState()
    // The looks and the selected chip live beside the feature and outlive the
    // panel. To reopen a session, seed the finalists kept in the project here
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
        // The feature keeps the selected look; an edited pin logs its values.
        candidates.leave()
        lab.sent = nil
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
            Button("Toolbar Lab") { showUITuningLab?() }
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
    // Owned by the coordinator, so the looks and the selection survive closing
    // and reopening the panel.
    @ObservedObject var candidates: UITuningLabCandidates<ToolbarStyle>
    let baseline: ToolbarStyle

    private static let compact = ToolbarStyle(height: 32, cornerRadius: 4)
    private static let spacious = ToolbarStyle(height: 56, cornerRadius: 16)

    var body: some View {
        Group {
            if let sent = lab.sent {
                // Choose collapses the panel to one bar; Change reopens it.
                VStack(alignment: .leading) {
                    HStack {
                        Text("Chosen: \(sent)")
                        Spacer()
                        Button("Change") { lab.sent = nil }
                    }
                    if let status = candidates.status { Text(status).font(.footnote) }
                }
                .padding()
                .frame(width: 320)
            } else {
                panel
            }
        }
    }

    // A plain stack, not a Form: on macOS a Form lays its rows out in two
    // columns, which pushes every control right and shows each label twice.
    private var panel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("UI tuning lab").font(.headline)
                Spacer()
                Menu {
                    Button("Copy values") {
                        candidates.status = uiTuningLabCopyValues(from: baseline, to: model.style)
                    }
                } label: {
                    Text("⋯")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("More")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    chip("Shipped", id: "original")
                    ForEach(candidates.all) { pin in
                        HStack(spacing: 2) {
                            chip(pin.name, id: pin.name)
                            Button("×") { model.style = candidates.remove(pin.name) }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove \(pin.name)")
                        }
                    }
                }
                .padding(2)  // room for the selected chip's outline
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button("Compact") { edit(Self.compact, preset: "compact") }
                        Button("Spacious") { edit(Self.spacious, preset: "spacious") }
                    }
                    slider("Height", \.height, 28...64)
                    slider("Radius", \.cornerRadius, 0...24)
                    if let status = candidates.status { Text(status).font(.footnote) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                // Duplicate branches the selected pin; Shipped has nothing to branch.
                Button("Duplicate") { candidates.duplicate(); model.style = candidates.selectedLook }
                    .disabled(candidates.selectedPin == nil)
                Spacer()
                Button("Choose") { lab.sent = candidates.choose() }
                    .keyboardShortcut(.defaultAction)
            }
            // Pinned at the bottom, so it shows however long the controls grow.
            Text("Duplicate to compare · Choose to finish")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        // The window follows its content, so this branch carries its own size:
        // without it the panel comes back from the result bar only as tall as
        // its header and chips.
        .frame(width: 320, height: 420, alignment: .top)
    }

    /// One row per control: the label and value, then the slider with its own
    /// label hidden, so no label shows twice.
    private func slider(_ title: String, _ path: WritableKeyPath<ToolbarStyle, Double>,
                        _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            LabeledContent(title, value: "\(Int(model.style[keyPath: path])) pt")
                .accessibilityHidden(true)  // the slider reports its own value
            Slider(value: Binding(get: { model.style[keyPath: path] }, set: { value in
                var next = model.style
                next[keyPath: path] = value
                edit(next)
            }), in: range, step: 1) { Text(title) }
                .labelsHidden()
        }
    }

    /// One chip. The selected chip is outlined and is the look the feature shows.
    private func chip(_ title: String, id: String) -> some View {
        let on = candidates.selected == id
        return Button(title) { model.style = candidates.select(id) }
            .buttonStyle(.bordered)
            .tint(on ? .accentColor : .secondary)
            .uiTuningLabSelected(on)
            .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Every control edits the selected look: a pin in place, or, on Shipped, a
    /// new pin.
    private func edit(_ value: ToolbarStyle, preset: String? = nil) {
        candidates.edit(value, preset: preset)
        model.style = candidates.selectedLook
    }

}
#endif
```

<!-- copy: assets/swift/UITuningLabValues.swift -->
`UITuningLabValues.swift`: copy `assets/swift/UITuningLabValues.swift` into the
app's target unchanged. It holds Copy values, the looks store and selection, pin names,
Choose with its result file, and the log lines every Swift lab shares,
all inside `#if DEBUG`.

Each window's `FeatureSceneModel` owns exactly one coordinator; the focused scene
routes the menu and `Command-Shift-L` shortcut to that coordinator, and the launch
argument opens one panel, in the first window to appear, for the agent. Window
dismissal closes the panel, which releases its hosting tree. Test focus return,
multiple windows, keyboard navigation, VoiceOver, closed-state allocations, and
the archived Release app before approval.

## Optional persistence, only when requested

If the user explicitly requests persistence, replace `UITuningLabPanel.swift`
with this version. The app and coordinator files stay unchanged. Each pin is
written as a `schemaVersion` 2 profile when it is created and again whenever it
logs new values, and × deletes that pin's file and nothing else. Files live under
Application Support's `<bundle-id>/.ui-tuning-lab/candidates/`: a non-sandboxed
app shares Application Support with every other app, so the bundle ID keeps labs
apart. Opening the panel adds every saved pin as a chip, ordered by the
`savedAt` of its first write (which keeps fractional seconds) and then by name,
and logs each one; the baseline stays the declared default, so Shipped still
shows it. Every stored file name stays taken, even for a file that was skipped.
A file that does not decode, has another schema or platform, or has a name that
differs from its file or is not kebab-case is reported in the status line,
skipped, and left untouched.

<!-- file: UITuningLabPanel.swift variant=persist -->
```swift
import SwiftUI

#if DEBUG
/// A pinned look on disk: `<name>.json` in `directory`, `schemaVersion` 2
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
    // Owned by the coordinator, so the looks and the selection survive closing
    // and reopening the panel.
    @ObservedObject var candidates: UITuningLabCandidates<ToolbarStyle>
    let baseline: ToolbarStyle

    // A persisting lab writes each pin whenever it logs, and deletes it on ×.
    private func persist() {
        candidates.store = save
        candidates.unstore = { try FileManager.default.removeItem(at: UITuningLabProfile.fileURL($0)) }
    }

    private static let compact = ToolbarStyle(height: 32, cornerRadius: 4)
    private static let spacious = ToolbarStyle(height: 56, cornerRadius: 16)

    var body: some View {
        Group {
            if let sent = lab.sent {
                // Choose collapses the panel to one bar; Change reopens it.
                VStack(alignment: .leading) {
                    HStack {
                        Text("Chosen: \(sent)")
                        Spacer()
                        Button("Change") { lab.sent = nil }
                    }
                    if let status = candidates.status { Text(status).font(.footnote) }
                }
                .padding()
                .frame(width: 320)
            } else {
                panel
            }
        }
        .onAppear(perform: loadSaved)
    }

    // A plain stack, not a Form: on macOS a Form lays its rows out in two
    // columns, which pushes every control right and shows each label twice.
    private var panel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("UI tuning lab").font(.headline)
                Spacer()
                Menu {
                    Button("Copy values") {
                        candidates.status = uiTuningLabCopyValues(from: baseline, to: model.style)
                    }
                } label: {
                    Text("⋯")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("More")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    chip("Shipped", id: "original")
                    ForEach(candidates.all) { pin in
                        HStack(spacing: 2) {
                            chip(pin.name, id: pin.name)
                            Button("×") { model.style = candidates.remove(pin.name) }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove \(pin.name)")
                        }
                    }
                }
                .padding(2)  // room for the selected chip's outline
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button("Compact") { edit(Self.compact, preset: "compact") }
                        Button("Spacious") { edit(Self.spacious, preset: "spacious") }
                    }
                    slider("Height", \.height, 28...64)
                    slider("Radius", \.cornerRadius, 0...24)
                    if let status = candidates.status { Text(status).font(.footnote) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                // Duplicate branches the selected pin; Shipped has nothing to branch.
                Button("Duplicate") { candidates.duplicate(); model.style = candidates.selectedLook }
                    .disabled(candidates.selectedPin == nil)
                Spacer()
                Button("Choose") { lab.sent = candidates.choose() }
                    .keyboardShortcut(.defaultAction)
            }
            // Pinned at the bottom, so it shows however long the controls grow.
            Text("Duplicate to compare · Choose to finish")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        // The window follows its content, so this branch carries its own size:
        // without it the panel comes back from the result bar only as tall as
        // its header and chips.
        .frame(width: 320, height: 420, alignment: .top)
    }

    /// One row per control: the label and value, then the slider with its own
    /// label hidden, so no label shows twice.
    private func slider(_ title: String, _ path: WritableKeyPath<ToolbarStyle, Double>,
                        _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            LabeledContent(title, value: "\(Int(model.style[keyPath: path])) pt")
                .accessibilityHidden(true)  // the slider reports its own value
            Slider(value: Binding(get: { model.style[keyPath: path] }, set: { value in
                var next = model.style
                next[keyPath: path] = value
                edit(next)
            }), in: range, step: 1) { Text(title) }
                .labelsHidden()
        }
    }

    /// One chip. The selected chip is outlined and is the look the feature shows.
    private func chip(_ title: String, id: String) -> some View {
        let on = candidates.selected == id
        return Button(title) { model.style = candidates.select(id) }
            .buttonStyle(.bordered)
            .tint(on ? .accentColor : .secondary)
            .uiTuningLabSelected(on)
            .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Every control edits the selected look: a pin in place, or, on Shipped, a
    /// new pin.
    private func edit(_ value: ToolbarStyle, preset: String? = nil) {
        candidates.edit(value, preset: preset)
        model.style = candidates.selectedLook
    }

    /// Writes a pin atomically. An existing file keeps its `savedAt`, so pins
    /// load in the order they were made.
    private func save(_ candidate: UITuningLabCandidate<ToolbarStyle>) throws {
        let file = UITuningLabProfile.fileURL(candidate.name)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let existing = try? JSONDecoder().decode(UITuningLabProfile.self, from: Data(contentsOf: file))
        let profile = UITuningLabProfile(
            name: candidate.name, basedOn: candidate.basedOn,
            savedAt: existing?.savedAt ?? formatter.string(from: .now), overrides: candidate.value)
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
        persist()
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
            candidates.adopt(UITuningLabCandidate(
                name: profile.name, basedOn: profile.basedOn, value: profile.overrides))
        }
        if !skipped.isEmpty {
            candidates.status = "Skipped \(skipped.joined(separator: ", ")). The files were left unchanged."
        }
    }
}
#endif
```

Each write replaces `<name>.json` atomically. A failed write shows in the status
line; the pin stays in the panel and in the log.
