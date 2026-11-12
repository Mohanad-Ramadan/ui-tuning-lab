# Candidate — entrance animation with spring controls

Animation tuning needs more than sliders: the motion must be replayed on demand,
slowed down to be judged, and flipped against the baseline. This example
tunes a card's entrance spring on SwiftUI and the web. The lab only scales the
values it renders; it never changes global animation speed or the user's
reduced-motion setting.

Every lab in this example provides:

- **Replay**: re-creates the card (a bumped `id` / `key`) so its entrance runs again.
- **Speed**: 1×, 0.5×, 0.25×, or 0.1×, applied by stretching the rendered duration.
- **Chips**: Shipped (the declared default) and each pinned look, named after
  its preset and numbered (**Snappy-1**, **Playful-1**, or **Custom-1** with no
  preset); the selected chip is outlined, and the card always renders it, so
  switching chips is the comparison. Tapping a chip renders it in the real card
  and replays it. Every chip is read-only, a pinned look included: the controls
  fork the selected chip into unsaved changes that start from its values, with
  no chip outlined, until **Save & pin** keeps them as a new look (an edit on
  **Snappy-1** pins as **Snappy-2**); the chip it came from never changes, and
  tapping a chip drops the unsaved changes.
- **Undo**, **Redo**, and **Reset**: act on the unsaved changes, back to the
  chip they were forked from, which is outlined again; a whole slider drag is
  one step, and Reset can be undone.
- **Default marker and ↺**: each slider marks the Shipped value with a tick
  under its track, on every chip, and a drag near it snaps to it exactly (with
  a light tap on iOS); the readout adds `· default` while the value differs.
  Duration and bounce are one spring, so one **↺** puts both back to Shipped as
  one Undo step; Offset has its own. On the web, a double-click on a slider's
  label does the same (`references/control-mapping.md`, "Default marker and per-control reset").
- **Reduced motion**: the feature keeps its own reduced animation, and the lab says
  when that is what you are seeing.
- **⋯ menu**: Copy values, which copies the selected look's fields that differ
  from the baseline and logs them as one `UITUNINGLAB_VALUES {...}` line for
  landing (`references/landing-protocol.md`). Speed is a preview setting and is
  never included.
- **Save & pin** and **Apply**: Save & pin, the one save button, pins the
  unsaved changes as a new look and copies `land <name>`, and is disabled when
  there are none; Apply pins unsaved changes first, then picks the selected chip, logs
  `UITUNINGLAB_DONE`, stores the result, copies `land <name>`, collapses the
  panel to a `Applied:` bar with Change and Replay, and is hidden after its
  first use, as in `references/candidates.md`. The hint *Save & pin to keep a
  look · Apply to finish* is pinned below the controls.

## SwiftUI (iOS 17+)

The toolbar Entrance Lab button is the human path and visible fallback; the DEBUG-only
`-UITuningLabOpen` launch argument is the agent path, read through
`UITuningLabLaunch` (`references/activation.md`). The host owns the
`UITuningLabCandidates` store beside the feature, so the looks, the unsaved
changes, and the selection survive closing the popover, and a name is never
reused within a run; seed its `initial:` array to reopen a session. Save & pin
names a look after its preset (**Snappy-1**, **Playful-1**, or **Custom-1**);
only a pin logs the look. Undo, Redo, and Reset act on the unsaved changes back
to the chip they were forked from, a whole slider drag is one step, and each
replays the card. `motion` always holds the selected look,
and `rendered(_:)` only stretches its duration for the speed. Apply writes
Application Support `.ui-tuning-lab/result.json`. Closing the lab keeps the
selected look and plays it at real time again.

<!-- file: EntranceFeature.swift -->
```swift
import SwiftUI

struct EntranceMotion: Codable, Equatable {
    var duration: Double  // seconds, SwiftUI spring duration
    var bounce: Double    // 0 = no overshoot
    var offset: Double    // points travelled upward on entrance
    static let appDefault = Self(duration: 0.5, bounce: 0.2, offset: 40)
}

struct EntranceCard: View {
    let motion: EntranceMotion
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("Welcome back")
            .padding(24)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : motion.offset)
            .onAppear {
                let animation: Animation = reduceMotion
                    ? .easeOut(duration: 0.2)
                    : .spring(duration: motion.duration, bounce: motion.bounce)
                withAnimation(animation) { shown = true }
            }
    }
}
```

<!-- file: EntranceScreen.swift -->
```swift
import SwiftUI

struct EntranceScreen: View {
    @State private var motion = EntranceMotion.appDefault
    #if DEBUG
    @State private var showUITuningLab = false
    @State private var uiTuningLab = UITuningLabMotionState()
    @State private var uiTuningLabDetent = PresentationDetent.medium
    // The looks and the selected chip live beside the feature and outlive the
    // popover. To reopen a session, seed the finalists kept in the project here
    // (references/candidates.md).
    @StateObject private var uiTuningLabCandidates =
        UITuningLabCandidates<EntranceMotion>(baseline: .appDefault, initial: [])
    #endif

    var body: some View {
        #if DEBUG
        EntranceCard(motion: uiTuningLab.rendered(motion))
            .id(uiTuningLab.replayToken)
            .frame(maxHeight: .infinity, alignment: .top)
            .toolbar {
                Button("Entrance Lab", action: openUITuningLab)
                    .disabled(showUITuningLab)
            }
            .popover(isPresented: $showUITuningLab) {
                UITuningLabMotionControls(
                    motion: $motion,
                    lab: $uiTuningLab,
                    candidates: uiTuningLabCandidates,
                    // The declared default, never the value on screen at open.
                    baseline: .appDefault
                )
                // Compact width adapts to a sheet; keep the card visible above
                // it, and let the user drag it taller to reach every control.
                .presentationDetents([.medium, .large], selection: $uiTuningLabDetent)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationDragIndicator(.visible)
            }
            .onChange(of: showUITuningLab) { _, open in
                // Closing plays the selected look at real time again. Keep the
                // replay token so closing does not re-create the card.
                if !open { uiTuningLab.speed = 1 }
            }
            .onAppear {
                // The agent path opens the lab once per launch.
                if UITuningLabLaunch.consumeRequest() { showUITuningLab = true }
            }
        #else
        EntranceCard(motion: motion)
            .frame(maxHeight: .infinity, alignment: .top)
        #endif
    }

    #if DEBUG
    private func openUITuningLab() {
        showUITuningLab = true
    }
    #endif
}
```

<!-- file: UITuningLabLaunch.swift -->
```swift
import Foundation

#if DEBUG
/// The agent path: a DEBUG-only launch argument, honored once per launch.
/// Launch with `xcrun simctl launch booted <bundle-id> -UITuningLabOpen 1`.
@MainActor
enum UITuningLabLaunch {
    // Launch arguments land in the volatile argument domain, so the value
    // counts: `-UITuningLabOpen 0` keeps the lab closed.
    private static var pending = UserDefaults.standard.bool(forKey: "UITuningLabOpen")

    /// True only the first time it is read, so a rebuilt or re-pushed screen
    /// does not reopen the lab.
    static func consumeRequest() -> Bool {
        defer { pending = false }
        return pending
    }
}
#endif
```

<!-- file: UITuningLabMotion.swift -->
```swift
import SwiftUI

#if DEBUG
struct UITuningLabMotionState {
    var replayToken = 0
    var speed = 1.0  // 1 = real time; smaller values slow the preview

    /// The selected look, slowed by stretching its duration.
    func rendered(_ look: EntranceMotion) -> EntranceMotion {
        var motion = look
        motion.duration /= speed
        return motion
    }
}

struct UITuningLabMotionControls: View {
    @Binding var motion: EntranceMotion
    @Binding var lab: UITuningLabMotionState
    // Owned by the host beside the feature, so the looks and the selection
    // survive closing and reopening the lab.
    @ObservedObject var candidates: UITuningLabCandidates<EntranceMotion>
    let baseline: EntranceMotion
    @State private var sent: String?  // the last pick; set, the lab is one bar
    @State private var dragging: String?  // the slider being dragged: only a drag snaps
    @State private var snaps = 0  // counts snaps onto a Shipped value, for the haptic
    @FocusState private var focused: String?  // ↺ hands focus to its slider as it hides
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    private static let snappy = EntranceMotion(duration: 0.3, bounce: 0, offset: 24)
    private static let playful = EntranceMotion(duration: 0.7, bounce: 0.45, offset: 64)

    var body: some View {
        VStack {
            if let sent {
                // Apply collapses the lab to one bar; Change reopens it.
                VStack(alignment: .leading) {
                    HStack {
                        Text(candidates.applies > 1
                            ? "Copied land \(sent): paste it in chat so the agent applies it"
                            : "Applied: \(uiTuningLabChipLabel(sent))")
                        Spacer()
                        Button("Change") { self.sent = nil }
                        Button("Replay") { lab.replayToken += 1 }
                    }
                    if let line = candidates.saved ?? candidates.status { Text(line).font(.footnote) }
                    Spacer(minLength: 0)
                }
                .padding()
            } else {
                panel
            }
        }
        // Closing keeps the card on the selected look, edits included, and logs
        // nothing: only a pin does.
        .frame(minWidth: 300)
    }

    private var panel: some View {
        Form {
            HStack {
                Text("UI tuning lab").font(.headline)
                Spacer()
                Menu {
                    Button("Copy values") {
                        candidates.status = uiTuningLabCopyValues(from: baseline, to: candidates.selectedLook)
                    }
                } label: {
                    Text("⋯")
                }
                .accessibilityLabel("More")
                Button("Close") { dismiss() }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    chip("Shipped", id: "original")
                    ForEach(candidates.all) { pin in
                        HStack(spacing: 2) {
                            chip(pin.label, id: pin.name)
                            // × only on the selected look, outlined, so nothing is removed by accident.
                            if candidates.isOutlined(pin.name) {
                                Button("×") { motion = candidates.remove(pin.name) }
                                    .accessibilityLabel("Remove \(pin.label)")
                            }
                        }
                    }
                }
                .padding(2)  // room for the selected chip's outline
            }
            if reduceMotion {
                Text("Reduce Motion is on, so the card shows its reduced animation.")
            }
            HStack {
                Button("Snappy") { apply(Self.snappy, named: "snappy") }
                Button("Playful") { apply(Self.playful, named: "playful") }
            }
            // The spring is one control made of two sliders: one ↺ puts both
            // back to Shipped as one Undo step.
            HStack {
                Text("Spring")
                if !candidates.isDefault(\.duration) || !candidates.isDefault(\.bounce) {
                    Button("↺") {
                        show(candidates.resetControl(\.duration, \.bounce))
                        focused = "Duration"
                    }
                        .accessibilityLabel(
                            "Reset Spring to default, \(uiTuningLabNumber(baseline.duration)) s, bounce \(uiTuningLabNumber(baseline.bounce))")
                }
            }
            slider("Duration", \.duration, in: 0.15...1.5, unit: "s", resettable: false)
            slider("Bounce", \.bounce, in: 0...0.6, resettable: false)
            slider("Offset", \.offset, in: 0...120, unit: "pt")
            Picker("Speed", selection: $lab.speed) {
                Text("1×").tag(1.0)
                Text("0.5×").tag(0.5)
                Text("0.25×").tag(0.25)
                Text("0.1×").tag(0.1)
            }
            .pickerStyle(.segmented)
            // Undo and Redo step through the unsaved edits, back to the chip they
            // were forked from; each replays the card.
            HStack {
                Button("Undo") { show(candidates.undo()) }
                    .disabled(!candidates.canUndo)
                Button("Redo") { show(candidates.redo()) }
                    .disabled(!candidates.canRedo)
                Button("Reset") { show(candidates.reset()) }
                    .disabled(!candidates.canReset)
            }
            HStack {
                Button("Replay") { lab.replayToken += 1 }
                // Save & pin, the one save button, keeps unsaved edits as a new
                // chip. After the first Apply it also hands the pick over for
                // pasting in chat.
                Button("Save & pin") {
                    let applied = candidates.applies > 0
                    if let name = candidates.save(), applied { sent = name }
                }
                .disabled(!candidates.canSave)
                Spacer()
                // Apply reaches the agent once; after that it is hidden for good.
                if candidates.applies == 0 {
                    Button("Apply") { sent = candidates.choose() }
                }
            }
            if let status = candidates.status { Text(status).font(.footnote) }
        }
        // Pinned below the scrolling controls, so it shows at every detent.
        .safeAreaInset(edge: .bottom) {
            Text(candidates.applies > 0
                ? "Save & pin, then paste it in chat"
                : "Save & pin to keep a look · Apply to finish")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
        }
        // Selecting a chip shows its look in the real card, so replay it.
        .onChange(of: candidates.selected) { lab.replayToken += 1 }
        .onChange(of: lab.speed) { lab.replayToken += 1 }
        // A Form row with several buttons fires all of them on iOS unless borderless.
        .buttonStyle(.borderless)
        .sensoryFeedback(.selection, trigger: snaps)  // a light tap when a drag snaps to Shipped
    }

    /// One chip. The selected chip is outlined and is the look the card shows.
    private func chip(_ title: String, id: String) -> some View {
        let on = candidates.isOutlined(id)
        return Button(title) { motion = candidates.select(id) }
            .buttonStyle(.bordered)
            .tint(on ? .accentColor : .secondary)
            .uiTuningLabSelected(on)
            .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// A slider shows the selected look and edits it; one drag is one Undo
    /// step, and releasing it replays the card. A tick under the track marks
    /// the Shipped value, and a drag near it snaps to it exactly, with a light
    /// tap. ↺ shows while the value differs from Shipped and puts it back as
    /// one Undo step; the spring's two sliders share the ↺ above them.
    private func slider(
        _ label: String, _ field: WritableKeyPath<EntranceMotion, Double>, in range: ClosedRange<Double>,
        unit: String = "", resettable: Bool = true
    ) -> some View {
        let shipped = candidates.defaultValue(field)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                LabeledContent(label, value: uiTuningLabReadout(motion[keyPath: field], shipped: shipped, unit: unit))
                    .accessibilityHidden(true)  // the slider reports its own value
                if resettable && !candidates.isDefault(field) {
                    Button("↺") {
                        show(candidates.resetControl(field))
                        focused = label
                    }
                        .accessibilityLabel("Reset \(label) to default, \(uiTuningLabReadout(shipped, shipped: shipped, unit: unit))")
                }
            }
            Slider(value: Binding(get: { motion[keyPath: field] }, set: { value in
                var look = motion
                let snap = dragging == label && uiTuningLabSnaps(value, to: shipped, in: range)
                if snap && look[keyPath: field] != shipped { snaps += 1 }
                look[keyPath: field] = snap ? shipped : value
                edit(look, control: label)
            }), in: range) {
                Text(label)
            } onEditingChanged: { editing in
                dragging = editing ? label : nil
                replayWhenReleased(editing)
            }
            .labelsHidden()  // the row above shows the label
            .focused($focused, equals: label)
            .uiTuningLabDefaultTick(at: shipped, in: range)
        }
    }

    /// Every control makes unsaved edits, forked from the selected chip when
    /// it is outlined; the chip itself never changes. Save & pin keeps them.
    private func edit(_ value: EntranceMotion, preset: String? = nil, control: String? = nil) {
        candidates.edit(value, preset: preset, control: control)
        motion = candidates.selectedLook
    }

    /// Shows the look Undo, Redo, or Reset left, and replays it.
    private func show(_ look: EntranceMotion) {
        motion = look
        lab.replayToken += 1
    }

    private func apply(_ preset: EntranceMotion, named name: String) {
        edit(preset, preset: name)
        lab.replayToken += 1
    }

    private func replayWhenReleased(_ editing: Bool) {
        if !editing { lab.replayToken += 1 }
    }
}
#endif
```

<!-- copy: assets/swift/UITuningLabValues.swift -->
`UITuningLabValues.swift`: copy `assets/swift/UITuningLabValues.swift` into the
app's target unchanged. It holds Copy values, the looks store and selection, look names,
Apply with its result file, and the log lines every Swift lab shares,
all inside `#if DEBUG`.

## Web (React)

`springEasing` turns a bounce value into a CSS `linear()` easing so the same spring
runs through the Web Animations API. `linear()` needs Chromium 113+, Safari 17.2+,
or Firefox 112+. The Entrance Lab button is the human path and visible fallback;
`?ui-tuning-lab=1` is the agent path, parsed only inside the DEV-gated lab module
(`references/activation.md`).

<!-- file: EntranceCard.tsx -->
```tsx
import { useLayoutEffect, useRef } from "react";

export type EntranceMotion = {
  durationMs: number; // whole entrance timeline
  bounce: number;     // 0 = no overshoot
  offsetPx: number;   // distance travelled upward on entrance
};
export const appDefault: EntranceMotion = { durationMs: 600, bounce: 0.2, offsetPx: 40 };

const PERIODS = 1.5; // natural spring periods inside the timeline

// Samples a damped spring into CSS linear() stops. Bounce maps to damping the way
// SwiftUI does: damping ratio = 1 - bounce.
export function springEasing(bounce: number, samples = 48): string {
  const zeta = 1 - Math.min(Math.max(bounce, 0), 0.9);
  const omega = 2 * Math.PI;
  const position = (t: number) => {
    if (zeta >= 1) return 1 - Math.exp(-omega * t) * (1 + omega * t);
    const damped = omega * Math.sqrt(1 - zeta * zeta);
    return 1 - Math.exp(-zeta * omega * t) *
      (Math.cos(damped * t) + (zeta * omega / damped) * Math.sin(damped * t));
  };
  const stops: string[] = [];
  for (let i = 0; i < samples; i++) stops.push(position((i / samples) * PERIODS).toFixed(4));
  stops.push("1");
  return `linear(${stops.join(", ")})`;
}

export function EntranceCard({ motion }: { motion: EntranceMotion }) {
  const card = useRef<HTMLDivElement>(null);
  const { durationMs, bounce, offsetPx } = motion;

  // Layout effect: start before the first paint so the card never flashes.
  useLayoutEffect(() => {
    const node = card.current;
    if (!node) return;
    const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
    const animation = reduce
      ? node.animate([{ opacity: 0 }, { opacity: 1 }],
          { duration: 200, easing: "ease-out", fill: "both" })
      : node.animate([
          { opacity: 0, transform: `translateY(${offsetPx}px)` },
          { opacity: 1, transform: "none" },
        ], { duration: durationMs, easing: springEasing(bounce), fill: "both" });
    return () => animation.cancel();
  }, [durationMs, bounce, offsetPx]);

  return <div ref={card} className="entrance-card">Welcome back</div>;
}
```

<!-- file: EntranceScreen.tsx -->
```tsx
import { lazy, Suspense, useState } from "react";
import type { ComponentType, Dispatch, SetStateAction } from "react";
import { appDefault, EntranceCard } from "./EntranceCard";
import type { EntranceMotion } from "./EntranceCard";

export type TuningLabHostProps = {
  motion: EntranceMotion;
  setMotion: Dispatch<SetStateAction<EntranceMotion>>;
};

// Production builds replace import.meta.env.DEV with false, which removes this
// branch and the lab chunk from the bundle.
let TuningLabHost: ComponentType<TuningLabHostProps> | null = null;
if (import.meta.env.DEV) {
  TuningLabHost = lazy(() => import("./EntranceScreen.ui-tuning-lab"));
}

export function EntranceScreen() {
  const [motion, setMotion] = useState(appDefault);
  if (TuningLabHost) {
    return (
      <Suspense fallback={<EntranceCard motion={motion} />}>
        <TuningLabHost motion={motion} setMotion={setMotion} />
      </Suspense>
    );
  }
  return <EntranceCard motion={motion} />;
}
```

<!-- file: EntranceScreen.ui-tuning-lab.tsx -->
```tsx
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import type { KeyboardEvent as ReactKeyboardEvent, RefObject } from "react";
import { appDefault, EntranceCard } from "./EntranceCard";
import type { EntranceMotion } from "./EntranceCard";
import type { TuningLabHostProps } from "./EntranceScreen";

// A manual popover stays open while the user clicks and scrolls the feature;
// Close and Escape dismiss it. React 18 types omit `popover`, so it is spread.
const popoverManual = { popover: "manual" };
// Pinned beside the feature rather than centered over it; the fixed trigger
// never shifts the feature's layout. The outline keeps the panel distinct when
// the screen behind it has the same background, where a shadow alone vanishes;
// GrayText and Canvas follow color-scheme, so it holds in light and dark mode.
const panelStyle = {
  insetBlockStart: "auto", insetInlineStart: "auto", insetBlockEnd: 72, insetInlineEnd: 16,
  margin: 0, maxWidth: "min(320px, calc(100vw - 32px))", maxHeight: "calc(100dvh - 88px)",
  overflow: "auto", border: "1px solid GrayText", background: "Canvas",
  colorScheme: "light dark", font: "inherit",
} as const;
const triggerStyle = { position: "fixed", insetBlockEnd: 16, insetInlineEnd: 16 } as const;
const rowStyle = { display: "flex", flexWrap: "wrap", alignItems: "center", gap: 4, margin: "4px 0" } as const;
// A selected chip is outlined, so it reads as selected without a label.
// Highlight follows color-scheme, so the outline holds in light and dark mode.
const selectedStyle = (on: boolean) =>
  on ? { outline: "2px solid Highlight", outlineOffset: 1, fontWeight: 600 } as const : undefined;

// A pinned look: the fields that differ from the baseline, plus where it came
// from. It never changes once pinned: an edit on it forks unsaved edits.
type Candidate = { name: string; basedOn: string; values: Partial<EntranceMotion> };
// One point in the unsaved edits' history: what it showed, and where it came from.
type Step = { value: EntranceMotion; basedOn: string };
// The unsaved edits' Undo and Redo steps, back to the chip they were forked from.
type History = { undo: Step[]; redo: Step[] };
const noHistory: History = { undo: [], redo: [] };
// Looks the lab opens with. Empty by default; a later session seeds the
// finalists kept in the project here (references/candidates.md).
const initialCandidates: Candidate[] = [];
// Apply writes the pick here, so it survives quitting the app.
const resultKey = "uiTuningLab.result";
// Never issued as a look's name: "original" is the Shipped chip, and the others
// are kept for older logs.
const reservedNames = ["draft", "now", "original", "baseline"];

// Preset keys are kebab-case: the key is what a look records as basedOn, and
// names the look when it is pinned (`snappy-1`, shown as Snappy-1).
const presets = {
  snappy: { durationMs: 350, bounce: 0, offsetPx: 24 },
  playful: { durationMs: 900, bounce: 0.45, offsetPx: 64 },
} satisfies Record<string, EntranceMotion>;
const speeds = [1, 0.5, 0.25, 0.1];
// The baseline is the declared default, never the value on screen when the lab
// opens: a look kept from an earlier session must still count as a change.
const baseline: EntranceMotion = appDefault;

// The agent path: `?ui-tuning-lab=1` opens the lab on load. It is parsed here,
// inside the development-only module, so production never sees the parameter.
function opensOnLaunch(): boolean {
  if (typeof window === "undefined") return false;
  return new URLSearchParams(window.location.search).get("ui-tuning-lab") === "1";
}

// Drop the parameter once it has been honored, so a remount, reload, or copied
// link does not reopen the lab.
function clearLaunchRequest() {
  const url = new URL(window.location.href);
  if (!url.searchParams.has("ui-tuning-lab")) return;
  url.searchParams.delete("ui-tuning-lab");
  window.history.replaceState(window.history.state, "", url);
}

// The fields of a look that differ from the baseline.
function changedValues<T extends object>(baseline: T, look: T): Partial<T> {
  return Object.fromEntries(Object.entries(look).filter(
    ([key, value]) => value !== baseline[key as keyof T])) as Partial<T>;
}

// JSON with sorted keys, so every log line has one stable shape.
function sortedJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(sortedJson).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.entries(value).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
      .map(([key, item]) => `${JSON.stringify(key)}:${sortedJson(item)}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

// Two looks are the same when they differ from the baseline in the same fields.
function sameLook(a: EntranceMotion, b: EntranceMotion): boolean {
  return sortedJson(changedValues(baseline, a)) === sortedJson(changedValues(baseline, b));
}
// A pinned look's values, every field filled in.
function savedLook(candidate: Candidate): EntranceMotion {
  return { ...baseline, ...candidate.values };
}

// A new look's name, `<prefix>-N`: the prefix is its preset's key, or `custom`
// for a look started from Shipped with no preset; N is one past the highest
// number issued for that prefix in this run, removed ones included, so a name
// is never reused.
function pinName(issued: Set<string>, prefix: string): string {
  const used = [...issued].filter(name => name.startsWith(`${prefix}-`))
    .map(name => name.slice(prefix.length + 1)).filter(rest => /^[0-9]+$/.test(rest)).map(Number);
  return `${prefix}-${Math.max(0, ...used) + 1}`;
}
// A chip's label: `Snappy-2` for `snappy-2`, `Warm Glow-1` for `warm-glow-1`,
// Shipped for `original`; a name that does not end in `-N` as it is.
function chipLabel(name: string): string {
  if (name === "original") return "Shipped";
  const m = /^(.+)-([0-9]+)$/.exec(name);
  if (!m) return name;
  const words = m[1].split("-").filter(Boolean).map(word => word[0].toUpperCase() + word.slice(1));
  return `${words.join(" ")}-${Number(m[2])}`;
}

// A range input with the Shipped value marked: a tick under the track, on
// every chip. Range inputs have no API for one tick at an arbitrary value, so
// the tick is drawn over the track; THUMB is the browser's thumb width, and the
// thumb's center runs from THUMB / 2 to the width minus THUMB / 2, so the tick
// sits under the thumb at that value. 16 px matches Chromium, Firefox, and
// Safari's default thumbs; measure it again when the app styles the thumb. A
// drag (never the arrow keys) within 1.5% of the range, or less than half a
// step, snaps to the Shipped value exactly. The Shipped value must sit on the
// step grid: a range input cannot hold 12.5 with step="1", so use a step that
// divides it, or step="any". The readout adds "· default 12" while the value
// differs. ↺, and double-clicking the label, put this control back to Shipped
// as one Undo step and move focus to the slider, so it stays in the panel as
// the ↺ goes away. The tick, the snap, and the readout are display only.
const THUMB = 16;
function ShippedSlider({ label, value, shipped, min, max, step = 1, unit = "", onEdit, onReset, resetButton = true,
  inputRef }: {
  label: string; value: number; shipped: number; min: number; max: number; step?: number; unit?: string;
  onEdit: (value: number) => void; onReset: () => void; resetButton?: boolean;
  inputRef?: RefObject<HTMLInputElement>;
}) {
  const dragging = useRef(false);
  const ownInput = useRef<HTMLInputElement>(null);
  const input = inputRef ?? ownInput;
  const reset = () => { onReset(); input.current?.focus(); };
  // A drag ends wherever the pointer is released, inside the input or not.
  // Removed on unmount, so closing the lab leaves no listener behind.
  useEffect(() => {
    const end = () => { dragging.current = false; };
    window.addEventListener("pointerup", end);
    window.addEventListener("pointercancel", end);
    return () => {
      window.removeEventListener("pointerup", end);
      window.removeEventListener("pointercancel", end);
    };
  }, []);
  const shown = (n: number) => unit ? `${n} ${unit}` : `${n}`;
  const readout = value === shipped ? shown(value) : `${shown(value)} · default ${shipped}`;
  const fraction = (shipped - min) / (max - min);
  return <div style={rowStyle}>
    <label>
      <span onDoubleClick={reset}>{label}</span>{" "}
      <span style={{ position: "relative", display: "inline-block" }}>
        <input ref={input} type="range" min={min} max={max} step={step} value={value}
          onPointerDown={() => { dragging.current = true; }}
          onChange={e => {
            const next = Number(e.target.value);
            const distance = Math.abs(next - shipped);
            const snap = dragging.current && (distance <= (max - min) * 0.015 || distance < step / 2);
            onEdit(snap ? shipped : next);
          }}/>
        <span aria-hidden="true" style={{ position: "absolute", insetBlockEnd: -2, width: 2, height: 6,
          insetInlineStart: `calc(${THUMB / 2}px + (100% - ${THUMB}px) * ${fraction} - 1px)`,
          background: "GrayText", pointerEvents: "none" }}/>
      </span>
    </label>
    <output aria-hidden="true">{readout}</output>
    {resetButton && value !== shipped && <button type="button"
      aria-label={`Reset ${label} to default, ${shown(shipped)}`} onClick={reset}>↺</button>}
  </div>;
}

export default function UITuningLabEntrance({ motion, setMotion }: TuningLabHostProps) {
  const [open, setOpen] = useState(opensOnLaunch);
  useEffect(clearLaunchRequest, []);
  const [replay, setReplay] = useState(0);
  const [speed, setSpeed] = useState(1);
  const [status, setStatus] = useState<string | null>(null);
  const panel = useRef<HTMLDivElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  const firstControl = useRef<HTMLButtonElement>(null);
  const changeButton = useRef<HTMLButtonElement>(null);
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  // Pinned looks live in memory and in the log, oldest first; only Apply
  // writes storage.
  const [candidates, setCandidates] = useState(initialCandidates);
  // Every name issued in this run, removed ones included: names are never reused.
  const issued = useRef(new Set([...reservedNames, ...initialCandidates.map(c => c.name)]));
  // The line each look last logged, so a look logs once.
  const logged = useRef(new Map<string, string>());
  // The selected chip: "original" (Shipped) or a look's name. The card renders
  // it, or the unsaved edits forked from it.
  const [selected, setSelected] = useState("original");
  // Edits not pinned yet, forked from the selected chip, with the preset they
  // came from. While set, no chip is outlined; the chip itself never changes.
  const [unsaved, setUnsaved] = useState<Step | null>(null);
  // Undo and Redo of the unsaved edits, back to the chip they were forked from,
  // and the control of the newest step, so one slider drag is one step.
  const [steps, setSteps] = useState<History>(noHistory);
  const lastControl = useRef<string | undefined>(undefined);
  // The winner after Apply; while set, the panel is the result bar.
  const [sent, setSent] = useState<string | null>(null);
  // How many times a pick reached the agent. The first Apply reaches its
  // waiter; after it the agent no longer listens, so Apply hides and Save & pin
  // also hands the pick over, for the user to paste as `land <name>`. Change
  // does not reset it.
  const [applies, setApplies] = useState(0);
  const [copied, setCopied] = useState(true);  // the clipboard took `land <name>`
  // The result bar's second line: where the pick was saved, or null when it could not.
  const [saved, setSaved] = useState<string | null>(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const selectedPin = candidates.find(c => c.name === selected);
  // The selected chip's look, which unsaved edits fork from.
  const chipLook: Step = selectedPin
    ? { value: savedLook(selectedPin), basedOn: selectedPin.basedOn }
    : { value: baseline, basedOn: "baseline" };
  // The look the card renders, and where it came from.
  const current: Step = unsaved ?? chipLook;
  const selectedValues = changedValues(baseline, current.value);
  // Only the selected chip is outlined, and none while there are unsaved edits.
  const outlined = (chip: string) => chip === selected && unsaved === null;
  // Save & pin, the one save button, and Reset need unsaved edits.
  const hasEdits = unsaved !== null;

  // Read the latest looks and selection through refs, so an effect that runs
  // once per open never reads stale state.
  const latest = useRef({ candidates, selected });
  useLayoutEffect(() => { latest.current = { candidates, selected }; });

  // Logs a look's line when it is new or changed since it last logged.
  function logPin(candidate: Candidate) {
    const line = sortedJson(candidate);
    if (logged.current.get(candidate.name) === line) return;
    logged.current.set(candidate.name, line);
    console.info(`UITUNINGLAB_CANDIDATE ${line}`);
  }

  // The one close path. It runs from the popover's toggle event, or directly
  // when the browser has no Popover API. The card keeps the selected look, at
  // real time again.
  function finishClose() {
    setSpeed(1);
    setSent(null);
    setMenuOpen(false);
    setOpen(false);
  }
  function closeLab() {
    const node = panel.current;
    if (node?.hidePopover && node.matches(":popover-open")) node.hidePopover();
    else finishClose();
  }

  useEffect(() => {
    const node = panel.current;
    if (!open || !node) return;
    node.showPopover?.();
    const focusFrame = requestAnimationFrame(() => firstControl.current?.focus());
    const onToggle = (event: Event) => {
      if ((event as ToggleEvent).newState === "closed") finishClose();
    };
    // Escape works wherever focus is, including on the feature. A select, or an
    // app dialog that already handled the key, keeps its own Escape.
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== "Escape" || event.defaultPrevented) return;
      if (event.target instanceof HTMLSelectElement) return;
      closeLab();
    };
    node.addEventListener("toggle", onToggle);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      cancelAnimationFrame(focusFrame);
      node.removeEventListener("toggle", onToggle);
      document.removeEventListener("keydown", onKeyDown);
      if (node.hidePopover && node.matches(":popover-open")) node.hidePopover();
      trigger.current?.focus();
    };
    // finishClose and closeLab read only refs and stable state setters.
  }, [open]);

  // Apply moves focus to Change, and Change moves it back to the chips.
  useEffect(() => { (sent ? changeButton : firstControl).current?.focus(); }, [sent]);

  // Seeded looks log their own line the first time the lab shows them.
  useEffect(() => {
    if (!open) return;
    for (const c of latest.current.candidates) if (!logged.current.has(c.name)) logPin(c);
  }, [open]);

  // The card renders the selected look, slowed by stretching its duration.
  const source = motion;
  const rendered = { ...source, durationMs: source.durationMs / speed };
  const replayNow = () => setReplay(count => count + 1);

  function openLab() { setStatus(null); setOpen(true); }

  // Shows a step. Matching the chip the edits were forked from leaves no
  // unsaved edits, and that chip is outlined again.
  function show(step: Step) {
    setUnsaved(sameLook(step.value, chipLook.value) ? null : step);
    setMotion(step.value);
  }
  function clearHistory() {
    setSteps(noHistory);
    lastControl.current = undefined;
  }

  // Selecting a chip renders its look in the real card and replays it.
  // Switching chips is the comparison. Unsaved edits are dropped, so a chip
  // always shows its look exactly, the one they were forked from included.
  function select(chip: string) {
    if (chip === selected && unsaved === null) return;
    clearHistory();
    setUnsaved(null);
    const pin = candidates.find(c => c.name === chip);
    setSelected(pin ? pin.name : "original");
    setMotion(pin ? savedLook(pin) : { ...baseline });
    replayNow();
  }
  // Every control makes unsaved edits. On an outlined chip the first edit forks
  // it: the edits start from its values and basedOn, and the chip itself never
  // changes. A preset becomes their basedOn. Sliders pass their key as
  // `control`: a run of edits from the same control in a row is one Undo step.
  // Presets pass none, so each is a step.
  function edit(next: EntranceMotion, preset?: string, control?: string) {
    if (sameLook(next, current.value) && (preset === undefined || preset === current.basedOn)) return;
    const extend = control !== undefined && control === lastControl.current && steps.undo.length > 0;
    setSteps({ undo: extend ? steps.undo : [...steps.undo, current], redo: [] });
    lastControl.current = control;
    show({ value: next, basedOn: preset ?? current.basedOn });
  }
  function apply(name: keyof typeof presets) { edit({ ...presets[name] }, name); replayNow(); }
  const resetSpring = () => resetControl("durationMs", "bounce");
  // The spring's ↺ hands focus to its first slider as it goes away.
  const springInput = useRef<HTMLInputElement>(null);
  // Undo steps the unsaved edits back one, never past the chip they were
  // forked from, which is outlined again when they reach it.
  function undo() {
    const previous = steps.undo[steps.undo.length - 1];
    if (!previous) return;
    setSteps({ undo: steps.undo.slice(0, -1), redo: [...steps.redo, current] });
    lastControl.current = undefined;
    show(previous);
  }
  // Redo brings back the edit Undo last took away.
  function redo() {
    const next = steps.redo[steps.redo.length - 1];
    if (!next) return;
    setSteps({ undo: [...steps.undo, current], redo: steps.redo.slice(0, -1) });
    lastControl.current = undefined;
    show(next);
  }
  // Reset drops the unsaved edits back to the chip they were forked from,
  // outlined again, in one step that Undo can take back.
  function reset() {
    if (!hasEdits) return;
    setSteps({ undo: [...steps.undo, current], redo: [] });
    lastControl.current = undefined;
    show(chipLook);
  }
  // ↺ on one control: puts its fields back to Shipped. An ordinary edit:
  // one Undo step that ends the current slider run, so it never merges with a
  // drag. On a pinned look it forks unsaved edits; edits that match the chip
  // they were forked from again are dropped, and that chip is outlined.
  function resetControl(...keys: (keyof EntranceMotion)[]) {
    edit({ ...current.value, ...Object.fromEntries(keys.map(key => [key, baseline[key]])) });
  }
  // Undo and Redo on the keyboard, only while focus is in the panel: Ctrl or
  // Cmd-Z, and Ctrl or Cmd-Shift-Z or Ctrl-Y. A text field keeps its own undo.
  function onPanelKeyDown(event: ReactKeyboardEvent<HTMLDivElement>) {
    if (!(event.ctrlKey || event.metaKey) || event.altKey) return;
    const target = event.target as HTMLElement;
    if ((target instanceof HTMLInputElement && target.type !== "range") ||
        target instanceof HTMLTextAreaElement || target.isContentEditable) return;
    const key = event.key.toLowerCase();
    if (key === "z" && !event.shiftKey) { event.preventDefault(); undo(); }
    else if ((key === "z" && event.shiftKey) || (key === "y" && !event.shiftKey)) { event.preventDefault(); redo(); }
  }

  // Pins the unsaved edits as a new look, named after their preset, selected
  // and outlined, and logs it. Returns the look the pick is (with no unsaved
  // edits the selected chip's, none for Shipped) and the list it is in, read
  // before React re-renders.
  function commit(): { look?: Candidate; list: Candidate[] } {
    if (unsaved === null) return { look: selectedPin, list: candidates };
    const prefix = unsaved.basedOn === "baseline" ? "custom" : unsaved.basedOn;
    const look: Candidate = { name: pinName(issued.current, prefix), basedOn: unsaved.basedOn,
      values: changedValues(baseline, unsaved.value) };
    issued.current.add(look.name);
    const list = [...candidates, look];
    setCandidates(list);
    setSelected(look.name);
    setUnsaved(null);
    clearHistory();
    logPin(look);
    return { look, list };
  }
  // Save & pin, the one save button: pins the unsaved edits and copies the new
  // look's land code. Before the first Apply the agent is listening for Apply,
  // so nothing more happens; after it, the pick is handed over for pasting.
  async function saveLook() {
    if (!hasEdits) return;
    const { look, list } = commit();
    if (!look) return;
    if (applies > 0) { await handOver(look, list); return; }
    setSaved(null);
    const kept = `Pinned ${chipLabel(look.name)}`;
    try {
      await navigator.clipboard.writeText(`land ${look.name}`);
      setStatus(`${kept} · copied land ${look.name}`);
    } catch {
      setStatus(`${kept}; clipboard unavailable, tell the agent "land ${look.name}"`);
    }
  }
  // Apply pins unsaved edits first, like Save & pin, then hands the selected
  // chip over.
  async function applyLook() {
    const { look, list } = commit();
    await handOver(look, list);
  }
  // Reports the selected look as shown, edits included. Speed is a preview
  // setting and never included.
  async function copyValues() {
    setMenuOpen(false);
    const values = sortedJson(selectedValues);
    console.info(`UITUNINGLAB_VALUES ${values}`);
    try {
      await navigator.clipboard.writeText(values);
      setStatus(values === "{}" ? "Same as Shipped" : `Copied ${values}`);
    } catch {
      setStatus(`Clipboard unavailable; values logged to the console: ${values}`);
    }
  }
  function remove(name: string) {
    setCandidates(list => list.filter(c => c.name !== name));
    logged.current.delete(name);
    console.info(`UITUNINGLAB_CANDIDATE_REMOVED ${sortedJson({ name })}`);
    setStatus(`Removed ${chipLabel(name)}`);
    if (selected === name) { setMotion({ ...baseline }); setSelected("original"); clearHistory(); replayNow(); }
  }
  // Hands a pick to the agent: logs it, sends it to the waiter, stores it under
  // `uiTuningLab.result` (one setItem replaces it atomically), copies its land
  // code, and collapses the panel to one bar. Picking again replaces the result.
  // `candidates` carry every pinned look.
  async function handOver(look: Candidate | undefined, list: Candidate[]) {
    const winner = look ? look.name : "original";
    const result = { candidates: list, values: look?.values ?? {}, winner };
    console.info(`UITUNINGLAB_DONE ${sortedJson(result)}`);
    // Hands the pick to the agent's waiter (scripts/wait-for-pick.py) at once,
    // so it resumes without a message. Fire and forget: with nothing listening,
    // the console and the stored result still carry the pick.
    fetch("http://localhost:47321/pick", { method: "POST", mode: "no-cors", keepalive: true,
      body: `UITUNINGLAB_DONE ${sortedJson(result)}` }).catch(() => {});
    const problems: string[] = [];
    try {
      localStorage.setItem(resultKey, sortedJson({ ...result, savedAt: new Date().toISOString() }));
      setSaved(`Saved ${chipLabel(winner)} in localStorage uiTuningLab.result`);
    } catch {
      setSaved(null);
      problems.push("result not saved");
    }
    try {
      await navigator.clipboard.writeText(`land ${winner}`);
      setCopied(true);
    } catch {
      setCopied(false);
      problems.push(`clipboard unavailable; tell the agent "land ${winner}"`);
    }
    setStatus(problems.length > 0 ? `Logged to the console; ${problems.join("; ")}` : null);
    setApplies(n => n + 1);
    setSent(winner);
  }

  return <>
    <EntranceCard key={replay} motion={rendered} />
    <button ref={trigger} type="button" onClick={openLab} disabled={open}
      style={triggerStyle}>Entrance Lab</button>
    {open && <div ref={panel} {...popoverManual} style={panelStyle} role="dialog"
      aria-labelledby="ui-tuning-lab-title" onKeyDown={onPanelKeyDown}>
      {sent ? <><p style={rowStyle}>
        <strong id="ui-tuning-lab-title">{applies > 1
          ? (copied ? `Copied land ${sent}: paste it in chat so the agent applies it` : `Tell the agent: land ${sent}`)
          : `Applied: ${chipLabel(sent)}`}</strong>
        <button ref={changeButton} type="button" onClick={() => setSent(null)}>Change</button>
        <button type="button" onClick={replayNow}>Replay</button>
      </p>
      {(saved ?? status) && <p role="status" style={{ margin: 0, fontSize: "0.85em" }}>
        {saved ?? status}</p>}</> : <>
        <div style={rowStyle}>
          <h2 id="ui-tuning-lab-title" style={{ margin: 0, marginInlineEnd: "auto", fontSize: "1em" }}>
            UI tuning lab</h2>
          <button type="button" aria-label="More actions" aria-expanded={menuOpen}
            onClick={() => setMenuOpen(value => !value)}>⋯</button>
          <button type="button" onClick={closeLab}>Close</button>
        </div>
        {menuOpen && <div style={rowStyle}>
          <button type="button" onClick={copyValues}>Copy values</button>
        </div>}
        <div role="group" aria-label="Looks" style={rowStyle}>
          <button ref={firstControl} type="button" aria-pressed={outlined("original")}
            style={selectedStyle(outlined("original"))}
            onClick={() => select("original")}>Shipped</button>
          {candidates.map(c => <span key={c.name}>
            <button type="button" aria-pressed={outlined(c.name)} style={selectedStyle(outlined(c.name))}
              onClick={() => select(c.name)}>{chipLabel(c.name)}</button>
            {/* × only on the selected look, outlined, so nothing is removed by accident. */}
            {outlined(c.name) && <button type="button" aria-label={`Remove ${chipLabel(c.name)}`}
              onClick={() => remove(c.name)}>×</button>}
          </span>)}
        </div>
        {reducedMotion && <p>Reduced motion is on, so the card shows its reduced animation.</p>}
        <div role="group" aria-label="Controls">
          <button type="button" onClick={() => apply("snappy")}>Snappy</button>
          <button type="button" onClick={() => apply("playful")}>Playful</button>
          {/* The spring is one control made of two sliders: one ↺ puts both
              back to Shipped as one Undo step. */}
          <div role="group" aria-label="Spring">
            <div style={rowStyle}>Spring
              {(motion.durationMs !== baseline.durationMs || motion.bounce !== baseline.bounce) &&
                <button type="button" onClick={() => { resetSpring(); springInput.current?.focus(); }}
                  aria-label={`Reset Spring to default, ${baseline.durationMs} ms, bounce ${baseline.bounce}`}>↺</button>}
            </div>
            <ShippedSlider label="Duration" min={150} max={1500} step={10} unit="ms"
              value={motion.durationMs} shipped={baseline.durationMs}
              onEdit={durationMs => edit({ ...motion, durationMs }, undefined, "durationMs")}
              onReset={resetSpring} resetButton={false} inputRef={springInput}/>
            <ShippedSlider label="Bounce" min={0} max={0.6} step={0.05}
              value={motion.bounce} shipped={baseline.bounce}
              onEdit={bounce => edit({ ...motion, bounce }, undefined, "bounce")}
              onReset={resetSpring} resetButton={false}/>
          </div>
          <ShippedSlider label="Offset" min={0} max={120} unit="px"
            value={motion.offsetPx} shipped={baseline.offsetPx}
            onEdit={offsetPx => edit({ ...motion, offsetPx }, undefined, "offsetPx")}
            onReset={() => resetControl("offsetPx")}/>
        </div>
        <div style={rowStyle}>
          <label>Speed <select value={speed}
            onChange={e => { setSpeed(Number(e.target.value)); replayNow(); }}>
            {speeds.map(s => <option key={s} value={s}>{s}×</option>)}
          </select></label>
          <button type="button" onClick={replayNow}>Replay</button>
        </div>
        <div role="group" aria-label="Edits" style={rowStyle}>
          <button type="button" disabled={steps.undo.length === 0} onClick={undo}>Undo</button>
          <button type="button" disabled={steps.redo.length === 0} onClick={redo}>Redo</button>
          <button type="button" disabled={!hasEdits} onClick={reset}>Reset</button>
        </div>
        <div style={rowStyle}>
          <button type="button" disabled={!hasEdits} onClick={saveLook}>Save & pin</button>
          {/* Apply reaches the agent once; after that it is hidden for good. */}
          {applies === 0 && <button type="button" onClick={applyLook}>Apply</button>}
        </div>
      </>}
      {status && !sent && <p role="status">{status}</p>}
      {!sent && <p style={{ position: "sticky", bottom: 0, margin: 0, padding: "8px 0", background: "Canvas" }}>
        {applies > 0 ? "Save & pin, then paste it in chat"
          : "Save & pin to keep a look · Apply to finish"}</p>}
    </div>}
  </>;
}
```

Slider changes replay the web card immediately because its animation depends on
the motion values; SwiftUI replays when a slider is released. Undo, Redo, and
Reset change the motion too, so they replay the card; on the web, Ctrl-Z and
Ctrl-Shift-Z (Cmd on a Mac, or Ctrl-Y) run Undo and Redo while focus is in the
panel. Save & pin names a web look after its preset (**Snappy-1**,
**Playful-1**, or **Custom-1**), and only a pin logs it. Validate on device
with Reduce Motion on and off, at every speed, and with each chip selected, and
confirm that closing the lab resets speed so the feature plays the selected look
at real time. Looks live in React state and the console log only, and
`initialCandidates` seeds them when reopening the lab; Apply writes the pick
to the `localStorage` key `uiTuningLab.result`.
