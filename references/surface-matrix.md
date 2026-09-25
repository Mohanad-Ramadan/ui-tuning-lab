# Surface Matrix — lightest container per platform

Tier labels: `verified` (full protocol + example), `minimal` (teardown +
one toggle smoke-tested), `community` (stub, unverified — confirm teardown
on your stack and report back).

| Platform | Tier | Container | Toggle / gate |
|---|---|---|---|
| Web | verified | `<div popover="auto">` + `popovertarget`, conditionally mounted; fallback `<details><summary>` | `?lab=1` / `localStorage` / `Ctrl+Shift+L`, `DEV`-only mount |
| SwiftUI iOS/iPadOS | verified | `.popover` iPad, `.sheet(detents)` iPhone compact, `presentationCompactAdaptation(.popover)` to force popover | `#if DEBUG` + shake / triple-tap / `Cmd+Shift+L` |
| macOS | minimal | Borderless nonactivating `NSPanel` + `NSHostingView`, `orderOut` on hide | `#if DEBUG` hotkey + `Window > UI Tuning Lab` menu |
| Android | minimal | Conditional `ModalBottomSheet`, removed from composition on hide | `BuildConfig.DEBUG` + shake / dev-drawer entry |
| Windows | community | `Flyout` on debug toolbar button (WinUI 3) | `_DEBUG` + `Ctrl+Shift+L` |
| Flutter | community | `OverlayEntry` + `remove()`, `maintainState=false` | `kDebugMode` |
| RN | community | `DevSettings.addMenuItem` + `__DEV__`-gated overlay | Shake / `Cmd+M` dev menu |
| visionOS | community | Ornament or secondary spatial window; no shake, no popover-arrow guarantees | DEBUG gate + window-attached toggle |
| Linux desktop | community | Web row for Tauri/Electron; debug-gated dialog destroyed on close for native GTK/Qt | DEV or debug-build gate per stack |
| HarmonyOS | community | Conditional sheet mirroring the Android row, removed on hide | Build-type DEBUG gate |

## Closed teardown (all platforms)

Closed = unmounted or removed from the tree, plus timers cancelled,
observers disconnected, listeners released. `display:none`,
`Opacity(0)`, or hidden-but-mounted is NOT closed.

## Forbiddens

- Web: `popover="manual"`, hidden-but-mounted DOM, patching `fetch`.
- SwiftUI: `.fullScreenCover` for the lab, persistent `GeometryReader` wrapper.
- macOS: modal sheet blocking the tuned window, main-window hosting.
- Android: persistent `BottomSheetScaffold`, always-on non-modal sheet.
- Windows: `ContentDialog` for the lab (modal, 1/thread), separate `Window` for simple labs.
- Flutter: `Opacity(0)` always-mounted panel, `maintainState:true`.
- RN: custom JS shake listener in release, always-on `Modal` lab.
- visionOS: iPad popover geometry applied to spatial windows, shake to toggle.
- Linux: lab shipped in the production bundle with no treeshake proof, persistent native dialog.
- HarmonyOS: always-composed sheet, release shake listener.

## Web prod-strip

Web has no `DEBUG` macro. Gate with `import.meta.env.DEV` or
`process.env.NODE_ENV !== "production"` plus dead-code elimination so the
bundler treeshakes the lab. Prove with `scripts/verify.sh --prod`.

## Out of scope

- Game engines (Unity/Unreal): different render loop and editor-driven
  workflow. A lab there is a separate skill, not a matrix row.
- watchOS / tvOS: no room for a lab alongside the feature (watch);
  focus-engine interaction breaks tap-outside assumptions (tv). Detached
  container-tuning only, no full rows.
- TUI / CLI: no graphical surface to tune. Outside the activation contract
  by definition.
