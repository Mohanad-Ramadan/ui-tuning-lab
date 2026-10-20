# Candidate — web floating panel

The feature and controls share one config state. All lab code lives in
`FeatureScreen.ui-tuning-lab.tsx`; the feature reaches it only through a dynamic
import inside an `import.meta.env.DEV` block, so production builds drop both the
branch and the lab chunk. The baseline is captured on open; closing unmounts the
popover and its listener. The default candidate is ephemeral and has no storage
writer or Save action.

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
import { useEffect, useRef, useState } from "react";
import { CardFeature } from "./CardFeature";
import type { CardConfig } from "./CardFeature";
import type { TuningLabHostProps } from "./FeatureScreen";

// React 18 types omit `popover`; the spread compiles on React 18 and 19 alike.
const popoverAuto = { popover: "auto" };

const presets = {
  compact: { radius: 4, gap: 4 },
  relaxed: { radius: 24, gap: 16 },
} satisfies Record<string, CardConfig>;

export default function UITuningLabFeature({ config, setConfig }: TuningLabHostProps) {
  const [open, setOpen] = useState(false);
  const [baseline, setBaseline] = useState<CardConfig | null>(null);
  const panel = useRef<HTMLDivElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  const firstControl = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    const node = panel.current;
    if (!open || !node) return;
    node.showPopover?.();
    const focusFrame = requestAnimationFrame(() => firstControl.current?.focus());
    const onToggle = (event: Event) => {
      if ((event as ToggleEvent).newState === "closed") {
        setOpen(false);
        setBaseline(null);
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

  function openLab() { setBaseline({ ...config }); setOpen(true); }
  function reset() { if (baseline) setConfig({ ...baseline }); }

  return <>
    <CardFeature config={config} />
    <button ref={trigger} type="button" onClick={openLab} disabled={open}>Tune</button>
    {open && <div ref={panel} {...popoverAuto} role="dialog"
      aria-labelledby="tuning-lab-title">
      <h2 id="tuning-lab-title">UI tuning lab</h2>
      <button ref={firstControl} type="button"
        onClick={() => setConfig(presets.compact)}>Compact</button>
      <button type="button" onClick={() => setConfig(presets.relaxed)}>Relaxed</button>
      <label>Radius <input type="range" min="0" max="32"
        value={config.radius}
        onChange={e => setConfig(c => ({ ...c, radius: Number(e.target.value) }))}/>
      </label>
      <label>Gap <input type="range" min="0" max="24"
        value={config.gap}
        onChange={e => setConfig(c => ({ ...c, gap: Number(e.target.value) }))}/>
      </label>
      <button type="button" onClick={reset}>Reset</button>
    </div>}
  </>;
}
```

Keep lab code only in `*.ui-tuning-lab.tsx` modules and import them only as shown
in `FeatureScreen.tsx`; a top-level static import fails `source-gates`. If
Popover API support is outside the app's browser baseline, use an accessible
dialog or conditionally mounted `<details>` while preserving focus and teardown.
Native popover light-dismiss and Escape close the panel; the `toggle` event
unmounts it and cleanup restores focus to Tune. Buttons and the labelled ranges
remain in normal keyboard order. Test Chromium, Safari, and Firefox on desktop and
mobile layouts, keyboard, screen readers, light-dismiss, unmounting, and emitted
production assets before approval.

## Optional persistence, only when requested

Only when the user explicitly requests saved profiles, replace
`FeatureScreen.ui-tuning-lab.tsx` with this version. The feature files stay
unchanged, and the writer lives only in the development-only module.

<!-- file: FeatureScreen.ui-tuning-lab.tsx variant=persist -->
```tsx
import { useEffect, useRef, useState } from "react";
import { CardFeature } from "./CardFeature";
import type { CardConfig } from "./CardFeature";
import type { TuningLabHostProps } from "./FeatureScreen";

// React 18 types omit `popover`; the spread compiles on React 18 and 19 alike.
const popoverAuto = { popover: "auto" };

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

export default function UITuningLabFeature({ config, setConfig }: TuningLabHostProps) {
  const [open, setOpen] = useState(false);
  const [baseline, setBaseline] = useState<CardConfig | null>(null);
  const [saveError, setSaveError] = useState<string | null>(null);
  const panel = useRef<HTMLDivElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  const firstControl = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    const node = panel.current;
    if (!open || !node) return;
    node.showPopover?.();
    const focusFrame = requestAnimationFrame(() => firstControl.current?.focus());
    const onToggle = (event: Event) => {
      if ((event as ToggleEvent).newState === "closed") {
        setOpen(false);
        setBaseline(null);
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

  function openLab() { setBaseline({ ...config }); setSaveError(null); setOpen(true); }
  function reset() { if (baseline) setConfig({ ...baseline }); }
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
      setSaveError(null);
    } catch (error) {
      setSaveError(error instanceof Error ? error.message : "Save failed");
    }
  }

  return <>
    <CardFeature config={config} />
    <button ref={trigger} type="button" onClick={openLab} disabled={open}>Tune</button>
    {open && <div ref={panel} {...popoverAuto} role="dialog"
      aria-labelledby="tuning-lab-title">
      <h2 id="tuning-lab-title">UI tuning lab</h2>
      <button ref={firstControl} type="button"
        onClick={() => setConfig(presets.compact)}>Compact</button>
      <button type="button" onClick={() => setConfig(presets.relaxed)}>Relaxed</button>
      <label>Radius <input type="range" min="0" max="32"
        value={config.radius}
        onChange={e => setConfig(c => ({ ...c, radius: Number(e.target.value) }))}/>
      </label>
      <label>Gap <input type="range" min="0" max="24"
        value={config.gap}
        onChange={e => setConfig(c => ({ ...c, gap: Number(e.target.value) }))}/>
      </label>
      <button type="button" onClick={reset}>Reset</button>
      <button type="button" onClick={save}>Save</button>
      {saveError && <p role="alert">{saveError}</p>}
    </div>}
  </>;
}
```

The explicit Save writes only `uiTuningLab.default`. Storage failures display an
alert and retain the draft. Inspect the emitted production bundle to confirm that
the lab module and writer were eliminated.
