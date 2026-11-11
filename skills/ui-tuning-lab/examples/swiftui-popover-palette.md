# Candidate — SwiftUI iOS/iPadOS palette

This is implementation guidance, not a completed validation. The feature and lab
share one `CardStyle`. The baseline is the declared default, `CardStyle.appDefault`,
so it stays the same however many times the lab is opened and closed.
The default host opens from the `-UITuningLabOpen` launch argument for the agent
and the toolbar button for the human; the optional shake variant adds shake as
the fast path and keeps a visible pill (`references/activation.md`).
Every lab type carries the `UITuningLab` prefix and lives in a file wrapped in
`#if DEBUG`, so `source-gates` can find it and Release builds compile it out.
**Copy values** puts the fields that differ from the baseline on the pasteboard
and logs them as one `UITUNINGLAB_VALUES {...}` line for landing
(`references/landing-protocol.md`).
The chips, **Save & pin** / **Save**, the **Undo**, **Redo**, and **Reset** row,
**Apply**, and the **⋯** menu (Copy values) follow `references/candidates.md`.
The chip row shows Shipped and each pinned look, named after its preset
(**Compact-1**, **Relaxed-1**, or **Custom-1** for a look started from the
sliders); the selected chip is outlined, and the feature always shows it, so
switching chips is the comparison. Shipped is read-only: the controls make
unsaved changes on it, with no chip outlined, until **Save & pin** keeps them as
a new look. On a pinned look the controls make edits that stay with it when you
switch away, until **Save** makes them its saved version. Undo and Redo step
through the selected look's edits back to its last save, and a whole slider drag
is one step; Reset takes the look back to its last save, and Undo can take that
back. **Apply** (hidden after its first use) saves, picks the selected chip, logs
`UITUNINGLAB_DONE`, writes Application Support `.ui-tuning-lab/result.json`,
copies `land <name>`, and collapses the lab to a `Applied:` bar whose Change
button reopens it. After that, Save & pin and Save hand the pick over too, for
pasting in chat. The host owns the `UITuningLabCandidates` store beside the
feature, so the looks, their edits, and the selection survive closing the
popover; they live in memory and in the log, and a name is never reused within a
run. Only a save logs a look's `UITUNINGLAB_CANDIDATE` line. Closing the lab
leaves the feature on the selected look. The hint is pinned below the scrolling
Form, so it shows at the smallest detent. To reopen a session, seed the store's
`initial:` array; each seeded look logs its own `UITUNINGLAB_CANDIDATE` line.

<!-- file: CardFeature.swift -->
```swift
import SwiftUI

struct CardStyle: Codable, Equatable {
    var cornerRadius: CGFloat
    var spacing: CGFloat
    static let appDefault = Self(cornerRadius: 12, spacing: 8)
}

struct CardFeature: View {
    let style: CardStyle

    var body: some View {
        VStack(spacing: style.spacing) {
            ForEach(["First card", "Second card"], id: \.self) { title in
                Text(title)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(.thinMaterial,
                                in: RoundedRectangle(cornerRadius: style.cornerRadius))
            }
        }
        .padding()
    }
}
```

<!-- file: FeatureScreen.swift -->
```swift
import SwiftUI

struct FeatureScreen: View {
    @State private var style = CardStyle.appDefault
    #if DEBUG
    @State private var showUITuningLab = false
    @State private var uiTuningLabDetent = PresentationDetent.height(320)
    // The looks and the selected chip live beside the feature and outlive the
    // popover. To reopen a session, seed the finalists kept in the project here
    // (references/candidates.md).
    @StateObject private var uiTuningLabCandidates =
        UITuningLabCandidates<CardStyle>(baseline: .appDefault, initial: [])
    #endif

    var body: some View {
        CardFeature(style: style)
            #if DEBUG
            .toolbar {
                Button("Card Lab", action: openUITuningLab)
                    .disabled(showUITuningLab)
            }
            .popover(isPresented: $showUITuningLab) {
                // The declared default, never the value on screen at open: a look
                // kept from an earlier session must still count as a change.
                UITuningLabControls(style: $style, baseline: .appDefault)
                    .environmentObject(uiTuningLabCandidates)
                    // On iPhone the popover becomes a short sheet the feature
                    // stays usable behind; drag it taller to reach every control
                    // (references/ios-hosting.md).
                    .presentationCompactAdaptation(.sheet)
                    .presentationDetents([.height(320), .medium, .large],
                                         selection: $uiTuningLabDetent)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                // The agent path opens the lab once per launch.
                if UITuningLabLaunch.consumeRequest() { showUITuningLab = true }
            }
            #endif
    }

    #if DEBUG
    private func openUITuningLab() {
        showUITuningLab = true
    }
    #endif
}
```

<!-- file: UITuningLabLaunch.swift -->
```swift
import Foundation

#if DEBUG
/// The agent path: a DEBUG-only launch argument, honored once per launch.
/// Launch with `xcrun simctl launch booted <bundle-id> -UITuningLabOpen 1`.
@MainActor
enum UITuningLabLaunch {
    // Launch arguments land in the volatile argument domain, so the value
    // counts: `-UITuningLabOpen 0` keeps the lab closed.
    private static var pending = UserDefaults.standard.bool(forKey: "UITuningLabOpen")

    /// True only the first time it is read, so a rebuilt or re-pushed screen
    /// does not reopen the lab.
    static func consumeRequest() -> Bool {
        defer { pending = false }
        return pending
    }
}
#endif
```

The launch argument opens the lab once on launch; the toolbar Card Lab button is the
human path and the visible fallback (`references/activation.md`). Leave
`UITuningLabLaunch.swift` in place for either variant.

## Optional shake activation, only when shake is free

Use this variant only when inspection found no shake owner, no text input on the
screen, and one unambiguous lab (`references/activation.md`). It replaces the
toolbar button with a visible pill and adds the DEBUG-only responder shim; the
agent launch argument stays shared. Replace `FeatureScreen.swift`, add
`UITuningLabShake.swift`, and leave the launch, controls, and values files
unchanged.

<!-- file: FeatureScreen.swift variant=shake -->
```swift
import SwiftUI

struct FeatureScreen: View {
    @State private var style = CardStyle.appDefault
    #if DEBUG
    @State private var showUITuningLab = false
    @State private var uiTuningLabDetent = PresentationDetent.height(320)
    // The looks and the selected chip live beside the feature and outlive the
    // popover. To reopen a session, seed the finalists kept in the project here
    // (references/candidates.md).
    @StateObject private var uiTuningLabCandidates =
        UITuningLabCandidates<CardStyle>(baseline: .appDefault, initial: [])
    #endif

    var body: some View {
        CardFeature(style: style)
            #if DEBUG
            // Pin the pill to the full screen: the feature is only as tall as
            // its content, so an overlay on it alone can land mid-screen.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) {
                Button("Card Lab") { showUITuningLab = true }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.75), in: Capsule())
                    .padding()
                    .accessibilityLabel("Open UI tuning lab")
                    .disabled(showUITuningLab)
            }
            .background {
                UITuningLabShakeReader(isLabOpen: showUITuningLab) {
                    showUITuningLab = true
                }
                .frame(width: 0, height: 0)
            }
            .popover(isPresented: $showUITuningLab) {
                UITuningLabControls(style: $style, baseline: .appDefault)
                    .environmentObject(uiTuningLabCandidates)
                    .presentationCompactAdaptation(.sheet)
                    .presentationDetents([.height(320), .medium, .large],
                                         selection: $uiTuningLabDetent)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                // The agent path opens the lab once per launch.
                if UITuningLabLaunch.consumeRequest() { showUITuningLab = true }
            }
            #endif
    }
}
```

<!-- file: UITuningLabShake.swift variant=shake -->
```swift
#if DEBUG
#if canImport(UIKit)
import SwiftUI
import UIKit

/// A zero-sized first-responder shim for shake-to-open. It never takes focus
/// from another responder and re-arms after the lab closes.
struct UITuningLabShakeReader: UIViewControllerRepresentable {
    let isLabOpen: Bool
    let onShake: () -> Void

    func makeUIViewController(context: Context) -> UITuningLabShakeController {
        let controller = UITuningLabShakeController()
        controller.onShake = onShake
        controller.isLabOpen = isLabOpen
        return controller
    }

    func updateUIViewController(_ controller: UITuningLabShakeController, context: Context) {
        controller.onShake = onShake
        controller.isLabOpen = isLabOpen
        controller.armIfNeeded()
    }
}

final class UITuningLabShakeController: UIViewController {
    var onShake: (() -> Void)?
    var isLabOpen = false

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        armIfNeeded()
    }

    /// Becomes first responder only when nothing else owns focus, so it never
    /// takes focus from a text field, a focused control, or a key-command owner.
    func armIfNeeded(attempts: Int = 3) {
        guard !isLabOpen, !isFirstResponder, let window = view.window,
              window.uiTuningLabFirstResponder == nil else { return }
        if becomeFirstResponder() || attempts <= 1 { return }
        // A popover or sheet that is still dismissing can refuse the first try;
        // retry briefly after it settles. Bounded, so nothing keeps running.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.armIfNeeded(attempts: attempts - 1)
        }
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard motion == .motionShake, !isLabOpen, !uiTuningLabHasFocusedTextInput else {
            return super.motionEnded(motion, with: event)
        }
        onShake?()
    }

    private var uiTuningLabHasFocusedTextInput: Bool {
        guard let responder = view.window?.uiTuningLabFirstResponder else { return false }
        return responder is UITextInput
    }
}

private extension UIView {
    var uiTuningLabFirstResponder: UIResponder? {
        if isFirstResponder { return self }
        for subview in subviews {
            if let responder = subview.uiTuningLabFirstResponder { return responder }
        }
        return nil
    }
}
#endif
#endif
```

The shared launch argument opens the lab once on launch; the pill replaces the
toolbar button as the visible fallback, and the shim re-arms it after close. In
the Simulator, Device > Shake exercises the human path (give the user the
current keys, `references/activation.md`); `xcrun simctl
launch --terminate-running-process booted <bundle-id> -UITuningLabOpen 1`
exercises the agent path.

<!-- file: UITuningLabControls.swift -->
```swift
import SwiftUI

#if DEBUG
struct UITuningLabControls: View {
    @Binding var style: CardStyle
    let baseline: CardStyle
    // Owned by the host beside the feature, so the looks and the selection
    // survive closing and reopening the lab.
    @EnvironmentObject private var candidates: UITuningLabCandidates<CardStyle>
    @Environment(\.dismiss) private var dismiss
    @State private var sent: String?  // the last pick; set, the lab is one bar

    private static let compact = CardStyle(cornerRadius: 4, spacing: 4)
    private static let relaxed = CardStyle(cornerRadius: 24, spacing: 16)

    var body: some View {
        VStack {
            if let sent {
                // Apply collapses the lab to one bar; Change reopens it.
                HStack {
                    Text(candidates.applies > 1
                        ? "Copied land \(sent): paste it in chat so the agent applies it"
                        : "Applied: \(uiTuningLabChipLabel(sent))")
                    Spacer()
                    Button("Change") { self.sent = nil }
                    Button("Close") { dismiss() }
                }
                .padding()
                if let line = candidates.saved ?? candidates.status { Text(line).font(.footnote).padding(.horizontal) }
                Spacer(minLength: 0)
            } else {
                panel
            }
        }
        // Closing keeps the feature on the selected look, edits included, and
        // logs nothing: only a save does.
        .frame(minWidth: 280)
    }

    private var panel: some View {
        Form {
            HStack {
                Text("UI tuning lab").font(.headline)
                Spacer()
                Menu {
                    Button("Copy values") {
                        candidates.status = uiTuningLabCopyValues(from: baseline, to: candidates.selectedLook)
                    }
                } label: {
                    Text("⋯")
                }
                .accessibilityLabel("More")
                Button("Close") { dismiss() }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    chip("Shipped", id: "original")
                    ForEach(candidates.all) { pin in
                        HStack(spacing: 2) {
                            chip(pin.label, id: pin.name)
                            // × only on the selected look, so nothing is removed by accident.
                            if candidates.selected == pin.name {
                                Button("×") { style = candidates.remove(pin.name) }
                                    .accessibilityLabel("Remove \(pin.label)")
                            }
                        }
                    }
                }
                .padding(2)  // room for the selected chip's outline
            }
            HStack {
                Button("Compact") { edit(Self.compact, preset: "compact") }
                Button("Relaxed") { edit(Self.relaxed, preset: "relaxed") }
            }
            LabeledContent("Corner radius", value: "\(Int(style.cornerRadius)) pt")
                .accessibilityHidden(true)  // the slider reports its own value
            Slider(value: look("corner-radius").cornerRadius, in: 0...32, step: 1) {
                Text("Corner radius")
            }
            LabeledContent("Spacing", value: "\(Int(style.spacing)) pt")
                .accessibilityHidden(true)  // the slider reports its own value
            Slider(value: look("spacing").spacing, in: 0...24, step: 1) { Text("Spacing") }
            // Undo and Redo per look, back to its last save.
            HStack {
                Button("Undo") { style = candidates.undo() }
                    .disabled(!candidates.canUndo)
                Button("Redo") { style = candidates.redo() }
                    .disabled(!candidates.canRedo)
                Button("Reset") { style = candidates.reset() }
                    .disabled(!candidates.canReset)
            }
            HStack {
                // Save & pin keeps Shipped's edits as a new chip; Save keeps a
                // pinned look's edits. After the first Apply either one also hands
                // the pick over for pasting in chat.
                Button(candidates.saveTitle) {
                    let applied = candidates.applies > 0
                    if let name = candidates.save(), applied { sent = name }
                }
                .disabled(!candidates.canSave)
                Spacer()
                // Apply reaches the agent once; after that it is hidden for good.
                if candidates.applies == 0 {
                    Button("Apply") { sent = candidates.choose() }
                }
            }
            if let status = candidates.status { Text(status).font(.footnote) }
        }
        // Pinned below the scrolling controls, so it shows at every detent.
        .safeAreaInset(edge: .bottom) {
            Text(candidates.applies > 0
                ? "Save, then paste it in chat"
                : "Save & pin to keep a look · Apply to finish")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
        }
        // A Form row with several buttons fires all of them on iOS unless borderless.
        .buttonStyle(.borderless)
    }

    /// One chip. The selected chip is outlined and is the look the feature shows.
    private func chip(_ title: String, id: String) -> some View {
        let on = candidates.isOutlined(id)
        return Button(title) { style = candidates.select(id) }
            .buttonStyle(.bordered)
            .tint(on ? .accentColor : .secondary)
            .uiTuningLabSelected(on)
            .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// A slider shows the selected look and edits it; one drag is one Undo step.
    private func look(_ control: String) -> Binding<CardStyle> {
        Binding(get: { style }, set: { edit($0, control: control) })
    }

    /// Every control edits the selected look: a pinned look's edits until Save,
    /// or, on Shipped, unsaved changes until Save & pin.
    private func edit(_ value: CardStyle, preset: String? = nil, control: String? = nil) {
        candidates.edit(value, preset: preset, control: control)
        style = candidates.selectedLook
    }
}
#endif
```

<!-- copy: assets/swift/UITuningLabValues.swift -->
`UITuningLabValues.swift`: copy `assets/swift/UITuningLabValues.swift` into the
app's target unchanged. It holds Copy values, the looks store and selection, look names,
Apply with its result file, and the log lines every Swift lab shares,
all inside `#if DEBUG`.

Dismissal destroys `UITuningLabControls`; no timer, observer, or gesture
registration is created. Check iPhone compact and iPad regular-width behavior,
rotation, Dynamic Type, VoiceOver, Reduce Motion, focus, and the archived Release
product.

## Optional persistence, only when requested

The looks above are ephemeral. If the user explicitly requests persistence,
replace `UITuningLabControls.swift` with this version. `FeatureScreen.swift` stays
unchanged, and the envelope, writer, and loader stay development-only. Each look
is written as a `schemaVersion` 2 profile when it is saved (Save & pin, Save,
or Apply), never on an unsaved edit, and × deletes that look's file and nothing else. Opening the
lab adds every saved look as a chip, ordered by the `savedAt` of its first write
(which keeps fractional seconds) and then by name, and logs each one; the
baseline stays the declared default, so Shipped still shows it. Every stored
file name stays taken, even for a file that was skipped. A file that does not
decode, has another schema or platform, or has a name that differs from its file
or is not kebab-case is reported in the status line, skipped, and left untouched.

<!-- file: UITuningLabControls.swift variant=persist -->
```swift
import SwiftUI

#if DEBUG
/// A pinned look on disk: `<name>.json` in `directory`, `schemaVersion` 2
/// (references/config-schema.md).
struct UITuningLabProfile: Codable {
    var schemaVersion = 2
    var name: String
    var basedOn: String
    var platform = "ios"
    var container = "FeatureScreen.popover"
    var scope = ["appearance", "layout"]
    var savedAt: String  // ISO-8601 UTC with fractional seconds, ending in Z
    var overrides: CardStyle
    var notes = ""

    static var directory: URL {
        URL.applicationSupportDirectory
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

struct UITuningLabControls: View {
    @Binding var style: CardStyle
    let baseline: CardStyle
    // Owned by the host beside the feature, so the looks and the selection
    // survive closing and reopening the lab.
    @EnvironmentObject private var candidates: UITuningLabCandidates<CardStyle>
    @Environment(\.dismiss) private var dismiss
    @State private var sent: String?  // the last pick; set, the lab is one bar

    private static let compact = CardStyle(cornerRadius: 4, spacing: 4)
    private static let relaxed = CardStyle(cornerRadius: 24, spacing: 16)

    var body: some View {
        VStack {
            if let sent {
                // Apply collapses the lab to one bar; Change reopens it.
                HStack {
                    Text(candidates.applies > 1
                        ? "Copied land \(sent): paste it in chat so the agent applies it"
                        : "Applied: \(uiTuningLabChipLabel(sent))")
                    Spacer()
                    Button("Change") { self.sent = nil }
                    Button("Close") { dismiss() }
                }
                .padding()
                if let line = candidates.saved ?? candidates.status { Text(line).font(.footnote).padding(.horizontal) }
                Spacer(minLength: 0)
            } else {
                panel
            }
        }
        // Closing keeps the feature on the selected look, edits included, and
        // logs nothing: only a save does.
        .frame(minWidth: 280)
    }

    private var panel: some View {
        Form {
            HStack {
                Text("UI tuning lab").font(.headline)
                Spacer()
                Menu {
                    Button("Copy values") {
                        candidates.status = uiTuningLabCopyValues(from: baseline, to: candidates.selectedLook)
                    }
                } label: {
                    Text("⋯")
                }
                .accessibilityLabel("More")
                Button("Close") { dismiss() }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    chip("Shipped", id: "original")
                    ForEach(candidates.all) { pin in
                        HStack(spacing: 2) {
                            chip(pin.label, id: pin.name)
                            // × only on the selected look, so nothing is removed by accident.
                            if candidates.selected == pin.name {
                                Button("×") { style = candidates.remove(pin.name) }
                                    .accessibilityLabel("Remove \(pin.label)")
                            }
                        }
                    }
                }
                .padding(2)  // room for the selected chip's outline
            }
            HStack {
                Button("Compact") { edit(Self.compact, preset: "compact") }
                Button("Relaxed") { edit(Self.relaxed, preset: "relaxed") }
            }
            LabeledContent("Corner radius", value: "\(Int(style.cornerRadius)) pt")
                .accessibilityHidden(true)  // the slider reports its own value
            Slider(value: look("corner-radius").cornerRadius, in: 0...32, step: 1) {
                Text("Corner radius")
            }
            LabeledContent("Spacing", value: "\(Int(style.spacing)) pt")
                .accessibilityHidden(true)  // the slider reports its own value
            Slider(value: look("spacing").spacing, in: 0...24, step: 1) { Text("Spacing") }
            // Undo and Redo per look, back to its last save.
            HStack {
                Button("Undo") { style = candidates.undo() }
                    .disabled(!candidates.canUndo)
                Button("Redo") { style = candidates.redo() }
                    .disabled(!candidates.canRedo)
                Button("Reset") { style = candidates.reset() }
                    .disabled(!candidates.canReset)
            }
            HStack {
                // Save & pin keeps Shipped's edits as a new chip; Save keeps a
                // pinned look's edits. After the first Apply either one also hands
                // the pick over for pasting in chat.
                Button(candidates.saveTitle) {
                    let applied = candidates.applies > 0
                    if let name = candidates.save(), applied { sent = name }
                }
                .disabled(!candidates.canSave)
                Spacer()
                // Apply reaches the agent once; after that it is hidden for good.
                if candidates.applies == 0 {
                    Button("Apply") { sent = candidates.choose() }
                }
            }
            if let status = candidates.status { Text(status).font(.footnote) }
        }
        // Pinned below the scrolling controls, so it shows at every detent.
        .safeAreaInset(edge: .bottom) {
            Text(candidates.applies > 0
                ? "Save, then paste it in chat"
                : "Save & pin to keep a look · Apply to finish")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
        }
        // A Form row with several buttons fires all of them on iOS unless borderless.
        .buttonStyle(.borderless)
        .onAppear(perform: loadSaved)
    }

    /// One chip. The selected chip is outlined and is the look the feature shows.
    private func chip(_ title: String, id: String) -> some View {
        let on = candidates.isOutlined(id)
        return Button(title) { style = candidates.select(id) }
            .buttonStyle(.bordered)
            .tint(on ? .accentColor : .secondary)
            .uiTuningLabSelected(on)
            .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// A slider shows the selected look and edits it; one drag is one Undo step.
    private func look(_ control: String) -> Binding<CardStyle> {
        Binding(get: { style }, set: { edit($0, control: control) })
    }

    /// Every control edits the selected look: a pinned look's edits until Save,
    /// or, on Shipped, unsaved changes until Save & pin.
    private func edit(_ value: CardStyle, preset: String? = nil, control: String? = nil) {
        candidates.edit(value, preset: preset, control: control)
        style = candidates.selectedLook
    }

    /// Writes a look atomically. An existing file keeps its `savedAt`, so looks
    /// load in the order they were made.
    private func save(_ candidate: UITuningLabCandidate<CardStyle>) throws {
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
    /// or a name that differs from its file or is not kebab-case is reported and
    /// left untouched.
    private func loadSaved() {
        // A persisting lab writes each look whenever it is saved, and deletes it on ×.
        candidates.store = save
        candidates.unstore = { try FileManager.default.removeItem(at: UITuningLabProfile.fileURL($0)) }
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
                guard profile.schemaVersion == 2, profile.platform == "ios" else {
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

Each write replaces `<name>.json` under Application Support's
`.ui-tuning-lab/candidates/` atomically. A failed write shows in the status line;
the look stays in the lab and in the log.
