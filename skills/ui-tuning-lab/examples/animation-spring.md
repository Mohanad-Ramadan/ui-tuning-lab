# Candidate — entrance animation with spring controls

Animation tuning needs more than sliders: the motion must be replayed on demand,
slowed down to be judged, and flipped against the baseline. This example
tunes a card's entrance spring on SwiftUI and the web. The lab only scales the
values it renders; it never changes global animation speed or the user's
reduced-motion setting.

Every lab in this example provides:

- **Replay**: re-creates the card (a bumped `id` / `key`) so its entrance runs again.
- **Speed**: 1×, 0.5×, 0.25×, or 0.1×, applied by stretching the rendered duration.
- **Chips**: Shipped (the declared default) and each saved look (**Look 1**, **Look 2**, …); the selected chip is
  outlined, and the card always renders it, so switching chips is the
  comparison. Tapping a chip renders it in the real card and replays it. The
  controls edit the selected look in place, and a saved look keeps its edits when
you switch away; on Shipped, which is read-only, they make unsaved changes,
with no chip outlined, until **Save & copy** keeps them as the next Look N.
- **Reduced motion**: the feature keeps its own reduced animation, and the lab says
  when that is what you are seeing.
- **⋯ menu**: Copy values, which copies the selected look's fields that differ
  from the baseline and logs them as one `UITUNINGLAB_VALUES {...}` line for
  landing (`references/landing-protocol.md`). Speed is a preview setting and is
  never included.
- **Save & copy** and **Apply**: Save & copy keeps the current look as the next
  Look N (or saves the selected look) and copies `land look-N`, and is disabled
  on Shipped with no edits; Apply picks the selected chip, logs
  `UITUNINGLAB_DONE`, stores the result, copies `land <name>`, collapses the
  panel to a `Applied:` bar with Change and Replay, and is hidden after its
  first use, as in `references/candidates.md`. The hint *Save & copy to keep a
  look · Apply to finish* is pinned below the controls.

## SwiftUI (iOS 17+)

The toolbar Entrance Lab button is the human path and visible fallback; the DEBUG-only
`-UITuningLabOpen` launch argument is the agent path, read through
`UITuningLabLaunch` (`references/activation.md`). The host owns the
`UITuningLabCandidates` store beside the feature, so the looks and the selection
survive closing the popover, and a name is never reused within a run; seed its
`initial:` array to reopen a session. `motion` always holds the selected look,
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
        .frame(minWidth: 300)
        // The card keeps the selected look; an edited look logs its values.
        .onDisappear { candidates.leave() }
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
                            // × only on the selected look, so nothing is removed by accident.
                            if candidates.selected == pin.name {
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
            LabeledContent("Duration", value: String(format: "%.2f s", motion.duration))
                .accessibilityHidden(true)  // the slider reports its own value
            Slider(value: look.duration, in: 0.15...1.5) {
                Text("Duration")
            } onEditingChanged: { replayWhenReleased($0) }
            LabeledContent("Bounce", value: String(format: "%.2f", motion.bounce))
                .accessibilityHidden(true)  // the slider reports its own value
            Slider(value: look.bounce, in: 0...0.6) {
                Text("Bounce")
            } onEditingChanged: { replayWhenReleased($0) }
            LabeledContent("Offset", value: "\(Int(motion.offset)) pt")
                .accessibilityHidden(true)  // the slider reports its own value
            Slider(value: look.offset, in: 0...120) {
                Text("Offset")
            } onEditingChanged: { replayWhenReleased($0) }
            Picker("Speed", selection: $lab.speed) {
                Text("1×").tag(1.0)
                Text("0.5×").tag(0.5)
                Text("0.25×").tag(0.25)
                Text("0.1×").tag(0.1)
            }
            .pickerStyle(.segmented)
            HStack {
                Button("Replay") { lab.replayToken += 1 }
                // Save & copy keeps the current look as a chip to compare; after the
                // first Apply it also hands the pick over for pasting in chat.
                Button("Save & copy") {
                    let applied = candidates.applies > 0
                    if let name = candidates.saveAndCopy(), applied { sent = name }
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
                ? "Save & copy, then paste it in chat"
                : "Save & copy to keep a look · Apply to finish")
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

    /// The sliders show the selected look and edit it.
    private var look: Binding<EntranceMotion> {
        Binding(get: { motion }, set: { edit($0) })
    }

    /// Every control edits the selected look: a saved look in place, or, on
    /// Shipped, unsaved changes until Save & copy.
    private func edit(_ value: EntranceMotion, preset: String? = nil) {
        candidates.edit(value, preset: preset)
        motion = candidates.selectedLook
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

// A look: the fields that differ from the baseline, plus where it started.
type Candidate = { name: string; basedOn: string; values: Partial<EntranceMotion> };
// Looks the lab opens with. Empty by default; a later session seeds the
// finalists kept in the project here (references/candidates.md).
const initialCandidates: Candidate[] = [];
// Apply writes the pick here, so it survives quitting the app.
const resultKey = "uiTuningLab.result";
// Never issued as a look's name: "original" is the Shipped chip, and the others
// are kept for older logs.
const reservedNames = ["draft", "now", "original", "baseline"];

// Preset keys are kebab-case: the key is what a look records as basedOn.
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

// The next look's name, `look-N`: one past the highest number issued in this
// run, removed ones included, so a number is never reused.
function nextLookName(issued: Set<string>): string {
  const used = [...issued].map(name => /^look-([0-9]+)$/.exec(name)).map(m => (m ? Number(m[1]) : 0));
  return `look-${Math.max(0, ...used) + 1}`;
}
// A chip's label: `Look 2` for `look-2`, Shipped for `original`, else the name.
function chipLabel(name: string): string {
  if (name === "original") return "Shipped";
  const m = /^look-([0-9]+)$/.exec(name);
  return m ? `Look ${m[1]}` : name;
}

export default function UITuningLabEntrance({ motion, setMotion }: TuningLabHostProps) {
  const [open, setOpen] = useState(opensOnLaunch);
  useEffect(clearLaunchRequest, []);
  const [replay, setReplay] = useState(0);
  const [speed, setSpeed] = useState(1);
  // Looks live in memory and in the log; only Apply writes storage. A look is a
  // look being worked on: the controls edit the selected look in place.
  const [candidates, setCandidates] = useState(initialCandidates);
  // Every name issued in this run, removed ones included: names are never reused.
  const issued = useRef(new Set([...reservedNames, ...initialCandidates.map(c => c.name)]));
  // The values each look last logged, so a look logs again only after it changed.
  const logged = useRef(new Map<string, string>());
  // The selected chip: "original" (Shipped) or a look's name. The card always
  // renders it.
  const [selected, setSelected] = useState("original");
  // Edits made on Shipped and not saved yet: the preset they started from, or
  // null when there are none. While set, no chip is outlined.
  const [unsavedBasedOn, setUnsavedBasedOn] = useState<string | null>(null);
  // The winner after Apply; while set, the panel is the result bar.
  const [sent, setSent] = useState<string | null>(null);
  // How many times Apply ran. The first reaches the agent's waiter; after it the
  // agent no longer listens, so the button becomes Save & copy and the next pick goes
  // through chat as a pasted `land <name>`. Change does not reset it.
  const [applies, setApplies] = useState(0);
  const [copied, setCopied] = useState(true);  // the clipboard took `land <name>`
  // The result bar's second line: where Apply saved the pick, or null when it could not.
  const [saved, setSaved] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const panel = useRef<HTMLDivElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  const firstControl = useRef<HTMLButtonElement>(null);
  const changeButton = useRef<HTMLButtonElement>(null);
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const selectedPin = candidates.find(c => c.name === selected);
  const selectedValues = selectedPin?.values ?? changedValues(baseline, motion);
  const shippedOutlined = selected === "original" && unsavedBasedOn === null;

  // Read the latest looks and selection through refs, so the close path, which
  // runs from an effect, never reads stale state.
  const latest = useRef({ candidates, selected });
  useLayoutEffect(() => { latest.current = { candidates, selected }; });

  // Logs a look's line when it is new or changed since it last logged.
  function logPin(candidate: Candidate) {
    const line = sortedJson(candidate);
    if (logged.current.get(candidate.name) === line) return;
    logged.current.set(candidate.name, line);
    console.info(`UITUNINGLAB_CANDIDATE ${line}`);
  }
  // A look edited in place logs its new values once it is left: another chip is
  // selected, the lab closes, or Apply.
  function leave() {
    const { candidates, selected } = latest.current;
    const pin = candidates.find(c => c.name === selected);
    if (pin) logPin(pin);
  }

  // The one close path. It runs from the popover's toggle event, or directly
  // when the browser has no Popover API. The card keeps the selected look, at
  // real time again.
  function finishClose() {
    leave();
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
    for (const c of candidates) if (!logged.current.has(c.name)) logPin(c);
  }, [open, candidates]);

  // The card renders the selected look, slowed by stretching its duration.
  const source = motion;
  const rendered = { ...source, durationMs: source.durationMs / speed };
  const replayNow = () => setReplay(count => count + 1);

  function openLab() { setStatus(null); setOpen(true); }
  // Selecting a chip renders its look in the real card and replays it.
  // Switching chips is the comparison.
  function select(chip: string) {
    if (chip === selected && unsavedBasedOn === null) return;
    leave();
    setUnsavedBasedOn(null);  // unsaved edits on Shipped are dropped
    const pin = candidates.find(c => c.name === chip);
    setMotion({ ...baseline, ...pin?.values });
    setSelected(chip);
    replayNow();
  }
  // Every control edits the selected look. Shipped is read-only, so an edit on
  // it shows live as unsaved changes until Save & copy; a saved look changes in
  // place and keeps its edits when the user switches away.
  function edit(next: EntranceMotion, preset?: string) {
    if (!selectedPin) {
      setUnsavedBasedOn(current => preset ?? current ?? "baseline");
      setMotion(next);
      return;
    }
    const values = changedValues(baseline, next);
    setCandidates(list => list.map(c => c.name === selected
      ? { ...c, values, basedOn: preset ?? c.basedOn } : c));
    setMotion(next);
  }
  function apply(name: keyof typeof presets) { edit({ ...presets[name] }, name); replayNow(); }
  // Keeps the current look: unsaved edits on Shipped become the next Look N,
  // selected; a selected look is logged as it is. Returns the look (none on
  // plain Shipped) and the list it is in, read before React re-renders.
  function keep(): { look?: Candidate; list: Candidate[] } {
    if (selectedPin) { logPin(selectedPin); return { look: selectedPin, list: candidates }; }
    if (unsavedBasedOn === null) return { list: candidates };
    const look: Candidate = { name: nextLookName(issued.current), basedOn: unsavedBasedOn,
      values: changedValues(baseline, motion) };
    issued.current.add(look.name);
    const list = [...candidates, look];
    setCandidates(list);
    setSelected(look.name);
    setUnsavedBasedOn(null);
    logPin(look);
    return { look, list };
  }
  // Save & copy keeps the current look as a chip to compare and copies its
  // land code. Before the first Apply the agent is listening for Apply, so
  // nothing more happens; after it, the pick is handed over for pasting.
  async function saveAndCopy() {
    const { look, list } = keep();
    if (!look) return;
    if (applies > 0) { await handOver(look, list); return; }
    try {
      await navigator.clipboard.writeText(`land ${look.name}`);
      setStatus(`Saved ${chipLabel(look.name)} · copied land ${look.name}`);
    } catch {
      setStatus(`Saved ${chipLabel(look.name)}; clipboard unavailable, tell the agent "land ${look.name}"`);
    }
  }
  // Apply keeps unsaved edits as a look first, then hands the pick over.
  async function applyLook() {
    const { look, list } = keep();
    await handOver(look, list);
  }
  // Reports the selected look. Speed is a preview setting and never included.
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
    if (selected === name) { setMotion({ ...baseline }); setSelected("original"); replayNow(); }
  }
  // Hands a pick to the agent: logs it, sends it to the waiter, stores it under
  // `uiTuningLab.result` (one setItem replaces it atomically), copies its land
  // code, and collapses the panel to one bar. Picking again replaces the result.
  async function handOver(look: Candidate | undefined, list: Candidate[]) {
    const winner = look ? look.name : "original";
    const done = { candidates: list, values: look?.values ?? {}, winner };
    console.info(`UITUNINGLAB_DONE ${sortedJson(done)}`);
    // Hands the pick to the agent's waiter (scripts/wait-for-pick.py) at once,
    // so it resumes without a message. Fire and forget: with nothing listening,
    // the console and the stored result still carry the pick.
    fetch("http://localhost:47321/pick", { method: "POST", mode: "no-cors", keepalive: true,
      body: `UITUNINGLAB_DONE ${sortedJson(done)}` }).catch(() => {});
    const notes: string[] = [];
    try {
      localStorage.setItem(resultKey, sortedJson({ ...done, savedAt: new Date().toISOString() }));
      setSaved(`Saved ${chipLabel(winner)} in localStorage uiTuningLab.result`);
    } catch {
      setSaved(null);
      notes.push("Result not stored");
    }
    try {
      await navigator.clipboard.writeText(`land ${winner}`);
      setCopied(true);
    } catch {
      setCopied(false);
      notes.push(`Clipboard unavailable; tell the agent "land ${winner}"`);
    }
    setStatus(notes.length ? notes.join(". ") : null);
    setApplies(n => n + 1);
    setSent(winner);
  }

  return <>
    <EntranceCard key={replay} motion={rendered} />
    <button ref={trigger} type="button" onClick={openLab} disabled={open}
      style={triggerStyle}>Entrance Lab</button>
    {open && <div ref={panel} {...popoverManual} style={panelStyle} role="dialog"
      aria-labelledby="ui-tuning-lab-title">
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
          <button ref={firstControl} type="button" aria-pressed={shippedOutlined}
            style={selectedStyle(shippedOutlined)}
            onClick={() => select("original")}>Shipped</button>
          {candidates.map(c => <span key={c.name}>
            <button type="button" aria-pressed={selected === c.name} style={selectedStyle(selected === c.name)}
              onClick={() => select(c.name)}>{chipLabel(c.name)}</button>
            {/* × only on the selected look, so nothing is removed by accident. */}
            {selected === c.name && <button type="button" aria-label={`Remove ${chipLabel(c.name)}`}
              onClick={() => remove(c.name)}>×</button>}
          </span>)}
        </div>
        {reducedMotion && <p>Reduced motion is on, so the card shows its reduced animation.</p>}
        <div role="group" aria-label="Controls">
          <button type="button" onClick={() => apply("snappy")}>Snappy</button>
          <button type="button" onClick={() => apply("playful")}>Playful</button>
          <label>Duration <input type="range" min="150" max="1500" step="10"
            value={motion.durationMs}
            onChange={e => edit({ ...motion, durationMs: Number(e.target.value) })}/>
            <output aria-hidden="true">{motion.durationMs}ms</output>
          </label>
          <label>Bounce <input type="range" min="0" max="0.6" step="0.05"
            value={motion.bounce}
            onChange={e => edit({ ...motion, bounce: Number(e.target.value) })}/>
            <output aria-hidden="true">{motion.bounce}</output>
          </label>
          <label>Offset <input type="range" min="0" max="120"
            value={motion.offsetPx}
            onChange={e => edit({ ...motion, offsetPx: Number(e.target.value) })}/>
            <output aria-hidden="true">{motion.offsetPx}px</output>
          </label>
        </div>
        <div style={rowStyle}>
          <label>Speed <select value={speed}
            onChange={e => { setSpeed(Number(e.target.value)); replayNow(); }}>
            {speeds.map(s => <option key={s} value={s}>{s}×</option>)}
          </select></label>
          <button type="button" onClick={replayNow}>Replay</button>
        </div>
        <div style={rowStyle}>
          <button type="button" disabled={!selectedPin && unsavedBasedOn === null}
            onClick={saveAndCopy}>Save & copy</button>
          {/* Apply reaches the agent once; after that it is hidden for good. */}
          {applies === 0 && <button type="button" onClick={applyLook}>Apply</button>}
        </div>
      </>}
      {status && <p role="status">{status}</p>}
      {!sent && <p style={{ position: "sticky", bottom: 0, margin: 0, padding: "8px 0", background: "Canvas" }}>
        {applies > 0 ? "Save & copy, then paste it in chat"
          : "Save & copy to keep a look · Apply to finish"}</p>}
    </div>}
  </>;
}
```

Slider changes replay the web card immediately because its animation depends on
the motion values; SwiftUI replays when a slider is released. Validate on device
with Reduce Motion on and off, at every speed, and with each chip selected, and
confirm that closing the lab resets speed so the feature plays the selected look
at real time. Looks live in React state and the console log only, and
`initialCandidates` seeds them when reopening the lab; Apply writes the pick
to the `localStorage` key `uiTuningLab.result`.
