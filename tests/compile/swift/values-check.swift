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
    // A pinned look never changes: ↺ on it forks unsaved edits that start
    // from its values, outline no chip, and pin as a new look.
    store.edit(draft { $0.radius = 20 }, preset: "brass")
    store.save()
    let pinned = store.selectedPin
    if pinned?.name != "brass-1" || !store.isOutlined("brass-1") || store.canUndo || store.canSave {
        print("save: expected Brass-1 pinned, outlined, with a fresh history"); failed = true
    }
    store.resetControl(\.radius)
    if !store.hasEdits || store.isOutlined("brass-1") || store.unsavedFrom != "brass-1" ||
        store.selectedLook.radius != store.defaultValue(\.radius) || store.named("brass-1")?.value.radius != 20 {
        print("resetControl: expected a fork of Brass-1, Brass-1 unchanged"); failed = true
    }
    // Undo back past the first edit after the fork outlines the source again.
    store.undo()
    if store.hasEdits || !store.isOutlined("brass-1") || store.selectedLook.radius != 20 || !store.canRedo {
        print("undo: expected Brass-1 outlined again"); failed = true
    }
    store.redo()
    store.edit(draft { $0.radius = 12; $0.bounce = 0.6 }, control: "bounce")
    store.reset()
    if store.hasEdits || !store.isOutlined("brass-1") || !store.canUndo || store.canReset {
        print("reset: expected the fork dropped back to Brass-1, undoably"); failed = true
    }
    store.undo()
    // The fork keeps Brass-1's basedOn, so Save & pin names it Brass-2.
    if store.save() != "brass-2" || store.named("brass-1")?.value != pinned?.value ||
        store.selectedLook != draft({ $0.bounce = 0.6 }) || !store.isOutlined("brass-2") {
        print("save: expected the fork pinned as Brass-2, Brass-1 unchanged"); failed = true
    }
    // ↺ that brings the fork back to its source outlines the source again.
    store.edit(draft { $0.radius = 18; $0.bounce = 0.6 }, control: "radius")
    store.resetControl(\.radius)
    if store.hasEdits || !store.isOutlined("brass-2") {
        print("resetControl: expected the fork back at Brass-2 to be outlined"); failed = true
    }
    // Tapping the source chip drops the unsaved edits.
    store.edit(draft { $0.radius = 30 }, control: "radius")
    store.select("brass-2")
    if store.hasEdits || store.canUndo || store.selectedLook != draft({ $0.bounce = 0.6 }) {
        print("select: expected tapping the source to drop the edits"); failed = true
    }
    store.select("original")
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
