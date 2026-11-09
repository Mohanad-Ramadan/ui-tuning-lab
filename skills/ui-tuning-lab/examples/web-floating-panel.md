# Candidate — web floating panel

The feature and controls share one config state. All lab code lives in
`FeatureScreen.ui-tuning-lab.tsx`; the feature reaches it only through a dynamic
import inside an `import.meta.env.DEV` block, so production builds drop both the
branch and the lab chunk. The Card Lab button is the human path and the visible
fallback; `?ui-tuning-lab=1` is the agent path, parsed only inside that
development module (`references/activation.md`). The baseline is the declared
default, `appDefault`; closing unmounts the popover and its listener.

The panel follows `references/candidates.md`. A chip row under the header shows
**Shipped** and each pin; the selected chip is outlined, and the feature always
shows it. Switching chips is the comparison: there is no draft and nothing is
stashed. Moving a control or applying a preset edits the selected pin in place;
on Shipped, which is read-only, it starts a new pin named after the preset or
`tweak`. **Duplicate** branches the selected pin. **Choose** picks the selected
chip: it logs `UITUNINGLAB_DONE`, writes the same object to the `localStorage`
key `uiTuningLab.result`, copies `land <name>` to the clipboard, and shrinks the
panel to `Chosen: <name>` with **Change** to reopen it. The **⋯** menu holds
**Copy values**, which logs the selected look's changed fields as one
`UITUNINGLAB_VALUES {...}` line (`references/landing-protocol.md`).

The default lab is ephemeral: pins live in React state and the console log,
and the result key is its only write. `initialCandidates` seeds the pins when
the lab is reopened in a later session.

<!-- file: CardFeature.tsx -->
```tsx
export type CardConfig = { radius: number; gap: number };
export const appDefault: CardConfig = { radius: 12, gap: 8 };

export function CardFeature({ config }: { config: CardConfig }) {
  return (
    <div style={{ display: "grid", gap: config.gap }}>
      <article style={{ borderRadius: config.radius, padding: 16 }}>First card</article>
      <article style={{ borderRadius: config.radius, padding: 16 }}>Second card</article>
    </div>
  );
}
```

<!-- file: FeatureScreen.tsx -->
```tsx
import { lazy, Suspense, useState } from "react";
import type { ComponentType, Dispatch, SetStateAction } from "react";
import { appDefault, CardFeature } from "./CardFeature";
import type { CardConfig } from "./CardFeature";

export type TuningLabHostProps = {
  config: CardConfig;
  setConfig: Dispatch<SetStateAction<CardConfig>>;
};

// Production builds replace import.meta.env.DEV with false, which removes this
// branch and the lab chunk from the bundle.
let TuningLabHost: ComponentType<TuningLabHostProps> | null = null;
if (import.meta.env.DEV) {
  TuningLabHost = lazy(() => import("./FeatureScreen.ui-tuning-lab"));
}

export function FeatureScreen() {
  const [config, setConfig] = useState(appDefault);
  if (TuningLabHost) {
    return (
      <Suspense fallback={<CardFeature config={config} />}>
        <TuningLabHost config={config} setConfig={setConfig} />
      </Suspense>
    );
  }
  return <CardFeature config={config} />;
}
```

<!-- file: FeatureScreen.ui-tuning-lab.tsx -->
```tsx
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { appDefault, CardFeature } from "./CardFeature";
import type { CardConfig } from "./CardFeature";
import type { TuningLabHostProps } from "./FeatureScreen";

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
// A selected chip or preset is outlined, so it reads as selected without a label.
// Highlight follows color-scheme, so the outline holds in light and dark mode.
const selectedStyle = (on: boolean) =>
  on ? { outline: "2px solid Highlight", outlineOffset: 1, fontWeight: 600 } as const : undefined;

// A pin: the fields that differ from the baseline, plus where it started.
type Candidate = { name: string; basedOn: string; values: Partial<CardConfig> };
// Pins the lab opens with. Empty by default; a later session seeds the
// finalists kept in the project here (references/candidates.md).
const initialCandidates: Candidate[] = [];
// Choose writes the pick here, so it survives quitting the app.
const resultKey = "uiTuningLab.result";
// Never issued as a pin's name: "original" is the Shipped chip, and the others
// are kept for older logs.
const reservedNames = ["draft", "now", "original", "baseline"];

// Preset keys are kebab-case: the key is what a pin records as basedOn and is
// named after.
const presets = {
  compact: { radius: 4, gap: 4 },
  relaxed: { radius: 24, gap: 16 },
} satisfies Record<string, CardConfig>;
// The baseline is the declared default, never the value on screen when the lab
// opens: a look kept from an earlier session must still count as a change.
const baseline: CardConfig = appDefault;

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

// `base`, or `base-2`, `base-3`, ... when taken. Removed names stay in `issued`,
// so a name is never reused in this run.
function nextName(base: string, issued: Set<string>): string {
  if (!issued.has(base)) return base;
  for (let i = 2; ; i++) {
    if (!issued.has(`${base}-${i}`)) return `${base}-${i}`;
  }
}

export default function UITuningLabFeature({ config, setConfig }: TuningLabHostProps) {
  const [open, setOpen] = useState(opensOnLaunch);
  useEffect(clearLaunchRequest, []);
  const [status, setStatus] = useState<string | null>(null);
  const panel = useRef<HTMLDivElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  const firstControl = useRef<HTMLButtonElement>(null);
  const changeButton = useRef<HTMLButtonElement>(null);
  // Pins live in memory and in the log. A pin is a
  // look being worked on: the controls edit the selected pin in place.
  const [candidates, setCandidates] = useState(initialCandidates);
  // Every name issued in this run, removed ones included: names are never reused.
  const issued = useRef(new Set([...reservedNames, ...initialCandidates.map(c => c.name)]));
  // The values each pin last logged, so a pin logs again only after it changed.
  const logged = useRef(new Map<string, string>());
  // The selected chip: "original" (Shipped) or a pin's name. The feature always
  // shows it; there is no draft and nothing is stashed.
  const [selected, setSelected] = useState("original");
  // The winner after Choose; while set, the panel is the result bar.
  const [sent, setSent] = useState<string | null>(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const selectedPin = candidates.find(c => c.name === selected);
  const selectedValues = selectedPin?.values ?? {};

  // Read the latest pins and selection through refs, so the close path, which
  // runs from an effect, never reads stale state.
  const latest = useRef({ candidates, selected });
  useLayoutEffect(() => { latest.current = { candidates, selected }; });

  // Logs a pin's line when it is new or changed since it last logged.
  function logPin(candidate: Candidate) {
    const line = sortedJson(candidate);
    if (logged.current.get(candidate.name) === line) return;
    logged.current.set(candidate.name, line);
    console.info(`UITUNINGLAB_CANDIDATE ${line}`);
  }
  // A pin edited in place logs its new values once it is left: another chip is
  // selected, the lab closes, or Choose.
  function leave() {
    const { candidates, selected } = latest.current;
    const pin = candidates.find(c => c.name === selected);
    if (pin) logPin(pin);
  }

  // The one close path. It runs from the popover's toggle event, or directly
  // when the browser has no Popover API. The feature keeps the selected look.
  function finishClose() {
    leave();
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

  // Choose moves focus to Change, and Change moves it back to the chips.
  useEffect(() => { (sent ? changeButton : firstControl).current?.focus(); }, [sent]);

  // Seeded pins log their own line the first time the lab shows them.
  useEffect(() => {
    if (!open) return;
    for (const c of candidates) if (!logged.current.has(c.name)) logPin(c);
  }, [open, candidates]);

  function openLab() { setStatus(null); setOpen(true); }
  // Selecting a chip shows its look in the real feature. Switching chips is the
  // comparison.
  function select(chip: string) {
    if (chip === selected) return;
    leave();
    const pin = candidates.find(c => c.name === chip);
    setConfig({ ...baseline, ...pin?.values });
    setSelected(chip);
  }
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
  // Reports the selected look.
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
    if (selected === name) { setConfig({ ...baseline }); setSelected("original"); }
  }
  // Choose picks the selected chip and finishes. Picking again replaces the
  // result.
  async function pickSelected() {
    leave();
    const winner = selectedPin ? selectedPin.name : "original";
    const result = { candidates, values: selectedValues, winner };
    console.info(`UITUNINGLAB_DONE ${sortedJson(result)}`);
    const problems: string[] = [];
    try {
      localStorage.setItem(resultKey, sortedJson({ ...result, savedAt: new Date().toISOString() }));
    } catch {
      problems.push("result not saved");
    }
    try {
      await navigator.clipboard.writeText(`land ${winner}`);
    } catch {
      problems.push(`clipboard unavailable; tell the agent "land ${winner}"`);
    }
    setStatus(problems.length > 0 ? `Logged to the console; ${problems.join("; ")}` : null);
    setSent(winner);
  }

  return <>
    <CardFeature config={config} />
    <button ref={trigger} type="button" onClick={openLab} disabled={open}
      style={triggerStyle}>Card Lab</button>
    {open && <div ref={panel} {...popoverManual} style={panelStyle} role="dialog"
      aria-labelledby="ui-tuning-lab-title">
      {sent ? <p style={rowStyle}>
        <strong id="ui-tuning-lab-title">Chosen: {sent}</strong>
        <button ref={changeButton} type="button" onClick={() => setSent(null)}>Change</button>
      </p> : <>
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
          <button ref={firstControl} type="button" aria-pressed={selected === "original"}
            style={selectedStyle(selected === "original")}
            onClick={() => select("original")}>Shipped</button>
          {candidates.map(c => <span key={c.name}>
            <button type="button" aria-pressed={selected === c.name} style={selectedStyle(selected === c.name)}
              onClick={() => select(c.name)}>{c.name}</button>
            <button type="button" aria-label={`Remove ${c.name}`} onClick={() => remove(c.name)}>×</button>
          </span>)}
        </div>
        <div role="group" aria-label="Controls">
          <button type="button" onClick={() => applyPreset("compact")}>Compact</button>
          <button type="button" onClick={() => applyPreset("relaxed")}>Relaxed</button>
          <label>Radius <input type="range" min="0" max="32"
            value={config.radius}
            onChange={e => edit({ ...config, radius: Number(e.target.value) })}/>
            <output aria-hidden="true">{config.radius}px</output>
          </label>
          <label>Gap <input type="range" min="0" max="24"
            value={config.gap}
            onChange={e => edit({ ...config, gap: Number(e.target.value) })}/>
            <output aria-hidden="true">{config.gap}px</output>
          </label>
        </div>
        <div style={rowStyle}>
          <button type="button" disabled={!selectedPin} onClick={duplicate}>Duplicate</button>
          <button type="button" onClick={pickSelected}>Choose</button>
        </div>
      </>}
      {status && <p role="status">{status}</p>}
      {!sent && <p style={{ position: "sticky", bottom: 0, margin: 0, padding: "8px 0", background: "Canvas" }}>
        Duplicate to compare · Choose to finish</p>}
    </div>}
  </>;
}
```

Keep lab code only in `*.ui-tuning-lab.tsx` modules and import them only as shown
in `FeatureScreen.tsx`; a top-level static import fails `source-gates`. If
Popover API support is outside the app's browser baseline, use an accessible
dialog or conditionally mounted `<details>` while preserving focus and teardown.
The manual popover stays open while the user clicks, scrolls, and inspects the
feature; Close and Escape dismiss it, the `toggle` event unmounts it, and cleanup
restores focus to Card Lab. The panel is pinned to the corner and the trigger is
fixed, so neither moves the feature. Chips use `aria-pressed`, and buttons and
the labelled ranges remain in normal keyboard order. Test Chromium, Safari, and
Firefox on desktop and mobile layouts, keyboard, screen readers, Close and
Escape, unmounting, and emitted production assets before approval.

## Optional persistence, only when requested

Only when the user explicitly requests saved profiles, replace
`FeatureScreen.ui-tuning-lab.tsx` with this version. The feature files stay
unchanged, and the writer and loader live only in the development-only module.
Each pin writes a `schemaVersion: 2` profile under `uiTuningLab.candidates.<name>`
when it is created and again whenever it logs new values, × deletes that key, and
opening the lab loads every such key into the chips; every stored name is taken,
readable or not. The baseline stays the declared default, so Shipped still shows
it. Unreadable or incompatible entries (wrong
`schemaVersion` or `platform`) are reported in the status line, skipped, and left
in storage untouched.

<!-- file: FeatureScreen.ui-tuning-lab.tsx variant=persist -->
```tsx
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { appDefault, CardFeature } from "./CardFeature";
import type { CardConfig } from "./CardFeature";
import type { TuningLabHostProps } from "./FeatureScreen";

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
// A selected chip or preset is outlined, so it reads as selected without a label.
// Highlight follows color-scheme, so the outline holds in light and dark mode.
const selectedStyle = (on: boolean) =>
  on ? { outline: "2px solid Highlight", outlineOffset: 1, fontWeight: 600 } as const : undefined;

type UITuningLabProfile = {
  basedOn: string;
  container: string;
  name: string;
  notes: string;
  overrides: CardConfig;
  platform: "web";
  savedAt: string;
  schemaVersion: 2;
  scope: string[];
};
// Each pin is stored under its own key: uiTuningLab.candidates.<name>.
const candidateKey = "uiTuningLab.candidates.";

// A pin: the fields that differ from the baseline, plus where it started.
type Candidate = { name: string; basedOn: string; values: Partial<CardConfig> };
// Pins the lab opens with, before anything stored is loaded. Empty by
// default; a later session can seed finalists kept in the project here.
const initialCandidates: Candidate[] = [];
// Choose writes the pick here, so it survives quitting the app.
const resultKey = "uiTuningLab.result";
// Never issued as a pin's name: "original" is the Shipped chip, and the others
// are kept for older logs.
const reservedNames = ["draft", "now", "original", "baseline"];

// Preset keys are kebab-case: the key is what a pin records as basedOn and is
// named after.
const presets = {
  compact: { radius: 4, gap: 4 },
  relaxed: { radius: 24, gap: 16 },
} satisfies Record<string, CardConfig>;
// The baseline is the declared default, never the value on screen when the lab
// opens: a look kept from an earlier session must still count as a change.
const baseline: CardConfig = appDefault;

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

// `base`, or `base-2`, `base-3`, ... when taken. Removed names stay in `issued`,
// so a name is never reused in this run.
function nextName(base: string, issued: Set<string>): string {
  if (!issued.has(base)) return base;
  for (let i = 2; ; i++) {
    if (!issued.has(`${base}-${i}`)) return `${base}-${i}`;
  }
}

function reasonOf(error: unknown): string {
  return error instanceof Error ? error.message : "unknown error";
}

// Reads every stored pin, oldest first. An entry that cannot be used is
// described in `problems` and left in storage untouched. Every stored name,
// readable or not, is added to `reserved` so a new pin never reuses it.
function readStored(reserved: Set<string>): { found: Candidate[]; problems: string[] } {
  const keys: string[] = [];
  for (let i = 0; i < localStorage.length; i++) {
    const key = localStorage.key(i);
    if (key?.startsWith(candidateKey)) keys.push(key);
  }
  const found: Array<Candidate & { savedAt: string }> = [];
  const problems: string[] = [];
  for (const key of keys) {
    reserved.add(key.slice(candidateKey.length));
    try {
      const profile = JSON.parse(localStorage.getItem(key) ?? "") as Partial<UITuningLabProfile>;
      const saved = profile.overrides;
      if (profile.schemaVersion !== 2 || profile.platform !== "web" ||
          typeof profile.name !== "string" || key !== candidateKey + profile.name ||
          typeof saved?.radius !== "number" || typeof saved?.gap !== "number") {
        throw new Error("incompatible schema, platform, or name");
      }
      const values = changedValues(baseline, { radius: saved.radius, gap: saved.gap });
      if (Object.keys(values).length === 0) throw new Error("matches the baseline");
      found.push({
        name: profile.name,
        basedOn: typeof profile.basedOn === "string" ? profile.basedOn : "baseline",
        values,
        savedAt: typeof profile.savedAt === "string" ? profile.savedAt : "",
      });
    } catch (error) {
      problems.push(`${key.slice(candidateKey.length)} (${reasonOf(error)})`);
    }
  }
  found.sort((a, b) => (a.savedAt < b.savedAt ? -1 : a.savedAt > b.savedAt ? 1 : 0));
  return { found: found.map(({ name, basedOn, values }) => ({ name, basedOn, values })), problems };
}

export default function UITuningLabFeature({ config, setConfig }: TuningLabHostProps) {
  const [open, setOpen] = useState(opensOnLaunch);
  useEffect(clearLaunchRequest, []);
  const [status, setStatus] = useState<{ text: string; error?: boolean } | null>(null);
  const panel = useRef<HTMLDivElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  const firstControl = useRef<HTMLButtonElement>(null);
  const changeButton = useRef<HTMLButtonElement>(null);
  // Pins live in memory and in the log; each is mirrored to localStorage. A pin is a
  // look being worked on: the controls edit the selected pin in place.
  const [candidates, setCandidates] = useState(initialCandidates);
  // Every name issued in this run, removed ones included: names are never reused.
  const issued = useRef(new Set([...reservedNames, ...initialCandidates.map(c => c.name)]));
  // The values each pin last logged, so a pin logs again only after it changed.
  const logged = useRef(new Map<string, string>());
  // The selected chip: "original" (Shipped) or a pin's name. The feature always
  // shows it; there is no draft and nothing is stashed.
  const [selected, setSelected] = useState("original");
  // The winner after Choose; while set, the panel is the result bar.
  const [sent, setSent] = useState<string | null>(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const selectedPin = candidates.find(c => c.name === selected);
  const selectedValues = selectedPin?.values ?? {};

  // Read the latest pins and selection through refs, so the close path, which
  // runs from an effect, never reads stale state.
  const latest = useRef({ candidates, selected });
  useLayoutEffect(() => { latest.current = { candidates, selected }; });

  // Logs a pin's line when it is new or changed since it last logged.
  function logPin(candidate: Candidate) {
    const line = sortedJson(candidate);
    if (logged.current.get(candidate.name) === line) return;
    logged.current.set(candidate.name, line);
    console.info(`UITUNINGLAB_CANDIDATE ${line}`);
    store(candidate);
  }
  // A pin edited in place logs its new values once it is left: another chip is
  // selected, the lab closes, or Choose.
  function leave() {
    const { candidates, selected } = latest.current;
    const pin = candidates.find(c => c.name === selected);
    if (pin) logPin(pin);
  }

  // The one close path. It runs from the popover's toggle event, or directly
  // when the browser has no Popover API. The feature keeps the selected look.
  function finishClose() {
    leave();
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

  // Choose moves focus to Change, and Change moves it back to the chips.
  useEffect(() => { (sent ? changeButton : firstControl).current?.focus(); }, [sent]);

  // Stored pins load each time the lab opens; in-memory ones that are not
  // stored (the initial candidates) stay in the list.
  useEffect(() => {
    if (!open) return;
    try {
      const { found, problems } = readStored(issued.current);
      setCandidates(list => [...found, ...list.filter(c => !found.some(f => f.name === c.name))]);
      if (problems.length > 0) {
        setStatus({ text: `Skipped unreadable pins, left in storage: ${problems.join(", ")}`, error: true });
      }
    } catch (error) {
      setStatus({ text: `Saved pins not loaded: ${reasonOf(error)}. Storage was left unchanged.`, error: true });
    }
  }, [open]);

  // Seeded and stored pins log their own line the first time the lab shows them.
  useEffect(() => {
    if (!open) return;
    for (const c of candidates) if (!logged.current.has(c.name)) logPin(c);
  }, [open, candidates]);

  function openLab() { setStatus(null); setOpen(true); }
  // Selecting a chip shows its look in the real feature. Switching chips is the
  // comparison.
  function select(chip: string) {
    if (chip === selected) return;
    leave();
    const pin = candidates.find(c => c.name === chip);
    setConfig({ ...baseline, ...pin?.values });
    setSelected(chip);
  }
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
    setStatus({ text: `New look ${name}` });
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
  // Writes a pin's profile under its own key. A failed write is reported; the
  // pin stays in the panel and the log still has it.
  function store(candidate: Candidate) {
    const profile: UITuningLabProfile = {
      basedOn: candidate.basedOn,
      container: "FeatureScreen.popover",
      name: candidate.name,
      notes: "",
      overrides: { ...baseline, ...candidate.values },
      platform: "web",
      savedAt: new Date().toISOString(),
      schemaVersion: 2,
      scope: ["appearance", "layout"],
    };
    try {
      localStorage.setItem(candidateKey + candidate.name, JSON.stringify(profile));
    } catch (error) {
      setStatus({ text: `${candidate.name} not saved: ${reasonOf(error)}`, error: true });
    }
  }
  // Reports the selected look.
  async function copyValues() {
    setMenuOpen(false);
    const values = sortedJson(selectedValues);
    console.info(`UITUNINGLAB_VALUES ${values}`);
    try {
      await navigator.clipboard.writeText(values);
      setStatus({ text: values === "{}" ? "Same as Shipped" : `Copied ${values}` });
    } catch {
      setStatus({ text: `Clipboard unavailable; values logged to the console: ${values}` });
    }
  }
  function remove(name: string) {
    try {
      localStorage.removeItem(candidateKey + name);
    } catch (error) {
      setStatus({ text: `Remove failed: ${reasonOf(error)}`, error: true });
      return;
    }
    setCandidates(list => list.filter(c => c.name !== name));
    logged.current.delete(name);
    console.info(`UITUNINGLAB_CANDIDATE_REMOVED ${sortedJson({ name })}`);
    if (selected === name) { setConfig({ ...baseline }); setSelected("original"); }
  }
  // Choose picks the selected chip and finishes. Picking again replaces the
  // result.
  async function pickSelected() {
    leave();
    const winner = selectedPin ? selectedPin.name : "original";
    const result = { candidates, values: selectedValues, winner };
    console.info(`UITUNINGLAB_DONE ${sortedJson(result)}`);
    const problems: string[] = [];
    try {
      localStorage.setItem(resultKey, sortedJson({ ...result, savedAt: new Date().toISOString() }));
    } catch {
      problems.push("result not saved");
    }
    try {
      await navigator.clipboard.writeText(`land ${winner}`);
    } catch {
      problems.push(`clipboard unavailable; tell the agent "land ${winner}"`);
    }
    setStatus(problems.length > 0 ? { text: `Logged to the console; ${problems.join("; ")}`, error: true } : null);
    setSent(winner);
  }

  return <>
    <CardFeature config={config} />
    <button ref={trigger} type="button" onClick={openLab} disabled={open}
      style={triggerStyle}>Card Lab</button>
    {open && <div ref={panel} {...popoverManual} style={panelStyle} role="dialog"
      aria-labelledby="ui-tuning-lab-title">
      {sent ? <p style={rowStyle}>
        <strong id="ui-tuning-lab-title">Chosen: {sent}</strong>
        <button ref={changeButton} type="button" onClick={() => setSent(null)}>Change</button>
      </p> : <>
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
          <button ref={firstControl} type="button" aria-pressed={selected === "original"}
            style={selectedStyle(selected === "original")}
            onClick={() => select("original")}>Shipped</button>
          {candidates.map(c => <span key={c.name}>
            <button type="button" aria-pressed={selected === c.name} style={selectedStyle(selected === c.name)}
              onClick={() => select(c.name)}>{c.name}</button>
            <button type="button" aria-label={`Remove ${c.name}`} onClick={() => remove(c.name)}>×</button>
          </span>)}
        </div>
        <div role="group" aria-label="Controls">
          <button type="button" onClick={() => applyPreset("compact")}>Compact</button>
          <button type="button" onClick={() => applyPreset("relaxed")}>Relaxed</button>
          <label>Radius <input type="range" min="0" max="32"
            value={config.radius}
            onChange={e => edit({ ...config, radius: Number(e.target.value) })}/>
            <output aria-hidden="true">{config.radius}px</output>
          </label>
          <label>Gap <input type="range" min="0" max="24"
            value={config.gap}
            onChange={e => edit({ ...config, gap: Number(e.target.value) })}/>
            <output aria-hidden="true">{config.gap}px</output>
          </label>
        </div>
        <div style={rowStyle}>
          <button type="button" disabled={!selectedPin} onClick={duplicate}>Duplicate</button>
          <button type="button" onClick={pickSelected}>Choose</button>
        </div>
      </>}
      {status && <p role={status.error ? "alert" : "status"}>{status.text}</p>}
      {!sent && <p style={{ position: "sticky", bottom: 0, margin: 0, padding: "8px 0", background: "Canvas" }}>
        Duplicate to compare · Choose to finish</p>}
    </div>}
  </>;
}
```


Creating or editing a pin writes only `uiTuningLab.candidates.<name>`, and ×
deletes only that key.
Storage failures are shown in the status line and leave the chips unchanged.
Inspect the emitted production bundle to confirm that the lab module and storage
code were eliminated.
