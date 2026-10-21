# Control Mapping

Pick each control from the kind of value it edits, not from what is easiest to
build. Ranges run from the smallest sensible value (usually 0 for radius, gap,
and padding) to about double the baseline, and use a step that lands clean
values. Generating controls from a list of fields is fine; keep each one
labelled.

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

## Required in every lab

- **Presets**: at least two meaningful presets that differ clearly from the
  baseline and from each other.
- **Show baseline**: a flip that renders the captured baseline in the real
  feature and restores the draft when turned off. While the baseline is shown,
  an edit must never land on it silently: either disable the controls (the
  palette examples, which also disable Reset and Copy values) or switch back to
  the draft on the first edit (the motion example). Copy values always reports
  the draft. Restore the draft if the lab closes while the baseline is shown.
- **Reset**: copies the baseline back into the draft.
- **Copy values**: see `references/landing-protocol.md`.

## Required for motion

- **Replay**: re-runs the animation on demand (bump an `id` or `key`).
- **Speed**: 1×, 0.5×, 0.25×, 0.1×, applied by stretching the rendered duration.
  Never change global animation speed (`UIView` layer speed, DevTools throttling).
- **Reduced motion**: show what the feature does with the user's setting, and say
  so in the lab. Never override the setting.

Speed, Show baseline, and Replay are preview settings: they never enter the draft,
Copy values, or a saved profile.
