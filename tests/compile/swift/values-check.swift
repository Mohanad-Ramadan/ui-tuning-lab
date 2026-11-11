// Runs the examples' UITuningLabValues.swift helper on real values.
import Foundation

struct Sample: Codable, Equatable {
    var radius: Double
    var bounce: Double
    var enabled: Bool
    var label: String
    var count: Int = 1
    var offset: Double? = 5
    var stops: [Double] = [0.3]
}

let baseline = Sample(radius: 12, bounce: 0.5, enabled: false, label: "card")
func draft(_ change: (inout Sample) -> Void) -> Sample {
    var sample = baseline
    change(&sample)
    return sample
}

let cases: [(String, Sample, String)] = [
    ("rounds floats and keeps bools",
     draft { $0.radius = 19.873046875; $0.bounce = 0.15 + 4 * 0.05; $0.enabled = true },
     #"{"bounce":0.35,"enabled":true,"radius":19.873}"#),
    ("ignores slider noise", draft { $0.radius = 12.0000001 }, "{}"),
    ("reports strings and whole numbers", draft { $0.label = "tile"; $0.radius = 20 },
     #"{"label":"tile","radius":20}"#),
    ("reports a field cleared to nil", draft { $0.offset = nil }, #"{"offset":null}"#),
    ("rounds nested numbers", draft { $0.stops = [0.1 + 0.2] }, "{}"),
    ("reports a changed nested array", draft { $0.stops = [0.3, 0.6] }, #"{"stops":[0.3,0.6]}"#),
    ("keeps large integers exact", draft { $0.count = 9_007_199_254_740_993 },
     #"{"count":9007199254740993}"#),
]
var failed = false
for (name, sample, expected) in cases {
    let actual = (try? uiTuningLabChangedValues(from: baseline, to: sample)) ?? "<threw>"
    if actual != expected { print("\(name): expected \(expected), got \(actual)"); failed = true }
}
// A value JSON cannot represent must be reported, never shown as "No changes".
if (try? uiTuningLabChangedValues(from: baseline, to: draft { $0.radius = .infinity })) != nil {
    print("non-finite value: expected an error"); failed = true
}
// ↺ on one control is an ordinary edit: one Undo step that ends the slider
// run, and on Shipped a look back at the baseline has no unsaved edits.
MainActor.assumeIsolated {
    let store = UITuningLabCandidates(baseline: baseline)
    store.edit(draft { $0.radius = 14 }, control: "radius")
    store.edit(draft { $0.radius = 14; $0.bounce = 0.7 }, control: "bounce")
    store.resetControl(\.bounce)
    if !store.isDefault(\.bounce) || store.selectedLook.radius != 14 {
        print("resetControl: expected bounce back at its default, radius kept"); failed = true
    }
    store.edit(draft { $0.radius = 16 }, control: "radius")
    store.undo()
    if store.selectedLook != draft({ $0.radius = 14 }) {
        print("resetControl: expected a drag after it to be its own Undo step"); failed = true
    }
    store.undo()
    if store.selectedLook != draft({ $0.radius = 14; $0.bounce = 0.7 }) {
        print("resetControl: expected Undo to bring the value back"); failed = true
    }
    store.redo()
    store.resetControl(\.radius)
    if store.hasEdits || store.unsaved != nil || store.canSave || !store.canUndo {
        print("resetControl: expected Shipped back at the baseline to have no unsaved edits"); failed = true
    }
    // On a pinned look, a reset is a draft that Save keeps.
    store.edit(draft { $0.radius = 20 })
    store.save()
    store.resetControl(\.radius)
    if !store.hasEdits || store.selectedLook.radius != store.defaultValue(\.radius) {
        print("resetControl: expected a draft on a pinned look"); failed = true
    }
    store.save()
    if store.selectedPin?.value != baseline || store.canUndo {
        print("resetControl: expected Save to keep the reset"); failed = true
    }
    // Fields of different types reset together as one step.
    store.edit(draft { $0.radius = 18; $0.enabled = true })
    store.resetControl { look, shipped in look.radius = shipped.radius; look.enabled = shipped.enabled }
    if store.hasEdits {
        print("resetControl: expected mixed fields back at Shipped"); failed = true
    }
    store.undo()
    if store.selectedLook != draft({ $0.radius = 18; $0.enabled = true }) {
        print("resetControl: expected one Undo to bring both fields back"); failed = true
    }
}

// A drag snaps only near the Shipped value, at either end of the range too,
// and never onto a neighbouring grid value.
let snapCases: [(Double, Double, ClosedRange<Double>, Double, Bool)] = [
    (0.4, 0, 0...32, 1, true), (1, 0, 0...32, 1, false),
    (32, 32, 0...32, 1, true), (31, 32, 0...32, 1, false),
    (12, 12.5, 0...32, 1, false), (13, 12.5, 0...32, 1, false),
    (12.6, 12.5, 0...32, 0, true), (12.5, 12.5, 0...32, 0.5, true), (13, 12.5, 0...32, 0.5, false),
]
for (value, shipped, range, step, expected) in snapCases
where uiTuningLabSnaps(value, to: shipped, in: range, step: step) != expected {
    print("uiTuningLabSnaps(\(value), to: \(shipped), step: \(step)): expected \(expected)"); failed = true
}
exit(failed ? 1 : 0)
