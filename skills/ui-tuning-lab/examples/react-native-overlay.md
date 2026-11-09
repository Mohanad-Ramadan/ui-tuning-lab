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

The lab component stays mounted while the screen is, so the pins and the
selection survive closing the panel. The default lab is ephemeral: pins live in
React state and the log, and a name is never reused within a JavaScript
runtime. The panel follows `references/candidates.md`. The chip row under the
header shows **Shipped** and each pin; the selected chip is outlined, and the
feature always shows it. Switching chips is the comparison: there is no draft
and nothing is stashed. The presets and steppers edit the selected pin in
place; on Shipped, which is read-only, they start a new pin named after the
preset or `tweak`. **Duplicate** branches the selected pin, **Choose** picks the
selected chip and shrinks the panel to the result bar (**Change** restores it),
and the **⋯** button holds **Copy values** for the selected look. Closing keeps
the selected look in the feature.

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
import { DevSettings, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
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

type Candidate = { name: string; basedOn: string; values: Partial<CardConfig> };
// Candidates the lab opens with. Empty by default; a later session seeds the
// finalists kept in the project here (references/candidates.md).
const initialCandidates: Candidate[] = [];
// Preset keys are kebab-case: the key is what a pin records as basedOn and is
// named after.
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
// `stem`, or `stem-2`, `stem-3`, ... when taken. Removed names stay in `issued`,
// so a name is never reused in this runtime.
function nextName(stem: string, issued: Set<string>): string {
  let name = stem;
  for (let i = 2; issued.has(name); i++) name = `${stem}-${i}`;
  return name;
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
function Stepper({ label, value, max, onChange }: {
  label: string; value: number; max: number; onChange: (v: number) => void;
}) {
  const set = (v: number) => onChange(Math.min(max, Math.max(0, v)));
  return <View accessible accessibilityRole="adjustable" accessibilityLabel={label}
    accessibilityValue={{ min: 0, max, now: value }}
    accessibilityActions={[{ name: "increment" }, { name: "decrement" }]}
    onAccessibilityAction={e => set(value + (e.nativeEvent.actionName === "increment" ? 1 : -1))}
    style={styles.row}>
    <Text style={{ flex: 1 }}>{label}</Text>
    <Button title="−" onPress={() => set(value - 1)} />
    <Text style={{ minWidth: 32, textAlign: "center" }}>{value}</Text>
    <Button title="+" onPress={() => set(value + 1)} />
  </View>;
}

export default function UITuningLabFeature({ config, setConfig }: TuningLabHostProps) {
  const [open, setOpen] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const [status, setStatus] = useState<string | null>(null);
  // Pins live in React state and the log. A pin is a look being worked on: the
  // controls edit the selected pin in place.
  const [candidates, setCandidates] = useState(initialCandidates);
  // Every name issued, removed ones included, plus the names a pin never takes.
  const issued = useRef(new Set(["draft", "now", "original", "baseline", ...initialCandidates.map(c => c.name)]));
  // The line each pin last logged, so a pin logs again only after it changed.
  const logged = useRef(new Map<string, string>());
  // The selected chip: "original" (Shipped) or a pin's name. The feature always
  // shows it; there is no draft and nothing is stashed.
  const [selected, setSelected] = useState("original");
  // The last pick; while set, the panel is the result bar.
  const [result, setResult] = useState<string | null>(null);
  const selectedPin = candidates.find(c => c.name === selected);
  const selectedValues: Partial<CardConfig> = selectedPin?.values ?? {};

  // In an effect rather than a state initializer: StrictMode runs initializers
  // twice, and the second call would see the request already consumed.
  useEffect(() => { if (consumeLaunchRequest()) setOpen(true); }, []);
  // The menu item and the agent reach this lab only while it is mounted.
  useEffect(() => {
    const openLab = () => { setStatus(null); setOpen(true); };
    globalThis.uiTuningLabOpen = openLab;
    return () => { if (globalThis.uiTuningLabOpen === openLab) globalThis.uiTuningLabOpen = undefined; };
  }, []);
  // Seeded pins log their own line the first time the lab shows them.
  useEffect(() => {
    if (!open) return;
    for (const c of candidates) if (!logged.current.has(c.name)) logPin(c);
  }, [open, candidates]);

  // Logs a pin's line when it is new or changed since it last logged.
  function logPin(candidate: Candidate) {
    const line = sortedJson(candidate);
    if (logged.current.get(candidate.name) === line) return;
    logged.current.set(candidate.name, line);
    log("UITUNINGLAB_CANDIDATE", candidate);
  }
  // A pin edited in place logs its new values once it is left: another chip is
  // selected, the lab closes, or Choose.
  function leave() { if (selectedPin) logPin(selectedPin); }
  // Tapping a chip shows its look in the real feature. Switching chips is the
  // comparison.
  function select(chip: string) {
    if (chip === selected) return;
    leave();
    const pin = candidates.find(c => c.name === chip);
    setConfig({ ...baseline, ...pin?.values });
    setSelected(chip);
  }
  // Closing keeps the selected look in the feature; reopening keeps the chips.
  function close() { leave(); setMenuOpen(false); setOpen(false); }
  // Adds a pin, selects it, and shows it.
  function add(stem: string, basedOn: string, look: CardConfig) {
    leave();
    const name = nextName(stem, issued.current);
    const candidate: Candidate = { name, basedOn, values: changedValues(baseline, look) };
    issued.current.add(name);
    setCandidates(list => [...list, candidate]);
    logPin(candidate);
    setConfig(look);
    setSelected(name);
    setStatus(`New look ${name}`);
  }
  // Every control edits the selected look. Shipped is read-only, so an edit on it
  // starts a new pin; a pin changes in place.
  function edit(next: CardConfig, preset?: string) {
    if (!selectedPin) { add(preset ?? "tweak", preset ?? "baseline", next); return; }
    const values = changedValues(baseline, next);
    setCandidates(list => list.map(c => c.name === selected
      ? { ...c, values, basedOn: preset ?? c.basedOn } : c));
    setConfig(next);
  }
  function applyPreset(name: keyof typeof presets) { edit({ ...presets[name] }, name); }
  // Duplicate branches the selected pin, so the two can be compared.
  function duplicate() {
    if (!selectedPin) return;
    add(selectedPin.name.replace(/-[0-9]+$/, ""), selectedPin.name, config);
  }
  // Reports the selected look. No clipboard module in core React Native: the
  // values are logged and shown as selectable text. Call the app's clipboard
  // module here if it already has one.
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
    if (selected === name) { setConfig({ ...baseline }); setSelected("original"); }
  }
  // Choose picks the selected chip and finishes. Picking again replaces the
  // result. Not named useThis, which React's lint rules would treat as a hook.
  function pick() {
    leave();
    const winner = selectedPin ? selectedPin.name : "original";
    const done = { candidates, values: selectedValues, winner };
    // Logcat cuts entries near 4 KB. When the Done line may be cut, repeat each
    // pin on its own line first, so the agent can rebuild the list.
    if (sortedJson(done).length > 3500) for (const c of candidates) log("UITUNINGLAB_CANDIDATE", c);
    log("UITUNINGLAB_DONE", done);
    // The result file needs AsyncStorage; without it the log and the land code
    // carry the pick ("The result file", below). With a clipboard module in the
    // app, copy `land ${winner}` here.
    setMenuOpen(false);
    setResult(winner);
  }

  return <View style={{ flex: 1 }}>
    <CardFeature config={config} />
    <View pointerEvents="box-none" style={StyleSheet.absoluteFill}>
      {!open && <View style={styles.pill}>
        <Button title="Card Lab" label="Open UI tuning lab" onPress={() => { setStatus(null); setOpen(true); }} />
      </View>}
      {open && result !== null && <View style={[styles.pill, styles.bar]}>
        <Text accessibilityLiveRegion="polite">Chosen: {result}</Text>
        <Text selectable style={{ color: "#555" }}>land {result}</Text>
        <Button title="Change" onPress={() => setResult(null)} />
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
        {/* The chips: Shipped, then each pin. The selected chip is outlined. */}
        <View style={styles.row}>
          <Button title="Shipped" selected={selected === "original"} onPress={() => select("original")} />
          {candidates.map(c => <View key={c.name} style={styles.chip}>
            <Button title={c.name} selected={selected === c.name} onPress={() => select(c.name)} />
            <Button title="×" label={`Remove ${c.name}`} onPress={() => remove(c.name)} />
          </View>)}
        </View>
        <ScrollView style={{ flexGrow: 0, flexShrink: 1 }}>
          {/* Presets are actions, never outlined. */}
          <View style={styles.row}>
            <Button title="Compact" onPress={() => applyPreset("compact")} />
            <Button title="Relaxed" onPress={() => applyPreset("relaxed")} />
          </View>
          <Stepper label="Radius" value={config.radius} max={32}
            onChange={radius => edit({ ...config, radius })} />
          <Stepper label="Gap" value={config.gap} max={24}
            onChange={gap => edit({ ...config, gap })} />
          {status && <Text selectable accessibilityLiveRegion="polite">{status}</Text>}
        </ScrollView>
        <View style={styles.row}>
          <Button title="Duplicate" disabled={!selectedPin} onPress={duplicate} />
          <Button title="Choose" onPress={pick} />
        </View>
        {/* Pinned below the controls, visible however long the panel grows. */}
        <Text style={{ paddingTop: 8 }}>Duplicate to compare · Choose to finish</Text>
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
Use the commands in `references/platform-handoff.md`: `adb logcat -d -s ReactNativeJS:I`
and the Android wait loop with `TAG=ReactNativeJS`, or the Simulator
`log show` command without the subsystem clause.

Logcat truncates an entry near 4 KB, so a Done line with many pins can be
cut. When its JSON exceeds about 3,500 characters, the lab logs every pin
on its own `UITUNINGLAB_CANDIDATE` line right before Done; if the Done line does
not parse, rebuild the list from those lines (`references/candidates.md`, "Log
lines") and take the winner's values from its last `UITUNINGLAB_CANDIDATE` line.

Core React Native has no clipboard module, so the result bar shows the
`land <name>` code as selectable text; when the app already has a clipboard
module (`expo-clipboard`, `@react-native-clipboard/clipboard`), copy it in
`pick()` as well.

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
otherwise skip this and rely on the log and the land code. Choose then
also stores the Done object plus `savedAt` under `uiTuningLab.result`, replacing
the last pick; AsyncStorage writes one key atomically.

```tsx
import AsyncStorage from "@react-native-async-storage/async-storage";

function writeResult(done: object) {
  return AsyncStorage.setItem("uiTuningLab.result", sortedJson({ ...done, savedAt: new Date().toISOString() }));
}
```

In `pick()`, right after `log("UITUNINGLAB_DONE", done)`:
``writeResult(done).catch(e => setStatus(`Result file failed: ${String(e)}`));``.
The status shows after Change. Read the key in React Native DevTools'
console with `AsyncStorage.getItem("uiTuningLab.result")` when the module is
reachable there; otherwise the log holds the same line.

## Persistence variant, only when requested

Only when the app already depends on `@react-native-async-storage/async-storage`;
otherwise ask, and never add a native module for the lab alone
(`references/platform-handoff.md`). One `schemaVersion: 2` profile per
pin under `uiTuningLab.candidates.<name>`, written when the pin is created and
again whenever it logs new values.

```tsx
import AsyncStorage from "@react-native-async-storage/async-storage";

const candidateKey = "uiTuningLab.candidates.";

// Writes the pin's own key; stored names are reserved, so a new pin never lands
// on another's key. AsyncStorage writes one key atomically.
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

Wiring: `logPin`, right after its log line, calls
``writeCandidate(candidate).catch(e => setStatus(`${candidate.name} not saved: ${String(e)}`))``,
so a pin is written when it is created and whenever it logs new values; a
failed write leaves the pin in the panel. `remove` becomes async and awaits
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
