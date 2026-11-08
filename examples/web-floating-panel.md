# Candidate — web floating panel

The feature and controls share one config state. All lab code lives in
`FeatureScreen.ui-tuning-lab.tsx`; the feature reaches it only through a dynamic
import inside an `import.meta.env.DEV` block, so production builds drop both the
branch and the lab chunk. The Card Lab button is the human path and the visible
fallback; `?ui-tuning-lab=1` is the agent path, parsed only inside that
development module (`references/activation.md`). The baseline is the declared
default, `appDefault`; closing unmounts the popover and its listener.

The panel follows `references/candidates.md`. A chip row under the header shows
**Shipped**, each pin, and, last, the draft chip, which appears only while the
draft holds unpinned changes and is labeled after where it came from
(`Shipped + edits`, `compact + edits`); tapping a chip shows it in the real
feature, and the highlighted chip is the one shown. The draft is stashed while
another chip is shown and restored when its chip is tapped or the lab closes.
The controls edit the draft and are disabled while Shipped is shown; moving one
while a pin is shown copies that pin into the draft first. **Pin** pins the
draft, named after the last preset applied or `tweak`, and is disabled while the
draft matches Shipped or a pin. **Choose** picks the shown chip: it logs
`UITUNINGLAB_DONE`, writes the same object to the `localStorage` key
`uiTuningLab.result`, copies `land <name>` to the clipboard, and shrinks the
panel to `Chosen: <name>` with **Change** to reopen it. The **⋯** menu holds
**Reset** and **Copy values**, which logs the draft's changed fields as one
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

// A pin: the fields that differ from the baseline, plus where it started.
type Candidate = { name: string; basedOn: string; values: Partial<CardConfig> };
// Pins the lab opens with. Empty by default; a later session seeds the
// finalists kept in the project here (references/candidates.md).
const initialCandidates: Candidate[] = [];
// Choose writes the pick here, so it survives quitting the app.
const resultKey = "uiTuningLab.result";
// Never issued as a pin's name: "draft" and "baseline" are the draft and
// Shipped chips.
const reservedNames = ["draft", "now", "original", "baseline"];

// Preset keys are kebab-case: the key is what a pin records as basedOn and is
// named after.
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
  // Pins live in memory and in the log.
  const [candidates, setCandidates] = useState(initialCandidates);
  // Every name issued in this run, removed ones included: names are never reused.
  const issued = useRef(new Set([...reservedNames, ...initialCandidates.map(c => c.name)]));
  // Pins already written to the log, so seeded ones log once.
  const logged = useRef(new Set<string>());
  // Where the draft came from: a preset, "baseline", or a pin's name.
  const [basedOn, setBasedOn] = useState("baseline");
  // The last preset applied since the lab opened or Reset; it names pins.
  const lastPreset = useRef<string | null>(null);
  // The chip the real feature shows: "draft", "baseline" (Shipped), or a pin's
  // name.
  const [shown, setShown] = useState("draft");
  // Holds the draft while another chip is shown in the feature.
  const stashedDraft = useRef<CardConfig | null>(null);
  // The winner after Choose; while set, the panel is the result bar.
  const [sent, setSent] = useState<string | null>(null);
  const [menuOpen, setMenuOpen] = useState(false);
  // The chip the draft matches ("baseline" for Shipped, or a pin), or null while
  // it holds unpinned changes and shows its own chip, last, as "<source> + edits".
  const draft = stashedDraft.current ?? config;
  const draftValues = changedValues(baseline, draft);
  const draftMatch = Object.keys(draftValues).length === 0 ? "baseline"
    : candidates.find(c => sortedJson(c.values) === sortedJson(draftValues))?.name ?? null;
  // The highlighted chip: the one shown, or the one the draft matches.
  const current = shown === "draft" ? draftMatch ?? "draft" : shown;
  const draftTitle = `${basedOn === "baseline" ? "Shipped" : basedOn} + edits`;

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

  // Seeded pins log their own line the first time the lab shows them; the
  // set also guards StrictMode's repeated effects.
  useEffect(() => {
    if (!open) return;
    for (const c of candidates) {
      if (logged.current.has(c.name)) continue;
      logged.current.add(c.name);
      console.info(`UITUNINGLAB_CANDIDATE ${sortedJson(c)}`);
    }
  }, [open, candidates]);

  function openLab() { setStatus(null); setOpen(true); }
  // Shows a chip in the real feature. The draft is stashed on the way out and
  // restored when its chip, or the chip it matches, is shown or the lab closes.
  function show(chip: string) {
    const target = chip === draftMatch ? "draft" : chip;
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
  // Controls edit the draft. Moving one while a pin is shown copies that pin
  // into the draft first; the pin itself does not change. Editing a pin, or a
  // draft that matches one, starts from that look.
  function edit(next: (current: CardConfig) => CardConfig) {
    const source = shown === "draft" ? draftMatch : shown;
    if (shown !== "draft") stashedDraft.current = null;
    if (source !== null) setBasedOn(source);
    setShown("draft");
    setConfig(next);
  }
  function applyPreset(name: keyof typeof presets) {
    edit(() => ({ ...presets[name] }));
    setBasedOn(name);
    lastPreset.current = name;
  }
  function reset() {
    stashedDraft.current = null;
    setShown("draft");
    setConfig({ ...baseline });
    setBasedOn("baseline");
    lastPreset.current = null;
    setMenuOpen(false);
  }
  // Reports the draft, whichever chip is shown.
  async function copyValues() {
    setMenuOpen(false);
    const values = JSON.stringify(changedValues(baseline, stashedDraft.current ?? config));
    console.info(`UITUNINGLAB_VALUES ${values}`);
    try {
      await navigator.clipboard.writeText(values);
      setStatus(values === "{}" ? "No changes from Shipped" : `Copied ${values}`);
    } catch {
      setStatus(`Clipboard unavailable; values logged to the console: ${values}`);
    }
  }
  // Pins the draft. Pin is disabled while the draft matches Shipped or a pin.
  function keep() {
    if (draftMatch !== null) return;
    const values = draftValues;
    const name = nextName(lastPreset.current ?? "tweak", issued.current);
    const candidate: Candidate = { name, basedOn, values };
    setCandidates(list => [...list, candidate]);
    issued.current.add(name);
    logged.current.add(name);
    console.info(`UITUNINGLAB_CANDIDATE ${sortedJson(candidate)}`);
    setStatus(`Pinned ${name}`);
  }
  function remove(name: string) {
    setCandidates(list => list.filter(c => c.name !== name));
    console.info(`UITUNINGLAB_CANDIDATE_REMOVED ${sortedJson({ name })}`);
    if (shown === name) show("draft");
  }
  // Choose picks the highlighted chip and finishes. Picking again replaces the
  // result.
  async function pickShown() {
    const pin = candidates.find(c => c.name === current);
    const winner = pin ? pin.name : current === "baseline" ? "original" : "draft";
    const values = pin ? pin.values : current === "baseline" ? {} : draftValues;
    const result = { candidates, values, winner };
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
          <button type="button" onClick={reset}>Reset</button>
          <button type="button" onClick={copyValues}>Copy values</button>
        </div>}
        <div role="group" aria-label="Shown in the feature" style={rowStyle}>
          <button ref={firstControl} type="button" aria-pressed={current === "baseline"}
            onClick={() => show("baseline")}>Shipped</button>
          {candidates.map(c => <span key={c.name}>
            <button type="button" aria-pressed={current === c.name} onClick={() => show(c.name)}>{c.name}</button>
            <button type="button" aria-label={`Remove ${c.name}`} onClick={() => remove(c.name)}>×</button>
          </span>)}
          {draftMatch === null && <button type="button" aria-pressed={current === "draft"}
            onClick={() => show("draft")}>{draftTitle}</button>}
        </div>
        <fieldset disabled={shown === "baseline"} aria-label="Controls"
          style={{ border: 0, margin: 0, padding: 0 }}>
          <button type="button" onClick={() => applyPreset("compact")}>Compact</button>
          <button type="button" onClick={() => applyPreset("relaxed")}>Relaxed</button>
          <label>Radius <input type="range" min="0" max="32"
            value={config.radius}
            onChange={e => edit(c => ({ ...c, radius: Number(e.target.value) }))}/>
            <output aria-hidden="true">{config.radius}px</output>
          </label>
          <label>Gap <input type="range" min="0" max="24"
            value={config.gap}
            onChange={e => edit(c => ({ ...c, gap: Number(e.target.value) }))}/>
            <output aria-hidden="true">{config.gap}px</output>
          </label>
        </fieldset>
        <div style={rowStyle}>
          <button type="button" disabled={draftMatch !== null} onClick={keep}>Pin</button>
          <button type="button" onClick={pickShown}>Choose</button>
        </div>
      </>}
      {status && <p role="status">{status}</p>}
      {!sent && <p style={{ position: "sticky", bottom: 0, margin: 0, padding: "8px 0", background: "Canvas" }}>
        Pin looks to compare · Choose to finish</p>}
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
Pin writes a `schemaVersion: 2` profile under `uiTuningLab.candidates.<name>`,
× deletes that key, and opening the lab loads every such key into the chips;
every stored name is taken, readable or not. The baseline stays the declared
default, so Reset still returns to it. Unreadable or incompatible entries (wrong
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
// Never issued as a pin's name: "draft" and "baseline" are the draft and
// Shipped chips.
const reservedNames = ["draft", "now", "original", "baseline"];

// Preset keys are kebab-case: the key is what a pin records as basedOn and is
// named after.
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
// readable or not, is added to `reserved` so Pin never reuses it.
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
  // Pins are mirrored to localStorage, one key each.
  const [candidates, setCandidates] = useState(initialCandidates);
  // Every name issued in this run, removed ones included: names are never reused.
  const issued = useRef(new Set([...reservedNames, ...initialCandidates.map(c => c.name)]));
  // Pins already written to the log, so seeded or stored ones log once.
  const logged = useRef(new Set<string>());
  // Where the draft came from: a preset, "baseline", or a pin's name.
  const [basedOn, setBasedOn] = useState("baseline");
  // The last preset applied since the lab opened or Reset; it names pins.
  const lastPreset = useRef<string | null>(null);
  // The chip the real feature shows: "draft", "baseline" (Shipped), or a pin's
  // name.
  const [shown, setShown] = useState("draft");
  // Holds the draft while another chip is shown in the feature.
  const stashedDraft = useRef<CardConfig | null>(null);
  // The winner after Choose; while set, the panel is the result bar.
  const [sent, setSent] = useState<string | null>(null);
  const [menuOpen, setMenuOpen] = useState(false);
  // The chip the draft matches ("baseline" for Shipped, or a pin), or null while
  // it holds unpinned changes and shows its own chip, last, as "<source> + edits".
  const draft = stashedDraft.current ?? config;
  const draftValues = changedValues(baseline, draft);
  const draftMatch = Object.keys(draftValues).length === 0 ? "baseline"
    : candidates.find(c => sortedJson(c.values) === sortedJson(draftValues))?.name ?? null;
  // The highlighted chip: the one shown, or the one the draft matches.
  const current = shown === "draft" ? draftMatch ?? "draft" : shown;
  const draftTitle = `${basedOn === "baseline" ? "Shipped" : basedOn} + edits`;

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

  // Seeded and stored pins log their own line the first time the lab shows them; the
  // set also guards StrictMode's repeated effects.
  useEffect(() => {
    if (!open) return;
    for (const c of candidates) {
      if (logged.current.has(c.name)) continue;
      logged.current.add(c.name);
      console.info(`UITUNINGLAB_CANDIDATE ${sortedJson(c)}`);
    }
  }, [open, candidates]);

  function openLab() { setStatus(null); setOpen(true); }
  // Shows a chip in the real feature. The draft is stashed on the way out and
  // restored when its chip, or the chip it matches, is shown or the lab closes.
  function show(chip: string) {
    const target = chip === draftMatch ? "draft" : chip;
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
  // Controls edit the draft. Moving one while a pin is shown copies that pin
  // into the draft first; the pin itself does not change. Editing a pin, or a
  // draft that matches one, starts from that look.
  function edit(next: (current: CardConfig) => CardConfig) {
    const source = shown === "draft" ? draftMatch : shown;
    if (shown !== "draft") stashedDraft.current = null;
    if (source !== null) setBasedOn(source);
    setShown("draft");
    setConfig(next);
  }
  function applyPreset(name: keyof typeof presets) {
    edit(() => ({ ...presets[name] }));
    setBasedOn(name);
    lastPreset.current = name;
  }
  function reset() {
    stashedDraft.current = null;
    setShown("draft");
    setConfig({ ...baseline });
    setBasedOn("baseline");
    lastPreset.current = null;
    setMenuOpen(false);
  }
  // Reports the draft, whichever chip is shown.
  async function copyValues() {
    setMenuOpen(false);
    const values = JSON.stringify(changedValues(baseline, stashedDraft.current ?? config));
    console.info(`UITUNINGLAB_VALUES ${values}`);
    try {
      await navigator.clipboard.writeText(values);
      setStatus({ text: values === "{}" ? "No changes from Shipped" : `Copied ${values}` });
    } catch {
      setStatus({ text: `Clipboard unavailable; values logged to the console: ${values}` });
    }
  }
  // Pins the draft. Pin is disabled while the draft matches Shipped or a pin.
  // A failed write refuses the Pin, so the chips never show a pin that storage
  // does not hold.
  function keep() {
    if (draftMatch !== null) return;
    const values = draftValues;
    const name = nextName(lastPreset.current ?? "tweak", issued.current);
    const candidate: Candidate = { name, basedOn, values };
    const profile: UITuningLabProfile = {
      basedOn,
      container: "FeatureScreen.popover",
      name,
      notes: "",
      overrides: draft,
      platform: "web",
      savedAt: new Date().toISOString(),
      schemaVersion: 2,
      scope: ["appearance", "layout"],
    };
    try {
      const key = candidateKey + name;
      if (localStorage.getItem(key) !== null) throw new Error(`${name} already exists in storage`);
      localStorage.setItem(key, JSON.stringify(profile));
    } catch (error) {
      setStatus({ text: `Pin failed: ${reasonOf(error)}`, error: true });
      return;
    }
    setCandidates(list => [...list, candidate]);
    issued.current.add(name);
    logged.current.add(name);
    console.info(`UITUNINGLAB_CANDIDATE ${sortedJson(candidate)}`);
    setStatus({ text: `Pinned ${name}` });
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
  // Choose picks the highlighted chip and finishes. Picking again replaces the
  // result.
  async function pickShown() {
    const pin = candidates.find(c => c.name === current);
    const winner = pin ? pin.name : current === "baseline" ? "original" : "draft";
    const values = pin ? pin.values : current === "baseline" ? {} : draftValues;
    const result = { candidates, values, winner };
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
          <button type="button" onClick={reset}>Reset</button>
          <button type="button" onClick={copyValues}>Copy values</button>
        </div>}
        <div role="group" aria-label="Shown in the feature" style={rowStyle}>
          <button ref={firstControl} type="button" aria-pressed={current === "baseline"}
            onClick={() => show("baseline")}>Shipped</button>
          {candidates.map(c => <span key={c.name}>
            <button type="button" aria-pressed={current === c.name} onClick={() => show(c.name)}>{c.name}</button>
            <button type="button" aria-label={`Remove ${c.name}`} onClick={() => remove(c.name)}>×</button>
          </span>)}
          {draftMatch === null && <button type="button" aria-pressed={current === "draft"}
            onClick={() => show("draft")}>{draftTitle}</button>}
        </div>
        <fieldset disabled={shown === "baseline"} aria-label="Controls"
          style={{ border: 0, margin: 0, padding: 0 }}>
          <button type="button" onClick={() => applyPreset("compact")}>Compact</button>
          <button type="button" onClick={() => applyPreset("relaxed")}>Relaxed</button>
          <label>Radius <input type="range" min="0" max="32"
            value={config.radius}
            onChange={e => edit(c => ({ ...c, radius: Number(e.target.value) }))}/>
            <output aria-hidden="true">{config.radius}px</output>
          </label>
          <label>Gap <input type="range" min="0" max="24"
            value={config.gap}
            onChange={e => edit(c => ({ ...c, gap: Number(e.target.value) }))}/>
            <output aria-hidden="true">{config.gap}px</output>
          </label>
        </fieldset>
        <div style={rowStyle}>
          <button type="button" disabled={draftMatch !== null} onClick={keep}>Pin</button>
          <button type="button" onClick={pickShown}>Choose</button>
        </div>
      </>}
      {status && <p role={status.error ? "alert" : "status"}>{status.text}</p>}
      {!sent && <p style={{ position: "sticky", bottom: 0, margin: 0, padding: "8px 0", background: "Canvas" }}>
        Pin looks to compare · Choose to finish</p>}
    </div>}
  </>;
}
```


Pin writes only `uiTuningLab.candidates.<name>` and × deletes only that key.
Storage failures are shown in the status line and leave the chips unchanged.
Inspect the emitted production bundle to confirm that the lab module and storage
code were eliminated.
