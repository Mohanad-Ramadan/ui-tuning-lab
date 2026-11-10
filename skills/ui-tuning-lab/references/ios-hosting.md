# iOS Hosting: Panels, Activation, and UIKit or Hybrid Apps

Read this when the lab runs on iPhone or iPad, or the app is UIKit or a mix of
UIKit and SwiftUI. The SwiftUI examples assume a `NavigationStack` toolbar and a
popover; many real apps have neither.

## Contents

- The panel on iPhone: a short sheet with tabs
- Features at the bottom edge: dock the panel at the top
- Activation: agent path, human path, fallback
- UIKit hosts
- New files must join the Xcode target
- `#if DEBUG` inside a view builder

## The panel on iPhone: a short sheet with tabs

A popover becomes a sheet on compact width, and a long `Form` sheet covers the
feature. Instead:

- Open the controls in a short sheet, about a third of the screen (320 pt), and
  let the user drag it taller. Never ship a single fixed detent: a sheet that
  cannot grow cuts off its last rows, and the user cannot reach them. Bind the
  selection so it always opens short:

  ```swift
  @State private var uiTuningLabDetent = PresentationDetent.height(320)
  // On the presented controls:
  .presentationDetents([.height(320), .medium, .large], selection: $uiTuningLabDetent)
  .presentationBackgroundInteraction(.enabled(upThrough: .medium))
  .presentationDragIndicator(.visible)
  ```

  The feature stays usable behind the short and medium sheet. `.large` is for
  reading every control at once.
- Budget rows for the short sheet. The tab header, grabber, `Form` insets, and
  home indicator take about 110 pt, so 320 pt leaves about 210 pt. A labeled
  slider (title and value above the slider) is about 70 pt in a `Form`, so **at
  most three sliders per tab**. A toggle, button, or single-line picker is about
  44 pt. Past that budget, split the controls into tabs (a segmented `Picker`):
  for example Layout, Animation, and Actions. Rows past the budget stay
  reachable by dragging the sheet taller, never only by scrolling a 320 pt
  sheet.
- Put a **Close** button in the tab header row and keep drag-to-dismiss. Close is
  required: drag alone is not discoverable and VoiceOver users need a button.
- Check the largest preset's layout with the lab open: during the tuning session,
  or when the user asks for a self-review, not as a screenshot sweep before
  handover. If the feature grows into the area under the sheet, move the
  feature's preview up or note the overlap in the report; never hide part of the
  feature silently.
- When a self-review is requested, screenshot **every tab** at the short detent
  and confirm its last row is fully visible. Then open the lab at `.large` (set
  `uiTuningLabDetent = .large` for one run, or drag the grabber) and screenshot
  that too. A tab whose last row is cut at 320 pt means the row budget was
  exceeded: split the tab. During a normal handover, the row budget is a
  static layout decision; do not tour the tabs first.

On iPad (regular width), keep the popover from the examples.

## Features at the bottom edge: dock the panel at the top

A bottom sheet covers whatever lives at the bottom of the screen: a tab bar, a
bottom toolbar, a floating action button, a composer or input bar, a mini
player. When the tuned feature is one of those, never use the sheet; the user
would tune a bar they cannot see. Dock the panel at the top instead, as a
non-modal card in the root view's overlay, mounted only while open:

```swift
.overlay(alignment: .top) {
  if showUITuningLab {
    UITuningLabPanel(...)                 // the same tabs and controls as the sheet
      .frame(maxHeight: 360)              // about 40% of the screen; scrolls inside
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
      .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.separator))
      .padding(.horizontal, 8)
      .transition(.move(edge: .top).combined(with: .opacity))
  }
}
```

- Attach it above the feature (on the `TabView` or the app's root), so it floats
  over the navigation bar and top content and leaves the bottom edge visible.
- Keep Close in the header row; the row budget is the short sheet's. Put the
  pill near the top trailing corner, clear of the navigation bar's buttons.
- With a UIKit host, present the panel from the top of the key window the same
  way, never as a `.pageSheet`.
- **Replacing the system tab bar** (a custom-bar design): hide the system bar
  from inside each tab's content, where SwiftUI reads it, never on the
  `TabView` itself, which has no effect:

  ```swift
  Tab(value: tab) {
    makeTabContent(for: tab)
      .toolbarVisibility(replaces ? .hidden : .automatic, for: .tabBar)
  } label: { ... }
  ```

  Then draw the custom bar once, in a bottom overlay or `safeAreaInset` on the
  `TabView`.

## Activation: agent path, human path, fallback

Choose activation from inspection (`references/activation.md`). The lab needs all
three paths, and the visible fallback is not optional: a shake-only lab is
inaccessible and unrecoverable when the gesture dies.

- **Agent path.** Read `UserDefaults.standard.bool(forKey: "UITuningLabOpen")`
  inside `#if DEBUG`, consume it once in `onAppear`, and launch with
  `xcrun simctl launch booted <bundle-id> -UITuningLabOpen 1`.
  Do not add a URL scheme: a scheme declared in `Info.plist` is registered in
  Release even when its handler is gated. The launch argument leaves nothing
  registered.
- **Human path.** Reuse an existing toolbar or debug menu. Shake only when
  inspection proves it free: no `motionEnded`, shake observer, or shake
  recognizer; no SDK that owns shake (React Native's developer menu, Instabug);
  no text input on the target screen; and one unambiguous lab. The user may pick
  both: keep the toolbar `<Feature> Lab` button, which then doubles as the fallback, and add
  the shake shim from the `variant=shake` example.
- **Fallback.** A small visible button or pill with explicit colors, for example
  white text on `.ultraThinMaterial`. It is the VoiceOver, Switch Control, and
  recovery path, and the thing to inspect when a self-review is requested. Apps
  often set an accent color that matches their background, which makes a default
  `Button` invisible.
  Pin it to the full screen, not to the feature: a feature view is often only as
  tall as its content, so an `.overlay(alignment: .bottomTrailing)` on it lands
  mid-screen, under other layers, or outside a hosted view's bounds. Attach the
  pill to the outermost view of the screen, after
  `.frame(maxWidth: .infinity, maxHeight: .infinity)`, and keep it inside the
  safe area. In a SwiftUI view hosted by a UIKit controller
  (`UIHostingController` added as a child), that outermost view is the hosted
  root view.

Shake is app code, not a SwiftUI modifier. There is no `.onShake`. The shim below
is DEBUG-only, calls `super.motionEnded`, leaves shake-to-undo to a focused text
input, and re-arms when the lab closes. Put the exact outer gate first and nest
`#if canImport(UIKit)` inside it; `source-gates` accepts that shape.

```swift
#if DEBUG
#if canImport(UIKit)
import SwiftUI
import UIKit

/// A zero-sized first-responder shim for shake-to-open. It never takes focus
/// from a text input and re-arms after the lab closes.
struct UITuningLabShakeReader: UIViewControllerRepresentable {
    let isLabOpen: Bool
    let onShake: () -> Void

    func makeUIViewController(context: Context) -> UITuningLabShakeController {
        let controller = UITuningLabShakeController()
        controller.onShake = onShake
        controller.isLabOpen = isLabOpen
        return controller
    }

    func updateUIViewController(_ controller: UITuningLabShakeController, context: Context) {
        controller.onShake = onShake
        controller.isLabOpen = isLabOpen
        controller.armIfNeeded()
    }
}

final class UITuningLabShakeController: UIViewController {
    var onShake: (() -> Void)?
    var isLabOpen = false

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        armIfNeeded()
    }

    /// Becomes first responder only when nothing else owns focus.
    func armIfNeeded() {
        guard !isLabOpen, !uiTuningLabHasFocusedTextInput, !isFirstResponder,
              view.window != nil else { return }
        becomeFirstResponder()
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard motion == .motionShake, !isLabOpen, !uiTuningLabHasFocusedTextInput else {
            return super.motionEnded(motion, with: event)
        }
        onShake?()
    }

    private var uiTuningLabHasFocusedTextInput: Bool {
        view.window?.uiTuningLabFirstResponder is UITextInput
    }
}

private extension UIView {
    var uiTuningLabFirstResponder: UIResponder? {
        if isFirstResponder { return self }
        for subview in subviews {
            if let responder = subview.uiTuningLabFirstResponder { return responder }
        }
        return nil
    }
}
#endif
#endif
```

Attach it with `.background { UITuningLabShakeReader(...).frame(width: 0, height: 0) }`
so it occupies no layout, and keep the fallback on screen. `simctl` has no
shake command, which is why the launch argument exists. Unless the agent's own
simulator tool shook the device, shake stays unverified by the agent: the report
must say so and give the user the exact check with the keys read from the host
they are looking at (`references/activation.md`, "Tell the user how to shake"),
for example "Press <the keys you found>, or choose Device > Shake, on the Who's
Watching screen; the lab should open." Never report shake as working without
the user's confirmation or the agent's own shake.

- When a self-review is requested, confirm in a screenshot that the visible
  fallback is on screen and that tapping it opens the lab. `source-gates` cannot
  see a control that never renders.
- If shake is not free, skip the shim and use the screen-appropriate human path;
  never force shake over a focused text field's undo.

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
        // Opens short; the user can drag it taller to reach every control.
        sheet.detents = [.custom(identifier: compact) { _ in 320 }, .medium(), .large()]
        sheet.selectedDetentIdentifier = compact
        sheet.largestUndimmedDetentIdentifier = .medium   // the feature stays usable
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
    .toolbar { /* lab activation */ }
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
