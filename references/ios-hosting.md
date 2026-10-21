# iOS Hosting: Panels, Triggers, and UIKit or Hybrid Apps

Read this when the lab runs on iPhone or iPad, or the app is UIKit or a mix of
UIKit and SwiftUI. The SwiftUI examples assume a `NavigationStack` toolbar and a
popover; many real apps have neither.

## The panel on iPhone: a short sheet with tabs

A popover becomes a sheet on compact width, and a long `Form` sheet covers the
feature. Instead:

- Present the controls in a sheet with one small fixed detent, about a third of
  the screen (270–320 pt; the iOS example uses 320):
  `.presentationDetents([.height(320)])`.
- Keep the feature usable behind it:
  `.presentationBackgroundInteraction(.enabled(upThrough: .height(320)))`.
- Keep each screen of controls within the detent. A handful of rows (the iOS
  example) fits in one `Form`; beyond about six rows, split the controls into
  tabs (a segmented `Picker`): for example Layout, Animation, and Actions. With a
  single detent the sheet cannot grow, so anything below the fold is reachable
  only by scrolling inside it.
- Put a **Close** button in the tab header row and keep drag-to-dismiss. Close is
  required: drag alone is not discoverable and VoiceOver users need a button.
- Check the largest preset in a screenshot. If the feature grows into the area
  under the sheet, move the feature's preview up or note the overlap in the
  report; never hide part of the feature silently.

On iPad (regular width), keep the popover from the examples.

## The trigger: visible, and on screen

- The trigger is DEBUG-only chrome, so it may add a button, but it must not move
  the feature. Prefer an existing navigation bar or debug menu. In SwiftUI
  without a `NavigationStack`, use `.overlay(alignment:)` or `.safeAreaInset`; in
  UIKit, add a `UIBarButtonItem` or a small fixed button in `viewDidLoad`, inside
  `#if DEBUG`.
- Give it explicit colors (for example white text on `.ultraThinMaterial`). Apps
  often set an accent color that matches their background, which makes a default
  `Button` invisible.
- Confirm in a screenshot that the trigger is visible and that tapping it opens
  the lab. `source-gates` cannot see a trigger that never renders.

## UIKit hosts

Keep the configuration in an object both sides observe, wrap the SwiftUI controls
in a `UIHostingController`, and present it as a sheet (custom detents need
iOS 16 or later):

```swift
#if DEBUG
/// The view controller applies `style` on every change; the controls edit it.
final class UITuningLabModel: ObservableObject {
    @Published var style = CardStyle.appDefault
}

// In the view controller:
private let uiTuningLabModel = UITuningLabModel()
private var uiTuningLabSubscription: AnyCancellable?

private func observeUITuningLab() {   // call from viewDidLoad
    uiTuningLabSubscription = uiTuningLabModel.$style
        .sink { [weak self] style in self?.apply(style) }  // re-layout, restart animation
}

@objc private func openUITuningLab() {
    // The controls take `@ObservedObject var model: UITuningLabModel` and bind
    // `$model.style`; the baseline is the declared default.
    let controls = UIHostingController(rootView: UITuningLabControls(
        model: uiTuningLabModel, baseline: .appDefault))
    if let sheet = controls.sheetPresentationController {
        let compact = UISheetPresentationController.Detent.Identifier("uiTuningLabCompact")
        sheet.detents = [.custom(identifier: compact) { _ in 270 }]
        sheet.largestUndimmedDetentIdentifier = compact   // the feature stays usable
        sheet.prefersGrabberVisible = true
    }
    present(controls, animated: true)
}
#endif
```

Closure `Binding`s to plain properties do not redraw a hosted view; observe an
object instead, as above and in `examples/macos-panel-minimal.md`.

## New files must join the Xcode target

Projects that list files explicitly in `project.pbxproj` ignore new files until
they are added to the app target. Check first:

```sh
grep -c PBXFileSystemSynchronizedRootGroup "<App>.xcodeproj/project.pbxproj"
```

A non-zero count means the project uses folder-synchronized groups (Xcode 16 and
later), so files placed in a synchronized folder can be picked up automatically.
Still confirm that the folder belongs to the app target and has no membership
exception for the new files. Otherwise add each
lab file to the app target, either in Xcode or with the `xcodeproj` Ruby gem,
then confirm it compiles: the Debug build log lists it, and a lab symbol appears
in the Debug binary (`nm` or `strings`). Never add lab files to a Release-only
target or an extension target.

## `#if DEBUG` inside a view builder

`#if` can wrap whole statements, or a run of modifiers after an expression:

```swift
CardFeature(style: style)
    #if DEBUG
    .toolbar { /* lab trigger */ }
    #endif
```

It cannot wrap the leading expression and leave shared modifiers outside. That
form does not compile:

```swift
#if DEBUG
labHost
#else
CardFeature(style: style)
#endif
    .padding()   // error
```

Move the branch into a computed property, and apply shared modifiers to that:

```swift
@ViewBuilder private var content: some View {
    #if DEBUG
    labHost
    #else
    CardFeature(style: style)
    #endif
}
// body: content.padding()
```
