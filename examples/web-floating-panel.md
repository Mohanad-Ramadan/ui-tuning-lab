# Candidate — web floating panel

The feature and controls share one config state. All lab code lives in
`FeatureScreen.ui-tuning-lab.tsx`; the feature reaches it only through a dynamic
import inside an `import.meta.env.DEV` block, so production builds drop both the
branch and the lab chunk. The baseline is captured on open; closing unmounts the
popover and its listener. The default candidate is ephemeral and has no storage
writer or Save action. **Copy values** copies the fields that differ from the
baseline and logs them as one `UITUNINGLAB_VALUES {...}` console line for landing
(`references/landing-protocol.md`).

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
import { CardFeature } from "./CardFeature";
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

const presets = {
  compact: { radius: 4, gap: 4 },
  relaxed: { radius: 24, gap: 16 },
} satisfies Record<string, CardConfig>;

// The draft fields that differ from the baseline.
function changedValues<T extends object>(baseline: T, draft: T): Partial<T> {
  return Object.fromEntries(Object.entries(draft).filter(
    ([key, value]) => value !== baseline[key as keyof T])) as Partial<T>;
}

export default function UITuningLabFeature({ config, setConfig }: TuningLabHostProps) {
  const [open, setOpen] = useState(false);
  const [baseline, setBaseline] = useState<CardConfig | null>(null);
  const [status, setStatus] = useState<string | null>(null);
  const panel = useRef<HTMLDivElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  const firstControl = useRef<HTMLButtonElement>(null);
  // Holds the draft while the baseline is shown in the real feature.
  const stashedDraft = useRef<CardConfig | null>(null);
  const [showingBaseline, setShowingBaseline] = useState(false);

  // Read the host's setter through a ref so an unstable setter never re-runs the
  // open effect, which would re-show the panel and steal focus.
  const setConfigRef = useRef(setConfig);
  useLayoutEffect(() => { setConfigRef.current = setConfig; });

  // The one close path. It runs from the popover's toggle event, or directly
  // when the browser has no Popover API.
  function finishClose() {
    if (stashedDraft.current) setConfigRef.current(stashedDraft.current);
    stashedDraft.current = null;
    setShowingBaseline(false);
    setOpen(false);
    setBaseline(null);
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

  function openLab() { setBaseline({ ...config }); setStatus(null); setOpen(true); }
  function reset() { if (baseline) setConfig({ ...baseline }); }
  function toggleBaseline() {
    if (stashedDraft.current) {
      setConfig(stashedDraft.current);
      stashedDraft.current = null;
      setShowingBaseline(false);
    } else if (baseline) {
      stashedDraft.current = config;
      setConfig({ ...baseline });
      setShowingBaseline(true);
    }
  }
  async function copyValues() {
    const values = JSON.stringify(changedValues(baseline ?? config, config));
    console.info(`UITUNINGLAB_VALUES ${values}`);
    try {
      await navigator.clipboard.writeText(values);
      setStatus(values === "{}" ? "No changes from baseline" : `Copied ${values}`);
    } catch {
      setStatus(`Clipboard unavailable; values logged to the console: ${values}`);
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
      <button type="button" aria-pressed={showingBaseline}
        onClick={toggleBaseline}>Show baseline</button>
      <fieldset disabled={showingBaseline} aria-label="Draft controls"
        style={{ border: 0, margin: 0, padding: 0 }}>
        <button ref={firstControl} type="button"
          onClick={() => setConfig({ ...presets.compact })}>Compact</button>
        <button type="button" onClick={() => setConfig({ ...presets.relaxed })}>Relaxed</button>
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
      </fieldset>
      {status && <p role="status">{status}</p>}
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
Load saved applies the stored overrides to the draft; the baseline stays as
captured, so Reset still returns to it. Unreadable or incompatible data is
reported and left in storage untouched.

<!-- file: FeatureScreen.ui-tuning-lab.tsx variant=persist -->
```tsx
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { CardFeature } from "./CardFeature";
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
  schemaVersion: 1;
  name: "default";
  platform: "web";
  container: "FeatureScreen.popover";
  scope: ["appearance", "layout"];
  overrides: CardConfig;
  notes: "";
};

const presets = {
  compact: { radius: 4, gap: 4 },
  relaxed: { radius: 24, gap: 16 },
} satisfies Record<string, CardConfig>;

// The draft fields that differ from the baseline.
function changedValues<T extends object>(baseline: T, draft: T): Partial<T> {
  return Object.fromEntries(Object.entries(draft).filter(
    ([key, value]) => value !== baseline[key as keyof T])) as Partial<T>;
}

export default function UITuningLabFeature({ config, setConfig }: TuningLabHostProps) {
  const [open, setOpen] = useState(false);
  const [baseline, setBaseline] = useState<CardConfig | null>(null);
  const [status, setStatus] = useState<{ text: string; error?: boolean } | null>(null);
  const panel = useRef<HTMLDivElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  const firstControl = useRef<HTMLButtonElement>(null);
  // Holds the draft while the baseline is shown in the real feature.
  const stashedDraft = useRef<CardConfig | null>(null);
  const [showingBaseline, setShowingBaseline] = useState(false);

  // Read the host's setter through a ref so an unstable setter never re-runs the
  // open effect, which would re-show the panel and steal focus.
  const setConfigRef = useRef(setConfig);
  useLayoutEffect(() => { setConfigRef.current = setConfig; });

  // The one close path. It runs from the popover's toggle event, or directly
  // when the browser has no Popover API.
  function finishClose() {
    if (stashedDraft.current) setConfigRef.current(stashedDraft.current);
    stashedDraft.current = null;
    setShowingBaseline(false);
    setOpen(false);
    setBaseline(null);
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

  function openLab() { setBaseline({ ...config }); setStatus(null); setOpen(true); }
  function reset() { if (baseline) setConfig({ ...baseline }); }
  function toggleBaseline() {
    if (stashedDraft.current) {
      setConfig(stashedDraft.current);
      stashedDraft.current = null;
      setShowingBaseline(false);
    } else if (baseline) {
      stashedDraft.current = config;
      setConfig({ ...baseline });
      setShowingBaseline(true);
    }
  }
  async function copyValues() {
    const values = JSON.stringify(changedValues(baseline ?? config, config));
    console.info(`UITUNINGLAB_VALUES ${values}`);
    try {
      await navigator.clipboard.writeText(values);
      setStatus({ text: values === "{}" ? "No changes from baseline" : `Copied ${values}` });
    } catch {
      setStatus({ text: `Clipboard unavailable; values logged to the console: ${values}` });
    }
  }
  function save() {
    try {
      const profile: UITuningLabProfile = {
        schemaVersion: 1,
        name: "default",
        platform: "web",
        container: "FeatureScreen.popover",
        scope: ["appearance", "layout"],
        overrides: config,
        notes: "",
      };
      localStorage.setItem("uiTuningLab.default", JSON.stringify(profile));
      setStatus({ text: "Saved" });
    } catch (error) {
      setStatus({ text: `Save failed: ${error instanceof Error ? error.message : "unknown error"}`, error: true });
    }
  }
  function loadSaved() {
    try {
      const stored = localStorage.getItem("uiTuningLab.default");
      if (stored === null) throw new Error("nothing has been saved yet");
      const profile = JSON.parse(stored) as Partial<UITuningLabProfile>;
      const saved = profile.overrides;
      if (profile.schemaVersion !== 1 || profile.platform !== "web" ||
          typeof saved?.radius !== "number" || typeof saved?.gap !== "number") {
        throw new Error("the saved profile has an incompatible schema or platform");
      }
      setConfig({ radius: saved.radius, gap: saved.gap });
      setStatus({ text: "Loaded saved values" });
    } catch (error) {
      const reason = error instanceof Error ? error.message : "unreadable";
      setStatus({ text: `Saved profile not loaded: ${reason}. Storage was left unchanged.`, error: true });
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
      <button type="button" aria-pressed={showingBaseline}
        onClick={toggleBaseline}>Show baseline</button>
      <fieldset disabled={showingBaseline} aria-label="Draft controls"
        style={{ border: 0, margin: 0, padding: 0 }}>
        <button ref={firstControl} type="button"
          onClick={() => setConfig({ ...presets.compact })}>Compact</button>
        <button type="button" onClick={() => setConfig({ ...presets.relaxed })}>Relaxed</button>
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
        <button type="button" onClick={save}>Save</button>
        <button type="button" onClick={loadSaved}>Load saved</button>
      </fieldset>
      {status && <p role={status.error ? "alert" : "status"}>{status.text}</p>}
    </div>}
  </>;
}
```

The explicit Save writes only `uiTuningLab.default`. Storage failures are shown
in the status line and retain the draft. Inspect the emitted production bundle to confirm that
the lab module and writer were eliminated.
