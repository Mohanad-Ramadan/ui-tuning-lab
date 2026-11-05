# Unvalidated adaptations — index

None of these has been compiled or run in this repository, and none is
validation evidence. Each needs the full protocol (`references/verify-protocol.md`)
and the manual gate check in `references/platform-handoff.md` on the target
stack before anyone relies on it.

| Platform | Example | Container · gate · agent path |
|---|---|---|
| Android (Compose) | `examples/android-compose-sheet.md` | non-modal corner panel · `src/debug/` source set · `--ez UITuningLabOpen true` |
| Flutter | `examples/flutter-overlay.md` | `OverlayEntry`, `maintainState: false` · `kDebugMode` · `--dart-define=UITUNINGLAB_OPEN=true` |
| React Native | `examples/react-native-overlay.md` | absolutely positioned `View` · `__DEV__` `require()` · Metro-time variable or `__DEV__` global |
| Windows (WinUI 3) | `examples/windows-flyout.md` | `Flyout` on a debug toolbar button · `#if DEBUG` · `--ui-tuning-lab-open` |

Remaining one-liners, with no worked example yet:

- visionOS: start from `examples/swiftui-popover-palette.md`; prefer an
  ornament or a separate window over a sheet, gate with `#if DEBUG`, and keep
  the `-UITuningLabOpen 1` launch argument and a visible fallback.
- Linux (GTK, Qt): a non-modal popover or tool window created on open and
  destroyed on close, a build-type gate (`#ifndef NDEBUG`, a debug Cargo
  feature), a command-line flag for the agent, and log lines on stderr or the
  journal with a `ui-tuning-lab` tag.
- HarmonyOS (ArkUI): a conditionally rendered bind sheet or popup, a debug
  build-mode gate, an agent path through `aa start` parameters, and `hilog`
  with a `ui-tuning-lab` tag read by `hdc hilog`.
