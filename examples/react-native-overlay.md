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
- **Visible fallback:** a **Tune** pill in a free corner.
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

The lab component stays mounted while the screen is, so favorites, `basedOn`,
and the stashed Now survive closing the panel. The default lab is ephemeral:
favorites live in React state and the log, and a name is never reused within a
JavaScript runtime. The chip row under the header shows Original, Now, or a
favorite in the real feature; Now is stashed meanwhile and restored when Now is
tapped or the panel closes. While Original is shown the presets and steppers
are disabled; moving one while a favorite is shown loads that favorite into Now
first. **★ Keep** adds Now to the favorites, **✓ Use this** picks the shown chip
and shrinks the panel to the result bar, and the **⋯** button opens Reset and
Copy values.

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
// Preset keys are kebab-case: the key is what a candidate records as basedOn.
const presets = {
  compact: { radius: 4, gap: 4 },
  relaxed: { radius: 24, gap: 16 },
} satisfies Record<string, CardConfig>;
// The declared default, never the value on screen when the lab opens.
const baseline: CardConfig = appDefault;

function changedValues<T extends object>(base: T, draft: T): Partial<T> {
  return Object.fromEntries(Object.entries(draft).filter(
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
function Stepper({ label, value, max, disabled, onChange }: {
  label: string; value: number; max: number; disabled: boolean; onChange: (v: number) => void;
}) {
  const set = (v: number) => { if (!disabled) onChange(Math.min(max, Math.max(0, v))); };
  return <View accessible accessibilityRole="adjustable" accessibilityLabel={label}
    accessibilityValue={{ min: 0, max, now: value }} accessibilityState={{ disabled }}
    accessibilityActions={[{ name: "increment" }, { name: "decrement" }]}
    onAccessibilityAction={e => set(value + (e.nativeEvent.actionName === "increment" ? 1 : -1))}
    style={styles.row}>
    <Text style={{ flex: 1 }}>{label}</Text>
    <Button title="−" disabled={disabled} onPress={() => set(value - 1)} />
    <Text style={{ minWidth: 32, textAlign: "center" }}>{value}</Text>
    <Button title="+" disabled={disabled} onPress={() => set(value + 1)} />
  </View>;
}

export default function UITuningLabFeature({ config, setConfig }: TuningLabHostProps) {
  const [open, setOpen] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const [status, setStatus] = useState<string | null>(null);
  const [candidates, setCandidates] = useState(initialCandidates);
  // Every name issued, removed ones included, plus the names a favorite never takes.
  const issued = useRef(new Set(["draft", "now", "original", "baseline", ...initialCandidates.map(c => c.name)]));
  const logged = useRef(new Set<string>());
  const [basedOn, setBasedOn] = useState("baseline");
  const lastPreset = useRef<string | null>(null);
  // The shown chip: "draft" (Now), "original", or a favorite's name.
  const [shown, setShown] = useState("draft");
  // The last pick; while set, the panel is the result bar.
  const [result, setResult] = useState<string | null>(null);
  const stashedDraft = useRef<CardConfig | null>(null); // Now, while another chip is shown
  const editable = shown !== "original"; // never edit the baseline

  // In an effect rather than a state initializer: StrictMode runs initializers
  // twice, and the second call would see the request already consumed.
  useEffect(() => { if (consumeLaunchRequest()) setOpen(true); }, []);
  // The menu item and the agent reach this lab only while it is mounted.
  useEffect(() => {
    const openLab = () => { setStatus(null); setOpen(true); };
    globalThis.uiTuningLabOpen = openLab;
    return () => { if (globalThis.uiTuningLabOpen === openLab) globalThis.uiTuningLabOpen = undefined; };
  }, []);
  useEffect(() => {
    if (!open) return;
    for (const c of candidates) {
      if (logged.current.has(c.name)) continue;
      logged.current.add(c.name);
      log("UITUNINGLAB_CANDIDATE", c);
    }
  }, [open, candidates]);

  // Tapping a chip shows it in the real feature.
  function show(target: string) {
    if (target === "draft") {
      if (stashedDraft.current) setConfig(stashedDraft.current);
      stashedDraft.current = null;
    } else {
      if (!stashedDraft.current) stashedDraft.current = config;
      const candidate = candidates.find(c => c.name === target);
      setConfig({ ...baseline, ...candidate?.values });
    }
    setShown(target);
  }
  function close() { show("draft"); setMenuOpen(false); setOpen(false); }
  // Every control edits Now. Moved while a favorite is shown, it loads that
  // favorite into Now first; the favorite itself does not change.
  function edit(next: CardConfig, from?: string) {
    stashedDraft.current = null;
    setBasedOn(from ?? (shown === "draft" ? basedOn : shown));
    setConfig(next);
    setShown("draft");
  }
  function applyPreset(name: keyof typeof presets) { lastPreset.current = name; edit({ ...presets[name] }, name); }
  function reset() { lastPreset.current = null; edit({ ...baseline }, "baseline"); setMenuOpen(false); }
  // Always reports Now. No clipboard module in core React Native: the values are
  // logged and shown as selectable text. Call the app's clipboard module here if
  // it already has one.
  function copyValues() {
    const values = changedValues(baseline, stashedDraft.current ?? config);
    log("UITUNINGLAB_VALUES", values);
    const text = sortedJson(values);
    setStatus(text === "{}" ? "No changes from Original" : `Logged ${text}`);
    setMenuOpen(false);
  }
  // Keep is enabled only while Now is shown, so config is Now.
  function prepareKeep(): Candidate | null {
    const values = changedValues(baseline, config);
    if (Object.keys(values).length === 0) { setStatus("Same as Original"); return null; }
    const same = candidates.find(c => sortedJson(c.values) === sortedJson(values));
    if (same) { setStatus(`Same as ${same.name}`); return null; }
    const stem = lastPreset.current ?? "tweak";
    let name = stem;
    for (let i = 2; issued.current.has(name); i++) name = `${stem}-${i}`;
    return { name, basedOn, values };
  }
  function commit(candidate: Candidate) {
    setCandidates(list => [...list, candidate]);
    issued.current.add(candidate.name);
    logged.current.add(candidate.name);
    log("UITUNINGLAB_CANDIDATE", candidate);
    setStatus(`Kept as ${candidate.name}`);
  }
  function keep() { const c = prepareKeep(); if (c) commit(c); }
  function remove(name: string) {
    if (shown === name) show("draft");
    setCandidates(list => list.filter(c => c.name !== name));
    log("UITUNINGLAB_CANDIDATE_REMOVED", { name });
  }
  // ✓ Use this: picks the shown chip and finishes. Picking again replaces the
  // result. Not named useThis, which React's lint rules would treat as a hook.
  function pick() {
    const picked = candidates.find(c => c.name === shown);
    const winner = picked?.name ?? (shown === "original" ? "original" : "draft");
    const values: Partial<CardConfig> = picked?.values ?? (shown === "original" ? {} : changedValues(baseline, config));
    const done = { candidates, values, winner };
    // Logcat cuts entries near 4 KB. When the Done line may be cut, repeat each
    // favorite on its own line first, so the agent can rebuild the list.
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
        <Button title="Tune" label="Open UI tuning lab" onPress={() => { setStatus(null); setOpen(true); }} />
      </View>}
      {open && result !== null && <View style={[styles.pill, styles.bar]}>
        <Text accessibilityLiveRegion="polite">✓ Sent: {result}</Text>
        <Text selectable style={{ color: "#555" }}>land {result}</Text>
        <Button title="Change" onPress={() => setResult(null)} />
      </View>}
      {open && result === null && <View style={styles.panel} accessibilityLabel="UI tuning lab">
        <View style={styles.row}>
          <Text accessibilityRole="header" style={{ flex: 1, fontWeight: "600" }}>UI tuning lab</Text>
          <Button title="⋯" label="More" selected={menuOpen} onPress={() => setMenuOpen(m => !m)} />
          <Button title="Close" onPress={close} />
        </View>
        {menuOpen && <View style={styles.row}>
          <Button title="Reset" onPress={reset} />
          <Button title="Copy values" onPress={copyValues} />
        </View>}
        {/* The chips: Original, Now, then each favorite. Highlighted = shown. */}
        <View style={styles.row}>
          <Button title="Original" selected={shown === "original"} onPress={() => show("original")} />
          <Button title="Now" selected={shown === "draft"} onPress={() => show("draft")} />
          {candidates.map(c => <View key={c.name} style={styles.chip}>
            <Button title={c.name} selected={shown === c.name} onPress={() => show(c.name)} />
            <Button title="×" label={`Remove ${c.name}`} onPress={() => remove(c.name)} />
          </View>)}
        </View>
        <ScrollView style={{ flexGrow: 0, flexShrink: 1 }}>
          <View style={styles.row}>
            <Button title="Compact" disabled={!editable} onPress={() => applyPreset("compact")} />
            <Button title="Relaxed" disabled={!editable} onPress={() => applyPreset("relaxed")} />
          </View>
          <Stepper label="Radius" value={config.radius} max={32} disabled={!editable}
            onChange={radius => edit({ ...config, radius })} />
          <Stepper label="Gap" value={config.gap} max={24} disabled={!editable}
            onChange={gap => edit({ ...config, gap })} />
          {status && <Text selectable accessibilityLiveRegion="polite">{status}</Text>}
        </ScrollView>
        <View style={styles.row}>
          <Button title="★ Keep" disabled={shown !== "draft"} onPress={keep} />
          <Button title="✓ Use this" onPress={pick} />
        </View>
        {/* Pinned below the controls, visible however long the panel grows. */}
        <Text style={{ paddingTop: 8 }}>Keep favorites · Use this to finish</Text>
      </View>}
    </View>
  </View>;
}

const styles = StyleSheet.create({
  // Pick the corner inspection found free of other dev overlays.
  pill: { position: "absolute", right: 16, bottom: 16 },
  panel: {
    position: "absolute", right: 16, bottom: 72, width: 320, maxWidth: "90%", maxHeight: "70%",
    padding: 12, borderRadius: 12, backgroundColor: "white", elevation: 8,
    shadowOpacity: 0.2, shadowRadius: 8,
  },
  row: { flexDirection: "row", flexWrap: "wrap", alignItems: "center", gap: 8, marginVertical: 4 },
  button: { paddingHorizontal: 10, paddingVertical: 6, borderRadius: 6, borderWidth: 1, borderColor: "#999" },
  selected: { backgroundColor: "#cde" },
  chip: { flexDirection: "row", gap: 2 },
  bar: {
    flexDirection: "row", alignItems: "center", gap: 8, padding: 8, borderRadius: 20,
    backgroundColor: "white", elevation: 8, shadowOpacity: 0.2, shadowRadius: 8,
  },
});
```

## Reading the lines and waiting for the pick

`console.info` lines reach logcat under `ReactNativeJS` on Android and the
unified log on the iOS Simulator, as well as React Native DevTools' console.
Use the commands in `references/platform-handoff.md`: `adb logcat -d -s ReactNativeJS:I`
and the Android wait loop with `TAG=ReactNativeJS`, or the Simulator
`log show` command without the subsystem clause.

Logcat truncates an entry near 4 KB, so a Done line with many favorites can be
cut. When its JSON exceeds about 3,500 characters, the lab logs every favorite
on its own `UITUNINGLAB_CANDIDATE` line right before Done; if the Done line does
not parse, rebuild the list from those lines (`references/candidates.md`, "Log
lines") and take Now's values from a fresh Copy values.

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

Close unmounts the panel and restores the stashed draft. Unmounting the screen
clears the `uiTuningLabOpen` global. The developer-menu item cannot be
unregistered: it stays in the menu until the next full reload and does nothing
while no lab is mounted. The lab owns no timers or subscriptions.

Removal at landing: delete `FeatureScreen.ui-tuning-lab.tsx` and the
`TuningLabHost` block, and point the screen back at
`<CardFeature config={appDefault} />`, which now holds the winner. Reload the
app so the menu item disappears.

## The result file, only when the app has AsyncStorage

Only when the app already depends on `@react-native-async-storage/async-storage`;
otherwise skip this and rely on the log and the land code. ✓ Use this then
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
candidate under `uiTuningLab.candidates.<name>`.

```tsx
import AsyncStorage from "@react-native-async-storage/async-storage";

const candidateKey = "uiTuningLab.candidates.";

// Never over an existing key. AsyncStorage writes one key atomically.
async function writeCandidate(candidate: Candidate, overrides: CardConfig) {
  const key = candidateKey + candidate.name;
  if ((await AsyncStorage.getItem(key)) !== null) throw new Error(`${candidate.name} already exists in storage`);
  await AsyncStorage.setItem(key, sortedJson({
    basedOn: candidate.basedOn, container: "FeatureScreen.overlay", name: candidate.name, notes: "",
    overrides, platform: "react-native", savedAt: new Date().toISOString(), schemaVersion: 2,
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

Wiring: `keep` becomes async, awaits `writeCandidate(c, config)` and calls
`commit(c)` only if it succeeded, otherwise `setStatus("Keep failed: ...")`;
`remove` awaits `AsyncStorage.removeItem(candidateKey + name)` first; an effect
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
