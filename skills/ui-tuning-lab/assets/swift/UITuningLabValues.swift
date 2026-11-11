import Foundation
import os
import SwiftUI
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

/// A look the lab holds (references/candidates.md): a pinned look with its
/// saved version. Edits made since the last save live in the store, not here.
/// It lives in memory, and in storage only when the lab persists it.
struct UITuningLabCandidate<Value: Codable>: Identifiable {
    var name: String     // `brass-1`, `custom-2`, ...; a kept finalist keeps its name
    var basedOn: String  // a preset's (or design's) kebab-case key, or `baseline`
    var value: Value     // the saved version
    var id: String { name }
    /// The chip's label: `Brass-2` for `brass-2`, `Warm Glow-1` for `warm-glow-1`.
    var label: String { uiTuningLabChipLabel(name) }
}

/// `Brass-2` for `brass-2`, `Warm Glow-1` for `warm-glow-1`; a name that does
/// not end in `-N` as it is.
func uiTuningLabChipLabel(_ name: String) -> String {
    guard let dash = name.lastIndex(of: "-"), let number = Int(name[name.index(after: dash)...]),
          dash > name.startIndex else { return name }
    let words = name[..<dash].split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }
    return "\(words.joined(separator: " "))-\(number)"
}

/// One point in a look's history: what it showed, and where it came from.
private struct UITuningLabStep<Value> {
    var value: Value
    var basedOn: String
}

/// The looks, oldest first, and the selected chip, owned beside the feature so
/// they survive closing the lab. The feature always shows the selected look.
/// Shipped (`original`) is read-only: an edit on it shows live as unsaved
/// changes, outlining no chip, until Save & pin keeps it as a new look named
/// after its preset (`brass-1`); tapping a chip first drops them. A pinned look
/// keeps its saved version plus the edits made since, which stay with it when
/// the user switches away, until Save. Each look has its own Undo and Redo
/// history back to its last save, and Reset. Lines the agent can replay:
/// `UITUNINGLAB_CANDIDATE {...}` whenever a look is saved, and
/// `UITUNINGLAB_CANDIDATE_REMOVED {...}`.
@MainActor
final class UITuningLabCandidates<Value: Codable & Equatable>: ObservableObject {
    @Published private(set) var all: [UITuningLabCandidate<Value>] = []
    /// The selected chip: `original` for Shipped, or a look's name.
    @Published private(set) var selected = "original"
    /// Edits made on Shipped and not pinned yet; while set, no chip is outlined.
    @Published private(set) var unsaved: Value?
    /// What the last action reported, for the panel's status line.
    @Published var status: String?
    /// How many times a pick reached the agent. The first Apply reaches its
    /// waiter; after it the agent no longer listens, so Apply hides and Save &
    /// pin and Save also hand the pick over, for the user to paste as
    /// `land <name>`. Change does not reset it; it lives as long as the lab's
    /// candidates.
    @Published private(set) var applies = 0
    /// The result bar's second line after a pick: where it was saved, or nil
    /// when the write failed (then `status` says why).
    @Published private(set) var saved: String?
    /// Each pinned look's edits since its last save, by name.
    @Published private var drafts: [String: Value] = [:]
    /// Undo and Redo steps per look (`original` for Shipped), back to its last save.
    @Published private var undoSteps: [String: [UITuningLabStep<Value>]] = [:]
    @Published private var redoSteps: [String: [UITuningLabStep<Value>]] = [:]
    let baseline: Value
    /// Set by a persisting lab: writes a look's profile whenever it is saved
    /// (Save & pin, Save, Apply), and deletes it on remove. A failure shows in
    /// `status`; the look stays.
    var store: ((UITuningLabCandidate<Value>) throws -> Void)?
    var unstore: ((String) throws -> Void)?
    private var taken: Set<String> = []  // every name issued or reserved this run
    private var unsavedBasedOn = "baseline"
    private var lastControl: [String: String] = [:]  // the control of each look's newest step
    private var storeError: String?  // a failed profile write during the current save
    private var logged: [String: String] = [:]  // the line each look last logged

    /// Seed with finalists kept in the project to reopen a session; empty by default.
    init(baseline: Value, initial: [UITuningLabCandidate<Value>] = []) {
        self.baseline = baseline
        for candidate in initial { adopt(candidate) }
    }

    func named(_ name: String) -> UITuningLabCandidate<Value>? {
        all.first { $0.name == name }
    }

    var selectedPin: UITuningLabCandidate<Value>? { named(selected) }

    /// The look the feature shows: the selected look with its edits, else
    /// unsaved edits on Shipped, else the baseline.
    var selectedLook: Value {
        if let pin = selectedPin { return drafts[pin.name] ?? pin.value }
        return unsaved ?? baseline
    }

    /// Whether a chip is outlined: false while Shipped has unsaved edits.
    func isOutlined(_ name: String) -> Bool { name == selected && (name != "original" || unsaved == nil) }

    /// Whether the selected look has edits since its last save.
    var hasEdits: Bool { selectedPin == nil ? unsaved != nil : drafts[selected] != nil }

    /// The save button's label: Save & pin on Shipped, Save on a pinned look.
    var saveTitle: String { selectedPin == nil ? "Save & pin" : "Save" }

    /// Save & pin needs edits on Shipped. Save needs edits until the first
    /// Apply; after it, Save is how a pick reaches the chat, so it stays enabled.
    var canSave: Bool { selectedPin == nil ? unsaved != nil : hasEdits || applies > 0 }
    var canUndo: Bool { !(undoSteps[selected] ?? []).isEmpty }
    var canRedo: Bool { !(redoSteps[selected] ?? []).isEmpty }
    var canReset: Bool { hasEdits }

    /// Marks names as used, such as every file in storage, so no look takes them.
    func reserve(_ names: some Sequence<String>) { taken.formUnion(names) }

    /// Selects a chip and returns the look the feature must now show. Unsaved
    /// edits on Shipped are dropped, so Shipped always shows the baseline; a
    /// pinned look keeps its edits.
    @discardableResult
    func select(_ name: String) -> Value {
        guard name != selected || unsaved != nil else { return selectedLook }
        lastControl[selected] = nil  // a drag after coming back is its own step
        clearHistory("original")
        unsaved = nil
        unsavedBasedOn = "baseline"
        selected = named(name) == nil ? "original" : name
        return selectedLook
    }

    /// Every control edits the selected look: on Shipped as unsaved edits, on
    /// a pinned look as edits on top of its saved version. A preset (or, in a
    /// lab with designs, a design) becomes its `basedOn`. Pass `control`, the
    /// control's key, for sliders and steppers: a run of edits from the same
    /// control in a row is one Undo step. Presets pass none, so each is a step.
    func edit(_ value: Value, preset: String? = nil, design: String? = nil, control: String? = nil) {
        let current = step
        guard value != current.value || (preset ?? design).map({ $0 != current.basedOn }) == true else { return }
        if control == nil || control != lastControl[selected] || !canUndo {
            undoSteps[selected, default: []].append(current)
        }
        redoSteps[selected] = nil
        lastControl[selected] = control
        apply(UITuningLabStep(value: value, basedOn: preset ?? design ?? current.basedOn))
    }

    /// Undo: steps the selected look back one edit, never past its last save.
    /// Returns the look the feature must now show.
    @discardableResult
    func undo() -> Value {
        guard let previous = undoSteps[selected]?.popLast() else { return selectedLook }
        redoSteps[selected, default: []].append(step)
        lastControl[selected] = nil
        apply(previous)
        return selectedLook
    }

    /// Redo: brings back the edit Undo last took away.
    @discardableResult
    func redo() -> Value {
        guard let next = redoSteps[selected]?.popLast() else { return selectedLook }
        undoSteps[selected, default: []].append(step)
        lastControl[selected] = nil
        apply(next)
        return selectedLook
    }

    /// Reset: takes the selected look back to its last save (Shipped: the
    /// baseline) in one step that Undo can take back.
    @discardableResult
    func reset() -> Value {
        guard hasEdits else { return selectedLook }
        undoSteps[selected, default: []].append(step)
        redoSteps[selected] = nil
        lastControl[selected] = nil
        if let pin = selectedPin {
            apply(UITuningLabStep(value: pin.value, basedOn: pin.basedOn))
        } else {
            apply(UITuningLabStep(value: baseline, basedOn: "baseline"))
        }
        return selectedLook
    }

    /// The Shipped value of one field: what its default marker, caption, or
    /// swatch shows on every chip, pinned looks included.
    func defaultValue<Field>(_ field: KeyPath<Value, Field>) -> Field { baseline[keyPath: field] }

    /// Whether the selected look shows the Shipped value of a field; its ↺
    /// shows only when this is false.
    func isDefault<Field: Equatable>(_ field: KeyPath<Value, Field>) -> Bool {
        selectedLook[keyPath: field] == baseline[keyPath: field]
    }

    /// ↺ on one control: `restore` copies that control's fields from Shipped
    /// (its second argument) into the look; a spring's two sliders go together,
    /// whatever their types. An ordinary edit: one Undo step that ends the
    /// current slider run, so it never merges with a drag. On Shipped, a look
    /// that matches the baseline again has no unsaved edits; on a pinned look
    /// it is an edit that Save keeps. Returns the look the feature must now show.
    @discardableResult
    func resetControl(_ restore: (inout Value, Value) -> Void) -> Value {
        var value = selectedLook
        restore(&value, baseline)
        edit(value)
        return selectedLook
    }

    /// ↺ on one control whose fields share a type, such as a spring's duration
    /// and bounce: `resetControl(\.duration, \.bounce)`.
    @discardableResult
    func resetControl<Field>(_ fields: WritableKeyPath<Value, Field>...) -> Value {
        resetControl { look, shipped in
            for field in fields { look[keyPath: field] = shipped[keyPath: field] }
        }
    }

    /// Removes a look and returns the look the feature must now show.
    @discardableResult
    func remove(_ name: String) -> Value {
        guard let look = named(name) else { return selectedLook }
        do { try unstore?(name) } catch {
            status = "\(look.label) not removed: \(error.localizedDescription)"
            return selectedLook
        }
        all.removeAll { $0.name == name }
        drafts[name] = nil
        clearHistory(name)
        logged[name] = nil
        uiTuningLabLogLine("UITUNINGLAB_CANDIDATE_REMOVED", ["name": name])
        if selected == name { selected = "original" }
        status = "Removed \(look.label)"
        return selectedLook
    }

    /// Adds a seeded or stored look and logs it, without storing it again.
    /// Returns false when the name is already in the list.
    @discardableResult
    func adopt(_ candidate: UITuningLabCandidate<Value>) -> Bool {
        taken.insert(candidate.name)
        guard named(candidate.name) == nil else { return false }
        all.append(candidate)
        log(candidate, storing: false)
        return true
    }

    /// Save & pin on Shipped (its edits become a new look named after its
    /// preset, and it is selected) or Save on a pinned look (its edits become
    /// its saved version); either way copies `land <name>` and starts a fresh
    /// history. Before the first Apply that is all: the agent's waiter is
    /// listening, so no Done line is sent. After it, it also hands the pick
    /// over like Apply, since the user pastes it in chat. Returns the look's
    /// name, or nil when there is nothing to save.
    @discardableResult
    func save() -> String? {
        guard canSave else { return nil }
        let pinned = commit()
        guard let look = selectedPin else { return nil }
        if applies > 0 { return choose() }
        uiTuningLabCopy("land \(look.name)")
        saved = nil
        status = storeError ?? "\(pinned ? "Pinned" : "Saved") \(look.label) · copied land \(look.name)"
        return look.name
    }

    /// Apply: saves first (unsaved edits on Shipped are pinned, a selected
    /// look's edits saved), then picks the selected chip, `original` for
    /// Shipped. Logs `UITUNINGLAB_DONE {...}`, hands it to the agent's waiter,
    /// replaces the result file atomically, and copies `land <winner>`. Returns
    /// the winner, or nil when the pick could not be made; sets `status` when
    /// part of that did not work.
    @discardableResult
    func choose() -> String? {
        commit()
        let winner = selectedPin?.name ?? "original"
        let label = selectedPin?.label ?? "Shipped"
        let line: [String: Any]
        do {
            let values = try uiTuningLabChangedFields(from: baseline, to: selectedLook)
            let kept = try all.map { try uiTuningLabCandidateFields($0, baseline: baseline) }
            line = ["candidates": kept, "values": values, "winner": winner]
        } catch {
            saved = nil
            status = "Not applied: \(error.localizedDescription)"
            return nil
        }
        applies += 1
        uiTuningLabLogLine("UITUNINGLAB_DONE", line)
        uiTuningLabSendPick(line)
        uiTuningLabCopy("land \(winner)")
        var result = line
        result["savedAt"] = ISO8601DateFormatter.uiTuningLabSavedAt.string(from: .now)
        do {
            let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            try FileManager.default.createDirectory(
                at: uiTuningLabResultURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: uiTuningLabResultURL, options: .atomic)  // temporary file, then rename
            status = storeError
            saved = "Saved \(label) in .ui-tuning-lab/result.json"
        } catch {
            saved = nil
            status = "Result file not written: \(error.localizedDescription)"
        }
        return winner
    }

    /// What the selected look shows now, as a history step.
    private var step: UITuningLabStep<Value> {
        UITuningLabStep(value: selectedLook, basedOn: selectedPin?.basedOn ?? unsavedBasedOn)
    }

    /// Shows a step on the selected look. Matching the last save leaves no edits.
    private func apply(_ step: UITuningLabStep<Value>) {
        if let index = all.firstIndex(where: { $0.name == selected }) {
            all[index].basedOn = step.basedOn
            drafts[selected] = step.value == all[index].value ? nil : step.value
        } else if step.value == baseline {
            unsaved = nil
            unsavedBasedOn = "baseline"
        } else {
            unsaved = step.value
            unsavedBasedOn = step.basedOn
        }
    }

    private func clearHistory(_ name: String) {
        undoSteps[name] = nil
        redoSteps[name] = nil
        lastControl[name] = nil
    }

    /// Keeps the selected look's edits: unsaved edits on Shipped become a new
    /// look, selected; a pinned look's edits become its saved version. Logs a
    /// look that changed. Returns true when it pinned a new look.
    @discardableResult
    private func commit() -> Bool {
        storeError = nil
        if let index = all.firstIndex(where: { $0.name == selected }) {
            if let draft = drafts[selected] { all[index].value = draft }
            drafts[selected] = nil
            clearHistory(selected)
            log(all[index])
            return false
        }
        guard let value = unsaved else { return false }
        let prefix = unsavedBasedOn == "baseline" ? "custom" : unsavedBasedOn
        let used = taken.compactMap { name -> Int? in
            guard name.hasPrefix(prefix + "-") else { return nil }
            return Int(name.dropFirst(prefix.count + 1))
        }
        let name = "\(prefix)-\((used.max() ?? 0) + 1)"
        let candidate = UITuningLabCandidate(name: name, basedOn: unsavedBasedOn, value: value)
        taken.insert(name)
        all.append(candidate)
        selected = name
        unsaved = nil
        unsavedBasedOn = "baseline"
        clearHistory("original")
        log(candidate)
        return true
    }

    private func log(_ candidate: UITuningLabCandidate<Value>, storing: Bool = true) {
        guard let fields = try? uiTuningLabCandidateFields(candidate, baseline: baseline),
              let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8),
              logged[candidate.name] != line else { return }
        logged[candidate.name] = line
        uiTuningLabLogLine("UITUNINGLAB_CANDIDATE", fields)
        guard storing, let store else { return }
        do { try store(candidate) } catch {
            storeError = "\(candidate.label) not saved: \(error.localizedDescription)"
            status = storeError
        }
    }
}

private func uiTuningLabCopy(_ text: String) {
    #if canImport(UIKit)
    UIPasteboard.general.string = text
    #elseif canImport(AppKit)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    #endif
}

/// The pick Apply writes: Application Support `.ui-tuning-lab/result.json`,
/// under the bundle ID on macOS, where every app shares Application Support.
var uiTuningLabResultURL: URL {
    var directory = URL.applicationSupportDirectory
    #if os(macOS)
    directory = directory.appending(
        path: Bundle.main.bundleIdentifier ?? "ui-tuning-lab", directoryHint: .isDirectory)
    #endif
    return directory.appending(path: ".ui-tuning-lab", directoryHint: .isDirectory)
        .appending(path: "result.json")
}

extension ISO8601DateFormatter {
    /// ISO-8601 UTC with fractional seconds, ending in Z.
    static var uiTuningLabSavedAt: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
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

/// Hands the pick to the agent's waiter (`scripts/wait-for-pick.py`) the moment
/// Apply is pressed, so the agent resumes without a message. Fire and forget:
/// with no waiter, or no route to the host (a physical device, a sandboxed Mac
/// app without the network client entitlement), the log and the result file
/// still carry the pick. `localhost`, not an IP address: ATS blocks plain HTTP
/// to IP addresses from iOS 17 and macOS 14.
private func uiTuningLabSendPick(_ object: [String: Any]) {
    guard let json = try? uiTuningLabJSON(object),
          let url = URL(string: "http://localhost:47321/pick") else { return }
    var request = URLRequest(url: url, timeoutInterval: 2)
    request.httpMethod = "POST"
    request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data("UITUNINGLAB_DONE \(json)".utf8)
    URLSession.shared.dataTask(with: request).resume()
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

/// Whether a drag lands on a slider's Shipped value: within 1.5% of the
/// range, or less than half a step, so the grid values on either side never
/// snap and stay reachable. Only a drag snaps; arrow keys, steppers, and
/// VoiceOver's adjustable action never do. The Shipped value must sit on the
/// slider's grid: pick a step that divides it, or a continuous slider.
func uiTuningLabSnaps(_ value: Double, to shipped: Double, in range: ClosedRange<Double>, step: Double = 0) -> Bool {
    let distance = abs(value - shipped)
    return distance <= (range.upperBound - range.lowerBound) * 0.015 || distance < step / 2
}

/// A slider value as the panel shows it: at most two decimals, none when whole
/// (`12`, `12.5`, `0.35`).
func uiTuningLabNumber(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
}

/// A slider's readout: `14 pt · default 12` while it differs from Shipped,
/// `12 pt` when it matches. Hide it from assistive technology, like the plain
/// readout: the slider reports its own value.
func uiTuningLabReadout(_ value: Double, shipped: Double, unit: String = "") -> String {
    let now = unit.isEmpty ? uiTuningLabNumber(value) : "\(uiTuningLabNumber(value)) \(unit)"
    return value == shipped ? now : "\(now) · default \(uiTuningLabNumber(shipped))"
}

extension View {
    /// Marks a slider's Shipped value with a short tick just under the track,
    /// shown on every chip. Sliders have no API for one tick at an arbitrary
    /// value, so it is drawn over the slider; `thumbInset`, half the thumb's
    /// width, keeps it under the thumb's center at that value (measure it on
    /// the OS you run). Display only: it is never part of a look.
    func uiTuningLabDefaultTick(at shipped: Double, in range: ClosedRange<Double>, thumbInset: CGFloat? = nil) -> some View {
        #if os(macOS)
        let inset = thumbInset ?? 10
        #else
        let inset = thumbInset ?? 14
        #endif
        let fraction = (shipped - range.lowerBound) / (range.upperBound - range.lowerBound)
        return overlay(alignment: .topLeading) {
            GeometryReader { proxy in
                Capsule()
                    .fill(.secondary)
                    .frame(width: 2, height: 6)
                    .offset(x: inset + (proxy.size.width - 2 * inset) * fraction - 1, y: proxy.size.height / 2 + 4)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Outlines a selected chip or preset, so it reads as selected without a
    /// label: a 2 pt accent ring around the control.
    func uiTuningLabSelected(_ on: Bool) -> some View {
        overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color.accentColor, lineWidth: on ? 2 : 0))
    }
}
#endif
