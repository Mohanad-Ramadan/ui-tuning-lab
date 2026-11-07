# Candidate — macOS panel

The coordinator lazily owns a nonmodal panel. Its baseline is the declared
default, `ToolbarStyle.appDefault`; presets and sliders edit the scene model's
style, and closing releases the panel and hosting tree. The DEBUG menu command and
Command-Shift-L are the human path and visible fallback; the DEBUG-only
`-UITuningLabOpen 1` launch argument, consumed once in `FeatureWindow.onAppear`, is
the agent path (`references/activation.md`). **Copy values** puts the fields that differ
from the baseline on the pasteboard and logs them as one
`UITUNINGLAB_VALUES {...}` line for landing (`references/landing-protocol.md`).
The chips, **Pin**, **Choose**, and the **⋯** menu (Reset, Copy values)
follow `references/candidates.md`. The chip row shows Shipped, each pin, and,
last, the draft chip ("Shipped + edits", "compact + edits"), which appears only
while the draft holds unpinned changes; clicking a chip shows it in the real
toolbar, and the draft is stashed meanwhile and restored when its chip is
clicked or the panel closes. The controls are disabled while Shipped is shown;
moving one while a pin is shown copies that pin into the draft first. **Pin** is
disabled while the draft matches Shipped or a pin. **Choose** logs
`UITUNINGLAB_DONE`, writes Application Support
`<bundle-id>/.ui-tuning-lab/result.json`, copies `land <name>`, and collapses
the panel to a `Chosen:` bar whose Change button reopens it. The coordinator
owns the `UITuningLabCandidates` store beside the draft, so pins and `basedOn`
survive closing the panel; in the default candidate they live in memory and in
the log, and a name is never reused within a run. The hint is pinned below the
controls. To reopen a session, seed the store's `initial:` array; each seeded
pin logs its own `UITUNINGLAB_CANDIDATE` line. The default candidate saves no
pins. Every
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
    @Published var stashedDraft: ToolbarStyle?  // the draft, while another chip is shown
    @Published var shown = "draft"              // the chip shown: draft, original (Shipped), or a pin's name
    @Published var sent: String?                // the last pick; set, the panel is one bar
}

@MainActor
final class UITuningLabCoordinator: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private let lab = UITuningLabState()
    // Pins and basedOn live beside the draft and outlive the panel. To
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
        lab.shown = "draft"
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
    // Owned by the coordinator beside the draft, so pins and basedOn
    // survive closing and reopening the panel.
    @ObservedObject var candidates: UITuningLabCandidates<ToolbarStyle>
    let baseline: ToolbarStyle
    @State private var status: String?

    private static let compact = ToolbarStyle(height: 32, cornerRadius: 4)
    private static let spacious = ToolbarStyle(height: 56, cornerRadius: 16)

    var body: some View {
        if let sent = lab.sent {
            // Choose collapses the panel to one bar; Change reopens it.
            VStack(alignment: .leading) {
                HStack {
                    Text("Chosen: \(sent)")
                    Spacer()
                    Button("Change") { lab.sent = nil }
                }
                if let status { Text(status).font(.footnote) }
            }
            .padding()
            .frame(width: 300)
        } else {
            panel
        }
    }

    private var panel: some View {
        Form {
            HStack {
                Text("UI tuning lab").font(.headline)
                Spacer()
                Menu {
                    Button("Reset", action: reset)
                    Button("Copy values") {
                        // Copy values always reports the draft, whatever chip is shown.
                        status = uiTuningLabCopyValues(from: baseline, to: lab.stashedDraft ?? model.style)
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
                            Button("×") { remove(pin.name) }
                                .accessibilityLabel("Remove \(pin.name)")
                        }
                    }
                    // The draft chip comes last, and only while the draft holds unpinned changes.
                    if draftMatch == nil { chip(candidates.draftTitle, id: "draft") }
                }
            }
            Group {
                HStack {
                    Button("Compact") { edit(Self.compact, basedOn: "compact") }
                    Button("Spacious") { edit(Self.spacious, basedOn: "spacious") }
                }
                LabeledContent("Height", value: "\(Int(model.style.height)) pt")
                    .accessibilityHidden(true)  // the slider reports its own value
                Slider(value: draft.height, in: 28...64, step: 1) { Text("Height") }
                LabeledContent("Radius", value: "\(Int(model.style.cornerRadius)) pt")
                    .accessibilityHidden(true)  // the slider reports its own value
                Slider(value: draft.cornerRadius, in: 0...24, step: 1) { Text("Radius") }
            }
            .disabled(lab.shown == "original")
            HStack {
                // Nothing to pin while the draft matches Shipped or a pin.
                Button("Pin", action: keep)
                    .disabled(draftMatch != nil)
                Button("Choose", action: useThis)
            }
            if let status { Text(status).font(.footnote) }
        }
        // Pinned below the controls, so it shows however long the panel grows.
        .safeAreaInset(edge: .bottom) {
            Text("Pin looks to compare · Choose to finish")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
        }
        .padding()
    }

    /// The chip the draft matches (`original` for Shipped, or a pin), or nil
    /// while it holds unpinned changes and shows its own chip.
    private var draftMatch: String? { candidates.match(lab.stashedDraft ?? model.style) }

    /// The highlighted chip: the one shown, or the one the draft matches.
    private var current: String { lab.shown == "draft" ? draftMatch ?? "draft" : lab.shown }

    /// One chip; the highlighted chip is the one the feature shows.
    private func chip(_ title: String, id: String) -> some View {
        Button(title) { show(id) }
            .buttonStyle(.bordered)
            .tint(current == id ? .accentColor : .secondary)
            .accessibilityAddTraits(current == id ? .isSelected : [])
    }

    /// Shows a chip in the real feature. The draft is stashed while another
    /// chip is shown and restored when its chip, or the chip it matches, is
    /// clicked, or the panel closes.
    private func show(_ id: String) {
        let target = id == draftMatch ? "draft" : id
        if target == "draft" {
            if let draft = lab.stashedDraft { model.style = draft }
            lab.stashedDraft = nil
        } else {
            if lab.stashedDraft == nil { lab.stashedDraft = model.style }
            model.style = target == "original" ? baseline : candidates.named(target)?.value ?? model.style
        }
        lab.shown = target
    }

    /// The controls edit the draft. Moving one while a pin is shown first
    /// copies that pin into the draft; the pin itself does not change.
    private var draft: Binding<ToolbarStyle> {
        Binding(get: { model.style }, set: { edit($0) })
    }

    private func edit(_ value: ToolbarStyle, basedOn preset: String? = nil) {
        // Editing a pin, or a draft that matches one, starts from that look.
        if let source = lab.shown == "draft" ? draftMatch : lab.shown {
            candidates.basedOn = source == "original" ? "baseline" : source
        }
        lab.stashedDraft = nil
        lab.shown = "draft"
        model.style = value
        if let preset { candidates.basedOn = preset }
    }

    private func reset() {
        lab.stashedDraft = nil
        lab.shown = "draft"
        model.style = baseline
        candidates.basedOn = "baseline"
    }

    private func remove(_ name: String) {
        if lab.shown == name { show("draft") }
        candidates.remove(name)
        status = "Removed \(name)"
    }

    private func keep() {
        do {
            let kept = try candidates.keep(lab.stashedDraft ?? model.style)
            status = "Pinned \(kept.name)"
        } catch {
            status = error.localizedDescription
        }
    }

    /// Choose picks the highlighted chip: a pin, `original` for Shipped, or `draft`.
    private func useThis() {
        let winner = current
        status = candidates.use(model.style, winner: winner)
        lab.sent = winner
    }
}
#endif
```

<!-- copy: assets/swift/UITuningLabValues.swift -->
`UITuningLabValues.swift`: copy `assets/swift/UITuningLabValues.swift` into the
app's target unchanged. It holds Copy values, the pins store, pin names,
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
with this version. The app and coordinator files stay unchanged. Each Pin also
writes the look as a `schemaVersion` 2 profile, and × deletes that
pin's file and nothing else. Files live under Application Support's
`<bundle-id>/.ui-tuning-lab/candidates/`: a non-sandboxed app shares Application
Support with every other app, so the bundle ID keeps labs apart. Opening the
panel adds every saved pin as a chip, ordered by `savedAt` (which keeps
fractional seconds) and then by name, and logs each one; the baseline stays the
declared default, so Reset still returns to it. Every stored file name stays
taken, even for a file that was skipped. A file that does not decode, has
another schema or platform, has a name that differs from its file or is not
kebab-case, or now matches the baseline is reported in the status line,
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
    // Owned by the coordinator beside the draft, so pins and basedOn
    // survive closing and reopening the panel.
    @ObservedObject var candidates: UITuningLabCandidates<ToolbarStyle>
    let baseline: ToolbarStyle
    @State private var status: String?

    private static let compact = ToolbarStyle(height: 32, cornerRadius: 4)
    private static let spacious = ToolbarStyle(height: 56, cornerRadius: 16)

    var body: some View {
        if let sent = lab.sent {
            // Choose collapses the panel to one bar; Change reopens it.
            VStack(alignment: .leading) {
                HStack {
                    Text("Chosen: \(sent)")
                    Spacer()
                    Button("Change") { lab.sent = nil }
                }
                if let status { Text(status).font(.footnote) }
            }
            .padding()
            .frame(width: 300)
        } else {
            panel
        }
    }

    private var panel: some View {
        Form {
            HStack {
                Text("UI tuning lab").font(.headline)
                Spacer()
                Menu {
                    Button("Reset", action: reset)
                    Button("Copy values") {
                        // Copy values always reports the draft, whatever chip is shown.
                        status = uiTuningLabCopyValues(from: baseline, to: lab.stashedDraft ?? model.style)
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
                            Button("×") { remove(pin.name) }
                                .accessibilityLabel("Remove \(pin.name)")
                        }
                    }
                    // The draft chip comes last, and only while the draft holds unpinned changes.
                    if draftMatch == nil { chip(candidates.draftTitle, id: "draft") }
                }
            }
            Group {
                HStack {
                    Button("Compact") { edit(Self.compact, basedOn: "compact") }
                    Button("Spacious") { edit(Self.spacious, basedOn: "spacious") }
                }
                LabeledContent("Height", value: "\(Int(model.style.height)) pt")
                    .accessibilityHidden(true)  // the slider reports its own value
                Slider(value: draft.height, in: 28...64, step: 1) { Text("Height") }
                LabeledContent("Radius", value: "\(Int(model.style.cornerRadius)) pt")
                    .accessibilityHidden(true)  // the slider reports its own value
                Slider(value: draft.cornerRadius, in: 0...24, step: 1) { Text("Radius") }
            }
            .disabled(lab.shown == "original")
            HStack {
                // Nothing to pin while the draft matches Shipped or a pin.
                Button("Pin", action: keep)
                    .disabled(draftMatch != nil)
                Button("Choose", action: useThis)
            }
            if let status { Text(status).font(.footnote) }
        }
        // Pinned below the controls, so it shows however long the panel grows.
        .safeAreaInset(edge: .bottom) {
            Text("Pin looks to compare · Choose to finish")
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

    /// The chip the draft matches (`original` for Shipped, or a pin), or nil
    /// while it holds unpinned changes and shows its own chip.
    private var draftMatch: String? { candidates.match(lab.stashedDraft ?? model.style) }

    /// The highlighted chip: the one shown, or the one the draft matches.
    private var current: String { lab.shown == "draft" ? draftMatch ?? "draft" : lab.shown }

    /// One chip; the highlighted chip is the one the feature shows.
    private func chip(_ title: String, id: String) -> some View {
        Button(title) { show(id) }
            .buttonStyle(.bordered)
            .tint(current == id ? .accentColor : .secondary)
            .accessibilityAddTraits(current == id ? .isSelected : [])
    }

    /// Shows a chip in the real feature. The draft is stashed while another
    /// chip is shown and restored when its chip, or the chip it matches, is
    /// clicked, or the panel closes.
    private func show(_ id: String) {
        let target = id == draftMatch ? "draft" : id
        if target == "draft" {
            if let draft = lab.stashedDraft { model.style = draft }
            lab.stashedDraft = nil
        } else {
            if lab.stashedDraft == nil { lab.stashedDraft = model.style }
            model.style = target == "original" ? baseline : candidates.named(target)?.value ?? model.style
        }
        lab.shown = target
    }

    /// The controls edit the draft. Moving one while a pin is shown first
    /// copies that pin into the draft; the pin itself does not change.
    private var draft: Binding<ToolbarStyle> {
        Binding(get: { model.style }, set: { edit($0) })
    }

    private func edit(_ value: ToolbarStyle, basedOn preset: String? = nil) {
        // Editing a pin, or a draft that matches one, starts from that look.
        if let source = lab.shown == "draft" ? draftMatch : lab.shown {
            candidates.basedOn = source == "original" ? "baseline" : source
        }
        lab.stashedDraft = nil
        lab.shown = "draft"
        model.style = value
        if let preset { candidates.basedOn = preset }
    }

    private func reset() {
        lab.stashedDraft = nil
        lab.shown = "draft"
        model.style = baseline
        candidates.basedOn = "baseline"
    }

    private func remove(_ name: String) {
        if lab.shown == name { show("draft") }
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

    private func keep() {
        do {
            let kept = try candidates.keep(lab.stashedDraft ?? model.style, store: save)
            status = "Pinned \(kept.name)"
        } catch {
            status = error.localizedDescription
        }
    }

    /// Choose picks the highlighted chip: a pin, `original` for Shipped, or `draft`.
    private func useThis() {
        let winner = current
        status = candidates.use(model.style, winner: winner)
        lab.sent = winner
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

Pin atomically writes `<name>.json` after checking that the file does not
exist. A write failure refuses the Pin: the status line shows the error, and the
pin is neither added nor logged.
