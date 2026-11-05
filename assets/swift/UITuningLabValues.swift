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
