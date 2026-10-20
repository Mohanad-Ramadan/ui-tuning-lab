# Candidate — SwiftUI iOS/iPadOS palette

This is implementation guidance, not a completed validation. The feature and lab
share one `CardStyle`; the immutable baseline is captured before presentation.
Every lab type carries the `UITuningLab` prefix and lives in a file wrapped in
`#if DEBUG`, so `source-gates` can find it and Release builds compile it out.

<!-- file: CardFeature.swift -->
```swift
import SwiftUI

struct CardStyle: Codable, Equatable {
    var cornerRadius: CGFloat
    var spacing: CGFloat
    static let appDefault = Self(cornerRadius: 12, spacing: 8)
}

struct CardFeature: View {
    let style: CardStyle

    var body: some View {
        VStack(spacing: style.spacing) {
            ForEach(["First card", "Second card"], id: \.self) { title in
                Text(title)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(.thinMaterial,
                                in: RoundedRectangle(cornerRadius: style.cornerRadius))
            }
        }
        .padding()
    }
}
```

<!-- file: FeatureScreen.swift -->
```swift
import SwiftUI

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
                UITuningLabControls(
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
```

<!-- file: UITuningLabControls.swift -->
```swift
import SwiftUI

#if DEBUG
struct UITuningLabControls: View {
    @Binding var style: CardStyle
    let reset: () -> Void

    private static let compact = CardStyle(cornerRadius: 4, spacing: 4)
    private static let relaxed = CardStyle(cornerRadius: 24, spacing: 16)

    var body: some View {
        Form {
            HStack {
                Button("Compact") { style = Self.compact }
                Button("Relaxed") { style = Self.relaxed }
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
        // A Form row with several buttons fires all of them on iOS unless borderless.
        .buttonStyle(.borderless)
    }
}
#endif
```

Dismissal destroys `UITuningLabControls`; no timer, observer, or gesture
registration is created. Validate iPhone compact and iPad regular-width behavior,
rotation, Dynamic Type, VoiceOver, Reduce Motion, focus, and the archived Release
product before changing the receipt from pending.

## Optional persistence, only when requested

The candidate above is ephemeral. If the user explicitly requests saved profiles,
replace `UITuningLabControls.swift` with this version. `FeatureScreen.swift` stays
unchanged, and both the envelope and writer stay development-only.

<!-- file: UITuningLabControls.swift variant=persist -->
```swift
import SwiftUI

#if DEBUG
struct UITuningLabProfile: Codable {
    var schemaVersion = 1
    var name = "default"
    var platform = "ios"
    var container = "FeatureScreen.popover"
    var scope = ["appearance", "layout"]
    var overrides: CardStyle
    var notes = ""
}

struct UITuningLabControls: View {
    @Binding var style: CardStyle
    let reset: () -> Void
    @State private var saveError: String?

    private static let compact = CardStyle(cornerRadius: 4, spacing: 4)
    private static let relaxed = CardStyle(cornerRadius: 24, spacing: 16)

    var body: some View {
        Form {
            HStack {
                Button("Compact") { style = Self.compact }
                Button("Relaxed") { style = Self.relaxed }
            }
            Slider(value: $style.cornerRadius, in: 0...32) {
                Text("Corner radius")
            }
            Slider(value: $style.spacing, in: 0...24) { Text("Spacing") }
            HStack {
                Button("Reset", action: reset)
                Button("Save") {
                    do { try save(); saveError = nil }
                    catch { saveError = error.localizedDescription }
                }
            }
            if let saveError { Text(saveError).foregroundStyle(.red) }
        }
        .frame(minWidth: 280)
        // A Form row with several buttons fires all of them on iOS unless borderless.
        .buttonStyle(.borderless)
    }

    private func save() throws {
        let data = try JSONEncoder().encode(UITuningLabProfile(overrides: style))
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

An explicit Save atomically writes `default.json` under Application Support's
`.ui-tuning-lab/`; a write failure displays an error and retains the current style.
