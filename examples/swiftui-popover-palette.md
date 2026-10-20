# Candidate — SwiftUI iOS/iPadOS palette

This is implementation guidance, not a completed validation. The feature and lab
share one `CardStyle`; the immutable baseline is captured before presentation.

```swift
struct CardStyle: Codable, Equatable {
    var cornerRadius: CGFloat
    var spacing: CGFloat
    static let appDefault = Self(cornerRadius: 12, spacing: 8)
    static let compact = Self(cornerRadius: 4, spacing: 4)
    static let relaxed = Self(cornerRadius: 24, spacing: 16)
}

struct FeatureScreen: View {
    @State private var style = CardStyle.appDefault
    #if DEBUG
    @State private var showLab = false
    @State private var baseline: CardStyle?
    #endif

    var body: some View {
        CardFeature(style: style)
            #if DEBUG
            .toolbar {
                Button("Tune", action: openLab)
                    .disabled(showLab)
            }
            .popover(isPresented: $showLab) {
                LabControls(
                    style: $style,
                    reset: { if let baseline { style = baseline } }
                )
                // On compact width, either accept the adaptive sheet or add
                // .presentationCompactAdaptation(.popover) deliberately.
            }
            .onChange(of: showLab) { _, open in
                if !open { baseline = nil }
            }
            #endif
    }

    #if DEBUG
    private func openLab() {
        guard !showLab, baseline == nil else { return }
        baseline = style
        showLab = true
    }
    #endif
}

#if DEBUG
private struct LabControls: View {
    @Binding var style: CardStyle
    let reset: () -> Void

    var body: some View {
        Form {
            HStack {
                Button("Compact") { style = .compact }
                Button("Relaxed") { style = .relaxed }
            }
            Slider(value: $style.cornerRadius, in: 0...32) {
                Text("Corner radius")
            }
            Slider(value: $style.spacing, in: 0...24) { Text("Spacing") }
            HStack {
                Button("Reset", action: reset)
            }
        }
        .frame(minWidth: 280)
    }
}
#endif
```

Dismissal destroys `LabControls`; no timer, observer, or gesture registration is
created. Validate iPhone compact and iPad regular-width behavior, rotation,
Dynamic Type, VoiceOver, Reduce Motion, focus, and the archived Release product
before changing the receipt from pending.

## Optional persistence, only when requested

The candidate above is ephemeral. If the user explicitly requests saved profiles,
add this code in the same file. Both the envelope and writer stay development-only.

```swift
#if DEBUG
struct LabProfile: Codable {
    let schemaVersion = 1
    let name = "default"
    let platform = "ios"
    let container = "FeatureScreen.popover"
    let scope = ["appearance", "layout"]
    let overrides: CardStyle
    let notes = ""
}

extension FeatureScreen {
    private func saveProfile() throws {
        let data = try JSONEncoder().encode(LabProfile(overrides: style))
        let directory = URL.applicationSupportDirectory
            .appending(path: ".ui-tuning-lab", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        try data.write(to: directory.appending(path: "default.json"),
                       options: .atomic)
    }
}
#endif
```

Then add a comma after the `reset:` closure and pass `save: saveProfile` when
creating `LabControls`, and
apply these changes to its existing debug-only definition:

```diff
 private struct LabControls: View {
     @Binding var style: CardStyle
     let reset: () -> Void
+    let save: () throws -> Void
+    @State private var saveError: String?
@@
                 Button("Reset", action: reset)
+                Button("Save") {
+                    do { try save(); saveError = nil }
+                    catch { saveError = error.localizedDescription }
+                }
             }
+            if let saveError { Text(saveError).foregroundStyle(.red) }
```

An explicit Save atomically writes `default.json` under Application Support's
`.ui-tuning-lab/`; a write failure displays an error and retains the current style.
