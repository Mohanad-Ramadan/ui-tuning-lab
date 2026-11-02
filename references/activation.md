# Activation: How the Lab Opens

Activation is how the human and the agent open the lab. It is part of the lab's
design, not an afterthought. Read this before building the panel. This is lab
activation, not the skill's trigger: whether the skill loads for a request is a
separate description-and-evaluation concern.

## The three paths

Every lab has three ways in:

| Path | Purpose | Requirement |
|---|---|---|
| Agent | The agent launches the lab deterministically to tune, screenshot, adjust | Development-only, documented, no shipped URL scheme |
| Human | The fastest path, or paths, for the person on the screen being tuned | Chosen by the user from inspection-derived candidates; shake only when it is free |
| Fallback | A visible way in when the gesture fails or a screen reader is used | Always present; never hidden |

The fallback is not optional. A gesture-only lab is inaccessible and
unrecoverable when the gesture dies.

## Inspect before choosing

Record these during setup:

- An existing debug menu, developer menu, or settings screen (`DebugMenu`,
  `DevMenu`, `InternalSettings`, `DeveloperSettings`, React Native
  `DevSettings.addMenuItem`, Flipper).
- A toolbar, navigation bar, or tab bar.
- A full-bleed canvas, game, camera, or gesture-driven screen.
- Text inputs on the screen being tuned.
- Existing motion handling: `motionEnded`, `EventSubtype.motionShake`, shake
  recognizers or observers, `UIApplicationSupportsShakeToEdit`, and shake-based
  SDKs such as the React Native developer menu or Instabug.
- The number of labs in the app.
- Simulator or device, and whether a hardware keyboard is available.
- The accessibility paths the app already uses.

Shake is free only when none of these conflict. Detection is heuristic; when it
is ambiguous, ask instead of guessing.

## Ask how the lab opens

Always ask "How should the lab open?" Skip it only when the user's request
already names the human path, or a remembered `activation` in
`.ui-tuning-lab/lab.json` still fits the screen. An existing debug menu or a
clear toolbar convention does not skip the question; it becomes the
recommendation.

- Recommend the best candidate for this screen, with a one-line reason.
- Offer up to three alternatives that inspection actually found.
- Let the user pick more than one. Use a multi-select question when the asking
  tool supports it; otherwise offer the sensible combination as its own option,
  for example "Shake + toolbar Tune button" when shake is free and the screen has
  a toolbar.
- Do not pad the list; two options are fine.
- Do not offer a candidate that conflicts with the inspection.
- Ask only about human paths. The agent path and the visible fallback are always
  built and are not options.

Activation is material because it changes both the implementation and daily
use, so it is asked in addition to the single setup question in
`references/setup-protocol.md`, never in place of it. When both are needed, put
them in the same prompt rather than asking twice.

Build every human path the user picks. A visible one, such as a toolbar Tune
button, also serves as the fallback; when every pick is a gesture or a shortcut,
add the pill.

## Screen cases

| Screen case | Recommend | Alternatives |
|---|---|---|
| No text input, no motion handling, single lab | Shake | Visible pill · keyboard shortcut · long-press active tab |
| Search field or form focused | Visible pill or keyboard shortcut | Toolbar · long-press active tab; never shake |
| NavigationStack with a toolbar | Toolbar Tune button | Shake · visible pill · keyboard shortcut |
| Tab-bar app | Long-press the active tab | Shake · visible pill · keyboard shortcut |
| Full-bleed canvas or game | Visible pill and the agent path | Shake if free · keyboard shortcut |
| Existing debug menu | The existing menu entry | Shake · visible pill |
| A sheet is already open | The parent screen's path | Never stack a second sheet |
| More than one lab | A picker, or scope the path to the visible feature | Shake scoped to that feature |

When the recommendation is shake, still implement the visible fallback. The table
recommends the fast path; it never removes the fallback. Any recommendation can
be combined with a free alternative from its row when the user picks both.

## Platform candidates

### iOS and iPadOS

- Shake, when free. In the Simulator, Device > Shake (⌃⌘Z).
- A toolbar Tune button.
- A long-press on the active tab.
- A small floating pill with explicit colors, pinned to the full screen rather
  than to a content-sized feature view (`references/ios-hosting.md`).
- ⌥⌘L on iPad, a hardware keyboard, or the Simulator.
- The `-UITuningLabOpen 1` launch argument for the agent.

### Web

- A floating pill pinned to a corner.
- An existing debug menu.
- A keyboard shortcut such as `Control+Shift+L`, registered only in the
  development-gated lab module.
- `?ui-tuning-lab=1` for the agent, parsed only inside the development gate.
- No URL scheme is needed.

### macOS

- A `#if DEBUG` menu command with a key equivalent.
- A floating pill.
- The `-UITuningLabOpen 1` launch argument, consumed when the first window
  appears.
- An existing debug menu.

### Other platforms

Android, Windows, Flutter, and React Native are unvalidated adaptations. Reuse
the platform's developer menu, keep the fallback visible, and keep every handler
behind the platform gate. React Native already owns shake through its developer
menu; do not add a second shake listener.

## Shake rules

- It is app code, not a SwiftUI modifier. There is no `.onShake`.
- It is DEBUG-only, marker-named (`UITuningLab…`, `uiTuningLab…`), and inside
  the development gate.
- Put the handler in the responder chain. A DEBUG-only hosting controller or a
  window subclass works; prefer the least invasive option that receives the
  event.
- Call `super.motionEnded` when the lab does not handle the event.
- Let the system win when a text input is first responder. Shake-to-undo belongs
  to the text field; do not override it at window level just to open the lab.
- Re-arm after the lab closes if the responder lost first responder.
- Do not install an observer or timer just for activation. If one is needed,
  remove it on close.
- With more than one lab, scope shake to the visible feature or show a picker;
  never silently open an arbitrary lab.
- On first use, print one hint line or put the hint in the report. Do not add
  permanent chrome for discoverability.
- Shake is never the only path. The visible fallback is required.

## Agent path rules

- **Honor the request once.** Consume it the first time it is read, so a
  re-pushed screen, a second window, a remount, or a reload does not reopen the
  lab.
- **iOS:** read `UserDefaults.standard.bool(forKey: "UITuningLabOpen")` inside
  `#if DEBUG`, so `-UITuningLabOpen 0` stays closed, and consume it in
  `onAppear`; launch with
  `xcrun simctl launch booted <bundle-id> -UITuningLabOpen 1`. Do not add a URL
  scheme: a scheme declared in `Info.plist` is registered in Release even when
  its handler is gated.
- **Web:** parse `?ui-tuning-lab=1` only inside the development-gated host, then
  remove it with `history.replaceState` once the lab has opened.
- **macOS:** read the same `UserDefaults` key inside `#if DEBUG` and open one
  panel when the first window appears; keep the `#if DEBUG` menu command and key
  equivalent as the human path and visible fallback. Launch with
  `open <App>.app --args -UITuningLabOpen 1`.
- The agent cannot shake: `simctl` has no shake command, and UI scripting needs
  focus and accessibility permissions. Do not make the agent depend on it.
- Release inspection must confirm the launch argument, its handler, and its
  strings are gone.

## Remember the choice

A project can remember its activation in `.ui-tuning-lab/lab.json`:

```json
"activation": {
  "human": "shake",
  "agent": "-UITuningLabOpen 1",
  "fallback": "pill"
}
```

- Read it during setup. If it conflicts with the current screen, report the
  conflict and ask before changing it.
- Write it only when the user asks to remember the entry point, or when a
  reusable `lab.json` already exists and the user confirms.
- If no `lab.json` exists and the user wants memory, create one from
  `assets/labconfig.template.json` with the inferred target, scope, container,
  baseline, and variants. This turns the lab into a reusable configuration; say
  so in the report.
- Use stable tokens, not prose. Suggested human values: `shake`,
  `toolbar-tune`, `long-press-active-tab`, `pill`, `debug-menu`. Suggested agent
  values: `-UITuningLabOpen 1`, `?ui-tuning-lab=1`, `menu:View > Tune UI`.
- `human` is one token or, when the user picked several, an array of distinct
  tokens: `"human": ["shake", "toolbar-tune"]`.
- `verify.sh config` checks the object when it is present. Configs without it
  remain valid.
- Do not put activation in a saved profile. `verify.sh profile` rejects extra
  fields.

## Verify

The hands-on and release checks are in `references/verify-protocol.md`. At
minimum, exercise the agent path, every chosen human path, and the visible
fallback; confirm that a focused text field keeps shake-to-undo; confirm that
VoiceOver or Switch Control can reach the fallback; and confirm that the human
path works again after the lab closes.
