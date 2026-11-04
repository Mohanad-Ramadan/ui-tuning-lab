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
the Simulator, Device > Shake (⌃⌘Z) exercises the human path; `xcrun simctl
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

Dismissal destroys `UITuningLabControls`; no timer, observer, or gesture
registration is created. Validate iPhone compact and iPad regular-width behavior,
rotation, Dynamic Type, VoiceOver, Reduce Motion, focus, and the archived Release
product before changing the receipt from pending.

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
