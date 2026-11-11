# Surface Matrix

Prefer an app's existing native transient surface when it satisfies teardown
and accessibility requirements.

| Platform | Container | Gate | Activation |
|---|---|---|---|
| Web | conditionally mounted `popover="manual"` pinned to a corner, with Close and Escape, in a `*.ui-tuning-lab.tsx` module; accessible dialog fallback | dynamic `import()` inside `if (import.meta.env.DEV) {` or a production-env build guard, plus dead-code elimination | visible pill; `?ui-tuning-lab=1`; DEV-only keyboard shortcut |
| iOS/iPadOS | SwiftUI popover on regular width; adaptive sheet or deliberate popover on compact width | `#if DEBUG` or established internal-build flag | shake when free plus a visible pill or toolbar button; `-UITuningLabOpen 1` launch argument |
| macOS | lazily created `NSPanel` with `NSHostingView`; release content and observers on close | `#if DEBUG` menu/command | DEBUG menu command with key equivalent, visible pill; launch argument |
| Android | non-modal overlay panel removed from composition (a `ModalBottomSheet` blocks the feature) | lab files in `src/debug/`, or `BuildConfig.DEBUG` | existing developer menu or a visible debug button; keep the fallback |
| Windows | debug toolbar `Flyout` | `#if DEBUG` (C#; `_DEBUG` in C++) | debug toolbar button plus a keyboard shortcut; keep the fallback |
| Flutter | removable `OverlayEntry`, `maintainState: false` | `kDebugMode` | existing developer menu or a visible debug button; keep the fallback |
| React Native | `__DEV__` conditional overlay via existing developer menu | `__DEV__` | the existing developer menu and shake; never a second shake listener |
| visionOS, Linux, HarmonyOS | derive from the platform's native nonmodal surface | platform build-type gate | platform debug menu plus a visible fallback; derive the agent path |

Every platform carries the same handoff: chips, Undo, Redo, Reset, Save & pin and Save, Apply, the result
file, and the hint (`references/candidates.md`). How each one logs, reads, waits
for Done, stores candidates, and checks its gate is in
`references/platform-handoff.md`; worked adaptations are in
`examples/android-compose-sheet.md`, `examples/flutter-overlay.md`,
`examples/react-native-overlay.md`, and `examples/windows-flyout.md`.

Platforms with no worked example:

- **visionOS:** start from `examples/swiftui-popover-palette.md`; prefer an
  ornament or a separate window over a sheet, gate with `#if DEBUG`, and keep
  the `-UITuningLabOpen 1` launch argument and a visible fallback.
- **Linux (GTK, Qt):** a non-modal popover or tool window created on open and
  destroyed on close, a build-type gate (`#ifndef NDEBUG`, a debug Cargo
  feature), a command-line flag for the agent, and log lines on stderr or the
  journal with a `ui-tuning-lab` tag.
- **HarmonyOS (ArkUI):** a conditionally rendered bind sheet or popup, a debug
  build-mode gate, an agent path through `aa start` parameters, and `hilog`
  with a `ui-tuning-lab` tag read by `hdc hilog`.

Closed means the UI is unmounted or released and all lab-owned timers, observers,
listeners, tasks, registrations, and alternate render trees are gone. Hidden or
transparent but mounted does not qualify.

Source gates are necessary but insufficient. Inspect the compiled Release archive
or production bundle and exercise the production entry points before reporting
the lab safe.
