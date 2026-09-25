# Example — SwiftUI popover palette (verified tier)

Binding-driven presentation. When `showLab` is false the lab has no
identity and costs nothing.

```swift
struct FeatureScreen: View {
    #if DEBUG
    @State private var showLab = false
    @State private var labConfig = LabConfig.baseline
    #endif

    #if DEBUG
    private var labConfigOrBaseline: LabConfig { labConfig }
    #else
    private var labConfigOrBaseline: LabConfig { LabConfig.baseline }
    #endif

    var body: some View {
        FeatureView(config: labConfigOrBaseline)
            #if DEBUG
            .popover(isPresented: $showLab) {
                LabControls(config: $labConfig)
            }
            #endif
    }
}
```

iPhone compact: add `.presentationCompactAdaptation(.popover)` only when a
popover is genuinely required; otherwise accept the adaptive sheet with
detents and verify the tuned gesture still works. Toggle via shake or
triple-tap, DEBUG only.
