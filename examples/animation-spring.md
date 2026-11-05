# Candidate — entrance animation with spring controls

Animation tuning needs more than sliders: the motion must be replayed on demand,
slowed down to be judged, and flipped against the baseline. This example
tunes a card's entrance spring on SwiftUI and the web. The lab only scales the
values it renders; it never changes global animation speed or the user's
reduced-motion setting.

Every lab in this example provides:

- **Replay**: re-creates the card (a bumped `id` / `key`) so its entrance runs again.
- **Speed**: 1×, 0.5×, 0.25×, or 0.1×, applied by stretching the rendered duration.
- **Chips**: Original (the declared default), Now (the draft), and each favorite;
  tapping one renders it in the real card and replays it. The controls are
  disabled while Original is shown, and moving one while a favorite is shown
  loads that favorite into Now first.
- **Reduced motion**: the feature keeps its own reduced animation, and the lab says
  when that is what you are seeing.
- **⋯ menu**: Reset, and Copy values, which copies the draft fields that differ
  from the baseline and logs them as one `UITUNINGLAB_VALUES {...}` line for
  landing (`references/landing-protocol.md`). Speed and the chip shown are
  preview settings and are never included.
- **★ Keep** and **✓ Use this**: Keep adds Now to the favorites; Use this picks
  the chip shown, logs `UITUNINGLAB_DONE`, stores the result, copies
  `land <name>`, and collapses the panel to a `✓ Sent:` bar with Change and
  Replay, as in `references/candidates.md`. The hint
  *Keep favorites · Use this to finish* is pinned below the controls.

## SwiftUI (iOS 17+)

The toolbar Tune button is the human path and visible fallback; the DEBUG-only
`-UITuningLabOpen` launch argument is the agent path, read through
`UITuningLabLaunch` (`references/activation.md`). The host owns the
`UITuningLabCandidates` store beside the draft, so favorites and `basedOn`
survive closing the popover, and a name is never reused within a run; seed its
`initial:` array to reopen a session. A chip other than Now renders through
`rendered(draft:baseline:)` while the draft stays in `motion`. Use this writes
Application Support `.ui-tuning-lab/result.json`. Closing the lab shows the
draft at real time again.

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
    // Favorites and basedOn live beside the draft and outlive the popover. To
    // reopen a session, seed the finalists kept in the project here
    // (references/candidates.md).
    @StateObject private var uiTuningLabCandidates =
        UITuningLabCandidates<EntranceMotion>(baseline: .appDefault, initial: [])
    #endif

    var body: some View {
        #if DEBUG
        EntranceCard(motion: uiTuningLab.rendered(draft: motion, baseline: .appDefault))
            .id(uiTuningLab.replayToken)
            .frame(maxHeight: .infinity, alignment: .top)
            .toolbar {
                Button("Tune", action: openUITuningLab)
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
                // Closing shows the draft at real time again. Keep the replay
                // token so closing does not re-create the card.
                if !open {
                    uiTuningLab.speed = 1
                    uiTuningLab.shown = "now"
                    uiTuningLab.showing = nil
                }
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
    var speed = 1.0              // 1 = real time; smaller values slow the preview
    var shown = "now"            // the chip shown: now, original, or a favorite's name
    var showing: EntranceMotion?  // what that chip shows; nil while Now is shown

    func rendered(draft: EntranceMotion, baseline: EntranceMotion) -> EntranceMotion {
        var motion = showing ?? draft
        motion.duration /= speed
        return motion
    }
}

struct UITuningLabMotionControls: View {
    @Binding var motion: EntranceMotion
    @Binding var lab: UITuningLabMotionState
    // Owned by the host beside the draft, so favorites and basedOn survive
    // closing and reopening the lab.
    @ObservedObject var candidates: UITuningLabCandidates<EntranceMotion>
    let baseline: EntranceMotion
    @State private var status: String?
    @State private var sent: String?  // the last pick; set, the lab is one bar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    private static let snappy = EntranceMotion(duration: 0.3, bounce: 0, offset: 24)
    private static let playful = EntranceMotion(duration: 0.7, bounce: 0.45, offset: 64)

    var body: some View {
        if let sent {
            // ✓ Use this collapses the lab to one bar; Change reopens it.
            VStack(alignment: .leading) {
                HStack {
                    Text("✓ Sent: \(sent)")
                    Spacer()
                    Button("Change") { self.sent = nil }
                    Button("Replay") { lab.replayToken += 1 }
                }
                if let status { Text(status).font(.footnote) }
                Spacer(minLength: 0)
            }
            .padding()
            .frame(minWidth: 300)
        } else {
            panel
        }
    }

    private var panel: some View {
        Form {
            HStack {
                Text("UI tuning lab").font(.headline)
                Spacer()
                Menu {
                    Button("Reset", action: reset)
                    Button("Copy values") {
                        // Copy values always reports Now, whatever chip is shown.
                        status = uiTuningLabCopyValues(from: baseline, to: motion)
                    }
                } label: {
                    Text("⋯")
                }
                .accessibilityLabel("More")
                Button("Close") { dismiss() }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    chip("Original", id: "original")
                    chip("Now", id: "now")
                    ForEach(candidates.all) { favorite in
                        HStack(spacing: 2) {
                            chip(favorite.name, id: favorite.name)
                            Button("×") { remove(favorite.name) }
                                .accessibilityLabel("Remove \(favorite.name)")
                        }
                    }
                }
            }
            if reduceMotion {
                Text("Reduce Motion is on, so the card shows its reduced animation.")
            }
            Group {
                HStack {
                    Button("Snappy") { apply(Self.snappy, named: "snappy") }
                    Button("Playful") { apply(Self.playful, named: "playful") }
                }
                LabeledContent("Duration", value: String(format: "%.2f s", draft.wrappedValue.duration))
                    .accessibilityHidden(true)  // the slider reports its own value
                Slider(value: draft.duration, in: 0.15...1.5) {
                    Text("Duration")
                } onEditingChanged: { replayWhenReleased($0) }
                LabeledContent("Bounce", value: String(format: "%.2f", draft.wrappedValue.bounce))
                    .accessibilityHidden(true)  // the slider reports its own value
                Slider(value: draft.bounce, in: 0...0.6) {
                    Text("Bounce")
                } onEditingChanged: { replayWhenReleased($0) }
                LabeledContent("Offset", value: "\(Int(draft.wrappedValue.offset)) pt")
                    .accessibilityHidden(true)  // the slider reports its own value
                Slider(value: draft.offset, in: 0...120) {
                    Text("Offset")
                } onEditingChanged: { replayWhenReleased($0) }
            }
            .disabled(lab.shown == "original")
            Picker("Speed", selection: $lab.speed) {
                Text("1×").tag(1.0)
                Text("0.5×").tag(0.5)
                Text("0.25×").tag(0.25)
                Text("0.1×").tag(0.1)
            }
            .pickerStyle(.segmented)
            HStack {
                Button("Replay") { lab.replayToken += 1 }
                Button("★ Keep", action: keep)
                    .accessibilityLabel("Keep")
                    .disabled(lab.shown != "now")
                Button("✓ Use this", action: useThis)
                    .accessibilityLabel("Use this")
            }
            if let status { Text(status).font(.footnote) }
        }
        // Pinned below the scrolling controls, so it shows at every detent.
        .safeAreaInset(edge: .bottom) {
            Text("Keep favorites · Use this to finish")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
        }
        .onChange(of: lab.shown) { lab.replayToken += 1 }
        .onChange(of: lab.speed) { lab.replayToken += 1 }
        .frame(minWidth: 300)
        // A Form row with several buttons fires all of them on iOS unless borderless.
        .buttonStyle(.borderless)
    }

    /// One chip; the highlighted chip is the one the card shows.
    private func chip(_ title: String, id: String) -> some View {
        Button(title) { show(id) }
            .buttonStyle(.bordered)
            .tint(lab.shown == id ? .accentColor : .secondary)
            .accessibilityAddTraits(lab.shown == id ? .isSelected : [])
    }

    /// Shows a chip in the real card. Now stays in `motion` the whole time.
    private func show(_ id: String) {
        lab.showing = id == "now" ? nil : id == "original" ? baseline : candidates.named(id)?.value
        lab.shown = lab.showing == nil ? "now" : id
    }

    /// The controls show and edit what is on screen. Moving one while a favorite
    /// is shown first loads that favorite into Now; the favorite does not change.
    private var draft: Binding<EntranceMotion> {
        Binding(get: { lab.showing ?? motion }, set: { edit($0) })
    }

    private func edit(_ value: EntranceMotion) {
        if lab.shown != "now" {
            candidates.basedOn = lab.shown
            lab.shown = "now"
            lab.showing = nil
        }
        motion = value
    }

    private func apply(_ preset: EntranceMotion, named name: String) {
        edit(preset)
        candidates.basedOn = name
        lab.replayToken += 1
    }

    private func reset() {
        edit(baseline)
        candidates.basedOn = "baseline"
        lab.replayToken += 1
    }

    private func remove(_ name: String) {
        if lab.shown == name { show("now") }
        candidates.remove(name)
        status = "Removed \(name)"
    }

    private func keep() {
        do {
            let kept = try candidates.keep(motion)
            status = "Kept \(kept.name)"
        } catch {
            status = error.localizedDescription
        }
    }

    /// Picks the chip on screen: a favorite, `original`, or `draft` for Now.
    private func useThis() {
        let winner = lab.shown == "now" ? "draft" : lab.shown
        status = candidates.use(lab.showing ?? motion, winner: winner)
        sent = winner
    }

    private func replayWhenReleased(_ editing: Bool) {
        if !editing { lab.replayToken += 1 }
    }
}
#endif
```

<!-- copy: assets/swift/UITuningLabValues.swift -->
`UITuningLabValues.swift`: copy `assets/swift/UITuningLabValues.swift` into the
app's target unchanged. It holds Copy values, the favorites store, favorite
names, Use this with its result file, and the log lines every Swift lab shares,
all inside `#if DEBUG`.

## Web (React)

`springEasing` turns a bounce value into a CSS `linear()` easing so the same spring
runs through the Web Animations API. `linear()` needs Chromium 113+, Safari 17.2+,
or Firefox 112+. The Tune button is the human path and visible fallback;
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
import { useEffect, useRef, useState } from "react";
import { appDefault, EntranceCard } from "./EntranceCard";
import type { EntranceMotion } from "./EntranceCard";
import type { TuningLabHostProps } from "./EntranceScreen";

// A manual popover stays open while the user clicks and scrolls the feature;
// Close and Escape dismiss it. React 18 types omit `popover`, so it is spread.
const popoverManual = { popover: "manual" };
// Pinned beside the feature rather than centered over it; the fixed trigger
// never shifts the feature's layout.
const panelStyle = {
  insetBlockStart: "auto", insetInlineStart: "auto", insetBlockEnd: 72, insetInlineEnd: 16,
  margin: 0, maxWidth: "min(320px, calc(100vw - 32px))", maxHeight: "calc(100dvh - 88px)",
  overflow: "auto", colorScheme: "light dark", font: "inherit",
} as const;
const triggerStyle = { position: "fixed", insetBlockEnd: 16, insetInlineEnd: 16 } as const;

// A favorite: the fields that differ from the baseline, plus where it started.
type Candidate = { name: string; basedOn: string; values: Partial<EntranceMotion> };
// Favorites the lab opens with. Empty by default; a later session seeds the
// finalists kept in the project here (references/candidates.md).
const initialCandidates: Candidate[] = [];

// Preset keys are kebab-case: the key is what a favorite records as basedOn.
const presets = {
  snappy: { durationMs: 350, bounce: 0, offsetPx: 24 },
  playful: { durationMs: 900, bounce: 0.45, offsetPx: 64 },
} satisfies Record<string, EntranceMotion>;
const speeds = [1, 0.5, 0.25, 0.1];
// The baseline is the declared default, never the value on screen when the lab
// opens: a draft kept from an earlier session must still count as a change.
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

// The draft fields that differ from the baseline.
function changedValues<T extends object>(baseline: T, draft: T): Partial<T> {
  return Object.fromEntries(Object.entries(draft).filter(
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

// A favorite's name: `stem`, or `stem-2`, `stem-3`, ... when taken. Names are
// never reused in a run, and never a chip or basedOn word.
function favoriteName(stem: string, issued: Set<string>): string {
  const taken = (name: string) => issued.has(name) || ["draft", "now", "original", "baseline"].includes(name);
  if (!taken(stem)) return stem;
  for (let i = 2; ; i++) {
    if (!taken(`${stem}-${i}`)) return `${stem}-${i}`;
  }
}

export default function UITuningLabEntrance({ motion, setMotion }: TuningLabHostProps) {
  const [open, setOpen] = useState(opensOnLaunch);
  useEffect(clearLaunchRequest, []);
  const [replay, setReplay] = useState(0);
  const [speed, setSpeed] = useState(1);
  // What the card renders: "draft", "baseline", or a candidate's name. The draft
  // stays in `motion` the whole time, so nothing needs stashing.
  // The chip shown: "now", "original", or a favorite's name. The draft stays in
  // `motion` the whole time, so nothing needs stashing.
  const [shown, setShown] = useState("now");
  // Favorites live in memory and in the log; only Use this writes storage.
  const [candidates, setCandidates] = useState(initialCandidates);
  // Every name issued in this run, removed ones included: names are never reused.
  const issued = useRef(new Set(initialCandidates.map(c => c.name)));
  // Favorites already written to the log, so seeded ones log once.
  const logged = useRef(new Set<string>());
  // Where the draft came from: a preset, "baseline", or a favorite's name.
  const [basedOn, setBasedOn] = useState("baseline");
  // The last pick; while set, the panel is one bar.
  const [sent, setSent] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);
  const panel = useRef<HTMLDivElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  const firstControl = useRef<HTMLButtonElement>(null);
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;

  // The one close path. It runs from the popover's toggle event, or directly
  // when the browser has no Popover API.
  function finishClose() {
    setOpen(false);
    setSpeed(1);
    setShown("now");
    setSent(null);
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

  const shownCandidate = candidates.find(c => c.name === shown);
  // Seeded favorites log their own line the first time the lab shows them; the
  // set also guards StrictMode's repeated effects.
  useEffect(() => {
    if (!open) return;
    for (const c of candidates) {
      if (logged.current.has(c.name)) continue;
      logged.current.add(c.name);
      console.info(`UITUNINGLAB_CANDIDATE ${sortedJson(c)}`);
    }
  }, [open, candidates]);

  const source = shown === "original" ? baseline
    : shownCandidate ? { ...baseline, ...shownCandidate.values } : motion;
  const rendered = { ...source, durationMs: source.durationMs / speed };
  const replayNow = () => setReplay(count => count + 1);

  function openLab() { setStatus(null); setOpen(true); }
  async function copyValues() {
    // Copy values always reports Now, whatever chip is shown.
    const values = JSON.stringify(changedValues(baseline, motion));
    console.info(`UITUNINGLAB_VALUES ${values}`);
    try {
      await navigator.clipboard.writeText(values);
      setStatus(values === "{}" ? "No changes from baseline" : `Copied ${values}`);
    } catch {
      setStatus(`Clipboard unavailable; values logged to the console: ${values}`);
    }
  }
  // The controls show and edit what is on screen. Moving one while a favorite is
  // shown first loads that favorite into Now; the favorite does not change.
  function edit(patch: Partial<EntranceMotion>, from?: string) {
    if (shown === "now") setMotion(m => ({ ...m, ...patch }));
    else setMotion({ ...source, ...patch });
    setBasedOn(from ?? shownCandidate?.name ?? basedOn);
    setShown("now");
  }
  function reset() { edit(baseline, "baseline"); replayNow(); }
  function apply(name: keyof typeof presets) { edit(presets[name], name); replayNow(); }
  function show(chip: string) { setShown(chip); replayNow(); }
  function keep() {
    const values = changedValues(baseline, motion);
    if (Object.keys(values).length === 0) {
      setStatus("Same as Original");
      return;
    }
    const same = candidates.find(c => sortedJson(c.values) === sortedJson(values));
    if (same) {
      setStatus(`Same as ${same.name}`);
      return;
    }
    // Named after the last preset, `tweak` from the baseline, or the favorite it
    // was loaded from without its number.
    const stem = basedOn === "baseline" ? "tweak"
      : issued.current.has(basedOn) ? basedOn.replace(/-[0-9]+$/, "") : basedOn;
    const candidate: Candidate = { name: favoriteName(stem, issued.current), basedOn, values };
    setCandidates(list => [...list, candidate]);
    issued.current.add(candidate.name);
    logged.current.add(candidate.name);
    console.info(`UITUNINGLAB_CANDIDATE ${sortedJson(candidate)}`);
    setStatus(`Kept ${candidate.name}`);
  }
  function remove(name: string) {
    setCandidates(list => list.filter(c => c.name !== name));
    console.info(`UITUNINGLAB_CANDIDATE_REMOVED ${sortedJson({ name })}`);
    if (shown === name) show("now");
  }
  // Picks the chip on screen and finishes: logs the result, stores it under
  // `uiTuningLab.result` (one setItem replaces it atomically), copies
  // `land <name>`, and collapses the panel to one bar.
  async function useThis() {
    const winner = shown === "now" ? "draft" : shown;
    const done = { candidates, values: changedValues(baseline, source), winner };
    console.info(`UITUNINGLAB_DONE ${sortedJson(done)}`);
    const notes: string[] = [];
    try {
      localStorage.setItem("uiTuningLab.result",
        sortedJson({ ...done, savedAt: new Date().toISOString() }));
    } catch {
      notes.push("Result not stored");
    }
    try {
      await navigator.clipboard.writeText(`land ${winner}`);
    } catch {
      notes.push(`Clipboard unavailable; tell the agent "land ${winner}"`);
    }
    setStatus(notes.length ? notes.join(". ") : null);
    setSent(winner);
  }

  const chipStyle = (chip: string) => ({ fontWeight: shown === chip ? 700 : 400,
    outline: shown === chip ? "2px solid AccentColor" : undefined });

  return <>
    <EntranceCard key={replay} motion={rendered} />
    <button ref={trigger} type="button" onClick={openLab} disabled={open}
      style={triggerStyle}>Tune</button>
    {open && <div ref={panel} {...popoverManual} style={panelStyle} role="dialog"
      aria-labelledby="ui-tuning-lab-title">
      {sent ? <>
        <p id="ui-tuning-lab-title" role="status">✓ Sent: {sent}{" "}
          <button type="button" onClick={() => setSent(null)}>Change</button>{" "}
          <button type="button" onClick={replayNow}>Replay</button>
        </p>
        {status && <p>{status}</p>}
      </> : <>
        <h2 id="ui-tuning-lab-title">UI tuning lab</h2>
        <details>
          <summary aria-label="More">⋯</summary>
          <button type="button" onClick={reset}>Reset</button>
          <button type="button" onClick={copyValues}>Copy values</button>
        </details>
        <button type="button" onClick={closeLab}>Close</button>
        <div role="group" aria-label="Looks">
          {["original", "now", ...candidates.map(c => c.name)].map(chip => <span key={chip}>
            <button type="button" aria-pressed={shown === chip} style={chipStyle(chip)}
              onClick={() => show(chip)}>
              {chip === "original" ? "Original" : chip === "now" ? "Now" : chip}</button>
            {chip !== "original" && chip !== "now" && <button type="button"
              aria-label={`Remove ${chip}`} onClick={() => remove(chip)}>×</button>}{" "}
          </span>)}
        </div>
        {reducedMotion && <p>Reduced motion is on, so the card shows its reduced animation.</p>}
        <fieldset disabled={shown === "original"} style={{ border: 0, margin: 0, padding: 0 }}>
          <button ref={firstControl} type="button"
            onClick={() => apply("snappy")}>Snappy</button>
          <button type="button" onClick={() => apply("playful")}>Playful</button>
          <label>Duration <input type="range" min="150" max="1500" step="10"
            value={source.durationMs}
            onChange={e => edit({ durationMs: Number(e.target.value) })}/>
            <output aria-hidden="true">{source.durationMs}ms</output>
          </label>
          <label>Bounce <input type="range" min="0" max="0.6" step="0.05"
            value={source.bounce}
            onChange={e => edit({ bounce: Number(e.target.value) })}/>
            <output aria-hidden="true">{source.bounce}</output>
          </label>
          <label>Offset <input type="range" min="0" max="120"
            value={source.offsetPx}
            onChange={e => edit({ offsetPx: Number(e.target.value) })}/>
            <output aria-hidden="true">{source.offsetPx}px</output>
          </label>
        </fieldset>
        <label>Speed <select value={speed}
          onChange={e => { setSpeed(Number(e.target.value)); replayNow(); }}>
          {speeds.map(s => <option key={s} value={s}>{s}×</option>)}
        </select></label>
        <button type="button" onClick={replayNow}>Replay</button>
        <button type="button" aria-label="Keep" disabled={shown !== "now"} onClick={keep}>★ Keep</button>
        <button type="button" aria-label="Use this" onClick={useThis}>✓ Use this</button>
        {status && <p role="status">{status}</p>}
        <p style={{ position: "sticky", bottom: 0, margin: 0, padding: "8px 0", background: "Canvas" }}>
          Keep favorites · Use this to finish</p>
      </>}
    </div>}
  </>;
}
```

Slider changes replay the web card immediately because its animation depends on
the motion values; SwiftUI replays when a slider is released. Validate on device
with Reduce Motion on and off, at every speed, and with each chip shown, and
confirm that closing the lab resets speed and the chip so the feature renders the
draft at real time. Favorites live in React state and the console log only, and
`initialCandidates` seeds them when reopening the lab; Use this writes the pick
to the `localStorage` key `uiTuningLab.result`.
