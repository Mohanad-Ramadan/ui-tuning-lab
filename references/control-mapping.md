# Control Mapping

Pick each control from the kind of value it edits, not from what is easiest to
build. Ranges run from the smallest sensible value (usually 0 for radius, gap,
and padding) to two or three times the baseline (the examples use 32 for a
radius of 12), and use a step that lands clean values. Generating controls from
a list of fields is fine; keep each one labelled.

| Value | Control | Notes |
|---|---|---|
| Length, radius, spacing, size | Slider with `step: 1` (points or px) | Show the current number next to the label; hide that readout from assistive technology, since the slider already reports its value. |
| Opacity, scale, ratio | Slider `0...1` (or `0.5...2` for scale) with `step: 0.05` | Values land with two decimals. |
| Color | Native color picker (`ColorPicker`, `<input type="color">`) | Land the token name when the app uses tokens; ask before introducing a raw color. |
| Enum or style choice | Segmented control or picker | One option per case; never free text. |
| Boolean | Toggle | |
| Duration | Slider in the app's unit (seconds in SwiftUI, ms on the web) | Pair with Replay and Speed. |
| Spring | Duration (or response) plus bounce (or damping) sliders | Pair with Replay and Speed; see `examples/animation-spring.md`. |
| Easing | Presets (ease-in-out, ease-out, linear, spring) plus a custom cubic-bézier only if requested | |
| Text length | Sample copy: short, typical, long, overflowing | Tests truncation and wrapping without editing strings. |
| UI state | Forced state picker: empty, loading, error, success | Drive the feature's real state, never a mock view. |
| Alternative design | **Design** picker at the top of the panel: Shipped (the `original` design) first, then one option per variant | A `design` string in the draft; see `references/design-variants.md`. Never in the feature's layout. |

## Required in every lab

- **Presets**: at least two meaningful presets that differ clearly from the
  baseline and from each other.
- **Chips, Pin, and Choose**, with the hint line: see
  `references/candidates.md`. The Shipped chip is the baseline flip; while it
  is shown the controls are disabled, so an edit never lands on the baseline.
  The draft chip ("Shipped + edits", "compact + edits") appears only while the
  draft holds unpinned changes. Restore the draft if the lab closes while
  another chip is shown.
- **⋯ menu** with **Reset** (copies the baseline back into the draft) and
  **Copy values** (`references/landing-protocol.md`; it always reports the
  draft).
- **Target picker**, when the feature has variants to choose between (a theme,
  a mode, a layout variant): at the top of the panel, driving the app's real
  setting, with the current choice in the panel header ("Ember · dark"). An
  empty or untunable state offers this picker instead of pointing to another
  screen or menu.

## Required for motion

- **Replay**: re-runs the animation on demand (bump an `id` or `key`).
- **Speed**: 1×, 0.5×, 0.25×, 0.1×, applied by stretching the rendered duration.
  Never change global animation speed (`UIView` layer speed, DevTools throttling).
- **Reduced motion**: show what the feature does with the user's setting, and say
  so in the lab. Never override the setting. If the feature has no reduced-motion
  path at all, do not add one inside the lab (the lab must not change how the
  feature behaves). Say so in the panel and list it in the report as a finding
  for the user.
- **One-shot and delayed animations**: an entrance that runs once, often after a
  fixed delay such as a splash screen, replays by re-creating the view (bump its
  `id`) with a short lab-only delay instead of the production one. Speed
  stretches every timing the motion is made of, including stagger, and the
  start delay too when it is part of what is being tuned. Leave a delay out of
  the controls unless the user asked to tune it, and say so.
- **Other places using the same value**: when another view hard-codes a value
  the lab now tunes (for example a matched transition that starts from the old
  card size), list it in the report. It will not follow the draft and may jump.

Speed, the shown chip, and Replay are preview settings: they never enter
the draft, Copy values, a candidate, or a saved profile.
