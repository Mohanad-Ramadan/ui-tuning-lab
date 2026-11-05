# Candidate — entrance animation with spring controls

Animation tuning needs more than sliders: the motion must be replayed on demand,
slowed down to be judged, and flipped against the baseline. This example
tunes a card's entrance spring on SwiftUI and the web. The lab only scales the
values it renders; it never changes global animation speed or the user's
reduced-motion setting.

Every lab in this example provides:

- **Replay**: re-creates the card (a bumped `id` / `key`) so its entrance runs again.
- **Speed**: 1×, 0.5×, 0.25×, or 0.1×, applied by stretching the rendered duration.
- **Show baseline**: flips the rendered motion between the baseline (the declared
  default) and the draft, replaying each time.
- **Reduced motion**: the feature keeps its own reduced animation, and the lab says
  when that is what you are seeing.
- **Copy values**: copies the draft fields that differ from the baseline and logs
  them as one `UITUNINGLAB_VALUES {...}` line for landing
  (`references/landing-protocol.md`). Speed and the flip are preview settings and
  are never included.
- **Keep as candidate, Compare, Done**: finalists, a picker that renders each one in
  the real card, and the session-end signal, as in `references/candidates.md`.

## SwiftUI (iOS 17+)

The toolbar Tune button is the human path and visible fallback; the DEBUG-only
`-UITuningLabOpen` launch argument is the agent path, read through
`UITuningLabLaunch` (`references/activation.md`). The host owns the
`UITuningLabCandidates` store beside the draft, so candidates and `basedOn`
survive closing the popover, and a name is never reused within a run; seed its
`initial:` array to reopen a session. Compare renders a candidate through
`rendered(draft:baseline:)` and is exclusive with Show baseline; as with the
baseline, the first edit switches back to the draft. Keep and Load are disabled
while anything else is shown, and Done only while Show baseline is on: while
Compare shows a candidate, Done loads it into the draft first, so it is the
winner. The finish hint is pinned below the scrolling Form. Closing the lab
shows the draft again.

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
    // Candidates and basedOn live beside the draft and outlive the popover. To
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
                    uiTuningLab.showBaseline = false
                    uiTuningLab.comparing = nil
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
    var speed = 1.0           // 1 = real time; smaller values slow the preview
    var showBaseline = false
    var comparing: UITuningLabCandidate<EntranceMotion>?  // set while Compare shows a candidate

    func rendered(draft: EntranceMotion, baseline: EntranceMotion) -> EntranceMotion {
        var motion = showBaseline ? baseline : (comparing?.value ?? draft)
        motion.duration /= speed
        return motion
    }
}

struct UITuningLabMotionControls: View {
    @Binding var motion: EntranceMotion
    @Binding var lab: UITuningLabMotionState
    // Owned by the host beside the draft, so candidates and basedOn survive
    // closing and reopening the lab.
    @ObservedObject var candidates: UITuningLabCandidates<EntranceMotion>
    let baseline: EntranceMotion
    @State private var status: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let snappy = EntranceMotion(duration: 0.3, bounce: 0, offset: 24)
    private static let playful = EntranceMotion(duration: 0.7, bounce: 0.45, offset: 64)

    var body: some View {
        Form {
            if reduceMotion {
                Text("Reduce Motion is on, so the card shows its reduced animation.")
            }
            HStack {
                Button("Snappy") { apply(Self.snappy, named: "snappy") }
                Button("Playful") { apply(Self.playful, named: "playful") }
            }
            LabeledContent("Duration", value: String(format: "%.2f s", motion.duration))
                .accessibilityHidden(true)  // the slider reports its own value
            Slider(value: $motion.duration, in: 0.15...1.5) {
                Text("Duration")
            } onEditingChanged: { replayWhenReleased($0) }
            LabeledContent("Bounce", value: String(format: "%.2f", motion.bounce))
                .accessibilityHidden(true)  // the slider reports its own value
            Slider(value: $motion.bounce, in: 0...0.6) {
                Text("Bounce")
            } onEditingChanged: { replayWhenReleased($0) }
            LabeledContent("Offset", value: "\(Int(motion.offset)) pt")
                .accessibilityHidden(true)  // the slider reports its own value
            Slider(value: $motion.offset, in: 0...120) {
                Text("Offset")
            } onEditingChanged: { replayWhenReleased($0) }
            Picker("Speed", selection: $lab.speed) {
                Text("1×").tag(1.0)
                Text("0.5×").tag(0.5)
                Text("0.25×").tag(0.25)
                Text("0.1×").tag(0.1)
            }
            .pickerStyle(.segmented)
            Toggle("Show baseline", isOn: $lab.showBaseline)
            if !candidates.all.isEmpty {
                Picker("Compare", selection: comparedCandidate) {
                    Text("Draft").tag(String?.none)
                    ForEach(candidates.all) { Text($0.name).tag(Optional($0.name)) }
                }
            }
            HStack {
                Button("Replay") { lab.replayToken += 1 }
                Button("Reset") { motion = baseline; candidates.basedOn = "baseline"; lab.replayToken += 1 }
                Button("Copy values") {
                    status = uiTuningLabCopyValues(from: baseline, to: motion)
                }
            }
            HStack {
                Button("Keep as candidate", action: keep)
                    // Keep snapshots the draft, so only while the draft is shown.
                    .disabled(lab.showBaseline || lab.comparing != nil)
                // While Compare shows a candidate, Done lands that candidate.
                Button("Done", action: done)
                    .disabled(lab.showBaseline)
            }
            if !candidates.all.isEmpty {
                Section("Candidates") {
                    ForEach(candidates.all) { candidate in
                        HStack {
                            Text("\(candidate.name), from \(candidate.basedOn)")
                            Spacer()
                            Button("Load") { load(candidate) }
                                .accessibilityLabel("Load \(candidate.name)")
                                .disabled(lab.showBaseline || lab.comparing != nil)
                            Button("Remove") { remove(candidate.name) }
                                .accessibilityLabel("Remove \(candidate.name)")
                        }
                    }
                }
            }
            if let status { Text(status).font(.footnote) }
        }
        // Pinned below the scrolling controls, so it shows at every detent.
        .safeAreaInset(edge: .bottom) {
            Text("Finished? Keep the ones you like, then press Done, or tell the agent \"land b\".")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
        }
        .onChange(of: lab.showBaseline) { _, shown in
            // Show baseline and Compare are exclusive.
            if shown { lab.comparing = nil }
            lab.replayToken += 1
        }
        .onChange(of: lab.comparing?.name) { lab.replayToken += 1 }
        // Editing the draft shows the draft, so a change is never hidden.
        .onChange(of: motion) { lab.showBaseline = false; lab.comparing = nil }
        .onChange(of: lab.speed) { lab.replayToken += 1 }
        .frame(minWidth: 300)
        // A Form row with several buttons fires all of them on iOS unless borderless.
        .buttonStyle(.borderless)
    }

    /// Shows a candidate in the real feature; Draft shows the draft again.
    private var comparedCandidate: Binding<String?> {
        Binding(
            get: { lab.comparing?.name },
            set: { name in
                lab.showBaseline = false
                lab.comparing = name.flatMap(candidates.named)
            }
        )
    }

    private func apply(_ preset: EntranceMotion, named name: String) {
        motion = preset
        candidates.basedOn = name
        lab.replayToken += 1
    }

    private func keep() {
        do {
            let kept = try candidates.keep(motion)
            status = "Kept \(kept.name)"
        } catch {
            status = error.localizedDescription
        }
    }

    private func done() {
        // The candidate on screen becomes the draft, so it is the winner.
        var draft = motion
        if let candidate = lab.comparing {
            load(candidate)
            draft = candidate.value
        }
        status = candidates.done(draft)
    }

    private func load(_ candidate: UITuningLabCandidate<EntranceMotion>) {
        motion = candidate.value
        candidates.basedOn = candidate.name
        lab.showBaseline = false
        lab.comparing = nil
        lab.replayToken += 1
        status = "Loaded \(candidate.name)"
    }

    private func remove(_ name: String) {
        if lab.comparing?.name == name { lab.comparing = nil }
        candidates.remove(name)
        status = "Removed \(name)"
    }

    private func replayWhenReleased(_ editing: Bool) {
        if !editing { lab.replayToken += 1 }
    }
}
#endif
```

<!-- copy: assets/swift/UITuningLabValues.swift -->
`UITuningLabValues.swift`: copy `assets/swift/UITuningLabValues.swift` into the
app's target unchanged. It holds Copy values, the candidate store, candidate
names, and the log lines every Swift lab shares, all inside `#if DEBUG`.

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

// A finalist: the fields that differ from the baseline, plus where it started.
type Candidate = { name: string; basedOn: string; values: Partial<EntranceMotion> };
// Candidates the lab opens with. Empty by default; a later session seeds the
// finalists kept in the project here (references/candidates.md).
const initialCandidates: Candidate[] = [];

// Preset keys are kebab-case: the key is what a candidate records as basedOn.
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

// 1 -> a, 26 -> z, 27 -> aa, 28 -> ab, ... (bijective base 26)
function candidateName(index: number): string {
  let name = "";
  for (let n = index; n > 0; n = Math.floor(n / 26)) {
    n -= 1;
    name = String.fromCharCode(97 + (n % 26)) + name;
  }
  return name;
}
// The first name never issued in this run, so a removed name is not reused.
function nextName(issued: Set<string>): string {
  for (let i = 1; ; i++) {
    if (!issued.has(candidateName(i))) return candidateName(i);
  }
}

export default function UITuningLabEntrance({ motion, setMotion }: TuningLabHostProps) {
  const [open, setOpen] = useState(opensOnLaunch);
  useEffect(clearLaunchRequest, []);
  const [replay, setReplay] = useState(0);
  const [speed, setSpeed] = useState(1);
  // What the card renders: "draft", "baseline", or a candidate's name. The draft
  // stays in `motion` the whole time, so nothing needs stashing.
  const [shown, setShown] = useState("draft");
  const showBaseline = shown === "baseline";
  // Candidates live in memory and in the log; nothing is written to storage.
  const [candidates, setCandidates] = useState(initialCandidates);
  // Every name issued in this run, removed ones included: names are never reused.
  const issued = useRef(new Set(initialCandidates.map(c => c.name)));
  // Candidates already written to the log, so seeded ones log once.
  const logged = useRef(new Set<string>());
  // Where the draft came from: a preset, "baseline", or a candidate's name.
  const [basedOn, setBasedOn] = useState("baseline");
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
    setShown("draft");
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
  // Seeded candidates log their own line the first time the lab shows them; the
  // set also guards StrictMode's repeated effects.
  useEffect(() => {
    if (!open) return;
    for (const c of candidates) {
      if (logged.current.has(c.name)) continue;
      logged.current.add(c.name);
      console.info(`UITUNINGLAB_CANDIDATE ${sortedJson(c)}`);
    }
  }, [open, candidates]);

  const source = showBaseline ? baseline
    : shownCandidate ? { ...baseline, ...shownCandidate.values } : motion;
  const rendered = { ...source, durationMs: source.durationMs / speed };
  const replayNow = () => setReplay(count => count + 1);

  function openLab() { setStatus(null); setOpen(true); }
  async function copyValues() {
    const values = JSON.stringify(changedValues(baseline, motion));
    console.info(`UITUNINGLAB_VALUES ${values}`);
    try {
      await navigator.clipboard.writeText(values);
      setStatus(values === "{}" ? "No changes from baseline" : `Copied ${values}`);
    } catch {
      setStatus(`Clipboard unavailable; values logged to the console: ${values}`);
    }
  }
  function reset() { setShown("draft"); setMotion({ ...baseline }); setBasedOn("baseline"); replayNow(); }
  function apply(name: keyof typeof presets) {
    setShown("draft");
    setMotion({ ...presets[name] });
    setBasedOn(name);
    replayNow();
  }
  // Editing the draft shows the draft, so a change is never hidden.
  function edit(patch: Partial<EntranceMotion>) {
    setShown("draft");
    setMotion(m => ({ ...m, ...patch }));
  }
  // Show baseline and Compare are exclusive: each switches the other off.
  function show(target: string) { setShown(target); replayNow(); }
  function keep() {
    const values = changedValues(baseline, motion);
    if (Object.keys(values).length === 0) {
      setStatus("Matches the baseline; nothing to keep");
      return;
    }
    const same = candidates.find(c => sortedJson(c.values) === sortedJson(values));
    if (same) {
      setStatus(`Same as ${same.name}`);
      return;
    }
    const candidate: Candidate = { name: nextName(issued.current), basedOn, values };
    setCandidates(list => [...list, candidate]);
    issued.current.add(candidate.name);
    logged.current.add(candidate.name);
    console.info(`UITUNINGLAB_CANDIDATE ${sortedJson(candidate)}`);
    setStatus(`Kept as ${candidate.name}`);
  }
  function load(candidate: Candidate) {
    setMotion({ ...baseline, ...candidate.values });
    setBasedOn(candidate.name);
    show("draft");
  }
  function remove(name: string) {
    setCandidates(list => list.filter(c => c.name !== name));
    console.info(`UITUNINGLAB_CANDIDATE_REMOVED ${sortedJson({ name })}`);
    if (shown === name) show("draft");
  }
  // Like Copy values, and it tells the agent the session is over. While Compare
  // shows a candidate, that candidate becomes the draft first, so it is the winner.
  async function done() {
    const picked = candidates.find(c => c.name === shown);
    if (picked) load(picked);
    const values = changedValues(baseline, picked ? { ...baseline, ...picked.values } : motion);
    const winner = candidates.find(c => sortedJson(c.values) === sortedJson(values));
    console.info(`UITUNINGLAB_DONE ${sortedJson({ candidates, values, winner: winner?.name ?? null })}`);
    const text = JSON.stringify(values);
    try {
      await navigator.clipboard.writeText(text);
      setStatus(`Done. Copied ${text}`);
    } catch {
      setStatus(`Done. Clipboard unavailable; values logged to the console: ${text}`);
    }
  }

  return <>
    <EntranceCard key={replay} motion={rendered} />
    <button ref={trigger} type="button" onClick={openLab} disabled={open}
      style={triggerStyle}>Tune</button>
    {open && <div ref={panel} {...popoverManual} style={panelStyle} role="dialog"
      aria-labelledby="ui-tuning-lab-title">
      <h2 id="ui-tuning-lab-title">UI tuning lab</h2>
      <button type="button" onClick={closeLab}>Close</button>
      {reducedMotion && <p>Reduced motion is on, so the card shows its reduced animation.</p>}
      <button ref={firstControl} type="button"
        onClick={() => apply("snappy")}>Snappy</button>
      <button type="button" onClick={() => apply("playful")}>Playful</button>
      <label>Duration <input type="range" min="150" max="1500" step="10"
        value={motion.durationMs}
        onChange={e => edit({ durationMs: Number(e.target.value) })}/>
        <output aria-hidden="true">{motion.durationMs}ms</output>
      </label>
      <label>Bounce <input type="range" min="0" max="0.6" step="0.05"
        value={motion.bounce}
        onChange={e => edit({ bounce: Number(e.target.value) })}/>
        <output aria-hidden="true">{motion.bounce}</output>
      </label>
      <label>Offset <input type="range" min="0" max="120"
        value={motion.offsetPx}
        onChange={e => edit({ offsetPx: Number(e.target.value) })}/>
        <output aria-hidden="true">{motion.offsetPx}px</output>
      </label>
      <label>Speed <select value={speed}
        onChange={e => { setSpeed(Number(e.target.value)); replayNow(); }}>
        {speeds.map(s => <option key={s} value={s}>{s}×</option>)}
      </select></label>
      <button type="button" aria-pressed={showBaseline}
        onClick={() => show(showBaseline ? "draft" : "baseline")}>Show baseline</button>
      <button type="button" onClick={replayNow}>Replay</button>
      <button type="button" onClick={reset}>Reset</button>
      <button type="button" onClick={copyValues}>Copy values</button>
      <button type="button" disabled={shown !== "draft"} onClick={keep}>Keep as candidate</button>
      {candidates.length > 0 && <>
        <ul aria-label="Candidates">
          {candidates.map(c => <li key={c.name}>
            <strong>{c.name}</strong> from {c.basedOn}{" "}
            <button type="button" aria-label={`Load ${c.name}`} disabled={shown !== "draft"}
              onClick={() => load(c)}>Load</button>
            <button type="button" aria-label={`Remove ${c.name}`} onClick={() => remove(c.name)}>Remove</button>
          </li>)}
        </ul>
        <fieldset style={{ border: 0, margin: 0, padding: 0 }}>
          <legend>Compare</legend>
          {["draft", ...candidates.map(c => c.name)].map(target => <label key={target}>
            <input type="radio" name="ui-tuning-lab-compare" checked={shown === target}
              onChange={() => show(target)}/>
            {target === "draft" ? "Draft" : target}{" "}
          </label>)}
        </fieldset>
      </>}
      <button type="button" disabled={showBaseline} onClick={done}>Done</button>
      {status && <p role="status">{status}</p>}
      <p style={{ position: "sticky", bottom: 0, margin: 0, padding: "8px 0", background: "Canvas" }}>
        Finished? Keep the ones you like, then press Done, or tell the agent "land b".</p>
    </div>}
  </>;
}
```

Slider changes replay the web card immediately because its animation depends on
the motion values; SwiftUI replays when a slider is released. Validate on device
with Reduce Motion on and off, at every speed, and with Show baseline and each
candidate shown, and confirm that closing the lab resets speed and the flip so the
feature renders the draft at real time. Keep as candidate, Load, Remove, Compare,
and Done follow `references/candidates.md`; candidates live in React state and the
console log only, and `initialCandidates` seeds them when reopening the lab. Editing
or applying a preset while a candidate or the baseline is shown switches back to the
draft.
