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

/// A look the lab holds (references/candidates.md): a saved look the controls
/// edit in place while it is selected. It lives in memory, and in storage only
/// when the lab persists it.
struct UITuningLabCandidate<Value: Codable>: Identifiable {
    var name: String     // `look-1`, `look-2`, ...; a kept finalist keeps its name
    var basedOn: String  // a preset's kebab-case name, or `baseline`
    var value: Value
    var id: String { name }
    /// The chip's label: `Look 2` for `look-2`, else the name.
    var label: String { uiTuningLabChipLabel(name) }
}

/// `Look 2` for `look-2`; any other name as it is.
func uiTuningLabChipLabel(_ name: String) -> String {
    guard name.hasPrefix("look-"), let number = Int(name.dropFirst(5)) else { return name }
    return "Look \(number)"
}

/// The looks, oldest first, and the selected chip, owned beside the feature so
/// they survive closing the lab. The feature always shows the selected look.
/// Shipped (`original`) is read-only: an edit on it shows live as unsaved
/// changes, outlining no chip, until Save & copy keeps it as the next
/// `Look N`; tapping a chip first drops them. A saved look changes in place and
/// keeps its edits when the user switches away. Lines the agent can replay:
/// `UITUNINGLAB_CANDIDATE {...}` when a look is saved and again when an edited
/// look is left, and `UITUNINGLAB_CANDIDATE_REMOVED {...}`.
@MainActor
final class UITuningLabCandidates<Value: Codable>: ObservableObject {
    @Published private(set) var all: [UITuningLabCandidate<Value>] = []
    /// The selected chip: `original` for Shipped, or a look's name.
    @Published private(set) var selected = "original"
    /// Edits made on Shipped and not saved yet; while set, no chip is outlined.
    @Published private(set) var unsaved: Value?
    /// What the last action reported, for the panel's status line.
    @Published var status: String?
    /// How many times a pick reached the agent. The first Apply reaches its
    /// waiter; after it the agent no longer listens, so Apply hides and Save &
    /// copy also hands the pick over, for the user to paste as `land <name>`.
    /// Change does not reset it; it lives as long as the lab's candidates.
    @Published private(set) var applies = 0
    /// The result bar's second line after a pick: where it was saved, or nil
    /// when the write failed (then `status` says why).
    @Published private(set) var saved: String?
    let baseline: Value
    /// Set by a persisting lab: writes a look's profile whenever it logs (Save &
    /// copy, and leaving an edited look), and deletes it on remove. A failure
    /// shows in `status`; the look stays.
    var store: ((UITuningLabCandidate<Value>) throws -> Void)?
    var unstore: ((String) throws -> Void)?
    private var taken: Set<String> = []  // every name issued or reserved this run
    private var unsavedBasedOn = "baseline"
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

    /// The look the feature shows: the selected look, else unsaved edits, else
    /// the baseline.
    var selectedLook: Value { selectedPin?.value ?? unsaved ?? baseline }

    /// Whether a chip is outlined: false while Shipped has unsaved edits.
    func isOutlined(_ name: String) -> Bool { name == selected && (name != "original" || unsaved == nil) }

    /// Save & copy is disabled on Shipped with no edits: there is nothing to keep.
    var canSave: Bool { selectedPin != nil || unsaved != nil }

    /// Marks names as used, such as every file in storage, so no look takes them.
    func reserve(_ names: some Sequence<String>) { taken.formUnion(names) }

    /// Selects a chip and returns the look the feature must now show. Unsaved
    /// edits on Shipped are dropped.
    @discardableResult
    func select(_ name: String) -> Value {
        guard name != selected || unsaved != nil else { return selectedLook }
        leave()
        unsaved = nil
        selected = named(name) == nil ? "original" : name
        return selectedLook
    }

    /// Every control edits the selected look. On Shipped the edit stays
    /// unsaved; a saved look changes in place, and a preset becomes its
    /// `basedOn`. `design` is accepted for design-variant labs; the design key
    /// is already in the value.
    func edit(_ value: Value, preset: String? = nil, design: String? = nil) {
        guard let index = all.firstIndex(where: { $0.name == selected }) else {
            unsaved = value
            if let preset { unsavedBasedOn = preset }
            return
        }
        all[index].value = value
        if let preset { all[index].basedOn = preset }
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
        logged[name] = nil
        uiTuningLabLogLine("UITUNINGLAB_CANDIDATE_REMOVED", ["name": name])
        if selected == name { selected = "original" }
        status = "Removed \(look.label)"
        return selectedLook
    }

    /// Logs the selected look again when it changed since it last logged. Runs
    /// when it is left: another chip, closing the lab, Save & copy, or Apply.
    func leave() {
        if let pin = selectedPin { log(pin) }
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

    /// Save & copy: keeps the current look (unsaved edits on Shipped become the
    /// next `Look N`, a selected look is saved as it is) and copies
    /// `land <name>`. Before the first Apply that is all: the agent's waiter is
    /// listening, so no Done line is sent. After it, it also hands the pick over
    /// like Apply, since the user pastes it in chat. Returns the look's name, or
    /// nil when there is nothing to save.
    @discardableResult
    func saveAndCopy() -> String? {
        guard keepUnsaved() || selectedPin != nil, let look = selectedPin else { return nil }
        leave()
        if applies > 0 { return choose() }
        uiTuningLabCopy("land \(look.name)")
        saved = nil
        status = "Saved \(look.label) · copied land \(look.name)"
        return look.name
    }

    /// Apply: keeps unsaved edits as the next `Look N` first, then picks the
    /// selected chip, `original` for Shipped. Logs `UITUNINGLAB_DONE {...}`,
    /// hands it to the agent's waiter, replaces the result file atomically, and
    /// copies `land <winner>`. Returns the winner, and sets `status` when part
    /// of that did not work.
    @discardableResult
    func choose() -> String {
        keepUnsaved()
        leave()
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
            return winner
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
            status = nil
            saved = "Saved \(label) in .ui-tuning-lab/result.json"
        } catch {
            saved = nil
            status = "Result file not written: \(error.localizedDescription)"
        }
        return winner
    }

    /// Turns unsaved edits on Shipped into the next `Look N` and selects it.
    /// Returns false when there were none.
    @discardableResult
    private func keepUnsaved() -> Bool {
        guard selectedPin == nil, let value = unsaved else { return false }
        let used = taken.compactMap { $0.hasPrefix("look-") ? Int($0.dropFirst(5)) : nil }
        let name = "look-\((used.max() ?? 0) + 1)"
        let candidate = UITuningLabCandidate(name: name, basedOn: unsavedBasedOn, value: value)
        taken.insert(name)
        all.append(candidate)
        selected = name
        unsaved = nil
        unsavedBasedOn = "baseline"
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
            status = "\(candidate.label) not saved: \(error.localizedDescription)"
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

extension View {
    /// Outlines a selected chip or preset, so it reads as selected without a
    /// label: a 2 pt accent ring around the control.
    func uiTuningLabSelected(_ on: Bool) -> some View {
        overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color.accentColor, lineWidth: on ? 2 : 0))
    }
}
#endif
