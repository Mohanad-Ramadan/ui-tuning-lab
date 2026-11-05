# Unvalidated adaptation — React Native overlay

> **Unvalidated adaptation — not compiled in this repository.** No React Native,
> Metro, or device toolchain runs here, so none of this code has been
> type-checked, bundled, or run. Treat it as a starting point and complete the
> full protocol (`references/verify-protocol.md`) in the target app before
> relying on it. Places where an API was assumed rather than checked are listed
> under "Assumptions to validate".

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

The lab component stays mounted while the screen is, so candidates, `basedOn`,
and the Compare stash survive closing the panel. The default lab is ephemeral:
candidates live in React state and the log, and a name is never reused within a
JavaScript runtime. Show baseline and Compare share one stash and are
exclusive; the draft controls are disabled while either shows something other
than the draft, Done is disabled only while Show baseline is on, and closing
restores the draft.

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
import { DevSettings, Pressable, ScrollView, StyleSheet, Switch, Text, View } from "react-native";
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
// 1 -> a, 26 -> z, 27 -> aa (bijective base 26).
function candidateName(index: number): string {
  let name = "";
  for (let n = index; n > 0; n = Math.floor(n / 26)) {
    n -= 1;
    name = String.fromCharCode(97 + (n % 26)) + name;
  }
  return name;
}

function Button({ title, onPress, disabled, label, role = "button", checked }: {
  title: string; onPress: () => void; disabled?: boolean; label?: string;
  role?: "button" | "radio"; checked?: boolean;
}) {
  return <Pressable onPress={onPress} disabled={disabled} accessibilityRole={role}
    accessibilityLabel={label ?? title} accessibilityState={{ disabled, checked }}
    style={[styles.button, checked && styles.checked, disabled && { opacity: 0.4 }]}>
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
  const [status, setStatus] = useState<string | null>(null);
  const [candidates, setCandidates] = useState(initialCandidates);
  const issued = useRef(new Set(initialCandidates.map(c => c.name)));
  const logged = useRef(new Set<string>());
  const [basedOn, setBasedOn] = useState("baseline");
  const [shown, setShown] = useState("draft");
  const stashedDraft = useRef<CardConfig | null>(null);
  const editing = shown === "draft";

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
  function close() { show("draft"); setOpen(false); }
  function applyPreset(name: keyof typeof presets) { setConfig({ ...presets[name] }); setBasedOn(name); }
  function reset() { setConfig({ ...baseline }); setBasedOn("baseline"); }
  // No clipboard module in core React Native: the values are logged and shown as
  // selectable text. Call the app's clipboard module here if it already has one.
  function copyValues() {
    const values = changedValues(baseline, config);
    log("UITUNINGLAB_VALUES", values);
    const text = sortedJson(values);
    setStatus(text === "{}" ? "No changes from baseline" : `Logged ${text}`);
  }
  function prepareKeep(): Candidate | null {
    const values = changedValues(baseline, config);
    if (Object.keys(values).length === 0) { setStatus("Matches the baseline; nothing to keep"); return null; }
    const same = candidates.find(c => sortedJson(c.values) === sortedJson(values));
    if (same) { setStatus(`Same as ${same.name}`); return null; }
    let i = 1;
    while (issued.current.has(candidateName(i))) i++;
    return { name: candidateName(i), basedOn, values };
  }
  function commit(candidate: Candidate) {
    setCandidates(list => [...list, candidate]);
    issued.current.add(candidate.name);
    logged.current.add(candidate.name);
    log("UITUNINGLAB_CANDIDATE", candidate);
    setStatus(`Kept as ${candidate.name}`);
  }
  function keep() { const c = prepareKeep(); if (c) commit(c); }
  function load(candidate: Candidate) {
    stashedDraft.current = null;
    setConfig({ ...baseline, ...candidate.values });
    setBasedOn(candidate.name);
    setShown("draft");
  }
  function remove(name: string) {
    setCandidates(list => list.filter(c => c.name !== name));
    log("UITUNINGLAB_CANDIDATE_REMOVED", { name });
    if (shown === name) show("draft");
  }
  // Like Copy values, and it tells the agent the session is over. While Compare
  // shows a candidate, that candidate becomes the draft first: it is the winner.
  function done() {
    const picked = candidates.find(c => c.name === shown);
    if (picked) load(picked);
    const values = changedValues(baseline, picked ? { ...baseline, ...picked.values } : config);
    const winner = candidates.find(c => sortedJson(c.values) === sortedJson(values));
    const payload = { candidates, values, winner: winner?.name ?? null };
    // Logcat cuts entries near 4 KB. When the Done line may be cut, repeat each
    // candidate on its own line first, so the agent can rebuild the list.
    if (sortedJson(payload).length > 3500) for (const c of candidates) log("UITUNINGLAB_CANDIDATE", c);
    log("UITUNINGLAB_DONE", payload);
    setStatus(`Done. Logged ${sortedJson(values)}`);
  }

  return <View style={{ flex: 1 }}>
    <CardFeature config={config} />
    <View pointerEvents="box-none" style={StyleSheet.absoluteFill}>
      {!open && <View style={styles.pill}>
        <Button title="Tune" label="Open UI tuning lab" onPress={() => { setStatus(null); setOpen(true); }} />
      </View>}
      {open && <View style={styles.panel} accessibilityLabel="UI tuning lab">
        <ScrollView style={{ flexGrow: 0 }}>
          <View style={styles.row}>
            <Text accessibilityRole="header" style={{ flex: 1, fontWeight: "600" }}>UI tuning lab</Text>
            <Button title="Close" onPress={close} />
          </View>
          <View style={styles.row}>
            <Text style={{ flex: 1 }}>Show baseline</Text>
            <Switch accessibilityLabel="Show baseline" value={shown === "baseline"}
              onValueChange={on => show(on ? "baseline" : "draft")} />
          </View>
          <View style={styles.row}>
            <Button title="Compact" disabled={!editing} onPress={() => applyPreset("compact")} />
            <Button title="Relaxed" disabled={!editing} onPress={() => applyPreset("relaxed")} />
          </View>
          <Stepper label="Radius" value={config.radius} max={32} disabled={!editing}
            onChange={radius => setConfig(c => ({ ...c, radius }))} />
          <Stepper label="Gap" value={config.gap} max={24} disabled={!editing}
            onChange={gap => setConfig(c => ({ ...c, gap }))} />
          <View style={styles.row}>
            <Button title="Reset" disabled={!editing} onPress={reset} />
            <Button title="Copy values" disabled={!editing} onPress={copyValues} />
            <Button title="Keep as candidate" disabled={!editing} onPress={keep} />
          </View>
          {candidates.length > 0 && <>
            {candidates.map(c => <View key={c.name} style={styles.row}>
              <Text style={{ flex: 1 }}>{c.name} from {c.basedOn}</Text>
              <Button title="Load" label={`Load ${c.name}`} disabled={!editing} onPress={() => load(c)} />
              <Button title="Remove" label={`Remove ${c.name}`} onPress={() => remove(c.name)} />
            </View>)}
            <Text>Compare</Text>
            <View style={styles.row} accessibilityRole="radiogroup">
              {["draft", ...candidates.map(c => c.name)].map(target =>
                <Button key={target} role="radio" checked={shown === target}
                  title={target === "draft" ? "Draft" : target} onPress={() => show(target)} />)}
            </View>
          </>}
          <Button title="Done" disabled={shown === "baseline"} onPress={done} />
          {status && <Text selectable accessibilityLiveRegion="polite">{status}</Text>}
        </ScrollView>
        {/* Pinned below the scrolling controls, visible however long the panel grows. */}
        <Text style={{ paddingTop: 8 }}>
          Finished? Keep the ones you like, then press Done, or tell the agent "land b".</Text>
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
  checked: { backgroundColor: "#cde" },
});
```

## Reading the lines and waiting for Done

`console.info` lines reach logcat under `ReactNativeJS` on Android and the
unified log on the iOS Simulator, as well as React Native DevTools' console.
Use the commands in `references/platform-handoff.md`: `adb logcat -d -s ReactNativeJS:I`
and the Android wait loop with `TAG=ReactNativeJS`, or the Simulator
`log show` command without the subsystem clause.

Logcat truncates an entry near 4 KB, so a Done line with many candidates can be
cut. When its JSON exceeds about 3,500 characters, the lab logs every
candidate on its own `UITUNINGLAB_CANDIDATE` line right before Done; if the Done
line does not parse, rebuild the list from those lines
(`references/candidates.md`, "Log lines") and take the draft's values from a
fresh Copy values.

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

## Assumptions to validate

- That Metro's release transform folds `if (__DEV__)` before collecting
  dependencies, so the required module is not in the bundle. The bundle search
  is the evidence.
- `DevSettings.addMenuItem` has no removal API, and its behavior when the same
  title is added twice; the global flag avoids the second call. Expo Go and
  `expo-dev-client` use their own developer menu, where this item may not
  appear; there, `expo-dev-menu`'s `registerDevMenuItems` is the equivalent.
- `process.env.EXPO_PUBLIC_*` is inlined by Expo's Babel preset; in bare React
  Native without an inlining plugin it is `undefined`, which leaves the lab
  closed rather than failing.
- Evaluating `uiTuningLabOpen()` over the debugger WebSocket from a script; the
  `/json/list` endpoint and `Runtime.evaluate` are the Chrome DevTools Protocol
  surface Metro's inspector proxy exposes, but this was not exercised.
- `accessibilityRole="radiogroup"` and the adjustable stepper's increment and
  decrement actions with TalkBack and VoiceOver.
