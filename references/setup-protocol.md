# Inspect-First Setup Protocol

Inspect before asking. Read the app entry point, build configuration, feature
configuration model, presentation conventions, persistence layer, and nearby
tests. Record these working choices:

- target: feature unless the request explicitly names the container;
- scope: only the animation, layout, appearance, or visible logic requested;
- container: the existing platform-native transient surface nearest the feature;
- gate: the project's development, DEBUG, internal, or tester mechanism;
- persistence: none unless the user asks to save or reuse profiles;
- profiles: one working draft unless named profiles were requested;
- baseline: a copy of the configuration currently rendered by the feature.

## Reuse an existing control surface

Before building a panel, look for one the project already has:

| Signal | Use it as the control surface |
|---|---|
| `leva`, `tweakpane`, `lil-gui`, or `dat.gui` in `package.json` | that library's panel, mounted only in the development-only lab module |
| `@storybook/*` with the feature already in a story | Storybook controls (args), when the user is happy to tune in Storybook rather than in the running app |
| An in-house debug menu, drawer, or settings screen (search for `DebugMenu`, `DevMenu`, `InternalSettings`, `DeveloperSettings`) | a new entry in that menu that opens the lab |
| React Native `DevSettings.addMenuItem` or Flipper plugins | the existing developer menu |

Reuse changes only the control surface. The four guarantees, the naming rule, a
captured baseline, Copy values, and landing still apply, and a third-party panel
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
- **Place the trigger so it moves nothing.** Prefer an existing toolbar, debug
  menu, or developer menu. Otherwise use a fixed-position button. Development-only
  trigger chrome is allowed: "opening changes nothing" is about the feature.
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

## Proceed or ask

Proceed without an interview when those choices are observable and safe. If one
material ambiguity remains, ask one focused question with concrete options and a
recommended default. Do not batch a questionnaire.

An ephemeral lab can live entirely in development-only state. Create
`.ui-tuning-lab/lab.json` only when the user wants a reusable profile or saved
configuration. A reusable configuration must pass
`sh <skill-dir>/scripts/verify.sh config`.

Stop only when the development gate cannot be established, the baseline cannot
be captured without changing production data, or the requested persistence would
overwrite a production key. Report the exact blocker and smallest decision needed.
