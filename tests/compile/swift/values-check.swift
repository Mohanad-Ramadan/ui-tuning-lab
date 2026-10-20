// Runs the examples' UITuningLabValues.swift helper on real values.
import Foundation

struct Sample: Codable {
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
exit(failed ? 1 : 0)
