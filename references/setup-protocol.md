# Inspect-First Setup Protocol

Inspect before asking. Read the app entry point, build configuration, feature
configuration model, presentation conventions, persistence layer, and nearby
tests. Record these working choices:

- target: feature unless the request explicitly names the container;
- scope: only the animation, layout, appearance, or visible logic requested;
- container: the existing platform-native transient surface nearest the feature;
- gate: the project's development, DEBUG, internal, or tester mechanism;
- activation: the agent path, the human path, and the visible fallback, chosen
  from inspection (`references/activation.md`);
- placement: which corners or edges other development overlays already hold
  (router or query devtools, a framework dev indicator, a hosting toolbar, a
  help or chat widget), found from the app's root layout and dev dependencies
  before the activation question is written, so the question names a free
  corner ("Wire the host", "Find a free corner");
- persistence: none unless the user asks to save or reuse profiles;
- profiles: one working draft unless named profiles were requested;
- baseline: the feature's declared default, the value it ships with (for example
  `CardStyle.appDefault` or `cardDefaults`). Never take it from the screen when the
  lab opens: the draft survives closing, so a reopened lab would treat the draft as
  the original, Reset would do nothing, and Copy values would miss earlier changes.
  When the shipped value is computed at runtime (from a theme, a server, or a
  device trait), the declared default is not what the user sees, and using it
  would make Reset change the feature and Copy values report edits nobody made.
  Then capture the rendered value on the first open, before any lab edit, and keep
  it in a DEBUG-only store that outlives the panel (keeping one value is allowed;
  the teardown guarantee is about work and UI). Capture it again if its source
  changes while the draft still equals it, for example on a theme switch, and key
  the store to that source. Copy values reports against this captured baseline.

## Reuse an existing control surface

Before building a panel, look for one the project already has:

| Signal | Use it as the control surface |
|---|---|
| `leva`, `tweakpane`, `lil-gui`, or `dat.gui` in `package.json` | that library's panel, mounted only in the development-only lab module |
| `@storybook/*` with the feature already in a story | Storybook controls (args), when the user is happy to tune in Storybook rather than in the running app |
| An in-house debug menu, drawer, or settings screen (search for `DebugMenu`, `DevMenu`, `InternalSettings`, `DeveloperSettings`) | a new entry in that menu that opens the lab |
| React Native `DevSettings.addMenuItem` or Flipper plugins | the existing developer menu |

Reuse changes only the control surface. The four guarantees, the naming rule, a
baseline, Copy values, and landing still apply, and a third-party panel
must be imported only from the gated lab module so it drops out of production.
If the existing tool cannot capture a baseline or unmount cleanly, build the
native panel instead and say why.

## Wire the host

- **Wrap the feature, not the screen.** Put the lab host exactly where the
  feature component is rendered. When the feature is one child of a larger screen
  (a card list under a heading), replace only that child with the host and keep
  its siblings untouched; the examples' whole-screen hosts are the simple case.
- **Constants become state.** When the feature reads a constant directly (for
  example `<CardList config={cardDefaults} />`), lift it into state in the
  nearest parent, initialised from that constant, so the lab has something to
  edit. Production still renders the same value. This is the one expected
  production-side change; mention it in the report.
- **Give the lab three ways in.** The agent path is deterministic, the human path
  is the fastest safe gesture or control on this screen, and a visible fallback is
  always present. Choose them from inspection, not from a fixed menu
  (`references/activation.md`). Prefer an existing toolbar, debug menu, or
  developer menu. Otherwise use a fixed-position button. Activation chrome is
  development-only and must not move the feature: "opening changes nothing" is
  about the feature.
- **Find a free corner.** Before pinning the pill and panel, check which corners
  other development overlays already hold: TanStack Router or Query Devtools,
  the Next.js dev indicator, the Vercel toolbar, Storybook, the app's own help
  or chat widget. Pick a free corner, or stack above the overlay, and say which
  in the report. Never move or hide the other tool to make room.
- **Put every choice the tuning needs inside the lab.** When the target has
  variants the user picks between (a color theme, light or dark mode, a layout
  variant, a locale), add that picker to the panel, driving the app's real
  setting. The user must never leave the lab to choose what they are tuning,
  and above all never through a modal: modal libraries (Radix, Headless UI,
  MUI) make everything outside the open modal inert, the lab included. Give
  the lab root `pointer-events: auto` and render it in the top layer
  (`popover="manual"`) so it stays usable over any app modal that does open.
- **Keep the panel beside the feature and open while it is used.** Pin it to an
  edge or corner, never centered over the feature, and do not light-dismiss it:
  clicking or scrolling the feature is part of tuning. Close it with an explicit
  Close button and Escape. Give it the app's font and `color-scheme` so it stays
  readable in dark mode; styling it beyond that is optional.

When the feature is one child of a screen, the web host looks like this
(`HomeScreen.ui-tuning-lab.tsx` holds the lab; `TuningLabHost` is set inside the
DEV gate exactly as in `examples/web-floating-panel.md`):

```tsx
<main>
  <h1>Home</h1>
  {TuningLabHost
    ? <Suspense fallback={<CardList config={config} />}>
        <TuningLabHost config={config} setConfig={setConfig} />
      </Suspense>
    : <CardList config={config} />}
</main>
```

The lab module imports the host's props type with `import type`. That import is
erased at build time, so the two modules never import each other at runtime.

## Remember the activation

Record activation in `.ui-tuning-lab/lab.json` only when the user asks to
remember it, or when a reusable configuration already exists and the user
confirms. Use stable tokens, not prose:

```json
"activation": {
  "human": "shake",
  "agent": "-UITuningLabOpen 1",
  "fallback": "pill"
}
```

If no configuration exists and the user wants memory, create one from
`assets/labconfig.template.json` with the inferred target, scope, container,
baseline, and variants, then say the lab is now reusable. When the user picked
several human paths, store them as an array: `"human": ["shake", "toolbar-tune"]`. Read the stored
activation during setup; if it conflicts with the current screen, report the
conflict and ask before replacing it. Never write activation to a saved profile:
`verify.sh profile` rejects extra fields.

## Proceed or ask

Proceed without an interview when those choices are observable and safe. If one
material ambiguity remains, ask one focused question with concrete options and a
recommended default. Activation is asked separately and always, unless the
request or a fitting remembered `activation` already answers it: "How should the
lab open?" with the inspection-derived candidates, more than one selectable, and
shake recommended only when it is free (`references/activation.md`). When both
questions are needed, ask them in one prompt. Do not batch a questionnaire.

An ephemeral lab can live entirely in development-only state. Create
`.ui-tuning-lab/lab.json` only when the user wants a reusable profile or saved
configuration. A reusable configuration must pass
`sh <skill-dir>/scripts/verify.sh config`.

Stop only when the development gate cannot be established, the baseline cannot
be captured without changing production data, or the requested persistence would
overwrite a production key. Report the exact blocker and smallest decision needed.
