# Candidate — web floating panel

The feature and controls share one config state. The baseline is captured on open;
closing unmounts the popover and its listener. The default candidate is ephemeral
and has no storage writer or Save action.

```tsx
type CardConfig = { radius: number; gap: number };
const appDefault: CardConfig = { radius: 12, gap: 8 };
const presets = {
  compact: { radius: 4, gap: 4 },
  relaxed: { radius: 24, gap: 16 },
} satisfies Record<string, CardConfig>;

export function FeatureScreen() {
  const [config, setConfig] = useState(appDefault);
  if (import.meta.env.DEV) {
    return <DevelopmentFeature config={config} setConfig={setConfig} />;
  }
  return <CardFeature config={config} />;
}

function DevelopmentFeature({ config, setConfig }: {
  config: CardConfig;
  setConfig: React.Dispatch<React.SetStateAction<CardConfig>>;
}) {
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
    const onToggle = (event: ToggleEvent) => {
      if (event.newState === "closed") {
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
    {open && <div ref={panel} popover="auto" role="dialog"
      aria-labelledby="tuning-lab-title">
      <h2 id="tuning-lab-title">UI tuning lab</h2>
      <button ref={firstControl} type="button"
        onClick={() => setConfig(presets.compact)}>Compact</button>
      <button type="button" onClick={() => setConfig(presets.relaxed)}>Relaxed</button>
      <label>Radius <input type="range" min="0" max="32"
        value={config.radius}
        onChange={e => setConfig({ ...config, radius: Number(e.target.value) })}/>
      </label>
      <button type="button" onClick={reset}>Reset</button>
    </div>}
  </>;
}
```

Place the development component in a development-only module so the production
bundler can eliminate it. If Popover API support is outside the app's browser
baseline, use an accessible dialog or conditionally mounted `<details>` while
preserving focus and teardown. Native popover light-dismiss and Escape close the
panel; the `toggle` event unmounts it and cleanup restores focus to Tune. Buttons
and the labelled range remain in normal keyboard order. Test Chromium, Safari, and Firefox on desktop and
mobile layouts, keyboard, screen readers, light-dismiss, unmounting, and emitted
production assets before approval.

## Optional persistence, only when requested

Only when the user explicitly requests saved profiles, add this envelope inside
the development-only module containing `DevelopmentFeature`:

```tsx
type LabProfile = {
  schemaVersion: 1;
  name: "default";
  platform: "web";
  container: "FeatureScreen.popover";
  scope: ["appearance", "layout"];
  overrides: CardConfig;
  notes: "";
};
```

Add the following state and writer inside `DevelopmentFeature`:

```tsx
  const [saveError, setSaveError] = useState<string | null>(null);
  function save() {
    try {
      const profile: LabProfile = {
        schemaVersion: 1,
        name: "default",
        platform: "web",
        container: "FeatureScreen.popover",
        scope: ["appearance", "layout"],
        overrides: config,
        notes: "",
      };
      localStorage.setItem("variantLab.default", JSON.stringify(profile));
      setSaveError(null);
    } catch (error) {
      setSaveError(error instanceof Error ? error.message : "Save failed");
    }
  }
```

Add `setSaveError(null)` to `openLab()` so each new session clears the previous
save error. After the Reset button, add:

```tsx
<button type="button" onClick={save}>Save</button>
{saveError && <p role="alert">{saveError}</p>}
```

The explicit Save writes only `variantLab.default`. Storage failures display an
alert and retain the draft. Inspect the emitted production bundle to confirm that
the development module and writer were eliminated.
