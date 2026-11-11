# Candidate — web floating panel

The feature and controls share one config state. All lab code lives in
`FeatureScreen.ui-tuning-lab.tsx`; the feature reaches it only through a dynamic
import inside an `import.meta.env.DEV` block, so production builds drop both the
branch and the lab chunk. The Card Lab button is the human path and the visible
fallback; `?ui-tuning-lab=1` is the agent path, parsed only inside that
development module (`references/activation.md`). The baseline is the declared
default, `appDefault`; closing unmounts the popover and its listener.

The panel follows `references/candidates.md`. A chip row under the header shows
**Shipped** and each pinned look, named after its preset and numbered
(**Compact-1**, **Relaxed-1**, or **Custom-1** for a look with no preset). The
selected chip is outlined, and the feature always shows it, so switching chips
is the comparison. Shipped is read-only: an edit on it shows live as unsaved
changes, with no chip outlined, until **Save & pin** keeps them as a new look
and selects it. On a pinned look the same button reads **Save**: edits stay
with the look when you switch away, and Save makes them its saved version.
**Undo**, **Redo**, and **Reset** work on the selected look, back to its last
save; one slider drag is one step. Ctrl-Z and Ctrl-Shift-Z (Cmd on a Mac, or
Ctrl-Y) run Undo and Redo only while focus is in the panel. **Apply** (hidden
after its first use) saves first, then picks the selected chip: it logs
`UITUNINGLAB_DONE`, writes the same object to the `localStorage` key
`uiTuningLab.result`, copies `land <name>` to the clipboard, and shrinks the
panel to `Applied: <name>` with **Change** to reopen it. The **⋯** menu holds
**Copy values**, which logs the selected look's changed fields as one
`UITUNINGLAB_VALUES {...}` line (`references/landing-protocol.md`).

The default lab is ephemeral: looks live in React state and the console log,
and the result key is its only write. A look logs its `UITUNINGLAB_CANDIDATE`
line only when it is saved. `initialCandidates` seeds the looks when the lab is
reopened in a later session.

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
import type { KeyboardEvent as ReactKeyboardEvent } from "react";
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

// A pinned look: its saved version, as the fields that differ from the
// baseline, plus where it came from. Edits since its last save live in `drafts`.
type Candidate = { name: string; basedOn: string; values: Partial<CardConfig> };
// One point in a look's history: what it showed, and where it came from.
type Step = { value: CardConfig; basedOn: string };
// Each look's Undo and Redo steps, back to its last save.
type History = { undo: Step[]; redo: Step[] };
const noHistory: History = { undo: [], redo: [] };
// Looks the lab opens with. Empty by default; a later session seeds the
// finalists kept in the project here (references/candidates.md).
const initialCandidates: Candidate[] = [];
// Apply writes the pick here, so it survives quitting the app.
const resultKey = "uiTuningLab.result";
// Never issued as a look's name: "original" is the Shipped chip, and the others
// are kept for older logs.
const reservedNames = ["draft", "now", "original", "baseline"];

// Preset keys are kebab-case: the key is what a look records as basedOn, and
// names the look when it is pinned (`compact-1`, shown as Compact-1).
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

// Two looks are the same when they differ from the baseline in the same fields.
function sameLook(a: CardConfig, b: CardConfig): boolean {
  return sortedJson(changedValues(baseline, a)) === sortedJson(changedValues(baseline, b));
}
// A pinned look's saved version, every field filled in.
function savedLook(candidate: Candidate): CardConfig {
  return { ...baseline, ...candidate.values };
}
// A copy of a record without one key.
function without<T>(record: Record<string, T>, key: string): Record<string, T> {
  const copy = { ...record };
  delete copy[key];
  return copy;
}

// A new look's name, `<prefix>-N`: the prefix is its preset's key, or `custom`
// for a look started from Shipped with no preset; N is one past the highest
// number issued for that prefix in this run, removed ones included, so a name
// is never reused.
function pinName(issued: Set<string>, prefix: string): string {
  const used = [...issued].filter(name => name.startsWith(`${prefix}-`))
    .map(name => name.slice(prefix.length + 1)).filter(rest => /^[0-9]+$/.test(rest)).map(Number);
  return `${prefix}-${Math.max(0, ...used) + 1}`;
}
// A chip's label: `Compact-2` for `compact-2`, `Warm Glow-1` for `warm-glow-1`,
// Shipped for `original`; a name that does not end in `-N` as it is.
function chipLabel(name: string): string {
  if (name === "original") return "Shipped";
  const m = /^(.+)-([0-9]+)$/.exec(name);
  if (!m) return name;
  const words = m[1].split("-").filter(Boolean).map(word => word[0].toUpperCase() + word.slice(1));
  return `${words.join(" ")}-${Number(m[2])}`;
}

export default function UITuningLabFeature({ config, setConfig }: TuningLabHostProps) {
  const [open, setOpen] = useState(opensOnLaunch);
  useEffect(clearLaunchRequest, []);
  const [status, setStatus] = useState<string | null>(null);
  const panel = useRef<HTMLDivElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  const firstControl = useRef<HTMLButtonElement>(null);
  const changeButton = useRef<HTMLButtonElement>(null);
  // Pinned looks live in memory and in the log, oldest first.
  const [candidates, setCandidates] = useState(initialCandidates);
  // Every name issued in this run, removed ones included: names are never reused.
  const issued = useRef(new Set([...reservedNames, ...initialCandidates.map(c => c.name)]));
  // The line each look last logged, so a save that changed nothing logs nothing.
  const logged = useRef(new Map<string, string>());
  // The selected chip: "original" (Shipped) or a look's name. The feature always
  // shows it.
  const [selected, setSelected] = useState("original");
  // Edits made on Shipped and not pinned yet, with the preset they came from.
  // While set, no chip is outlined.
  const [unsaved, setUnsaved] = useState<Step | null>(null);
  // Each pinned look's edits since its last save, by name. They stay with the
  // look when the user switches away.
  const [drafts, setDrafts] = useState<Record<string, CardConfig>>({});
  // Undo and Redo per look ("original" for Shipped), and the control of each
  // look's newest step, so one slider drag is one step.
  const [history, setHistory] = useState<Record<string, History>>({});
  const lastControl = useRef(new Map<string, string | undefined>());
  // The winner after Apply; while set, the panel is the result bar.
  const [sent, setSent] = useState<string | null>(null);
  // How many times a pick reached the agent. The first Apply reaches its
  // waiter; after it the agent no longer listens, so Apply hides and Save & pin
  // and Save also hand the pick over, for the user to paste as `land <name>`.
  // Change does not reset it.
  const [applies, setApplies] = useState(0);
  const [copied, setCopied] = useState(true);  // the clipboard took `land <name>`
  // The result bar's second line: where the pick was saved, or null when it could not.
  const [saved, setSaved] = useState<string | null>(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const selectedPin = candidates.find(c => c.name === selected);
  // The look the feature shows, and where it came from.
  const current: Step = selectedPin
    ? { value: drafts[selectedPin.name] ?? savedLook(selectedPin), basedOn: selectedPin.basedOn }
    : unsaved ?? { value: baseline, basedOn: "baseline" };
  const selectedValues = changedValues(baseline, current.value);
  const shippedOutlined = selected === "original" && unsaved === null;
  const steps = history[selected] ?? noHistory;
  const hasEdits = selectedPin ? selectedPin.name in drafts : unsaved !== null;
  // Save & pin needs edits on Shipped. Save needs edits until the first Apply;
  // after it, Save is how a pick reaches the chat, so it stays enabled.
  const saveTitle = selectedPin ? "Save" : "Save & pin";
  const canSave = selectedPin ? hasEdits || applies > 0 : unsaved !== null;

  // Read the latest looks and selection through refs, so an effect that runs
  // once per open never reads stale state.
  const latest = useRef({ candidates, selected });
  useLayoutEffect(() => { latest.current = { candidates, selected }; });

  // Logs a look's line when it is new or changed since it last logged.
  function logPin(candidate: Candidate) {
    const line = sortedJson(candidate);
    if (logged.current.get(candidate.name) === line) return;
    logged.current.set(candidate.name, line);
    console.info(`UITUNINGLAB_CANDIDATE ${line}`);
  }

  // The one close path. It runs from the popover's toggle event, or directly
  // when the browser has no Popover API. The feature keeps the selected look.
  function finishClose() {
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

  // Apply moves focus to Change, and Change moves it back to the chips.
  useEffect(() => { (sent ? changeButton : firstControl).current?.focus(); }, [sent]);

  // Seeded looks log their own line the first time the lab shows them.
  useEffect(() => {
    if (!open) return;
    for (const c of latest.current.candidates) if (!logged.current.has(c.name)) logPin(c);
  }, [open]);

  function openLab() { setStatus(null); setOpen(true); }

  // Shows a step on the selected look. Matching the last save leaves no edits.
  function show(step: Step) {
    if (selectedPin) {
      const name = selectedPin.name;
      setCandidates(list => list.map(c => c.name === name ? { ...c, basedOn: step.basedOn } : c));
      setDrafts(all => sameLook(step.value, savedLook(selectedPin))
        ? without(all, name) : { ...all, [name]: step.value });
    } else {
      setUnsaved(sameLook(step.value, baseline) ? null : step);
    }
    setConfig(step.value);
  }
  function setSteps(name: string, next: History) {
    setHistory(all => ({ ...all, [name]: next }));
  }
  function clearHistory(name: string) {
    setHistory(all => without(all, name));
    lastControl.current.delete(name);
  }

  // Selecting a chip shows its look in the real feature. Switching chips is the
  // comparison. Unsaved edits on Shipped are dropped, so Shipped always shows
  // the baseline; a pinned look keeps its edits.
  function select(chip: string) {
    if (chip === selected && unsaved === null) return;
    lastControl.current.delete(selected);  // a drag after coming back is its own step
    clearHistory("original");
    setUnsaved(null);
    const pin = candidates.find(c => c.name === chip);
    setSelected(pin ? pin.name : "original");
    setConfig(pin ? drafts[pin.name] ?? savedLook(pin) : { ...baseline });
  }
  // Every control edits the selected look: on Shipped as unsaved edits, on a
  // pinned look as edits on top of its saved version. A preset becomes its
  // basedOn. Sliders pass their key as `control`: a run of edits from the same
  // control in a row is one Undo step. Presets pass none, so each is a step.
  function edit(next: CardConfig, preset?: string, control?: string) {
    if (sameLook(next, current.value) && (preset === undefined || preset === current.basedOn)) return;
    const extend = control !== undefined && control === lastControl.current.get(selected) && steps.undo.length > 0;
    setSteps(selected, { undo: extend ? steps.undo : [...steps.undo, current], redo: [] });
    lastControl.current.set(selected, control);
    show({ value: next, basedOn: preset ?? current.basedOn });
  }
  function applyPreset(name: keyof typeof presets) { edit({ ...presets[name] }, name); }
  // Undo steps the selected look back one edit, never past its last save.
  function undo() {
    const previous = steps.undo[steps.undo.length - 1];
    if (!previous) return;
    setSteps(selected, { undo: steps.undo.slice(0, -1), redo: [...steps.redo, current] });
    lastControl.current.delete(selected);
    show(previous);
  }
  // Redo brings back the edit Undo last took away.
  function redo() {
    const next = steps.redo[steps.redo.length - 1];
    if (!next) return;
    setSteps(selected, { undo: [...steps.undo, current], redo: steps.redo.slice(0, -1) });
    lastControl.current.delete(selected);
    show(next);
  }
  // Reset takes the selected look back to its last save (Shipped: the
  // baseline) in one step that Undo can take back.
  function reset() {
    if (!hasEdits) return;
    setSteps(selected, { undo: [...steps.undo, current], redo: [] });
    lastControl.current.delete(selected);
    show(selectedPin ? { value: savedLook(selectedPin), basedOn: selectedPin.basedOn }
      : { value: baseline, basedOn: "baseline" });
  }
  // Undo and Redo on the keyboard, only while focus is in the panel: Ctrl or
  // Cmd-Z, and Ctrl or Cmd-Shift-Z or Ctrl-Y. A text field keeps its own undo.
  function onPanelKeyDown(event: ReactKeyboardEvent<HTMLDivElement>) {
    if (!(event.ctrlKey || event.metaKey) || event.altKey) return;
    const target = event.target as HTMLElement;
    if ((target instanceof HTMLInputElement && target.type !== "range") ||
        target instanceof HTMLTextAreaElement || target.isContentEditable) return;
    const key = event.key.toLowerCase();
    if (key === "z" && !event.shiftKey) { event.preventDefault(); undo(); }
    else if ((key === "z" && event.shiftKey) || (key === "y" && !event.shiftKey)) { event.preventDefault(); redo(); }
  }

  // Keeps the selected look's edits: unsaved edits on Shipped become a new
  // look, named after its preset and selected; a pinned look's edits become its
  // saved version. Logs a look that changed. Returns the look (none on plain
  // Shipped), the list it is in, read before React re-renders, and whether it
  // pinned a new look.
  function commit(): { look?: Candidate; list: Candidate[]; pinned: boolean } {
    if (selectedPin) {
      const look = { ...selectedPin, values: changedValues(baseline, current.value) };
      const list = candidates.map(c => c.name === look.name ? look : c);
      setCandidates(list);
      setDrafts(all => without(all, look.name));
      clearHistory(look.name);
      logPin(look);
      return { look, list, pinned: false };
    }
    if (unsaved === null) return { list: candidates, pinned: false };
    const prefix = unsaved.basedOn === "baseline" ? "custom" : unsaved.basedOn;
    const look: Candidate = { name: pinName(issued.current, prefix), basedOn: unsaved.basedOn,
      values: changedValues(baseline, unsaved.value) };
    issued.current.add(look.name);
    const list = [...candidates, look];
    setCandidates(list);
    setSelected(look.name);
    setUnsaved(null);
    clearHistory("original");
    logPin(look);
    return { look, list, pinned: true };
  }
  // Save & pin on Shipped, Save on a pinned look: keeps the look and copies its
  // land code. Before the first Apply the agent is listening for Apply, so
  // nothing more happens; after it, the pick is handed over for pasting.
  async function saveLook() {
    if (!canSave) return;
    const { look, list, pinned } = commit();
    if (!look) return;
    if (applies > 0) { await handOver(look, list); return; }
    setSaved(null);
    const kept = pinned ? `Pinned ${chipLabel(look.name)}` : `Saved ${chipLabel(look.name)}`;
    try {
      await navigator.clipboard.writeText(`land ${look.name}`);
      setStatus(`${kept} · copied land ${look.name}`);
    } catch {
      setStatus(`${kept}; clipboard unavailable, tell the agent "land ${look.name}"`);
    }
  }
  // Apply saves first (unsaved edits on Shipped are pinned, a selected look's
  // edits saved), then hands the pick over.
  async function applyLook() {
    const { look, list } = commit();
    await handOver(look, list);
  }
  // Reports the selected look as shown, edits included.
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
    setDrafts(all => without(all, name));
    clearHistory(name);
    logged.current.delete(name);
    console.info(`UITUNINGLAB_CANDIDATE_REMOVED ${sortedJson({ name })}`);
    setStatus(`Removed ${chipLabel(name)}`);
    if (selected === name) { setConfig({ ...baseline }); setSelected("original"); }
  }
  // Hands a pick to the agent: logs it, sends it to the waiter, stores the
  // result, and copies its land code. Picking again replaces the result.
  // `candidates` carry each look's saved version.
  async function handOver(look: Candidate | undefined, list: Candidate[]) {
    const winner = look ? look.name : "original";
    const result = { candidates: list, values: look?.values ?? {}, winner };
    console.info(`UITUNINGLAB_DONE ${sortedJson(result)}`);
    // Hands the pick to the agent's waiter (scripts/wait-for-pick.py) at once,
    // so it resumes without a message. Fire and forget: with nothing listening,
    // the console and the stored result still carry the pick.
    fetch("http://localhost:47321/pick", { method: "POST", mode: "no-cors", keepalive: true,
      body: `UITUNINGLAB_DONE ${sortedJson(result)}` }).catch(() => {});
    const problems: string[] = [];
    try {
      localStorage.setItem(resultKey, sortedJson({ ...result, savedAt: new Date().toISOString() }));
      setSaved(`Saved ${chipLabel(winner)} in localStorage uiTuningLab.result`);
    } catch {
      setSaved(null);
      problems.push("result not saved");
    }
    try {
      await navigator.clipboard.writeText(`land ${winner}`);
      setCopied(true);
    } catch {
      setCopied(false);
      problems.push(`clipboard unavailable; tell the agent "land ${winner}"`);
    }
    setStatus(problems.length > 0 ? `Logged to the console; ${problems.join("; ")}` : null);
    setApplies(n => n + 1);
    setSent(winner);
  }

  return <>
    <CardFeature config={config} />
    <button ref={trigger} type="button" onClick={openLab} disabled={open}
      style={triggerStyle}>Card Lab</button>
    {open && <div ref={panel} {...popoverManual} style={panelStyle} role="dialog"
      aria-labelledby="ui-tuning-lab-title" onKeyDown={onPanelKeyDown}>
      {sent ? <><p style={rowStyle}>
        <strong id="ui-tuning-lab-title">{applies > 1
          ? (copied ? `Copied land ${sent}: paste it in chat so the agent applies it` : `Tell the agent: land ${sent}`)
          : `Applied: ${chipLabel(sent)}`}</strong>
        <button ref={changeButton} type="button" onClick={() => setSent(null)}>Change</button>
      </p>
      {(saved ?? status) && <p role="status" style={{ margin: 0, fontSize: "0.85em" }}>
        {saved ?? status}</p>}</> : <>
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
          <button ref={firstControl} type="button" aria-pressed={shippedOutlined}
            style={selectedStyle(shippedOutlined)}
            onClick={() => select("original")}>Shipped</button>
          {candidates.map(c => <span key={c.name}>
            <button type="button" aria-pressed={selected === c.name} style={selectedStyle(selected === c.name)}
              onClick={() => select(c.name)}>{chipLabel(c.name)}</button>
            {/* × only on the selected look, so nothing is removed by accident. */}
            {selected === c.name && <button type="button" aria-label={`Remove ${chipLabel(c.name)}`}
              onClick={() => remove(c.name)}>×</button>}
          </span>)}
        </div>
        <div role="group" aria-label="Controls">
          <button type="button" onClick={() => applyPreset("compact")}>Compact</button>
          <button type="button" onClick={() => applyPreset("relaxed")}>Relaxed</button>
          <label>Radius <input type="range" min="0" max="32"
            value={config.radius}
            onChange={e => edit({ ...config, radius: Number(e.target.value) }, undefined, "radius")}/>
            <output aria-hidden="true">{config.radius}px</output>
          </label>
          <label>Gap <input type="range" min="0" max="24"
            value={config.gap}
            onChange={e => edit({ ...config, gap: Number(e.target.value) }, undefined, "gap")}/>
            <output aria-hidden="true">{config.gap}px</output>
          </label>
        </div>
        <div role="group" aria-label="Edits" style={rowStyle}>
          <button type="button" disabled={steps.undo.length === 0} onClick={undo}>Undo</button>
          <button type="button" disabled={steps.redo.length === 0} onClick={redo}>Redo</button>
          <button type="button" disabled={!hasEdits} onClick={reset}>Reset</button>
        </div>
        <div style={rowStyle}>
          <button type="button" disabled={!canSave} onClick={saveLook}>{saveTitle}</button>
          {/* Apply reaches the agent once; after that it is hidden for good. */}
          {applies === 0 && <button type="button" onClick={applyLook}>Apply</button>}
        </div>
      </>}
      {status && !sent && <p role="status">{status}</p>}
      {!sent && <p style={{ position: "sticky", bottom: 0, margin: 0, padding: "8px 0", background: "Canvas" }}>
        {applies > 0 ? "Save, then paste it in chat"
          : "Save & pin to keep a look · Apply to finish"}</p>}
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
Each look writes a `schemaVersion: 2` profile under `uiTuningLab.candidates.<name>`
when it is saved (Save & pin, Save, or Apply), never while it is only edited;
× deletes that key, and
opening the lab loads every such key into the chips; every stored name is taken,
readable or not. The baseline stays the declared default, so Shipped still shows
it. Unreadable or incompatible entries (wrong
`schemaVersion` or `platform`) are reported in the status line, skipped, and left
in storage untouched.

<!-- file: FeatureScreen.ui-tuning-lab.tsx variant=persist -->
```tsx
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import type { KeyboardEvent as ReactKeyboardEvent } from "react";
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
// Each look is stored under its own key: uiTuningLab.candidates.<name>.
const candidateKey = "uiTuningLab.candidates.";

// A pinned look: its saved version, as the fields that differ from the
// baseline, plus where it came from. Edits since its last save live in `drafts`.
type Candidate = { name: string; basedOn: string; values: Partial<CardConfig> };
// One point in a look's history: what it showed, and where it came from.
type Step = { value: CardConfig; basedOn: string };
// Each look's Undo and Redo steps, back to its last save.
type History = { undo: Step[]; redo: Step[] };
const noHistory: History = { undo: [], redo: [] };
// Looks the lab opens with, before anything stored is loaded. Empty by
// default; a later session can seed finalists kept in the project here.
const initialCandidates: Candidate[] = [];
// Apply writes the pick here, so it survives quitting the app.
const resultKey = "uiTuningLab.result";
// Never issued as a look's name: "original" is the Shipped chip, and the others
// are kept for older logs.
const reservedNames = ["draft", "now", "original", "baseline"];

// Preset keys are kebab-case: the key is what a look records as basedOn, and
// names the look when it is pinned (`compact-1`, shown as Compact-1).
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

// Two looks are the same when they differ from the baseline in the same fields.
function sameLook(a: CardConfig, b: CardConfig): boolean {
  return sortedJson(changedValues(baseline, a)) === sortedJson(changedValues(baseline, b));
}
// A pinned look's saved version, every field filled in.
function savedLook(candidate: Candidate): CardConfig {
  return { ...baseline, ...candidate.values };
}
// A copy of a record without one key.
function without<T>(record: Record<string, T>, key: string): Record<string, T> {
  const copy = { ...record };
  delete copy[key];
  return copy;
}

// A new look's name, `<prefix>-N`: the prefix is its preset's key, or `custom`
// for a look started from Shipped with no preset; N is one past the highest
// number issued for that prefix in this run, removed ones included, so a name
// is never reused.
function pinName(issued: Set<string>, prefix: string): string {
  const used = [...issued].filter(name => name.startsWith(`${prefix}-`))
    .map(name => name.slice(prefix.length + 1)).filter(rest => /^[0-9]+$/.test(rest)).map(Number);
  return `${prefix}-${Math.max(0, ...used) + 1}`;
}
// A chip's label: `Compact-2` for `compact-2`, `Warm Glow-1` for `warm-glow-1`,
// Shipped for `original`; a name that does not end in `-N` as it is.
function chipLabel(name: string): string {
  if (name === "original") return "Shipped";
  const m = /^(.+)-([0-9]+)$/.exec(name);
  if (!m) return name;
  const words = m[1].split("-").filter(Boolean).map(word => word[0].toUpperCase() + word.slice(1));
  return `${words.join(" ")}-${Number(m[2])}`;
}

function reasonOf(error: unknown): string {
  return error instanceof Error ? error.message : "unknown error";
}

// Reads every stored look, oldest first. An entry that cannot be used is
// described in `problems` and left in storage untouched. Every stored name,
// readable or not, is added to `reserved` so a new look never reuses it.
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
  // Pinned looks live in memory and in the log, oldest first; each saved
  // version is mirrored to localStorage.
  const [candidates, setCandidates] = useState(initialCandidates);
  // Every name issued in this run, removed ones included: names are never reused.
  const issued = useRef(new Set([...reservedNames, ...initialCandidates.map(c => c.name)]));
  // The line each look last logged, so a save that changed nothing logs nothing.
  const logged = useRef(new Map<string, string>());
  // The selected chip: "original" (Shipped) or a look's name. The feature always
  // shows it.
  const [selected, setSelected] = useState("original");
  // Edits made on Shipped and not pinned yet, with the preset they came from.
  // While set, no chip is outlined.
  const [unsaved, setUnsaved] = useState<Step | null>(null);
  // Each pinned look's edits since its last save, by name. They stay with the
  // look when the user switches away.
  const [drafts, setDrafts] = useState<Record<string, CardConfig>>({});
  // Undo and Redo per look ("original" for Shipped), and the control of each
  // look's newest step, so one slider drag is one step.
  const [history, setHistory] = useState<Record<string, History>>({});
  const lastControl = useRef(new Map<string, string | undefined>());
  // A failed profile write during the current save, so the next status keeps it.
  const storeError = useRef<string | null>(null);
  // The winner after Apply; while set, the panel is the result bar.
  const [sent, setSent] = useState<string | null>(null);
  // How many times a pick reached the agent. The first Apply reaches its
  // waiter; after it the agent no longer listens, so Apply hides and Save & pin
  // and Save also hand the pick over, for the user to paste as `land <name>`.
  // Change does not reset it.
  const [applies, setApplies] = useState(0);
  const [copied, setCopied] = useState(true);  // the clipboard took `land <name>`
  // The result bar's second line: where the pick was saved, or null when it could not.
  const [saved, setSaved] = useState<string | null>(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const selectedPin = candidates.find(c => c.name === selected);
  // The look the feature shows, and where it came from.
  const current: Step = selectedPin
    ? { value: drafts[selectedPin.name] ?? savedLook(selectedPin), basedOn: selectedPin.basedOn }
    : unsaved ?? { value: baseline, basedOn: "baseline" };
  const selectedValues = changedValues(baseline, current.value);
  const shippedOutlined = selected === "original" && unsaved === null;
  const steps = history[selected] ?? noHistory;
  const hasEdits = selectedPin ? selectedPin.name in drafts : unsaved !== null;
  // Save & pin needs edits on Shipped. Save needs edits until the first Apply;
  // after it, Save is how a pick reaches the chat, so it stays enabled.
  const saveTitle = selectedPin ? "Save" : "Save & pin";
  const canSave = selectedPin ? hasEdits || applies > 0 : unsaved !== null;

  // Read the latest looks and selection through refs, so an effect that runs
  // once per open never reads stale state.
  const latest = useRef({ candidates, selected });
  useLayoutEffect(() => { latest.current = { candidates, selected }; });

  // Logs a look's line when it is new or changed since it last logged, and
  // stores it: a look is written only when it is saved. Seeded and stored
  // looks log without being written again.
  function logPin(candidate: Candidate, storing = true) {
    const line = sortedJson(candidate);
    if (logged.current.get(candidate.name) === line) return;
    logged.current.set(candidate.name, line);
    console.info(`UITUNINGLAB_CANDIDATE ${line}`);
    if (storing) store(candidate);
  }

  // The one close path. It runs from the popover's toggle event, or directly
  // when the browser has no Popover API. The feature keeps the selected look.
  function finishClose() {
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

  // Apply moves focus to Change, and Change moves it back to the chips.
  useEffect(() => { (sent ? changeButton : firstControl).current?.focus(); }, [sent]);

  // Stored looks load each time the lab opens; in-memory ones that are not
  // stored (the initial candidates) stay in the list. Seeded and stored looks
  // log their own line the first time the lab shows them.
  useEffect(() => {
    if (!open) return;
    for (const c of latest.current.candidates) if (!logged.current.has(c.name)) logPin(c, false);
    try {
      const { found, problems } = readStored(issued.current);
      setCandidates(list => [...found, ...list.filter(c => !found.some(f => f.name === c.name))]);
      for (const c of found) if (!logged.current.has(c.name)) logPin(c, false);
      if (problems.length > 0) {
        setStatus({ text: `Skipped unreadable pins, left in storage: ${problems.join(", ")}`, error: true });
      }
    } catch (error) {
      setStatus({ text: `Saved pins not loaded: ${reasonOf(error)}. Storage was left unchanged.`, error: true });
    }
  }, [open]);

  function openLab() { setStatus(null); setOpen(true); }

  // Shows a step on the selected look. Matching the last save leaves no edits.
  function show(step: Step) {
    if (selectedPin) {
      const name = selectedPin.name;
      setCandidates(list => list.map(c => c.name === name ? { ...c, basedOn: step.basedOn } : c));
      setDrafts(all => sameLook(step.value, savedLook(selectedPin))
        ? without(all, name) : { ...all, [name]: step.value });
    } else {
      setUnsaved(sameLook(step.value, baseline) ? null : step);
    }
    setConfig(step.value);
  }
  function setSteps(name: string, next: History) {
    setHistory(all => ({ ...all, [name]: next }));
  }
  function clearHistory(name: string) {
    setHistory(all => without(all, name));
    lastControl.current.delete(name);
  }

  // Selecting a chip shows its look in the real feature. Switching chips is the
  // comparison. Unsaved edits on Shipped are dropped, so Shipped always shows
  // the baseline; a pinned look keeps its edits.
  function select(chip: string) {
    if (chip === selected && unsaved === null) return;
    lastControl.current.delete(selected);  // a drag after coming back is its own step
    clearHistory("original");
    setUnsaved(null);
    const pin = candidates.find(c => c.name === chip);
    setSelected(pin ? pin.name : "original");
    setConfig(pin ? drafts[pin.name] ?? savedLook(pin) : { ...baseline });
  }
  // Every control edits the selected look: on Shipped as unsaved edits, on a
  // pinned look as edits on top of its saved version. A preset becomes its
  // basedOn. Sliders pass their key as `control`: a run of edits from the same
  // control in a row is one Undo step. Presets pass none, so each is a step.
  function edit(next: CardConfig, preset?: string, control?: string) {
    if (sameLook(next, current.value) && (preset === undefined || preset === current.basedOn)) return;
    const extend = control !== undefined && control === lastControl.current.get(selected) && steps.undo.length > 0;
    setSteps(selected, { undo: extend ? steps.undo : [...steps.undo, current], redo: [] });
    lastControl.current.set(selected, control);
    show({ value: next, basedOn: preset ?? current.basedOn });
  }
  function applyPreset(name: keyof typeof presets) { edit({ ...presets[name] }, name); }
  // Undo steps the selected look back one edit, never past its last save.
  function undo() {
    const previous = steps.undo[steps.undo.length - 1];
    if (!previous) return;
    setSteps(selected, { undo: steps.undo.slice(0, -1), redo: [...steps.redo, current] });
    lastControl.current.delete(selected);
    show(previous);
  }
  // Redo brings back the edit Undo last took away.
  function redo() {
    const next = steps.redo[steps.redo.length - 1];
    if (!next) return;
    setSteps(selected, { undo: [...steps.undo, current], redo: steps.redo.slice(0, -1) });
    lastControl.current.delete(selected);
    show(next);
  }
  // Reset takes the selected look back to its last save (Shipped: the
  // baseline) in one step that Undo can take back.
  function reset() {
    if (!hasEdits) return;
    setSteps(selected, { undo: [...steps.undo, current], redo: [] });
    lastControl.current.delete(selected);
    show(selectedPin ? { value: savedLook(selectedPin), basedOn: selectedPin.basedOn }
      : { value: baseline, basedOn: "baseline" });
  }
  // Undo and Redo on the keyboard, only while focus is in the panel: Ctrl or
  // Cmd-Z, and Ctrl or Cmd-Shift-Z or Ctrl-Y. A text field keeps its own undo.
  function onPanelKeyDown(event: ReactKeyboardEvent<HTMLDivElement>) {
    if (!(event.ctrlKey || event.metaKey) || event.altKey) return;
    const target = event.target as HTMLElement;
    if ((target instanceof HTMLInputElement && target.type !== "range") ||
        target instanceof HTMLTextAreaElement || target.isContentEditable) return;
    const key = event.key.toLowerCase();
    if (key === "z" && !event.shiftKey) { event.preventDefault(); undo(); }
    else if ((key === "z" && event.shiftKey) || (key === "y" && !event.shiftKey)) { event.preventDefault(); redo(); }
  }

  // Keeps the selected look's edits: unsaved edits on Shipped become a new
  // look, named after its preset and selected; a pinned look's edits become its
  // saved version. Logs a look that changed. Returns the look (none on plain
  // Shipped), the list it is in, read before React re-renders, and whether it
  // pinned a new look.
  function commit(): { look?: Candidate; list: Candidate[]; pinned: boolean } {
    storeError.current = null;
    if (selectedPin) {
      const look = { ...selectedPin, values: changedValues(baseline, current.value) };
      const list = candidates.map(c => c.name === look.name ? look : c);
      setCandidates(list);
      setDrafts(all => without(all, look.name));
      clearHistory(look.name);
      logPin(look);
      return { look, list, pinned: false };
    }
    if (unsaved === null) return { list: candidates, pinned: false };
    const prefix = unsaved.basedOn === "baseline" ? "custom" : unsaved.basedOn;
    const look: Candidate = { name: pinName(issued.current, prefix), basedOn: unsaved.basedOn,
      values: changedValues(baseline, unsaved.value) };
    issued.current.add(look.name);
    const list = [...candidates, look];
    setCandidates(list);
    setSelected(look.name);
    setUnsaved(null);
    clearHistory("original");
    logPin(look);
    return { look, list, pinned: true };
  }
  // Save & pin on Shipped, Save on a pinned look: keeps the look and copies its
  // land code. Before the first Apply the agent is listening for Apply, so
  // nothing more happens; after it, the pick is handed over for pasting.
  async function saveLook() {
    if (!canSave) return;
    const { look, list, pinned } = commit();
    if (!look) return;
    if (applies > 0) { await handOver(look, list); return; }
    setSaved(null);
    const kept = pinned ? `Pinned ${chipLabel(look.name)}` : `Saved ${chipLabel(look.name)}`;
    try {
      await navigator.clipboard.writeText(`land ${look.name}`);
      setStatus(storeError.current ? { text: storeError.current, error: true }
        : { text: `${kept} · copied land ${look.name}` });
    } catch {
      setStatus(storeError.current ? { text: storeError.current, error: true }
        : { text: `${kept}; clipboard unavailable, tell the agent "land ${look.name}"` });
    }
  }
  // Apply saves first (unsaved edits on Shipped are pinned, a selected look's
  // edits saved), then hands the pick over.
  async function applyLook() {
    const { look, list } = commit();
    await handOver(look, list);
  }
  // Writes a look's profile under its own key. A rewrite keeps the first
  // savedAt, so looks load in the order they were pinned. A failed write is
  // reported, and stays shown through the rest of the save; the look stays in
  // the panel and the log still has it.
  function store(candidate: Candidate) {
    const key = candidateKey + candidate.name;
    let firstSavedAt: unknown;
    try { firstSavedAt = JSON.parse(localStorage.getItem(key) ?? "null")?.savedAt; } catch { firstSavedAt = undefined; }
    const profile: UITuningLabProfile = {
      basedOn: candidate.basedOn,
      container: "FeatureScreen.popover",
      name: candidate.name,
      notes: "",
      overrides: savedLook(candidate),
      platform: "web",
      savedAt: typeof firstSavedAt === "string" ? firstSavedAt : new Date().toISOString(),
      schemaVersion: 2,
      scope: ["appearance", "layout"],
    };
    try {
      localStorage.setItem(key, JSON.stringify(profile));
    } catch (error) {
      storeError.current = `${chipLabel(candidate.name)} not saved: ${reasonOf(error)}`;
      setStatus({ text: storeError.current, error: true });
    }
  }
  // Reports the selected look as shown, edits included.
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
      setStatus({ text: `${chipLabel(name)} not removed: ${reasonOf(error)}`, error: true });
      return;
    }
    setCandidates(list => list.filter(c => c.name !== name));
    setDrafts(all => without(all, name));
    clearHistory(name);
    logged.current.delete(name);
    console.info(`UITUNINGLAB_CANDIDATE_REMOVED ${sortedJson({ name })}`);
    setStatus({ text: `Removed ${chipLabel(name)}` });
    if (selected === name) { setConfig({ ...baseline }); setSelected("original"); }
  }
  // Hands a pick to the agent: logs it, sends it to the waiter, stores the
  // result, and copies its land code. Picking again replaces the result.
  // `candidates` carry each look's saved version.
  async function handOver(look: Candidate | undefined, list: Candidate[]) {
    const winner = look ? look.name : "original";
    const result = { candidates: list, values: look?.values ?? {}, winner };
    console.info(`UITUNINGLAB_DONE ${sortedJson(result)}`);
    // Hands the pick to the agent's waiter (scripts/wait-for-pick.py) at once,
    // so it resumes without a message. Fire and forget: with nothing listening,
    // the console and the stored result still carry the pick.
    fetch("http://localhost:47321/pick", { method: "POST", mode: "no-cors", keepalive: true,
      body: `UITUNINGLAB_DONE ${sortedJson(result)}` }).catch(() => {});
    const problems: string[] = [];
    try {
      localStorage.setItem(resultKey, sortedJson({ ...result, savedAt: new Date().toISOString() }));
      setSaved(`Saved ${chipLabel(winner)} in localStorage uiTuningLab.result`);
    } catch {
      setSaved(null);
      problems.push("result not saved");
    }
    try {
      await navigator.clipboard.writeText(`land ${winner}`);
      setCopied(true);
    } catch {
      setCopied(false);
      problems.push(`clipboard unavailable; tell the agent "land ${winner}"`);
    }
    setStatus(problems.length > 0 ? { text: `Logged to the console; ${problems.join("; ")}`, error: true }
      : storeError.current ? { text: storeError.current, error: true } : null);
    setApplies(n => n + 1);
    setSent(winner);
  }

  return <>
    <CardFeature config={config} />
    <button ref={trigger} type="button" onClick={openLab} disabled={open}
      style={triggerStyle}>Card Lab</button>
    {open && <div ref={panel} {...popoverManual} style={panelStyle} role="dialog"
      aria-labelledby="ui-tuning-lab-title" onKeyDown={onPanelKeyDown}>
      {sent ? <><p style={rowStyle}>
        <strong id="ui-tuning-lab-title">{applies > 1
          ? (copied ? `Copied land ${sent}: paste it in chat so the agent applies it` : `Tell the agent: land ${sent}`)
          : `Applied: ${chipLabel(sent)}`}</strong>
        <button ref={changeButton} type="button" onClick={() => setSent(null)}>Change</button>
      </p>
      {(saved ?? status?.text) && <p role="status" style={{ margin: 0, fontSize: "0.85em" }}>
        {saved ?? status?.text}</p>}</> : <>
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
          <button ref={firstControl} type="button" aria-pressed={shippedOutlined}
            style={selectedStyle(shippedOutlined)}
            onClick={() => select("original")}>Shipped</button>
          {candidates.map(c => <span key={c.name}>
            <button type="button" aria-pressed={selected === c.name} style={selectedStyle(selected === c.name)}
              onClick={() => select(c.name)}>{chipLabel(c.name)}</button>
            {/* × only on the selected look, so nothing is removed by accident. */}
            {selected === c.name && <button type="button" aria-label={`Remove ${chipLabel(c.name)}`}
              onClick={() => remove(c.name)}>×</button>}
          </span>)}
        </div>
        <div role="group" aria-label="Controls">
          <button type="button" onClick={() => applyPreset("compact")}>Compact</button>
          <button type="button" onClick={() => applyPreset("relaxed")}>Relaxed</button>
          <label>Radius <input type="range" min="0" max="32"
            value={config.radius}
            onChange={e => edit({ ...config, radius: Number(e.target.value) }, undefined, "radius")}/>
            <output aria-hidden="true">{config.radius}px</output>
          </label>
          <label>Gap <input type="range" min="0" max="24"
            value={config.gap}
            onChange={e => edit({ ...config, gap: Number(e.target.value) }, undefined, "gap")}/>
            <output aria-hidden="true">{config.gap}px</output>
          </label>
        </div>
        <div role="group" aria-label="Edits" style={rowStyle}>
          <button type="button" disabled={steps.undo.length === 0} onClick={undo}>Undo</button>
          <button type="button" disabled={steps.redo.length === 0} onClick={redo}>Redo</button>
          <button type="button" disabled={!hasEdits} onClick={reset}>Reset</button>
        </div>
        <div style={rowStyle}>
          <button type="button" disabled={!canSave} onClick={saveLook}>{saveTitle}</button>
          {/* Apply reaches the agent once; after that it is hidden for good. */}
          {applies === 0 && <button type="button" onClick={applyLook}>Apply</button>}
        </div>
      </>}
      {status && !sent && <p role={status.error ? "alert" : "status"}>{status.text}</p>}
      {!sent && <p style={{ position: "sticky", bottom: 0, margin: 0, padding: "8px 0", background: "Canvas" }}>
        {applies > 0 ? "Save, then paste it in chat"
          : "Save & pin to keep a look · Apply to finish"}</p>}
    </div>}
  </>;
}
```


Saving a look writes only `uiTuningLab.candidates.<name>`, and × deletes only
that key. Unsaved edits are never written.
Storage failures are shown in the status line and leave the chips unchanged.
Inspect the emitted production bundle to confirm that the lab module and storage
code were eliminated.
