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
**Keep as candidate**, the candidates list (Load, Remove), **Compare**, and
**Done** follow `references/candidates.md`. The host owns the
`UITuningLabCandidates` store beside the draft, so candidates and `basedOn`
survive closing the popover; they live in memory and in the log only, and a
name is never reused within a run. Compare shares the Show baseline stash, and
while either shows something other than the draft the editing controls, Keep,
Reset, Copy values, and Load are disabled. Done is disabled only while Show
baseline is on; while Compare shows a candidate, Done loads it into the draft
first, so it is the winner. Closing the lab restores the draft. The finish hint
is pinned below the scrolling Form, so it shows at the smallest detent. To
reopen a session, seed the store's `initial:` array; each seeded candidate logs
its own `UITUNINGLAB_CANDIDATE` line.

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
    // Candidates and basedOn live beside the draft and outlive the popover. To
    // reopen a session, seed the finalists kept in the project here
    // (references/candidates.md).
    @StateObject private var uiTuningLabCandidates =
        UITuningLabCandidates<CardStyle>(baseline: .appDefault, initial: [])
    #endif

    var body: some View {
        CardFeature(style: style)
            #if DEBUG
            .toolbar {
                Button("Tune", action: openUITuningLab)
                    .disabled(showUITuningLab)
            }
            .popover(isPresented: $showUITuningLab) {
                // The declared default, never the value on screen at open: a draft
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

The launch argument opens the lab once on launch; the toolbar Tune button is the
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
    // Candidates and basedOn live beside the draft and outlive the popover. To
    // reopen a session, seed the finalists kept in the project here
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
                Button("Tune") { showUITuningLab = true }
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
    // Owned by the host beside the draft, so candidates and basedOn survive
    // closing and reopening the lab.
    @EnvironmentObject private var candidates: UITuningLabCandidates<CardStyle>
    @Environment(\.dismiss) private var dismiss
    @State private var status: String?
    @State private var stashedDraft: CardStyle?  // set while the baseline or a candidate is shown
    @State private var comparing: String?       // the candidate Compare shows, nil for the draft

    private static let compact = CardStyle(cornerRadius: 4, spacing: 4)
    private static let relaxed = CardStyle(cornerRadius: 24, spacing: 16)

    var body: some View {
        Form {
            Button("Close") { dismiss() }
            Toggle("Show baseline", isOn: showingBaseline)
            if !candidates.all.isEmpty {
                Picker("Compare", selection: comparedCandidate) {
                    Text("Draft").tag(String?.none)
                    ForEach(candidates.all) { Text($0.name).tag(Optional($0.name)) }
                }
            }
            Group {
                HStack {
                    Button("Compact") { style = Self.compact; candidates.basedOn = "compact" }
                    Button("Relaxed") { style = Self.relaxed; candidates.basedOn = "relaxed" }
                }
                LabeledContent("Corner radius", value: "\(Int(style.cornerRadius)) pt")
                    .accessibilityHidden(true)  // the slider reports its own value
                Slider(value: $style.cornerRadius, in: 0...32, step: 1) {
                    Text("Corner radius")
                }
                LabeledContent("Spacing", value: "\(Int(style.spacing)) pt")
                    .accessibilityHidden(true)  // the slider reports its own value
                Slider(value: $style.spacing, in: 0...24, step: 1) { Text("Spacing") }
                HStack {
                    Button("Reset") { style = baseline; candidates.basedOn = "baseline" }
                    Button("Copy values") {
                        status = uiTuningLabCopyValues(from: baseline, to: style)
                    }
                }
            }
            .disabled(stashedDraft != nil)
            HStack {
                Button("Keep as candidate", action: keep)
                    .disabled(stashedDraft != nil)
                // While Compare shows a candidate, Done lands that candidate.
                Button("Done", action: done)
                    .disabled(stashedDraft != nil && comparing == nil)
            }
            if !candidates.all.isEmpty {
                Section("Candidates") {
                    ForEach(candidates.all) { candidate in
                        HStack {
                            Text("\(candidate.name), from \(candidate.basedOn)")
                            Spacer()
                            Button("Load") { load(candidate) }
                                .accessibilityLabel("Load \(candidate.name)")
                                .disabled(stashedDraft != nil)
                            Button("Remove") { remove(candidate.name) }
                                .accessibilityLabel("Remove \(candidate.name)")
                        }
                    }
                }
            }
            if let status { Text(status).font(.footnote) }
        }
        // Pinned below the scrolling controls, so it shows at every detent.
        .safeAreaInset(edge: .bottom) {
            Text("Finished? Keep the ones you like, then press Done, or tell the agent \"land b\".")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
        }
        .frame(minWidth: 280)
        // A Form row with several buttons fires all of them on iOS unless borderless.
        .buttonStyle(.borderless)
        // Never leave the feature showing the baseline or a candidate once the lab is gone.
        .onDisappear { if let stashedDraft { style = stashedDraft } }
    }

    /// Shows the baseline in the real feature; turning it off restores the draft.
    private var showingBaseline: Binding<Bool> {
        Binding(
            get: { stashedDraft != nil && comparing == nil },
            set: { show in
                comparing = nil
                if show {
                    if stashedDraft == nil { stashedDraft = style }
                    style = baseline
                } else if let draft = stashedDraft {
                    style = draft
                    stashedDraft = nil
                }
            }
        )
    }

    /// Shows a candidate in the real feature, sharing the baseline's stash;
    /// Draft restores the draft.
    private var comparedCandidate: Binding<String?> {
        Binding(
            get: { comparing },
            set: { name in
                if let name, let candidate = candidates.named(name) {
                    if stashedDraft == nil { stashedDraft = style }
                    style = candidate.value
                    comparing = name
                } else {
                    if let draft = stashedDraft { style = draft }
                    stashedDraft = nil
                    comparing = nil
                }
            }
        )
    }

    private func keep() {
        do {
            let kept = try candidates.keep(style)
            status = "Kept \(kept.name)"
        } catch {
            status = error.localizedDescription
        }
    }

    private func done() {
        // The candidate on screen becomes the draft, so it is the winner.
        var draft = style
        if let name = comparing, let candidate = candidates.named(name) {
            stashedDraft = nil
            comparing = nil
            load(candidate)
            draft = candidate.value
        }
        status = candidates.done(draft)
    }

    private func load(_ candidate: UITuningLabCandidate<CardStyle>) {
        style = candidate.value
        candidates.basedOn = candidate.name
        status = "Loaded \(candidate.name)"
    }

    private func remove(_ name: String) {
        if comparing == name { comparedCandidate.wrappedValue = nil }
        candidates.remove(name)
        status = "Removed \(name)"
    }
}
#endif
```

<!-- copy: assets/swift/UITuningLabValues.swift -->
`UITuningLabValues.swift`: copy `assets/swift/UITuningLabValues.swift` into the
app's target unchanged. It holds Copy values, the candidate store, candidate
names, and the log lines every Swift lab shares, all inside `#if DEBUG`.

Dismissal destroys `UITuningLabControls`; no timer, observer, or gesture
registration is created. Check iPhone compact and iPad regular-width behavior,
rotation, Dynamic Type, VoiceOver, Reduce Motion, focus, and the archived Release
product.

## Optional persistence, only when requested

The candidate above is ephemeral. If the user explicitly requests persistence,
replace `UITuningLabControls.swift` with this version. `FeatureScreen.swift` stays
unchanged, and the envelope, writer, and loader stay development-only. Each Keep
also writes the candidate as a `schemaVersion` 2 profile, and Remove deletes that
candidate's file and nothing else. Opening the lab adds every saved candidate to
the list, ordered by `savedAt` (which keeps fractional seconds) and then by name,
and logs each one; Load applies its overrides to the draft, and the baseline
stays the declared default, so Reset still returns to it. Every stored file name
stays taken, even for a file that was skipped. A file that does not decode, has
another schema or platform, has a name that differs from its file or is not
kebab-case, or now matches the baseline is reported in the status line, skipped,
and left untouched.

<!-- file: UITuningLabControls.swift variant=persist -->
```swift
import SwiftUI

#if DEBUG
/// A kept candidate on disk: `<name>.json` in `directory`, `schemaVersion` 2
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
    // Owned by the host beside the draft, so candidates and basedOn survive
    // closing and reopening the lab.
    @EnvironmentObject private var candidates: UITuningLabCandidates<CardStyle>
    @Environment(\.dismiss) private var dismiss
    @State private var status: String?
    @State private var stashedDraft: CardStyle?  // set while the baseline or a candidate is shown
    @State private var comparing: String?       // the candidate Compare shows, nil for the draft

    private static let compact = CardStyle(cornerRadius: 4, spacing: 4)
    private static let relaxed = CardStyle(cornerRadius: 24, spacing: 16)

    var body: some View {
        Form {
            Button("Close") { dismiss() }
            Toggle("Show baseline", isOn: showingBaseline)
            if !candidates.all.isEmpty {
                Picker("Compare", selection: comparedCandidate) {
                    Text("Draft").tag(String?.none)
                    ForEach(candidates.all) { Text($0.name).tag(Optional($0.name)) }
                }
            }
            Group {
                HStack {
                    Button("Compact") { style = Self.compact; candidates.basedOn = "compact" }
                    Button("Relaxed") { style = Self.relaxed; candidates.basedOn = "relaxed" }
                }
                LabeledContent("Corner radius", value: "\(Int(style.cornerRadius)) pt")
                    .accessibilityHidden(true)  // the slider reports its own value
                Slider(value: $style.cornerRadius, in: 0...32, step: 1) {
                    Text("Corner radius")
                }
                LabeledContent("Spacing", value: "\(Int(style.spacing)) pt")
                    .accessibilityHidden(true)  // the slider reports its own value
                Slider(value: $style.spacing, in: 0...24, step: 1) { Text("Spacing") }
                HStack {
                    Button("Reset") { style = baseline; candidates.basedOn = "baseline" }
                    Button("Copy values") {
                        status = uiTuningLabCopyValues(from: baseline, to: style)
                    }
                }
            }
            .disabled(stashedDraft != nil)
            HStack {
                Button("Keep as candidate", action: keep)
                    .disabled(stashedDraft != nil)
                // While Compare shows a candidate, Done lands that candidate.
                Button("Done", action: done)
                    .disabled(stashedDraft != nil && comparing == nil)
            }
            if !candidates.all.isEmpty {
                Section("Candidates") {
                    ForEach(candidates.all) { candidate in
                        HStack {
                            Text("\(candidate.name), from \(candidate.basedOn)")
                            Spacer()
                            Button("Load") { load(candidate) }
                                .accessibilityLabel("Load \(candidate.name)")
                                .disabled(stashedDraft != nil)
                            Button("Remove") { remove(candidate.name) }
                                .accessibilityLabel("Remove \(candidate.name)")
                        }
                    }
                }
            }
            if let status { Text(status).font(.footnote) }
        }
        // Pinned below the scrolling controls, so it shows at every detent.
        .safeAreaInset(edge: .bottom) {
            Text("Finished? Keep the ones you like, then press Done, or tell the agent \"land b\".")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
        }
        .frame(minWidth: 280)
        // A Form row with several buttons fires all of them on iOS unless borderless.
        .buttonStyle(.borderless)
        // Never leave the feature showing the baseline or a candidate once the lab is gone.
        .onDisappear { if let stashedDraft { style = stashedDraft } }
        .onAppear(perform: loadSaved)
    }

    /// Shows the baseline in the real feature; turning it off restores the draft.
    private var showingBaseline: Binding<Bool> {
        Binding(
            get: { stashedDraft != nil && comparing == nil },
            set: { show in
                comparing = nil
                if show {
                    if stashedDraft == nil { stashedDraft = style }
                    style = baseline
                } else if let draft = stashedDraft {
                    style = draft
                    stashedDraft = nil
                }
            }
        )
    }

    /// Shows a candidate in the real feature, sharing the baseline's stash;
    /// Draft restores the draft.
    private var comparedCandidate: Binding<String?> {
        Binding(
            get: { comparing },
            set: { name in
                if let name, let candidate = candidates.named(name) {
                    if stashedDraft == nil { stashedDraft = style }
                    style = candidate.value
                    comparing = name
                } else {
                    if let draft = stashedDraft { style = draft }
                    stashedDraft = nil
                    comparing = nil
                }
            }
        )
    }

    private func keep() {
        do {
            let kept = try candidates.keep(style, store: save)
            status = "Kept \(kept.name)"
        } catch {
            status = error.localizedDescription
        }
    }

    private func done() {
        // The candidate on screen becomes the draft, so it is the winner.
        var draft = style
        if let name = comparing, let candidate = candidates.named(name) {
            stashedDraft = nil
            comparing = nil
            load(candidate)
            draft = candidate.value
        }
        status = candidates.done(draft)
    }

    private func load(_ candidate: UITuningLabCandidate<CardStyle>) {
        style = candidate.value
        candidates.basedOn = candidate.name
        status = "Loaded \(candidate.name)"
    }

    private func remove(_ name: String) {
        if comparing == name { comparedCandidate.wrappedValue = nil }
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
    private func save(_ candidate: UITuningLabCandidate<CardStyle>) throws {
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

Keep atomically writes `<name>.json` under Application Support's
`.ui-tuning-lab/candidates/` after checking that the file does not exist. A write
failure refuses the Keep: the status line shows the error, and the candidate is
neither added nor logged.
