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

/// A look the lab holds (references/candidates.md): a pin the controls edit in
/// place while it is selected. It lives in memory, and in storage only when the
/// lab persists it.
struct UITuningLabCandidate<Value: Codable>: Identifiable {
    var name: String
    var basedOn: String  // a preset's kebab-case name, `baseline`, or the pin it was duplicated from
    var value: Value
    var id: String { name }
}

/// The looks, oldest first, and the selected chip, owned beside the feature so
/// they survive closing the lab. The feature always shows the selected look:
/// switching chips is the comparison, and there is no draft and no stash.
/// Shipped (`original`) is read-only, so an edit on it starts a new pin; a pin
/// changes in place. Lines the agent can replay: `UITUNINGLAB_CANDIDATE {...}`
/// when a pin is created and again when an edited pin is left, and
/// `UITUNINGLAB_CANDIDATE_REMOVED {...}`.
@MainActor
final class UITuningLabCandidates<Value: Codable>: ObservableObject {
    @Published private(set) var all: [UITuningLabCandidate<Value>] = []
    /// The selected chip: `original` for Shipped, or a pin's name.
    @Published private(set) var selected = "original"
    /// What the last action reported, for the panel's status line.
    @Published var status: String?
    let baseline: Value
    /// Set by a persisting lab: writes a pin's profile whenever it logs, and
    /// deletes it on remove. A failure shows in `status`; the pin stays.
    var store: ((UITuningLabCandidate<Value>) throws -> Void)?
    var unstore: ((String) throws -> Void)?
    private var taken: Set<String> = []  // every name issued or reserved this run
    private var logged: [String: String] = [:]  // the line each pin last logged

    /// Seed with finalists kept in the project to reopen a session; empty by default.
    init(baseline: Value, initial: [UITuningLabCandidate<Value>] = []) {
        self.baseline = baseline
        for candidate in initial { adopt(candidate) }
    }

    func named(_ name: String) -> UITuningLabCandidate<Value>? {
        all.first { $0.name == name }
    }

    var selectedPin: UITuningLabCandidate<Value>? { named(selected) }

    /// The look the feature shows: the baseline for Shipped, else the selected pin.
    var selectedLook: Value { selectedPin?.value ?? baseline }

    /// Marks names as used, such as every file in storage, so no pin takes them.
    func reserve(_ names: some Sequence<String>) { taken.formUnion(names) }

    /// Selects a chip and returns the look the feature must now show.
    @discardableResult
    func select(_ name: String) -> Value {
        guard name != selected else { return selectedLook }
        leave()
        selected = named(name) == nil ? "original" : name
        return selectedLook
    }

    /// Every control edits the selected look. On Shipped it starts a new pin,
    /// named after the design key in a design-variant lab, else the preset, else
    /// `tweak`; a pin changes in place, and a preset becomes its `basedOn`.
    func edit(_ value: Value, preset: String? = nil, design: String? = nil) {
        guard let index = all.firstIndex(where: { $0.name == selected }) else {
            let stem = design.flatMap { $0 == "original" ? nil : $0 } ?? preset ?? "tweak"
            add(stem: stem, basedOn: preset ?? "baseline", value: value)
            return
        }
        all[index].value = value
        if let preset { all[index].basedOn = preset }
    }

    /// Branches the selected pin into a new one, so the two can be compared.
    func duplicate() {
        guard let pin = selectedPin else { return }
        add(stem: Self.stem(of: pin.name), basedOn: pin.name, value: pin.value)
    }

    /// Removes a pin and returns the look the feature must now show.
    @discardableResult
    func remove(_ name: String) -> Value {
        guard named(name) != nil else { return selectedLook }
        do { try unstore?(name) } catch {
            status = "\(name) not removed: \(error.localizedDescription)"
            return selectedLook
        }
        all.removeAll { $0.name == name }
        logged[name] = nil
        uiTuningLabLogLine("UITUNINGLAB_CANDIDATE_REMOVED", ["name": name])
        if selected == name { selected = "original" }
        status = "Removed \(name)"
        return selectedLook
    }

    /// Logs the selected pin again when it changed since it last logged. Runs
    /// when it is left: another chip, closing the lab, or Choose.
    func leave() {
        if let pin = selectedPin { log(pin) }
    }

    /// Adds a seeded or stored pin and logs it, without storing it again.
    /// Returns false when the name is already in the list.
    @discardableResult
    func adopt(_ candidate: UITuningLabCandidate<Value>) -> Bool {
        taken.insert(candidate.name)
        guard named(candidate.name) == nil else { return false }
        all.append(candidate)
        log(candidate, storing: false)
        return true
    }

    /// Choose: picks the selected chip, `original` for Shipped. Logs
    /// `UITUNINGLAB_DONE {...}`, replaces the result file atomically, and copies
    /// `land <winner>`. Returns the winner, and sets `status` when part of that
    /// did not work.
    func choose() -> String {
        leave()
        let winner = selectedPin?.name ?? "original"
        let line: [String: Any]
        do {
            let values = try uiTuningLabChangedFields(from: baseline, to: selectedLook)
            let kept = try all.map { try uiTuningLabCandidateFields($0, baseline: baseline) }
            line = ["candidates": kept, "values": values, "winner": winner]
        } catch {
            status = "Not chosen: \(error.localizedDescription)"
            return winner
        }
        uiTuningLabLogLine("UITUNINGLAB_DONE", line)
        let code = "land \(winner)"
        #if canImport(UIKit)
        UIPasteboard.general.string = code
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        #endif
        var result = line
        result["savedAt"] = ISO8601DateFormatter.uiTuningLabSavedAt.string(from: .now)
        do {
            let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            try FileManager.default.createDirectory(
                at: uiTuningLabResultURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: uiTuningLabResultURL, options: .atomic)  // temporary file, then rename
            status = nil
        } catch {
            status = "Result file not written: \(error.localizedDescription)"
        }
        return winner
    }

    /// A pin's name without its `-2` suffix: what its duplicates are named after.
    private static func stem(of name: String) -> String {
        guard let suffix = name.range(of: "-[0-9]+$", options: .regularExpression) else { return name }
        return String(name[..<suffix.lowerBound])
    }

    private func add(stem: String, basedOn: String, value: Value) {
        leave()
        let candidate = UITuningLabCandidate(
            name: uiTuningLabFavoriteName(stem, excluding: taken), basedOn: basedOn, value: value)
        taken.insert(candidate.name)
        all.append(candidate)
        selected = candidate.name
        status = "New look \(candidate.name)"
        log(candidate)
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
            status = "\(candidate.name) not saved: \(error.localizedDescription)"
        }
    }
}

/// `stem`, or `stem-2`, `stem-3`, ...: the first not in `taken`. Never `draft`,
/// `now`, `original`, or `baseline`, which the chips and basedOn use.
func uiTuningLabFavoriteName(_ stem: String, excluding taken: Set<String>) -> String {
    let used = taken.union(["draft", "now", "original", "baseline"])
    if !used.contains(stem) { return stem }
    return (2...).lazy.map { "\(stem)-\($0)" }.first { !used.contains($0) }!
}

/// The pick Choose writes: Application Support `.ui-tuning-lab/result.json`,
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
