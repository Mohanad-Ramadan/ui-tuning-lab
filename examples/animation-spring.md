# Candidate — entrance animation with spring controls

Animation tuning needs more than sliders: the motion must be replayed on demand,
slowed down to be judged, and flipped against the captured baseline. This example
tunes a card's entrance spring on SwiftUI and the web. The lab only scales the
values it renders; it never changes global animation speed or the user's
reduced-motion setting.

Every lab in this example provides:

- **Replay**: re-creates the card (a bumped `id` / `key`) so its entrance runs again.
- **Speed**: 1×, 0.5×, 0.25×, or 0.1×, applied by stretching the rendered duration.
- **Show baseline**: flips the rendered motion between the captured baseline and the
  draft, replaying each time.
- **Reduced motion**: the feature keeps its own reduced animation, and the lab says
  when that is what you are seeing.
- **Copy values**: copies the draft fields that differ from the baseline and logs
  them as one `UITUNINGLAB_VALUES {...}` line for landing
  (`references/landing-protocol.md`). Speed and the flip are preview settings and
  are never included.

## SwiftUI (iOS 17+)

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
    @State private var uiTuningLabBaseline: EntranceMotion?
    @State private var uiTuningLab = UITuningLabMotionState()
    #endif

    var body: some View {
        #if DEBUG
        EntranceCard(motion: uiTuningLab.rendered(draft: motion, baseline: uiTuningLabBaseline))
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
                    baseline: uiTuningLabBaseline ?? motion
                )
                // Compact width adapts to a sheet; keep the card visible above it.
                .presentationDetents([.medium])
                .presentationBackgroundInteraction(.enabled)
            }
            .onChange(of: showUITuningLab) { _, open in
                // Keep the replay token so closing does not re-create the card.
                if !open { uiTuningLabBaseline = nil; uiTuningLab.speed = 1; uiTuningLab.showBaseline = false }
            }
        #else
        EntranceCard(motion: motion)
            .frame(maxHeight: .infinity, alignment: .top)
        #endif
    }

    #if DEBUG
    private func openUITuningLab() {
        guard !showUITuningLab, uiTuningLabBaseline == nil else { return }
        uiTuningLabBaseline = motion
        showUITuningLab = true
    }
    #endif
}
```

<!-- file: UITuningLabMotion.swift -->
```swift
import SwiftUI

#if DEBUG
struct UITuningLabMotionState {
    var replayToken = 0
    var speed = 1.0           // 1 = real time; smaller values slow the preview
    var showBaseline = false

    func rendered(draft: EntranceMotion, baseline: EntranceMotion?) -> EntranceMotion {
        var motion = showBaseline ? (baseline ?? draft) : draft
        motion.duration /= speed
        return motion
    }
}

struct UITuningLabMotionControls: View {
    @Binding var motion: EntranceMotion
    @Binding var lab: UITuningLabMotionState
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
                Button("Snappy") { apply(Self.snappy) }
                Button("Playful") { apply(Self.playful) }
            }
            Slider(value: $motion.duration, in: 0.15...1.5) {
                Text("Duration")
            } onEditingChanged: { replayWhenReleased($0) }
            Slider(value: $motion.bounce, in: 0...0.6) {
                Text("Bounce")
            } onEditingChanged: { replayWhenReleased($0) }
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
            HStack {
                Button("Replay") { lab.replayToken += 1 }
                Button("Reset") { motion = baseline; lab.replayToken += 1 }
                Button("Copy values") {
                    status = uiTuningLabCopyValues(from: baseline, to: motion)
                }
            }
            if let status { Text(status).font(.footnote) }
        }
        .onChange(of: lab.showBaseline) { lab.replayToken += 1 }
        // Editing the draft shows the draft, so a change is never hidden.
        .onChange(of: motion) { lab.showBaseline = false }
        .onChange(of: lab.speed) { lab.replayToken += 1 }
        .frame(minWidth: 300)
        // A Form row with several buttons fires all of them on iOS unless borderless.
        .buttonStyle(.borderless)
    }

    private func apply(_ preset: EntranceMotion) {
        motion = preset
        lab.replayToken += 1
    }

    private func replayWhenReleased(_ editing: Bool) {
        if !editing { lab.replayToken += 1 }
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

## Web (React)

`springEasing` turns a bounce value into a CSS `linear()` easing so the same spring
runs through the Web Animations API. `linear()` needs Chromium 113+, Safari 17.2+,
or Firefox 112+.

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
import { EntranceCard } from "./EntranceCard";
import type { EntranceMotion } from "./EntranceCard";
import type { TuningLabHostProps } from "./EntranceScreen";

// React 18 types omit `popover`; the spread compiles on React 18 and 19 alike.
const popoverAuto = { popover: "auto" };

const presets = {
  snappy: { durationMs: 350, bounce: 0, offsetPx: 24 },
  playful: { durationMs: 900, bounce: 0.45, offsetPx: 64 },
} satisfies Record<string, EntranceMotion>;
const speeds = [1, 0.5, 0.25, 0.1];

// The draft fields that differ from the baseline.
function changedValues<T extends object>(baseline: T, draft: T): Partial<T> {
  return Object.fromEntries(Object.entries(draft).filter(
    ([key, value]) => value !== baseline[key as keyof T])) as Partial<T>;
}

export default function UITuningLabEntrance({ motion, setMotion }: TuningLabHostProps) {
  const [open, setOpen] = useState(false);
  const [baseline, setBaseline] = useState<EntranceMotion | null>(null);
  const [replay, setReplay] = useState(0);
  const [speed, setSpeed] = useState(1);
  const [showBaseline, setShowBaseline] = useState(false);
  const [status, setStatus] = useState<{ text: string; error?: boolean } | null>(null);
  const panel = useRef<HTMLDivElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  const firstControl = useRef<HTMLButtonElement>(null);
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;

  useEffect(() => {
    const node = panel.current;
    if (!open || !node) return;
    node.showPopover?.();
    const focusFrame = requestAnimationFrame(() => firstControl.current?.focus());
    const onToggle = (event: Event) => {
      if ((event as ToggleEvent).newState === "closed") {
        setOpen(false);
        setBaseline(null);
        setSpeed(1);
        setShowBaseline(false);
      }
    };
    node.addEventListener("toggle", onToggle);
    return () => {
      cancelAnimationFrame(focusFrame);
      node.removeEventListener("toggle", onToggle);
      if (node.matches(":popover-open")) node.hidePopover?.();
      trigger.current?.focus();
    };
  }, [open]);

  const source = showBaseline && baseline ? baseline : motion;
  const rendered = { ...source, durationMs: source.durationMs / speed };
  const replayNow = () => setReplay(count => count + 1);

  function openLab() { setBaseline({ ...motion }); setStatus(null); setOpen(true); }
  async function copyValues() {
    const values = JSON.stringify(changedValues(baseline ?? motion, motion));
    console.info(`UITUNINGLAB_VALUES ${values}`);
    try {
      await navigator.clipboard.writeText(values);
      setStatus({ text: values === "{}" ? "No changes from baseline" : `Copied ${values}` });
    } catch {
      setStatus({ text: `Clipboard unavailable; values logged to the console: ${values}` });
    }
  }
  function reset() { if (baseline) setMotion({ ...baseline }); replayNow(); }
  function apply(preset: EntranceMotion) { setShowBaseline(false); setMotion(preset); replayNow(); }
  // Editing the draft shows the draft, so a change is never hidden.
  function edit(patch: Partial<EntranceMotion>) {
    setShowBaseline(false);
    setMotion(m => ({ ...m, ...patch }));
  }

  return <>
    <EntranceCard key={replay} motion={rendered} />
    <button ref={trigger} type="button" onClick={openLab} disabled={open}>Tune</button>
    {open && <div ref={panel} {...popoverAuto} role="dialog"
      aria-labelledby="tuning-lab-title">
      <h2 id="tuning-lab-title">UI tuning lab</h2>
      {reducedMotion && <p>Reduced motion is on, so the card shows its reduced animation.</p>}
      <button ref={firstControl} type="button"
        onClick={() => apply(presets.snappy)}>Snappy</button>
      <button type="button" onClick={() => apply(presets.playful)}>Playful</button>
      <label>Duration <input type="range" min="150" max="1500" step="10"
        value={motion.durationMs}
        onChange={e => edit({ durationMs: Number(e.target.value) })}/>
      </label>
      <label>Bounce <input type="range" min="0" max="0.6" step="0.05"
        value={motion.bounce}
        onChange={e => edit({ bounce: Number(e.target.value) })}/>
      </label>
      <label>Offset <input type="range" min="0" max="120"
        value={motion.offsetPx}
        onChange={e => edit({ offsetPx: Number(e.target.value) })}/>
      </label>
      <label>Speed <select value={speed}
        onChange={e => { setSpeed(Number(e.target.value)); replayNow(); }}>
        {speeds.map(s => <option key={s} value={s}>{s}×</option>)}
      </select></label>
      <button type="button" aria-pressed={showBaseline}
        onClick={() => { setShowBaseline(shown => !shown); replayNow(); }}>Show baseline</button>
      <button type="button" onClick={replayNow}>Replay</button>
      <button type="button" onClick={reset}>Reset</button>
      <button type="button" onClick={copyValues}>Copy values</button>
      {status && <p role={status.error ? "alert" : "status"}>{status.text}</p>}
    </div>}
  </>;
}
```

Slider changes replay the web card immediately because its animation depends on
the motion values; SwiftUI replays when a slider is released. Validate on device
with Reduce Motion on and off, at every speed, and with Show baseline toggled, and
confirm that closing the lab resets speed and the flip so the feature renders the
draft at real time.
