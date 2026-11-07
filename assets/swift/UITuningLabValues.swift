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

/// A pinned look: a frozen snapshot of the draft (references/candidates.md).
/// It lives in memory, and in storage only when the lab persists it.
struct UITuningLabCandidate<Value: Codable>: Identifiable {
    var name: String
    var basedOn: String  // a preset's kebab-case name, `baseline`, or a pin's name
    var value: Value
    var id: String { name }
}

/// Why Pin did not add a look, worded for the panel's status line.
struct UITuningLabNotKept: LocalizedError {
    let errorDescription: String?
}

/// The pinned looks, oldest first, owned beside the draft so they survive
/// closing the lab. Every change logs one line the agent can replay:
/// `UITUNINGLAB_CANDIDATE {...}` and `UITUNINGLAB_CANDIDATE_REMOVED {...}`.
@MainActor
final class UITuningLabCandidates<Value: Codable>: ObservableObject {
    @Published private(set) var all: [UITuningLabCandidate<Value>] = []
    /// Where the draft came from: `baseline` until a preset, Reset, or a pin
    /// copied into the draft changes it.
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

    /// The chip the draft already matches: `original` for Shipped, a pin's
    /// name, or nil when the draft holds unpinned changes. The draft chip is
    /// shown only while this is nil.
    func match(_ draft: Value) -> String? {
        guard let values = try? uiTuningLabChangedValues(from: baseline, to: draft) else { return nil }
        if values == "{}" { return "original" }
        return all.first { (try? uiTuningLabChangedValues(from: baseline, to: $0.value)) == values }?.name
    }

    /// The draft chip's label: where the draft came from, plus edits
    /// ("Shipped + edits", "compact + edits", "capsule + edits").
    var draftTitle: String { "\(basedOn == "baseline" ? "Shipped" : basedOn) + edits" }

    /// Marks names as used, such as every file in storage, so Pin never issues them.
    func reserve(_ names: some Sequence<String>) { taken.formUnion(names) }

    /// Pins the draft, named after what it is: the design key in a
    /// design-variant lab, else the last preset, else `tweak`, never a name used
    /// before in this run. A look that matches Shipped or a pin is not pinned.
    /// `store` runs before the pin is added; if it throws, nothing is added or logged.
    func keep(_ draft: Value, design: String? = nil,
              store: (UITuningLabCandidate<Value>) throws -> Void = { _ in })
        throws -> UITuningLabCandidate<Value> {
        let stem = design.flatMap { $0 == "original" ? nil : $0 } ?? stem(of: basedOn)
        let candidate = UITuningLabCandidate(
            name: uiTuningLabFavoriteName(stem, excluding: taken), basedOn: basedOn, value: draft)
        let line = try checked(candidate)
        do { try store(candidate) } catch {
            throw UITuningLabNotKept(errorDescription: "Not pinned: \(error.localizedDescription)")
        }
        add(candidate, line: line)
        return candidate
    }

    /// Adds a seeded or stored pin and logs it. Returns false, silently,
    /// when the name is already in the list; throws when it now matches the
    /// baseline or another pin.
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

    /// Choose. `winner` is the pin shown, `original` for Shipped, or `draft`, and
    /// `shown` is the look on screen. Logs `UITUNINGLAB_DONE {...}`, replaces the
    /// result file atomically, and copies `land <winner>`. Returns nil when all
    /// of that worked, otherwise what did not.
    func use(_ shown: Value, winner: String) -> String? {
        let line: [String: Any]
        do {
            let values = try uiTuningLabChangedFields(from: baseline, to: winner == "original" ? baseline : shown)
            let kept = try all.map { try uiTuningLabCandidateFields($0, baseline: baseline) }
            line = ["candidates": kept, "values": values, "winner": winner]
        } catch {
            return "Not chosen: \(error.localizedDescription)"
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
        } catch {
            return "Result file not written: \(error.localizedDescription)"
        }
        return nil
    }

    /// The name a pin made from `basedOn` starts from: `tweak` for the
    /// baseline, and a pin's name without its `-2` suffix.
    private func stem(of basedOn: String) -> String {
        if basedOn == "baseline" { return "tweak" }
        guard taken.contains(basedOn),
              let suffix = basedOn.range(of: "-[0-9]+$", options: .regularExpression) else { return basedOn }
        return String(basedOn[..<suffix.lowerBound])
    }

    /// The pin's log line, or why it cannot join the list.
    private func checked(_ candidate: UITuningLabCandidate<Value>) throws -> [String: Any] {
        let line: [String: Any]
        let values: String
        do {
            line = try uiTuningLabCandidateFields(candidate, baseline: baseline)
            values = try uiTuningLabChangedValues(from: baseline, to: candidate.value)
        } catch {
            throw UITuningLabNotKept(errorDescription: "Not pinned: \(error.localizedDescription)")
        }
        if values == "{}" {
            throw UITuningLabNotKept(errorDescription: "Same as Shipped")
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
#endif
