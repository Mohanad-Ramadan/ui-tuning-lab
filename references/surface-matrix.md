# Surface Matrix

Every row is guidance, not validation evidence. Prefer an app's existing native
transient surface when it satisfies teardown and accessibility requirements.

| Platform | Status | Candidate container | Candidate gate |
|---|---|---|---|
| Web | candidate | conditionally mounted `popover="auto"`; accessible dialog fallback | `import.meta.env.DEV` or production-env build guard plus dead-code elimination |
| iOS/iPadOS | candidate | SwiftUI popover on regular width; adaptive sheet or deliberate popover on compact width | `#if DEBUG` or established internal-build flag |
| macOS | candidate | lazily created `NSPanel` with `NSHostingView`; release content and observers on close | `#if DEBUG` menu/command |
| Android | unvalidated adaptation | conditional `ModalBottomSheet` removed from composition | `BuildConfig.DEBUG` |
| Windows | unvalidated adaptation | debug toolbar `Flyout` | `_DEBUG` |
| Flutter | unvalidated adaptation | removable `OverlayEntry`, `maintainState: false` | `kDebugMode` |
| React Native | unvalidated adaptation | `__DEV__` conditional overlay via existing developer menu | `__DEV__` |
| visionOS, Linux, HarmonyOS | unvalidated adaptation | derive from the platform's native nonmodal surface | platform build-type gate |

Closed means the UI is unmounted or released and all lab-owned timers, observers,
listeners, tasks, registrations, and alternate render trees are gone. Hidden or
transparent but mounted does not qualify.

Source gates are necessary but insufficient. Inspect the compiled Release archive
or production bundle and exercise the production entry points before completing a
validation receipt.
