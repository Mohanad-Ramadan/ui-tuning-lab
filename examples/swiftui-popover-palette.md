# Candidate — SwiftUI iOS/iPadOS palette

This is implementation guidance, not a completed validation. The feature and lab
share one `CardStyle`; the immutable baseline is captured before presentation.
Every lab type carries the `UITuningLab` prefix and lives in a file wrapped in
`#if DEBUG`, so `source-gates` can find it and Release builds compile it out.
**Copy values** puts the fields that differ from the baseline on the pasteboard
and logs them as one `UITUNINGLAB_VALUES {...}` line for landing
(`references/landing-protocol.md`).

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
    @State private var showUITuningLab = false
    @State private var uiTuningLabBaseline: CardStyle?
    #endif

    var body: some View {
        CardFeature(style: style)
            #if DEBUG
            .toolbar {
                Button("Tune", action: openUITuningLab)
                    .disabled(showUITuningLab)
            }
            .popover(isPresented: $showUITuningLab) {
                UITuningLabControls(style: $style, baseline: uiTuningLabBaseline ?? style)
                // On compact width, either accept the adaptive sheet or add
                // .presentationCompactAdaptation(.popover) deliberately.
            }
            .onChange(of: showUITuningLab) { _, open in
                if !open { uiTuningLabBaseline = nil }
            }
            #endif
    }

    #if DEBUG
    private func openUITuningLab() {
        guard !showUITuningLab, uiTuningLabBaseline == nil else { return }
        uiTuningLabBaseline = style
        showUITuningLab = true
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
    let baseline: CardStyle
    @State private var status: String?
    @State private var stashedDraft: CardStyle?  // set while the baseline is shown

    private static let compact = CardStyle(cornerRadius: 4, spacing: 4)
    private static let relaxed = CardStyle(cornerRadius: 24, spacing: 16)

    var body: some View {
        Form {
            Toggle("Show baseline", isOn: showingBaseline)
            Group {
                HStack {
                    Button("Compact") { style = Self.compact }
                    Button("Relaxed") { style = Self.relaxed }
                }
                LabeledContent("Corner radius", value: "\(Int(style.cornerRadius)) pt")
                    .accessibilityHidden(true)  // the slider reports its own value
                Slider(value: $style.cornerRadius, in: 0...32, step: 1) {
                    Text("Corner radius")
                }
                LabeledContent("Spacing", value: "\(Int(style.spacing)) pt")
                    .accessibilityHidden(true)  // the slider reports its own value
                Slider(value: $style.spacing, in: 0...24, step: 1) { Text("Spacing") }
                HStack {
                    Button("Reset") { style = baseline }
                    Button("Copy values") {
                        status = uiTuningLabCopyValues(from: baseline, to: style)
                    }
                }
            }
            .disabled(stashedDraft != nil)
            if let status { Text(status).font(.footnote) }
        }
        .frame(minWidth: 280)
        // A Form row with several buttons fires all of them on iOS unless borderless.
        .buttonStyle(.borderless)
        // Never leave the feature showing the baseline once the lab is gone.
        .onDisappear { if let stashedDraft { style = stashedDraft } }
    }

    /// Shows the captured baseline in the real feature; turning it off restores the draft.
    private var showingBaseline: Binding<Bool> {
        Binding(
            get: { stashedDraft != nil },
            set: { show in
                if show {
                    stashedDraft = style
                    style = baseline
                } else if let draft = stashedDraft {
                    style = draft
                    stashedDraft = nil
                }
            }
        )
    }
}
#endif
```

<!-- file: UITuningLabValues.swift -->
```swift
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
    let before = try uiTuningLabFields(baseline)
    let after = try uiTuningLabFields(draft)
    var changed: [String: Any] = [:]
    for key in Set(before.keys).union(after.keys)
    where (before[key] as? NSObject) != (after[key] as? NSObject) {
        changed[key] = after[key] ?? NSNull()
    }
    let data = try JSONSerialization.data(withJSONObject: changed, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
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
```

Dismissal destroys `UITuningLabControls`; no timer, observer, or gesture
registration is created. Validate iPhone compact and iPad regular-width behavior,
rotation, Dynamic Type, VoiceOver, Reduce Motion, focus, and the archived Release
product before changing the receipt from pending.

## Optional persistence, only when requested

The candidate above is ephemeral. If the user explicitly requests saved profiles,
replace `UITuningLabControls.swift` with this version. `FeatureScreen.swift` stays
unchanged, and the envelope, writer, and loader stay development-only. Load saved
applies the stored overrides to the draft; the baseline stays as captured, so
Reset still returns to it. An unreadable or incompatible file is reported and
left untouched.

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

    static var fileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: ".ui-tuning-lab", directoryHint: .isDirectory)
            .appending(path: "default.json")
    }
}

struct UITuningLabProfileMismatch: LocalizedError {
    var errorDescription: String? { "the saved profile has an incompatible schema or platform" }
}

struct UITuningLabControls: View {
    @Binding var style: CardStyle
    let baseline: CardStyle
    @State private var status: String?
    @State private var stashedDraft: CardStyle?  // set while the baseline is shown

    private static let compact = CardStyle(cornerRadius: 4, spacing: 4)
    private static let relaxed = CardStyle(cornerRadius: 24, spacing: 16)

    var body: some View {
        Form {
            Toggle("Show baseline", isOn: showingBaseline)
            Group {
                HStack {
                    Button("Compact") { style = Self.compact }
                    Button("Relaxed") { style = Self.relaxed }
                }
                LabeledContent("Corner radius", value: "\(Int(style.cornerRadius)) pt")
                    .accessibilityHidden(true)  // the slider reports its own value
                Slider(value: $style.cornerRadius, in: 0...32, step: 1) {
                    Text("Corner radius")
                }
                LabeledContent("Spacing", value: "\(Int(style.spacing)) pt")
                    .accessibilityHidden(true)  // the slider reports its own value
                Slider(value: $style.spacing, in: 0...24, step: 1) { Text("Spacing") }
                HStack {
                    Button("Reset") { style = baseline }
                    Button("Copy values") {
                        status = uiTuningLabCopyValues(from: baseline, to: style)
                    }
                }
                HStack {
                    Button("Save") {
                        do { try save(); status = "Saved" }
                        catch { status = "Save failed: \(error.localizedDescription)" }
                    }
                    Button("Load saved") {
                        do { try loadSaved(); status = "Loaded saved values" }
                        catch {
                            status = "Saved profile not loaded: \(error.localizedDescription). The file was left unchanged."
                        }
                    }
                }
            }
            .disabled(stashedDraft != nil)
            if let status { Text(status).font(.footnote) }
        }
        .frame(minWidth: 280)
        // A Form row with several buttons fires all of them on iOS unless borderless.
        .buttonStyle(.borderless)
        // Never leave the feature showing the baseline once the lab is gone.
        .onDisappear { if let stashedDraft { style = stashedDraft } }
    }

    /// Shows the captured baseline in the real feature; turning it off restores the draft.
    private var showingBaseline: Binding<Bool> {
        Binding(
            get: { stashedDraft != nil },
            set: { show in
                if show {
                    stashedDraft = style
                    style = baseline
                } else if let draft = stashedDraft {
                    style = draft
                    stashedDraft = nil
                }
            }
        )
    }

    private func save() throws {
        let data = try JSONEncoder().encode(UITuningLabProfile(overrides: style))
        try FileManager.default.createDirectory(
            at: UITuningLabProfile.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try data.write(to: UITuningLabProfile.fileURL, options: .atomic)
    }

    private func loadSaved() throws {
        let data = try Data(contentsOf: UITuningLabProfile.fileURL)
        let profile = try JSONDecoder().decode(UITuningLabProfile.self, from: data)
        guard profile.schemaVersion == 1, profile.platform == "ios" else {
            throw UITuningLabProfileMismatch()
        }
        style = profile.overrides
    }
}
#endif
```

An explicit Save atomically writes `default.json` under Application Support's
`.ui-tuning-lab/`; a write failure displays an error and retains the current style.
