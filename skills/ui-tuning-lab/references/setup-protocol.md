# Inspect-First Setup Protocol

Inspect before asking. Read the app entry point, build configuration, feature
configuration model, presentation conventions, persistence layer, and nearby
tests. Record these working choices:

## Contents

- Labs already in the project
- Reuse an existing control surface
- Wire the host
- Run the fresh build
- Proceed or ask

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
- profiles: looks in memory unless named profiles were requested;
- baseline: the feature's declared default, the value it ships with (for example
  `CardStyle.appDefault` or `cardDefaults`). Never take it from the screen when the
  lab opens: the selected look survives closing, so a reopened lab would treat it
  as the original, Shipped would show it, and Copy values would miss earlier changes.
  When the shipped value is computed at runtime (from a theme, a server, or a
  device trait), the declared default is not what the user sees, and using it
  would make Shipped change the feature and Copy values report edits nobody made.
  Then capture the rendered value on the first open, before any lab edit, and keep
  it in a DEBUG-only store that outlives the panel (keeping one value is allowed;
  the teardown guarantee is about work and UI). Capture it again if its source
  changes while Shipped is selected, for example on a theme switch, and key
  the store to that source. Copy values reports against this captured baseline.

## Labs already in the project

Before writing a lab, search the source tree for lab markers: file names
containing `ui-tuning-lab` or `UITuningLab`, and host code that references a
`UITuningLab` or `uiTuningLab` symbol (for example
`grep -rlE 'UITuningLab|uiTuningLab|ui-tuning-lab' <source-dir>`, skipping build
output and dependencies). Also read `.ui-tuning-lab/result.json` and
`.ui-tuning-lab/lab.json` when they exist. A lab found this way was left behind
by earlier work: nobody landed it, or it was kept on purpose.

- **A lab for the same feature:** extend it, rather than writing a second one.
  Its kept `candidates` seed the new lab. Say in the report that you reused it.
- **A lab for another feature:** ask the user before writing anything. Name
  that lab by feature and file, say whether it has an unread pick (a
  `result.json` or a `UITUNINGLAB_DONE` line for it), and offer:
  1. **Remove it** (recommended when it has no pick): take out its file and host
     wiring per `references/landing-protocol.md`, step 3, so only the new lab
     runs.
  2. **Land it first:** finish that lab with its pick, then build the new one.
  3. **Keep both:** leave it in place; scope each lab's activation to its own
     feature (`references/activation.md`, "Screen cases", "More than one lab").

This question is always asked when another feature's lab is found, even when
the request mentions "the existing lab": that phrase comes from the request,
which may have been written by another agent, not from the user's choice. It
does not use up the one setup question, and it goes in the same prompt as the
setup and activation questions. If the user cannot be asked, keep the other lab
untouched, build the new one beside it with scoped activation, and name the
other lab in the report as still active.

## Reuse an existing control surface

Before building a panel, look for one the project already has:

| Signal | Use it as the control surface |
|---|---|
| `leva`, `tweakpane`, `lil-gui`, or `dat.gui` in `package.json` | that library's panel, mounted only in the development-only lab module |
| `@storybook/*` with the feature already in a story | Storybook controls (args), when the user is happy to tune in Storybook rather than in the running app |
| An in-house debug menu, drawer, or settings screen (search for `DebugMenu`, `DevMenu`, `InternalSettings`, `DeveloperSettings`) | a new entry in that menu that opens the lab |
| React Native `DevSettings.addMenuItem` or Flipper plugins | the existing developer menu |

Reuse changes only the control surface. The four guarantees, the naming rule, a
baseline, the chips, Undo, Redo, Reset, Save & pin, Apply with its hint, Copy values
(`references/candidates.md`), and landing still apply. When the tool cannot host
one of them (Storybook renders outside the running app, so its chips would not
show the real feature), add it as a plain button beside the library's panel or say
in the report what is missing, and a third-party panel
must be imported only from the gated lab module so it drops out of production.
If the existing tool cannot capture a baseline or unmount cleanly, build the
native panel instead and say why.

## Wire the host

- **Wrap the feature, not the screen.** Put the lab host exactly where the
  feature component is rendered. When the feature is one child of a larger screen
  (a card list under a heading), replace only that child with the host and keep
  its siblings untouched; the examples' whole-screen hosts are the simple case.
  The pill and panel are not part of that wrap: pin them to the screen or
  window (the web top layer, an iOS overlay, Flutter's `Overlay`, a Compose
  root box), so they stay in the corner even when the feature sits inside a
  scroll view.
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
  Alternative designs follow the same rule: a Design picker in the panel, never
  chips or tabs inserted into the screen (`references/design-variants.md`).
- **Keep the panel beside the feature and open while it is used.** Pin it to an
  edge or corner, never centered over the feature, and do not light-dismiss it:
  clicking or scrolling the feature is part of tuning. Close it with an explicit
  Close button and Escape. Give it the app's font and `color-scheme` so it stays
  readable in dark mode.
- **Make the panel its own surface.** A shadow alone disappears when the screen
  behind the panel has the same background, and flat themes drop it entirely.
  Draw a hairline outline (1px, 1dp, or 1pt) in the platform's stronger
  separator token — `GrayText` or `CanvasText` at low opacity on the web,
  `colorScheme.outline` on Flutter and Compose, `separatorColor` on SwiftUI —
  and keep it on the result bar too. A distinct surface tint or elevation may
  support the outline, never replace it. Keep any shadow static: animating
  elevation or adding a backdrop blur costs frames and buys nothing for the
  boundary. When the container already draws native chrome (an iOS sheet, a
  macOS panel window, a WinUI `Flyout`, a system dialog), verify that chrome
  instead of double-bordering it.
- **Phones.** On compact width (under about 600 points or dp), a corner panel
  covers the feature. Dock the panel full width at the bottom, at most about 45%
  of the screen tall, and leave the feature scrollable above it (on iOS, the
  short sheet in `references/ios-hosting.md`). When the feature itself lives at
  the bottom edge (a tab bar, bottom toolbar, floating button, input bar), dock
  the panel at the top instead, so it never covers what is being tuned
  (`references/ios-hosting.md`, "Features at the bottom edge"); the same rule
  holds for Android, Flutter, and React Native overlays.
- **Tabs and routes.** When the screen is one tab of a tab bar or one route of a
  stack, show the pill and panel only while that screen is visible, and keep
  the selected look while it is hidden.
- **Right-to-left apps.** The feature keeps the app's locale and direction;
  never change them for the lab. The panel's own labels may stay in English and
  left-to-right. Pick the pill's corner after mirroring, so it does not cover
  the feature's leading edge.

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

## Run the fresh build

An app that was already open when the lab was added keeps running the old
code: it has no lab, and the agent path or the user's shortcut does nothing.
Hot reload is not enough either, since the lab adds files, gates, and launch
handling. After every build that adds or changes the lab, before the smoke
launch and before **How to try it**:

1. **Quit every running copy.** Ask nothing; it is a development build.

   | Platform | Quit |
   |---|---|
   | macOS | `osascript -e 'quit app id "<bundle-id>"'`, then `pkill -x <ExecutableName>` if it is still running a few seconds later |
   | iOS Simulator | `xcrun simctl terminate booted <bundle-id>` |
   | Android (Compose, Flutter, React Native) | `adb shell am force-stop <package>` |
   | Flutter desktop | quit the app; stop the `flutter run` session |
   | Windows | `Stop-Process -Name <App> -ErrorAction SilentlyContinue` |
   | Web | stop and restart the dev server when its config or entry changed; otherwise reload every open tab of the app, not just the one you opened |

2. **Launch the new build**, with the agent path when it is the smoke launch:
   the exact product the build wrote (macOS: `open -n <path>/<App>.app --args
   -UITuningLabOpen 1` from the build's own products directory, never an older
   copy in `/Applications`; iOS: `xcrun simctl install booted <App>.app`, then
   `simctl launch`; Android: install, then `am start -S`; Flutter and React
   Native: a full restart or a new `run`).
3. **Confirm it is the new one.** The process must have started after the
   build finished: compare its start time (`ps -o lstart= -p <pid>`) or its new
   process ID with the one you quit, and the binary's modification time with
   the build. On the web, the lab's toggle must be in the page you load. If it
   is not, quit and launch again before going on; never hand over a stale app.
4. Leave the fresh build running for the user, the lab closed (or open, when
   the smoke launch leaves it open on purpose), and say in **How to try it**
   that the app on screen is the new build.

## Proceed or ask

Proceed without an interview when those choices are observable and safe. If one
material ambiguity remains, ask one focused question with concrete options and a
recommended default. Activation is asked separately and always, unless the
request or a fitting remembered `activation` already answers it: "How should the
lab open?" with the inspection-derived candidates, more than one selectable, and
shake recommended only when it is free (`references/activation.md`). When both
questions are needed, ask them in one prompt. A lab for another feature found
during inspection adds its own question to that prompt ("Labs already in the
project"). Do not batch a questionnaire.

An ephemeral lab can live entirely in development-only state. Create
`.ui-tuning-lab/lab.json` only when the user wants a reusable profile or saved
configuration. A reusable configuration must pass
`sh <skill-dir>/scripts/verify.sh config`.

Stop only when the development gate cannot be established, the baseline cannot
be captured without changing production data, or the requested persistence would
overwrite a production key. Report the exact blocker and smallest decision needed.
