# React Native overlay

The feature and the lab share one config state. All lab code lives in
`FeatureScreen.ui-tuning-lab.tsx`; the host loads it with `require()` inside
`if (__DEV__)`, which Metro folds to `false` in a release bundle, dropping the
branch and the module. The panel is an absolutely positioned `View` in a
`pointerEvents="box-none"` layer, mounted only while open, so touches outside
the panel reach the feature. A `Modal` would block the feature unless it is
transparent and non-blocking; prefer the `View`.

Activation (`references/activation.md`):

- **Human:** an **Open UI tuning lab** item in the React Native developer menu
  (`DevSettings.addMenuItem`), which the developer already opens by shake,
  `Cmd+D`/`Cmd+M`, or `adb shell input keyevent 82`. React Native owns shake
  through that menu; the lab never adds a second shake listener.
- **Visible fallback:** a **Card Lab** pill in a free corner.
- **Agent:** a Metro-time variable, `EXPO_PUBLIC_UITUNINGLAB_OPEN=1`, read only
  inside the lab module and consumed once per JavaScript runtime; or, when the
  app has no bundle-time environment, the `__DEV__`-only global
  `uiTuningLabOpen()` evaluated in the app's JavaScript console.

Why not a deep link: a URL scheme lives in `Info.plist` and
`AndroidManifest.xml`, which ship in Release even when the handler is gated
(`references/edge-cases.md`). Launch arguments or intent extras would need
native changes in `AppDelegate` or `MainActivity` that also ship. A Metro-time
variable is inlined only into a development bundle, and only inside a module the
release bundle never contains, so nothing of it reaches Release.

The lab component stays mounted while the screen is, so the looks and the
selection survive closing the panel. The default lab is ephemeral: looks live in
React state and the log, and a name is never reused within a JavaScript
runtime. The panel follows `references/candidates.md`. The chip row under the
header shows **Shipped** and each pinned look, named after its preset
(**Compact-1**, **Relaxed-1**, **Custom-1**); the selected chip is outlined, and
the feature always shows it. Switching chips is the comparison. Every chip is
read-only, a pinned look included: the presets and steppers fork the selected
chip into unsaved changes that start from its values, with no chip outlined,
until **Save & pin** keeps them as a new look (an edit on **Compact-1** pins as
**Compact-2**); the chip it came from never changes, and tapping a chip drops
the unsaved changes. **Undo**, **Redo**, and **Reset** work on the unsaved
changes, back to the chip they were forked from, which is outlined again; a run
of presses on one stepper is one step. Each stepper marks the
Shipped value with a tick on a thin track under it, on every chip, and its
readout reads `14 · default 12` while the value differs. **↺** beside a changed
stepper puts that one control back to Shipped as one Undo step
(`references/control-mapping.md`, "Default marker and per-control reset"). A stepper has no drag, so nothing snaps; with a real slider,
add the snap from that section. There are no keyboard
shortcuts on mobile. **Apply** (hidden after its first use) pins unsaved changes, then picks
the selected chip and shrinks the panel to the result bar (**Change** restores
it), and the **⋯** button holds **Copy values** for the selected look. Closing
keeps the selected look in the feature.

## Host change

The feature took `appDefault` directly; it now reads screen state. Undo this at
landing (`references/landing-protocol.md`).

`CardFeature.tsx`

```tsx
import { Text, View } from "react-native";

export type CardConfig = { radius: number; gap: number };
export const appDefault: CardConfig = { radius: 12, gap: 8 };

export function CardFeature({ config }: { config: CardConfig }) {
  const card = { borderRadius: config.radius, padding: 16, backgroundColor: "#eee" };
  return (
    <View style={{ padding: 16, gap: config.gap }}>
      <View style={card}><Text>First card</Text></View>
      <View style={card}><Text>Second card</Text></View>
    </View>
  );
}
```

`FeatureScreen.tsx`

```tsx
import { useState } from "react";
import type { ComponentType, Dispatch, SetStateAction } from "react";
import { appDefault, CardFeature } from "./CardFeature";
import type { CardConfig } from "./CardFeature";

export type TuningLabHostProps = {
  config: CardConfig;
  setConfig: Dispatch<SetStateAction<CardConfig>>;
};

// Metro replaces __DEV__ with false in a release bundle and drops this branch,
// and with it the lab module.
let TuningLabHost: ComponentType<TuningLabHostProps> | null = null;
if (__DEV__) {
  TuningLabHost = require("./FeatureScreen.ui-tuning-lab").default;
}

export function FeatureScreen() {
  const [config, setConfig] = useState(appDefault);
  if (TuningLabHost) return <TuningLabHost config={config} setConfig={setConfig} />;
  return <CardFeature config={config} />;
}
```

## Lab code

`FeatureScreen.ui-tuning-lab.tsx`

```tsx
import { useEffect, useRef, useState } from "react";
import { AccessibilityInfo, DevSettings, findNodeHandle, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { appDefault, CardFeature } from "./CardFeature";
import type { CardConfig } from "./CardFeature";
import type { TuningLabHostProps } from "./FeatureScreen";

declare global {
  // Development-only globals: the menu item and the agent call the mounted lab.
  var uiTuningLabOpen: (() => void) | undefined;
  var uiTuningLabMenuRegistered: boolean | undefined;
  var uiTuningLabLaunchConsumed: boolean | undefined;
}

// The menu cannot be unregistered, so register once per JavaScript runtime; it
// opens whichever lab is mounted, and does nothing when none is.
if (!globalThis.uiTuningLabMenuRegistered) {
  globalThis.uiTuningLabMenuRegistered = true;
  DevSettings.addMenuItem("Open UI tuning lab", () => globalThis.uiTuningLabOpen?.());
}

// Agent path: EXPO_PUBLIC_UITUNINGLAB_OPEN=1 at Metro start. Honored once per
// JavaScript runtime; Fast Refresh keeps the flag, a full reload resets it.
function consumeLaunchRequest(): boolean {
  if (globalThis.uiTuningLabLaunchConsumed) return false;
  globalThis.uiTuningLabLaunchConsumed = true;
  return process.env.EXPO_PUBLIC_UITUNINGLAB_OPEN === "1";
}

type Values = Partial<CardConfig>;
// A pinned look: its values are the diff against the baseline. It never changes
// once pinned: an edit on it forks unsaved edits.
type Candidate = { name: string; basedOn: string; values: Values };
// One point in the unsaved edits' history: what it showed, and where it came from.
type Step = { values: Values; basedOn: string };
// The unsaved edits' Undo and Redo steps back to the chip they were forked from,
// and the control of the newest step, so a run of presses on one stepper is one step.
type EditHistory = { undo: Step[]; redo: Step[]; control?: string | undefined };
const noHistory: EditHistory = { undo: [], redo: [] };
// Candidates the lab opens with. Empty by default; a later session seeds the
// finalists kept in the project here (references/candidates.md).
const initialCandidates: Candidate[] = [];
// Preset keys are kebab-case: the key is what a look records as basedOn.
const presets = {
  compact: { radius: 4, gap: 4 },
  relaxed: { radius: 24, gap: 16 },
} satisfies Record<string, CardConfig>;
// The declared default, never the value on screen when the lab opens.
const baseline: CardConfig = appDefault;

function changedValues<T extends object>(base: T, look: T): Partial<T> {
  return Object.fromEntries(Object.entries(look).filter(
    ([key, value]) => value !== base[key as keyof T])) as Partial<T>;
}
// JSON with sorted keys and two-decimal rounding, so every line has one shape.
function sortedJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(sortedJson).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.entries(value).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
      .map(([key, item]) => `${JSON.stringify(key)}:${sortedJson(item)}`).join(",")}}`;
  }
  if (typeof value === "number") return JSON.stringify(Math.round(value * 100) / 100);
  return JSON.stringify(value ?? null);
}
function log(tag: string, payload: unknown) {
  if (__DEV__) console.info(`${tag} ${sortedJson(payload)}`);
}
function sameValues(a: Values, b: Values): boolean {
  const keys = Object.keys(a) as Array<keyof CardConfig>;
  return keys.length === Object.keys(b).length && keys.every(key => a[key] === b[key]);
}
// The next look's name, `<prefix>-N`: one past the highest N already issued for
// that prefix in this runtime, removed ones included, so a number is never reused.
function nextName(issued: Set<string>, prefix: string): string {
  const used = [...issued].filter(name => name.startsWith(`${prefix}-`))
    .map(name => Number(name.slice(prefix.length + 1)) || 0);
  return `${prefix}-${Math.max(0, ...used) + 1}`;
}
// A chip's label: `Brass-2` for `brass-2`, `Warm Glow-1` for `warm-glow-1`,
// Shipped for `original`; a name that does not end in `-N` as it is.
function chipLabel(name: string): string {
  if (name === "original") return "Shipped";
  const m = /^(.+)-([0-9]+)$/.exec(name);
  if (!m) return name;
  const words = m[1].split("-").filter(Boolean).map(word => word[0].toUpperCase() + word.slice(1));
  return `${words.join(" ")}-${m[2]}`;
}
function Button({ title, onPress, disabled, label, selected }: {
  title: string; onPress: () => void; disabled?: boolean; label?: string; selected?: boolean;
}) {
  return <Pressable onPress={onPress} disabled={disabled} accessibilityRole="button"
    accessibilityLabel={label ?? title} accessibilityState={{ disabled, selected }}
    style={[styles.button, selected && styles.selected, disabled && { opacity: 0.4 }]}>
    <Text>{title}</Text>
  </Pressable>;
}

// Core React Native has no slider. This stepper is adjustable for screen
// readers; use @react-native-community/slider instead if the app already has it.
// The Shipped value is marked by a tick on a thin track under the stepper, on
// every chip; the readout adds "· default 12" while the value differs, and ↺
// puts this control back to Shipped as one Undo step, then moves screen reader
// focus to the stepper, so it stays in the panel as the ↺ goes away. A stepper
// has no drag, so nothing snaps; it moves in whole steps from wherever it is,
// so from a default off the grid (12.5) it reaches 13.5, never 13: keep the
// default on the stepper's grid. With a real slider,
// overlay the same tick inset by half the thumb, snap a drag within 1.5% of the
// range to Shipped, and add a light haptic only if the app already has a
// haptics module (core Vibration is too strong for a tick). The tick and the
// readout are display only.
function Stepper({ label, value, shipped, max, onChange, onReset }: {
  label: string; value: number; shipped: number; max: number; onChange: (v: number) => void; onReset: () => void;
}) {
  const set = (v: number) => onChange(Math.min(max, Math.max(0, v)));
  const adjustable = useRef<View>(null);
  const reset = () => {
    onReset();
    const node = findNodeHandle(adjustable.current);
    if (node) AccessibilityInfo.setAccessibilityFocus(node);
  };
  return <View>
    <View style={styles.row}>
      <View ref={adjustable} accessible accessibilityRole="adjustable" accessibilityLabel={label}
        accessibilityValue={{ min: 0, max, now: value }}
        accessibilityActions={[{ name: "increment" }, { name: "decrement" }]}
        onAccessibilityAction={e => set(value + (e.nativeEvent.actionName === "increment" ? 1 : -1))}
        style={[styles.row, { flex: 1 }]}>
        <Text style={{ flex: 1 }}>{label}</Text>
        <Button title="−" onPress={() => set(value - 1)} />
        <Text style={{ minWidth: 32, textAlign: "center" }}>
          {value === shipped ? value : `${value} · default ${shipped}`}</Text>
        <Button title="+" onPress={() => set(value + 1)} />
      </View>
      {/* Outside the adjustable group, so a screen reader reaches it. */}
      {value !== shipped && <Button title="↺" label={`Reset ${label} to default, ${shipped}`} onPress={reset} />}
    </View>
    <View style={styles.track} importantForAccessibility="no-hide-descendants" accessibilityElementsHidden>
      <View style={[styles.tick, { left: `${(shipped / max) * 100}%` as const }]} />
    </View>
  </View>;
}

export default function UITuningLabFeature({ config, setConfig }: TuningLabHostProps) {
  const [open, setOpen] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const [status, setStatus] = useState<string | null>(null);
  // Pinned looks live in React state and the log. Their values never change once
  // pinned; the controls fork the selected chip into unsaved edits.
  const [candidates, setCandidates] = useState(initialCandidates);
  // Every name issued, removed ones included, so a look number is never reused.
  const issued = useRef(new Set(initialCandidates.map(c => c.name)));
  // The line each look last logged, so a look logs once.
  const logged = useRef(new Map<string, string>());
  // The selected chip: "original" (Shipped) or a look's name. The feature shows
  // it, or the unsaved edits forked from it.
  const [selected, setSelected] = useState("original");
  // Undo and Redo of the unsaved edits, back to the chip they were forked from.
  const [history, setHistory] = useState(noHistory);
  // Where the unsaved edits came from: the forked chip's basedOn, or the last
  // preset applied to them.
  const [unsavedBasedOn, setUnsavedBasedOn] = useState("baseline");
  // The last pick; while set, the panel is the result bar.
  const [result, setResult] = useState<string | null>(null);
  // How many picks reached the agent. The first Apply reaches its waiter; after
  // it the agent no longer listens, so Apply hides and Save & pin also hands
  // the pick over for the user to paste as `land <name>`. Change does not reset
  // it.
  const [applies, setApplies] = useState(0);
  // The result bar's second line: where Apply saved the pick. Only the
  // AsyncStorage variant below saves one; without it the line stays empty.
  const [saved, setSaved] = useState<string | null>(null);
  // A failed profile write during the current pin, so the next status keeps it.
  const storeError = useRef<string | null>(null);
  const selectedPin = candidates.find(c => c.name === selected);
  // The selected chip's look, which unsaved edits fork from.
  const source: Step = { values: selectedPin?.values ?? {}, basedOn: selectedPin?.basedOn ?? "baseline" };
  // The look as shown: the feature always renders it.
  const selectedValues = changedValues(baseline, config);
  // Unsaved edits: the look shown differs from the selected chip's. Save & pin,
  // the one save button, and Reset need them.
  const hasEdits = !sameValues(selectedValues, source.values);
  const currentStep: Step = hasEdits ? { values: selectedValues, basedOn: unsavedBasedOn } : source;
  // Only the selected chip is outlined, and none while there are unsaved edits.
  const outlined = (chip: string) => chip === selected && !hasEdits;
  const undoSteps = history.undo;
  const redoSteps = history.redo;
  const canUndo = undoSteps.length > 0;
  const canRedo = redoSteps.length > 0;

  // In an effect rather than a state initializer: StrictMode runs initializers
  // twice, and the second call would see the request already consumed.
  useEffect(() => { if (consumeLaunchRequest()) setOpen(true); }, []);
  // The menu item and the agent reach this lab only while it is mounted.
  useEffect(() => {
    const openLab = () => { setStatus(null); setOpen(true); };
    globalThis.uiTuningLabOpen = openLab;
    return () => { if (globalThis.uiTuningLabOpen === openLab) globalThis.uiTuningLabOpen = undefined; };
  }, []);
  // Seeded looks log their own line the first time the lab shows them.
  useEffect(() => {
    if (!open) return;
    for (const c of candidates) if (!logged.current.has(c.name)) logPin(c);
  }, [open, candidates]);

  // Logs a look's line the first time. Only a new pin or a seeded look gets
  // here: unsaved edits are never logged.
  function logPin(candidate: Candidate) {
    const line = sortedJson(candidate);
    if (logged.current.get(candidate.name) === line) return;
    logged.current.set(candidate.name, line);
    log("UITUNINGLAB_CANDIDATE", candidate);
  }
  // Closing keeps the selected look in the feature; reopening keeps the chips.
  function close() { setMenuOpen(false); setOpen(false); }
  // Tapping a chip shows its look in the real feature. Switching chips is the
  // comparison. Unsaved edits and their history are dropped, so a chip always
  // shows its look exactly, the one they were forked from included.
  function select(chip: string) {
    if (chip === selected && !hasEdits) return;
    const pin = candidates.find(c => c.name === chip);
    setHistory(noHistory);
    setUnsavedBasedOn("baseline");
    setConfig({ ...baseline, ...(pin ? pin.values : {}) });
    setSelected(pin ? chip : "original");
  }
  // Shows a step. Matching the chip the edits were forked from leaves no
  // unsaved edits, and that chip is outlined again.
  function show(step: Step) {
    setConfig({ ...baseline, ...step.values });
    setUnsavedBasedOn(sameValues(step.values, source.values) ? "baseline" : step.basedOn);
  }
  // Every control makes unsaved edits. On an outlined chip the first edit forks
  // it: the edits start from its values and basedOn, and the chip itself never
  // changes. A preset becomes their basedOn. Steppers pass `control`, their key:
  // a run of presses on the same control in a row is one Undo step. Presets
  // pass none, so each is a step.
  function edit(next: CardConfig, options: { preset?: string; control?: string } = {}) {
    const values = changedValues(baseline, next);
    if (sameValues(values, currentStep.values) &&
        (!options.preset || options.preset === currentStep.basedOn)) return;
    setHistory(h => ({
      undo: !options.control || options.control !== h.control || h.undo.length === 0
        ? [...h.undo, currentStep] : h.undo,
      redo: [],
      control: options.control,
    }));
    show({ values, basedOn: options.preset ?? currentStep.basedOn });
  }
  function applyPreset(name: keyof typeof presets) { edit({ ...presets[name] }, { preset: name }); }
  // Undo steps the unsaved edits back one, never past the chip they were forked
  // from, which is outlined again when they reach it.
  function undo() {
    const previous = undoSteps[undoSteps.length - 1];
    if (!previous) return;
    setHistory(h => ({ undo: h.undo.slice(0, -1), redo: [...h.redo, currentStep] }));
    show(previous);
  }
  // Redo brings back the edit Undo last took away.
  function redo() {
    const next = redoSteps[redoSteps.length - 1];
    if (!next) return;
    setHistory(h => ({ undo: [...h.undo, currentStep], redo: h.redo.slice(0, -1) }));
    show(next);
  }
  // ↺ on one control: puts its fields back to Shipped. An ordinary edit: one
  // Undo step that ends the current run of presses. On a pinned look it forks
  // unsaved edits; edits that match the chip they were forked from again are
  // dropped, and that chip is outlined.
  function resetControl(...keys: (keyof CardConfig)[]) {
    edit({ ...config, ...Object.fromEntries(keys.map(key => [key, baseline[key]])) });
  }
  // Reset drops the unsaved edits back to the chip they were forked from,
  // outlined again, in one step that Undo can take back.
  function reset() {
    if (!hasEdits) return;
    setHistory(h => ({ undo: [...h.undo, currentStep], redo: [] }));
    show(source);
  }
  // Pins the unsaved edits as a new look named `<prefix>-N`, selected and
  // outlined (prefix: their basedOn, or `custom` for `baseline`); the look is
  // logged and the history starts fresh. Returns the look the pick is (with no
  // unsaved edits the selected chip's, none for Shipped) and the list it is in,
  // read before React re-renders.
  function commit(): { look?: Candidate; list: Candidate[] } {
    storeError.current = null;
    if (!hasEdits) return { look: selectedPin, list: candidates };
    const look: Candidate = {
      name: nextName(issued.current, unsavedBasedOn === "baseline" ? "custom" : unsavedBasedOn),
      basedOn: unsavedBasedOn, values: selectedValues,
    };
    issued.current.add(look.name);
    const list = [...candidates, look];
    setCandidates(list);
    setSelected(look.name);
    setUnsavedBasedOn("baseline");
    setHistory(noHistory);
    logPin(look);
    return { look, list };
  }
  // Save & pin, the one save button, pins the unsaved edits. Before the first
  // Apply the agent is listening for Apply, so nothing more happens; after it,
  // the pick is handed over for pasting. No clipboard module in core React
  // Native: the land code is shown as selectable text instead.
  function save() {
    if (!hasEdits) return;
    const { look, list } = commit();
    if (!look) return;
    if (applies > 0) { handOver(look, list); return; }
    setSaved(null);
    setStatus(storeError.current ?? `Pinned ${chipLabel(look.name)} · land ${look.name}`);
  }
  // Reports the selected look as shown, edits included. No clipboard module in
  // core React Native: the values are logged and shown as selectable text. Call
  // the app's clipboard module here if it already has one.
  function copyValues() {
    log("UITUNINGLAB_VALUES", selectedValues);
    const text = sortedJson(selectedValues);
    setStatus(text === "{}" ? "Same as Shipped" : `Logged ${text}`);
    setMenuOpen(false);
  }
  function remove(name: string) {
    setCandidates(list => list.filter(c => c.name !== name));
    logged.current.delete(name);
    log("UITUNINGLAB_CANDIDATE_REMOVED", { name });
    if (selected === name) { setConfig({ ...baseline }); setSelected("original"); setHistory(noHistory); }
    setStatus(`Removed ${chipLabel(name)}`);
  }
  // Apply pins unsaved edits first, like Save & pin, then hands the selected
  // chip over.
  function applyLook() {
    const { look, list } = commit();
    handOver(look, list);
  }
  // Hands a pick to the agent and finishes. Picking again replaces the result.
  function handOver(look: Candidate | undefined, list: Candidate[]) {
    const winner = look ? look.name : "original";
    const done = { candidates: list, values: look?.values ?? {}, winner };
    // Logcat cuts entries near 4 KB. When the Done line may be cut, repeat each
    // look on its own line first, so the agent can rebuild the list.
    if (sortedJson(done).length > 3500) for (const c of list) log("UITUNINGLAB_CANDIDATE", c);
    log("UITUNINGLAB_DONE", done);
    // Hands the pick to the agent's waiter (scripts/wait-for-pick.py) at once, so
    // it resumes without a message. Android reaches it through the waiter's
    // `adb reverse`. Fire and forget: with nothing listening, the log carries it.
    if (__DEV__) fetch("http://localhost:47321/pick", { method: "POST",
      body: `UITUNINGLAB_DONE ${sortedJson(done)}` }).catch(() => {});
    // The result file needs AsyncStorage; without it the log and the land code
    // carry the pick ("The result file", below). With a clipboard module in the
    // app, copy `land ${winner}` here.
    setSaved(null);
    setMenuOpen(false);
    setApplies(n => n + 1);
    setResult(winner);
  }

  return <View style={{ flex: 1 }}>
    <CardFeature config={config} />
    <View pointerEvents="box-none" style={StyleSheet.absoluteFill}>
      {!open && <View style={styles.pill}>
        <Button title="Card Lab" label="Open UI tuning lab" onPress={() => { setStatus(null); setOpen(true); }} />
      </View>}
      {open && result !== null && <View style={[styles.pill, styles.bar]}>
        <Text accessibilityLiveRegion="polite">{applies > 1 ? "Tell the agent:" : `Applied: ${chipLabel(result)}`}</Text>
        <Text selectable style={{ color: "#555" }}>land {result}</Text>
        <Button title="Change" onPress={() => setResult(null)} />
        {(saved ?? status) && <Text style={{ fontSize: 12, color: "#555" }}>{saved ?? status}</Text>}
      </View>}
      {open && result === null && <View style={styles.panel} accessibilityLabel="UI tuning lab">
        <View style={styles.row}>
          <Text accessibilityRole="header" style={{ flex: 1, fontWeight: "600" }}>UI tuning lab</Text>
          <Button title="⋯" label="More actions" onPress={() => setMenuOpen(m => !m)} />
          <Button title="Close" onPress={close} />
        </View>
        {menuOpen && <View style={styles.row}>
          <Button title="Copy values" onPress={copyValues} />
        </View>}
        {/* The chips: Shipped, then each saved look. The selected chip is outlined. */}
        <View style={styles.row}>
          <Button title="Shipped" selected={outlined("original")} onPress={() => select("original")} />
          {candidates.map(c => <View key={c.name} style={styles.chip}>
            <Button title={chipLabel(c.name)} selected={outlined(c.name)} onPress={() => select(c.name)} />
            {/* × only on the selected look, outlined, so nothing is removed by accident. */}
            {outlined(c.name) &&
              <Button title="×" label={`Remove ${chipLabel(c.name)}`} onPress={() => remove(c.name)} />}
          </View>)}
        </View>
        <ScrollView style={{ flexGrow: 0, flexShrink: 1 }}>
          {/* Presets are actions, never outlined. */}
          <View style={styles.row}>
            <Button title="Compact" onPress={() => applyPreset("compact")} />
            <Button title="Relaxed" onPress={() => applyPreset("relaxed")} />
          </View>
          {/* A stepper passes its key, so a run of presses is one Undo step. */}
          <Stepper label="Radius" value={config.radius} shipped={baseline.radius} max={32}
            onChange={radius => edit({ ...config, radius }, { control: "radius" })}
            onReset={() => resetControl("radius")} />
          <Stepper label="Gap" value={config.gap} shipped={baseline.gap} max={24}
            onChange={gap => edit({ ...config, gap }, { control: "gap" })}
            onReset={() => resetControl("gap")} />
          {status && <Text selectable accessibilityLiveRegion="polite">{status}</Text>}
        </ScrollView>
        {/* The edit row: each button is disabled when it has nothing to do. */}
        <View style={styles.row}>
          <Button title="Undo" disabled={!canUndo} onPress={undo} />
          <Button title="Redo" disabled={!canRedo} onPress={redo} />
          <Button title="Reset" disabled={!hasEdits} onPress={reset} />
        </View>
        <View style={styles.row}>
          <Button title="Save & pin" disabled={!hasEdits} onPress={save} />
          {/* Apply reaches the agent once; after that it is hidden for good. */}
          {applies === 0 && <Button title="Apply" onPress={applyLook} />}
        </View>
        {/* Pinned below the controls, visible however long the panel grows. */}
        <Text style={{ paddingTop: 8 }}>{applies > 0 ? "Save & pin, then paste it in chat"
          : "Save & pin to keep a look · Apply to finish"}</Text>
      </View>}
    </View>
  </View>;
}

const styles = StyleSheet.create({
  // Pick the corner inspection found free of other dev overlays.
  pill: { position: "absolute", right: 16, bottom: 16 },
  // The outline keeps the panel distinct when the screen behind it has the same
  // background, where a shadow alone vanishes.
  panel: {
    position: "absolute", right: 16, bottom: 72, width: 320, maxWidth: "90%", maxHeight: "70%",
    padding: 12, borderRadius: 12, backgroundColor: "white", elevation: 8,
    borderWidth: 1, borderColor: "#8a8a8a",
    shadowOpacity: 0.2, shadowRadius: 8,
  },
  row: { flexDirection: "row", flexWrap: "wrap", alignItems: "center", gap: 8, marginVertical: 4 },
  button: { paddingHorizontal: 10, paddingVertical: 6, borderRadius: 6, borderWidth: 1, borderColor: "#999" },
  // Outlined, so the selected chip reads as selected without a label.
  selected: { backgroundColor: "#dbeafe", borderColor: "#06c", borderWidth: 2, paddingHorizontal: 9, paddingVertical: 5 },
  chip: { flexDirection: "row", gap: 2 },
  // The thin track under a stepper and the tick that marks the Shipped value.
  track: { height: 2, marginHorizontal: 1, marginBottom: 6, backgroundColor: "#d4d4d4" },
  tick: { position: "absolute", top: -2, width: 2, height: 6, marginLeft: -1, backgroundColor: "#6b6b6b" },
  bar: {
    flexDirection: "row", alignItems: "center", gap: 8, padding: 8, borderRadius: 20,
    backgroundColor: "white", elevation: 8, shadowOpacity: 0.2, shadowRadius: 8,
    borderWidth: 1, borderColor: "#8a8a8a",
  },
});
```

## Reading the lines and waiting for the pick

`console.info` lines reach logcat under `ReactNativeJS` on Android and the
unified log on the iOS Simulator, as well as React Native DevTools' console.
Use the commands in `references/platform-handoff.md`: `adb logcat -d -s ReactNativeJS:I`,
or the Simulator `log show` command without the subsystem clause. Wait for the
pick with `python3 <skill-dir>/scripts/wait-for-pick.py --log android` or
`--log ios-sim` in the background (`references/platform-handoff.md`, "Wait for
Done"); Apply's beacon usually reaches it first.

Logcat truncates an entry near 4 KB, so a Done line with many looks can be
cut. When its JSON exceeds about 3,500 characters, the lab logs every look
on its own `UITUNINGLAB_CANDIDATE` line right before Done; if the Done line does
not parse, rebuild the list from those lines (`references/candidates.md`, "Log
lines") and take the winner's values from its last `UITUNINGLAB_CANDIDATE` line.

Core React Native has no clipboard module, so the result bar shows the
`land <name>` code as selectable text; when the app already has a clipboard
module (`expo-clipboard`, `@react-native-clipboard/clipboard`), copy it in
`handOver()` and `save()` as well.

Agent opening, in order of preference:

1. Expo: `EXPO_PUBLIC_UITUNINGLAB_OPEN=1 npx expo start --clear`, then open the
   app. Restart Metro without the variable when the session ends, or a full
   reload opens the lab again.
2. Bare React Native that already inlines environment variables at bundle time
   (for example `babel-plugin-transform-inline-environment-variables`): the
   same variable at `npx react-native start --reset-cache`. Do not add a Babel
   plugin for the lab alone.
3. Otherwise: evaluate `uiTuningLabOpen()` in the app's JavaScript context,
   through React Native DevTools' console (`j` in the Metro terminal), or by
   sending `Runtime.evaluate` to the debugger WebSocket that Metro lists at
   `http://localhost:8081/json/list`.

## Teardown

Close unmounts the panel; the feature keeps the selected look, which is screen
state like any other and returns to `appDefault` when the screen unmounts.
Unmounting the screen
clears the `uiTuningLabOpen` global. The developer-menu item cannot be
unregistered: it stays in the menu until the next full reload and does nothing
while no lab is mounted. The lab owns no timers or subscriptions.

Removal at landing: delete `FeatureScreen.ui-tuning-lab.tsx` and the
`TuningLabHost` block, and point the screen back at
`<CardFeature config={appDefault} />`, which now holds the winner. Reload the
app so the menu item disappears.

## The result file, only when the app has AsyncStorage

Only when the app already depends on `@react-native-async-storage/async-storage`;
otherwise skip this and rely on the log and the land code. Apply (and
Save & pin after the first Apply) then also stores the Done object plus
`savedAt` under `uiTuningLab.result`, replacing the last pick; AsyncStorage
writes one key atomically.

```tsx
import AsyncStorage from "@react-native-async-storage/async-storage";

function writeResult(done: object) {
  return AsyncStorage.setItem("uiTuningLab.result", sortedJson({ ...done, savedAt: new Date().toISOString() }));
}
```

In `handOver()`, right after `setSaved(null)`:
``writeResult(done).then(() => { setStatus(storeError.current); setSaved(`Saved ${chipLabel(winner)} in AsyncStorage uiTuningLab.result`); }, e => setStatus(`Result file failed: ${String(e)}`));``.
Either line shows under the result bar. Read the key in React Native DevTools'
console with `AsyncStorage.getItem("uiTuningLab.result")` when the module is
reachable there; otherwise the log holds the same line.

## Persistence variant, only when requested

Only when the app already depends on `@react-native-async-storage/async-storage`;
otherwise ask, and never add a native module for the lab alone
(`references/platform-handoff.md`). One `schemaVersion: 2` profile per
look under `uiTuningLab.candidates.<name>`, written once, when the look is
pinned: Save & pin, or Apply with unsaved edits. Unsaved edits are never
written, and a pinned look's key is never written again.

```tsx
import AsyncStorage from "@react-native-async-storage/async-storage";

const candidateKey = "uiTuningLab.candidates.";

// Writes the look's own key; stored names are reserved, so a new look never lands
// on another's key. AsyncStorage writes one key atomically. savedAt orders the
// looks when they load.
async function writeCandidate(candidate: Candidate) {
  await AsyncStorage.setItem(candidateKey + candidate.name, sortedJson({
    basedOn: candidate.basedOn, container: "FeatureScreen.overlay", name: candidate.name, notes: "",
    overrides: { ...baseline, ...candidate.values }, platform: "react-native",
    savedAt: new Date().toISOString(), schemaVersion: 2,
    scope: ["appearance", "layout"],
  }));
}

// Every stored name is reserved, readable or not; unusable entries are reported and left alone.
async function readStored(reserved: Set<string>) {
  const keys = (await AsyncStorage.getAllKeys()).filter(k => k.startsWith(candidateKey));
  const found: Array<Candidate & { savedAt: number }> = [];
  const problems: string[] = [];
  for (const [key, raw] of await AsyncStorage.multiGet(keys)) {
    const name = key.slice(candidateKey.length);
    reserved.add(name);
    try {
      const p = JSON.parse(raw ?? "");
      if (p.schemaVersion !== 2 || p.platform !== "react-native" || p.name !== name ||
          typeof p.overrides?.radius !== "number" || typeof p.overrides?.gap !== "number") {
        throw new Error("incompatible schema, platform, or name");
      }
      const values = changedValues(baseline, { radius: p.overrides.radius, gap: p.overrides.gap });
      if (Object.keys(values).length === 0) throw new Error("matches the baseline");
      // Sort by instant, not by string: "…24Z" and "…24.5Z" do not compare as text.
      found.push({ name, basedOn: p.basedOn ?? "baseline", values, savedAt: Date.parse(p.savedAt) || 0 });
    } catch (error) {
      problems.push(`${name} (${error instanceof Error ? error.message : "unknown error"})`);
    }
  }
  found.sort((a, b) => a.savedAt - b.savedAt);
  return { found: found.map(({ name, basedOn, values }) => ({ name, basedOn, values })), problems };
}
```

Wiring: `logPin` gains a `storing = true` parameter and, right after its log
line, when `storing` is true calls
``writeCandidate(candidate).catch(e => { storeError.current = `${chipLabel(candidate.name)} not saved: ${String(e)}`; setStatus(storeError.current); })``,
so a look is written once, when it is pinned; a
failed write leaves the look in the panel. The effect that logs seeded and
stored looks passes `storing = false`, since they are already stored. `remove` becomes async and awaits
`AsyncStorage.removeItem(candidateKey + name)` first, and on failure sets the
status and returns without removing the chip; an effect
on `open` awaits `readStored(issued.current)`, merges the found candidates, and
puts the problems in the status line. Copy a stored value to a file and
validate it with `sh <skill-dir>/scripts/verify.sh profile <file>`.

## Manual gate check

Record the evidence for each step (`references/platform-handoff.md`):

1. Run `sh <skill-dir>/scripts/verify.sh source-gates <feature-dir>` on the
   host and lab files. It accepts `require()` inside `if (__DEV__) {` (and
   rejects `import()` there). A PASS means the source is linted, not that the
   release build is clean.
2. Build the release bundle and search it:
   `npx react-native bundle --entry-file index.js --platform android --dev false --minify true --bundle-output <out>/index.android.bundle`
   (repeat with `--platform ios --bundle-output <out>/main.jsbundle`), then
   `grep -cE 'UITuningLab|UITUNINGLAB_|ui-tuning-lab' <out>/index.android.bundle`
   prints `0`. The minifier renames identifiers, so the string literals
   (`UITUNINGLAB_`, `ui-tuning-lab`) are the evidence that matters; also
   search for the menu and pill labels (`Open UI tuning lab`). For a Hermes release build, search the compiled `.hbc` the
   same way.
3. A release build's developer menu does not exist, so the human path is gone;
   confirm the pill is absent.

## Version notes

- Expo Go and `expo-dev-client` have their own developer menu: register the
  item with `expo-dev-menu`'s `registerDevMenuItems` instead of
  `DevSettings.addMenuItem`, which has no removal API (the global flag keeps it
  from being added twice).
- `process.env.EXPO_PUBLIC_*` is inlined only by Expo's Babel preset. In bare
  React Native without an inlining plugin it is `undefined`, so the lab stays
  closed.
- If the release bundle search finds lab strings, Metro did not fold
  `if (__DEV__)`: load the lab from a separate development entry file instead.
