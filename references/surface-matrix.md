# Surface Matrix

Every row is guidance, not validation evidence. Prefer an app's existing native
transient surface when it satisfies teardown and accessibility requirements.

| Platform | Status | Candidate container | Candidate gate | Candidate activation |
|---|---|---|---|---|
| Web | candidate | conditionally mounted `popover="manual"` pinned to a corner, with Close and Escape, in a `*.ui-tuning-lab.tsx` module; accessible dialog fallback | dynamic `import()` inside `if (import.meta.env.DEV) {` or a production-env build guard, plus dead-code elimination | visible pill; `?ui-tuning-lab=1`; DEV-only keyboard shortcut |
| iOS/iPadOS | candidate | SwiftUI popover on regular width; adaptive sheet or deliberate popover on compact width | `#if DEBUG` or established internal-build flag | shake when free plus a visible pill or toolbar button; `-UITuningLabOpen 1` launch argument |
| macOS | candidate | lazily created `NSPanel` with `NSHostingView`; release content and observers on close | `#if DEBUG` menu/command | DEBUG menu command with key equivalent, visible pill; launch argument |
| Android | unvalidated adaptation | conditional `ModalBottomSheet` removed from composition | `BuildConfig.DEBUG` | existing developer menu or a visible debug button; keep the fallback |
| Windows | unvalidated adaptation | debug toolbar `Flyout` | `_DEBUG` | debug toolbar button plus a keyboard shortcut; keep the fallback |
| Flutter | unvalidated adaptation | removable `OverlayEntry`, `maintainState: false` | `kDebugMode` | existing developer menu or a visible debug button; keep the fallback |
| React Native | unvalidated adaptation | `__DEV__` conditional overlay via existing developer menu | `__DEV__` | the existing developer menu and shake; never a second shake listener |
| visionOS, Linux, HarmonyOS | unvalidated adaptation | derive from the platform's native nonmodal surface | platform build-type gate | platform debug menu plus a visible fallback; derive the agent path |

Closed means the UI is unmounted or released and all lab-owned timers, observers,
listeners, tasks, registrations, and alternate render trees are gone. Hidden or
transparent but mounted does not qualify.

Source gates are necessary but insufficient. Inspect the compiled Release archive
or production bundle and exercise the production entry points before completing a
validation receipt.
