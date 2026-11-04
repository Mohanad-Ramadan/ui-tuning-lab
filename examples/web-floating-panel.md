# Candidate — web floating panel

The feature and controls share one config state. All lab code lives in
`FeatureScreen.ui-tuning-lab.tsx`; the feature reaches it only through a dynamic
import inside an `import.meta.env.DEV` block, so production builds drop both the
branch and the lab chunk. The Tune button is the human path and the visible
fallback; `?ui-tuning-lab=1` is the agent path, parsed only inside that
development module (`references/activation.md`). The baseline is the declared
default, `appDefault`; closing unmounts the popover and its listener. The default
candidate is ephemeral: candidates live in React state and the console log, with
no storage writer or Save action. **Copy values** copies the fields that differ
from the baseline and logs them as one `UITUNINGLAB_VALUES {...}` console line
for landing (`references/landing-protocol.md`). **Keep as candidate**, the
candidates list (Load, Remove), **Compare** (Draft plus each candidate, shown
once one exists), **Done**, and the footer hint are described in
`references/candidates.md`; they log `UITUNINGLAB_CANDIDATE`,
`UITUNINGLAB_CANDIDATE_REMOVED`, and `UITUNINGLAB_DONE` lines. Compare and Show
baseline share one stash and are exclusive; the draft controls are disabled
while either shows something other than the draft, and closing restores the
draft. `initialCandidates` seeds the list when reopening the lab later.

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
// never shifts the feature's layout.
const panelStyle = {
  insetBlockStart: "auto", insetInlineStart: "auto", insetBlockEnd: 72, insetInlineEnd: 16,
  margin: 0, maxWidth: "min(320px, calc(100vw - 32px))", maxHeight: "calc(100dvh - 88px)",
  overflow: "auto", colorScheme: "light dark", font: "inherit",
} as const;
const triggerStyle = { position: "fixed", insetBlockEnd: 16, insetInlineEnd: 16 } as const;

// A finalist: the fields that differ from the baseline, plus where it started.
type Candidate = { name: string; basedOn: string; values: Partial<CardConfig> };
// Candidates the lab opens with. Empty by default; a later session seeds the
// finalists kept in the project here (references/candidates.md).
const initialCandidates: Candidate[] = [];

// Preset keys are kebab-case: the key is what a candidate records as basedOn.
const presets = {
  compact: { radius: 4, gap: 4 },
  relaxed: { radius: 24, gap: 16 },
} satisfies Record<string, CardConfig>;
// The baseline is the declared default, never the value on screen when the lab
// opens: a draft kept from an earlier session must still count as a change.
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

export default function UITuningLabFeature({ config, setConfig }: TuningLabHostProps) {
  const [open, setOpen] = useState(opensOnLaunch);
  useEffect(clearLaunchRequest, []);
  const [status, setStatus] = useState<string | null>(null);
  const panel = useRef<HTMLDivElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  const firstControl = useRef<HTMLButtonElement>(null);
  // Candidates live in memory and in the log; nothing is written to storage.
  const [candidates, setCandidates] = useState(initialCandidates);
  // Every name issued in this run, removed ones included: names are never reused.
  const issued = useRef(new Set(initialCandidates.map(c => c.name)));
  // Candidates already written to the log, so seeded or loaded ones log once.
  const logged = useRef(new Set<string>());
  // Where the draft came from: a preset, "baseline", or a candidate's name.
  const [basedOn, setBasedOn] = useState("baseline");
  // What the real feature shows: "draft", "baseline", or a candidate's name.
  const [shown, setShown] = useState("draft");
  // Holds the draft while the baseline or a candidate is shown in the feature.
  const stashedDraft = useRef<CardConfig | null>(null);

  // Read the host's setter through a ref so an unstable setter never re-runs the
  // open effect, which would re-show the panel and steal focus.
  const setConfigRef = useRef(setConfig);
  useLayoutEffect(() => { setConfigRef.current = setConfig; });

  // The one close path. It runs from the popover's toggle event, or directly
  // when the browser has no Popover API.
  function finishClose() {
    if (stashedDraft.current) setConfigRef.current(stashedDraft.current);
    stashedDraft.current = null;
    setShown("draft");
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

  // Candidates seeded or loaded from storage log their own line the first time
  // the lab shows them; the set also guards StrictMode's repeated effects.
  useEffect(() => {
    if (!open) return;
    for (const c of candidates) {
      if (logged.current.has(c.name)) continue;
      logged.current.add(c.name);
      console.info(`UITUNINGLAB_CANDIDATE ${sortedJson(c)}`);
    }
  }, [open, candidates]);

  function openLab() { setStatus(null); setOpen(true); }
  function reset() { setConfig({ ...baseline }); setBasedOn("baseline"); }
  function applyPreset(name: keyof typeof presets) {
    setConfig({ ...presets[name] });
    setBasedOn(name);
  }
  // Shows "draft", "baseline", or a candidate in the real feature. The draft is
  // stashed on the way out and restored when "draft" is picked or the lab closes.
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
  function toggleBaseline() { show(shown === "baseline" ? "draft" : "baseline"); }
  async function copyValues() {
    const values = JSON.stringify(changedValues(baseline, config));
    console.info(`UITUNINGLAB_VALUES ${values}`);
    try {
      await navigator.clipboard.writeText(values);
      setStatus(values === "{}" ? "No changes from baseline" : `Copied ${values}`);
    } catch {
      setStatus(`Clipboard unavailable; values logged to the console: ${values}`);
    }
  }
  function keep() {
    const values = changedValues(baseline, config);
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
    stashedDraft.current = null;
    setConfig({ ...baseline, ...candidate.values });
    setBasedOn(candidate.name);
    setShown("draft");
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
    const draft = picked ? { ...baseline, ...picked.values } : stashedDraft.current ?? config;
    const values = changedValues(baseline, draft);
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
    <CardFeature config={config} />
    <button ref={trigger} type="button" onClick={openLab} disabled={open}
      style={triggerStyle}>Tune</button>
    {open && <div ref={panel} {...popoverManual} style={panelStyle} role="dialog"
      aria-labelledby="ui-tuning-lab-title">
      <h2 id="ui-tuning-lab-title">UI tuning lab</h2>
      <button type="button" onClick={closeLab}>Close</button>
      <button type="button" aria-pressed={shown === "baseline"}
        onClick={toggleBaseline}>Show baseline</button>
      <fieldset disabled={shown !== "draft"} aria-label="Draft controls"
        style={{ border: 0, margin: 0, padding: 0 }}>
        <button ref={firstControl} type="button"
          onClick={() => applyPreset("compact")}>Compact</button>
        <button type="button" onClick={() => applyPreset("relaxed")}>Relaxed</button>
        <label>Radius <input type="range" min="0" max="32"
          value={config.radius}
          onChange={e => setConfig(c => ({ ...c, radius: Number(e.target.value) }))}/>
          <output aria-hidden="true">{config.radius}px</output>
        </label>
        <label>Gap <input type="range" min="0" max="24"
          value={config.gap}
          onChange={e => setConfig(c => ({ ...c, gap: Number(e.target.value) }))}/>
          <output aria-hidden="true">{config.gap}px</output>
        </label>
        <button type="button" onClick={reset}>Reset</button>
        <button type="button" onClick={copyValues}>Copy values</button>
        <button type="button" onClick={keep}>Keep as candidate</button>
      </fieldset>
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
      <button type="button" disabled={shown === "baseline"} onClick={done}>Done</button>
      {status && <p role="status">{status}</p>}
      <p style={{ position: "sticky", bottom: 0, margin: 0, padding: "8px 0", background: "Canvas" }}>
        Finished? Keep the ones you like, then press Done, or tell the agent "land b".</p>
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
restores focus to Tune. The panel is pinned to the corner and the trigger is
fixed, so neither moves the feature. Buttons and the labelled ranges
remain in normal keyboard order. Test Chromium, Safari, and Firefox on desktop and
mobile layouts, keyboard, screen readers, Close and Escape, unmounting, and emitted
production assets before approval.

## Optional persistence, only when requested

Only when the user explicitly requests saved profiles, replace
`FeatureScreen.ui-tuning-lab.tsx` with this version. The feature files stay
unchanged, and the writer and loader live only in the development-only module.
Keep as candidate writes a `schemaVersion: 2` profile under
`uiTuningLab.candidates.<name>`, Remove deletes that key, and opening the lab
loads every such key into the list. The baseline stays the declared default, so
Reset still returns to it. Unreadable or incompatible entries (wrong
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
// never shifts the feature's layout.
const panelStyle = {
  insetBlockStart: "auto", insetInlineStart: "auto", insetBlockEnd: 72, insetInlineEnd: 16,
  margin: 0, maxWidth: "min(320px, calc(100vw - 32px))", maxHeight: "calc(100dvh - 88px)",
  overflow: "auto", colorScheme: "light dark", font: "inherit",
} as const;
const triggerStyle = { position: "fixed", insetBlockEnd: 16, insetInlineEnd: 16 } as const;

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
// Each candidate is stored under its own key: uiTuningLab.candidates.<name>.
const candidateKey = "uiTuningLab.candidates.";

// A finalist: the fields that differ from the baseline, plus where it started.
type Candidate = { name: string; basedOn: string; values: Partial<CardConfig> };
// Candidates the lab opens with, before anything stored is loaded. Empty by
// default; a later session can seed finalists kept in the project here.
const initialCandidates: Candidate[] = [];

// Preset keys are kebab-case: the key is what a candidate records as basedOn.
const presets = {
  compact: { radius: 4, gap: 4 },
  relaxed: { radius: 24, gap: 16 },
} satisfies Record<string, CardConfig>;
// The baseline is the declared default, never the value on screen when the lab
// opens: a draft kept from an earlier session must still count as a change.
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

function reasonOf(error: unknown): string {
  return error instanceof Error ? error.message : "unknown error";
}

// Reads every stored candidate, oldest first. An entry that cannot be used is
// described in `problems` and left in storage untouched. Every stored name,
// readable or not, is added to `reserved` so Keep never reuses it.
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
  // Candidates are mirrored to localStorage, one key each.
  const [candidates, setCandidates] = useState(initialCandidates);
  // Every name issued in this run, removed ones included: names are never reused.
  const issued = useRef(new Set(initialCandidates.map(c => c.name)));
  // Candidates already written to the log, so seeded or loaded ones log once.
  const logged = useRef(new Set<string>());
  // Where the draft came from: a preset, "baseline", or a candidate's name.
  const [basedOn, setBasedOn] = useState("baseline");
  // What the real feature shows: "draft", "baseline", or a candidate's name.
  const [shown, setShown] = useState("draft");
  // Holds the draft while the baseline or a candidate is shown in the feature.
  const stashedDraft = useRef<CardConfig | null>(null);

  // Read the host's setter through a ref so an unstable setter never re-runs the
  // open effect, which would re-show the panel and steal focus.
  const setConfigRef = useRef(setConfig);
  useLayoutEffect(() => { setConfigRef.current = setConfig; });

  // The one close path. It runs from the popover's toggle event, or directly
  // when the browser has no Popover API.
  function finishClose() {
    if (stashedDraft.current) setConfigRef.current(stashedDraft.current);
    stashedDraft.current = null;
    setShown("draft");
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

  // Stored candidates load each time the lab opens; in-memory ones that are not
  // stored (the initial candidates) stay in the list.
  useEffect(() => {
    if (!open) return;
    try {
      const { found, problems } = readStored(issued.current);
      setCandidates(list => [...found, ...list.filter(c => !found.some(f => f.name === c.name))]);
      if (problems.length > 0) {
        setStatus({ text: `Skipped unreadable candidates, left in storage: ${problems.join(", ")}`, error: true });
      }
    } catch (error) {
      setStatus({ text: `Saved candidates not loaded: ${reasonOf(error)}. Storage was left unchanged.`, error: true });
    }
  }, [open]);

  // Candidates seeded or loaded from storage log their own line the first time
  // the lab shows them; the set also guards StrictMode's repeated effects.
  useEffect(() => {
    if (!open) return;
    for (const c of candidates) {
      if (logged.current.has(c.name)) continue;
      logged.current.add(c.name);
      console.info(`UITUNINGLAB_CANDIDATE ${sortedJson(c)}`);
    }
  }, [open, candidates]);

  function openLab() { setStatus(null); setOpen(true); }
  function reset() { setConfig({ ...baseline }); setBasedOn("baseline"); }
  function applyPreset(name: keyof typeof presets) {
    setConfig({ ...presets[name] });
    setBasedOn(name);
  }
  // Shows "draft", "baseline", or a candidate in the real feature. The draft is
  // stashed on the way out and restored when "draft" is picked or the lab closes.
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
  function toggleBaseline() { show(shown === "baseline" ? "draft" : "baseline"); }
  async function copyValues() {
    const values = JSON.stringify(changedValues(baseline, config));
    console.info(`UITUNINGLAB_VALUES ${values}`);
    try {
      await navigator.clipboard.writeText(values);
      setStatus({ text: values === "{}" ? "No changes from baseline" : `Copied ${values}` });
    } catch {
      setStatus({ text: `Clipboard unavailable; values logged to the console: ${values}` });
    }
  }
  function keep() {
    const values = changedValues(baseline, config);
    if (Object.keys(values).length === 0) {
      setStatus({ text: "Matches the baseline; nothing to keep" });
      return;
    }
    const same = candidates.find(c => sortedJson(c.values) === sortedJson(values));
    if (same) {
      setStatus({ text: `Same as ${same.name}` });
      return;
    }
    const candidate: Candidate = { name: nextName(issued.current), basedOn, values };
    const profile: UITuningLabProfile = {
      basedOn: candidate.basedOn,
      container: "FeatureScreen.popover",
      name: candidate.name,
      notes: "",
      overrides: config,
      platform: "web",
      savedAt: new Date().toISOString(),
      schemaVersion: 2,
      scope: ["appearance", "layout"],
    };
    try {
      const key = candidateKey + candidate.name;
      if (localStorage.getItem(key) !== null) throw new Error(`${candidate.name} already exists in storage`);
      localStorage.setItem(key, JSON.stringify(profile));
    } catch (error) {
      setStatus({ text: `Keep failed: ${reasonOf(error)}`, error: true });
      return;
    }
    setCandidates(list => [...list, candidate]);
    issued.current.add(candidate.name);
    logged.current.add(candidate.name);
    console.info(`UITUNINGLAB_CANDIDATE ${sortedJson(candidate)}`);
    setStatus({ text: `Kept as ${candidate.name}` });
  }
  function load(candidate: Candidate) {
    stashedDraft.current = null;
    setConfig({ ...baseline, ...candidate.values });
    setBasedOn(candidate.name);
    setShown("draft");
  }
  function remove(name: string) {
    try {
      localStorage.removeItem(candidateKey + name);
    } catch (error) {
      setStatus({ text: `Remove failed: ${reasonOf(error)}`, error: true });
      return;
    }
    setCandidates(list => list.filter(c => c.name !== name));
    console.info(`UITUNINGLAB_CANDIDATE_REMOVED ${sortedJson({ name })}`);
    if (shown === name) show("draft");
  }
  // Like Copy values, and it tells the agent the session is over. While Compare
  // shows a candidate, that candidate becomes the draft first, so it is the winner.
  async function done() {
    const picked = candidates.find(c => c.name === shown);
    if (picked) load(picked);
    const draft = picked ? { ...baseline, ...picked.values } : stashedDraft.current ?? config;
    const values = changedValues(baseline, draft);
    const winner = candidates.find(c => sortedJson(c.values) === sortedJson(values));
    console.info(`UITUNINGLAB_DONE ${sortedJson({ candidates, values, winner: winner?.name ?? null })}`);
    const text = JSON.stringify(values);
    try {
      await navigator.clipboard.writeText(text);
      setStatus({ text: `Done. Copied ${text}` });
    } catch {
      setStatus({ text: `Done. Clipboard unavailable; values logged to the console: ${text}` });
    }
  }

  return <>
    <CardFeature config={config} />
    <button ref={trigger} type="button" onClick={openLab} disabled={open}
      style={triggerStyle}>Tune</button>
    {open && <div ref={panel} {...popoverManual} style={panelStyle} role="dialog"
      aria-labelledby="ui-tuning-lab-title">
      <h2 id="ui-tuning-lab-title">UI tuning lab</h2>
      <button type="button" onClick={closeLab}>Close</button>
      <button type="button" aria-pressed={shown === "baseline"}
        onClick={toggleBaseline}>Show baseline</button>
      <fieldset disabled={shown !== "draft"} aria-label="Draft controls"
        style={{ border: 0, margin: 0, padding: 0 }}>
        <button ref={firstControl} type="button"
          onClick={() => applyPreset("compact")}>Compact</button>
        <button type="button" onClick={() => applyPreset("relaxed")}>Relaxed</button>
        <label>Radius <input type="range" min="0" max="32"
          value={config.radius}
          onChange={e => setConfig(c => ({ ...c, radius: Number(e.target.value) }))}/>
          <output aria-hidden="true">{config.radius}px</output>
        </label>
        <label>Gap <input type="range" min="0" max="24"
          value={config.gap}
          onChange={e => setConfig(c => ({ ...c, gap: Number(e.target.value) }))}/>
          <output aria-hidden="true">{config.gap}px</output>
        </label>
        <button type="button" onClick={reset}>Reset</button>
        <button type="button" onClick={copyValues}>Copy values</button>
        <button type="button" onClick={keep}>Keep as candidate</button>
      </fieldset>
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
      <button type="button" disabled={shown === "baseline"} onClick={done}>Done</button>
      {status && <p role={status.error ? "alert" : "status"}>{status.text}</p>}
      <p style={{ position: "sticky", bottom: 0, margin: 0, padding: "8px 0", background: "Canvas" }}>
        Finished? Keep the ones you like, then press Done, or tell the agent "land b".</p>
    </div>}
  </>;
}
```

Keep writes only `uiTuningLab.candidates.<name>` and Remove deletes only that key.
Storage failures are shown in the status line and leave the list unchanged.
Inspect the emitted production bundle to confirm that the lab module and storage
code were eliminated.
