# Control Mapping

Pick each control from the kind of value it edits, not from what is easiest to
build. Ranges run from the smallest sensible value (usually 0 for radius, gap,
and padding) to two or three times the baseline (the examples use 32 for a
radius of 12), and use a step that lands clean values. A range always includes the baseline:
when the baseline sits outside the usual range, widen the range to reach it
rather than hide its marker. Generating controls from a list of fields is fine;
keep each one labelled.

| Value | Control | Notes |
|---|---|---|
| Length, radius, spacing, size | Slider with `step: 1` (points or px) | Show the current number next to the label; hide that readout from assistive technology, since the slider already reports its value. Default marker, snap, and ↺ (below). |
| Opacity, scale, ratio | Slider `0...1` (or `0.5...2` for scale) with `step: 0.05` | Values land with two decimals. Default marker, snap, and ↺. |
| Color | Native color picker (`ColorPicker`, `<input type="color">`) | Land the token name when the app uses tokens; ask before introducing a raw color. A swatch of the default beside the picker restores it. |
| Enum or style choice | Segmented control or picker | One option per case; never free text. The Shipped option is marked "default". |
| Boolean | Toggle | "default: On" caption while it differs. |
| Duration | Slider in the app's unit (seconds in SwiftUI, ms on the web) | Pair with Replay and Speed. Default marker, snap, and ↺. |
| Spring | Duration (or response) plus bounce (or damping) sliders | Pair with Replay and Speed; see `examples/animation-spring.md`. A marker and snap on each slider, one ↺ for both. |
| Easing | Presets (ease-in-out, ease-out, linear, spring) plus a custom cubic-bézier only if requested | The Shipped curve is marked "default". |
| Text length | Sample copy: short, typical, long, overflowing | Tests truncation and wrapping without editing strings. Mark "Real data" first; no ↺. |
| UI state | Forced state picker: empty, loading, error, success | Drive the feature's real state, never a mock view. Mark "Live state" first; no ↺. |
| Alternative design | **Design** picker at the top of the panel: Shipped (the `original` design) first, then one option per variant | A `design` string in each look; see `references/design-variants.md`. Never in the feature's layout. |

## Required in every lab

- **Presets**: at least two meaningful presets that differ clearly from the
  baseline and from each other.
- **Chips, Save & pin, and Apply**, with the hint line: see
  `references/candidates.md`. The selected chip is outlined and is what the
  feature shows. Every chip is read-only, Shipped and pinned looks alike: an
  edit forks the outlined chip into unsaved edits, outlining none, until Save &
  pin keeps them as a new look named after its `basedOn` (an edit on `Brass-1`
  pins as `Brass-2`). An edit never lands on the baseline or changes a pinned
  look. There is no Save button.
- **Undo, Redo, and Reset** in one row under the controls: one history of the
  unsaved edits, back to the chip they were forked from, one step per control
  run, Reset back to that chip (`references/candidates.md`, "Edits, Undo,
  Redo, and Reset").
- **Default marker and per-control reset** on every control that edits a
  look's values (next section).
- **⋯ menu** with **Copy values** (`references/landing-protocol.md`; it reports
  the selected look).
- **Target picker**, when the feature has variants to choose between (a theme,
  a mode, a layout variant): at the top of the panel, driving the app's real
  setting, with the current choice in the panel header ("Ember · dark"). An
  empty or untunable state offers this picker instead of pointing to another
  screen or menu.

## Default marker and per-control reset

Reset takes the whole tune back to the chip it was forked from. To put one
control back, each control shows its default and has its own ↺. The default is
always the baseline, what the Shipped chip shows, never a pinned look's value.

| Control | Default shown as |
|---|---|
| Slider (length, radius, opacity, scale, duration) | A short tick on or just under the track at the baseline, always visible, on Shipped too. Native sliders have no API for one tick at an arbitrary value (WinUI ticks are evenly spaced only), so draw it over the track, inset by half the thumb so it sits under the thumb's center at that value. |
| Spring (two sliders) | A tick and snap on each slider, and one ↺ that puts both back together as one step. |
| Toggle | A caption, `default: On`, shown only while the toggle differs. |
| Enum (segmented control or picker) | A small `default` caption or dot under the Shipped option; in a dropdown the option reads `Rounded (default)`. |
| Color | A swatch of the default beside the picker, with the token name when the app uses tokens. Clicking it restores the default. |
| Easing presets | A `default` caption on the Shipped curve. |

Sliders also:

- **Snap while dragging.** Within about 1.5% of the range of the baseline, a
  drag lands on the baseline exactly; the values one step to either side never
  snap. The baseline must sit on the slider's grid: a slider with a step of 1
  cannot land on 12.5, and a web range input with `step="1"` cannot hold it,
  so pick a step that divides the baseline, or a continuous slider
  (`step="any"` on the web). A light haptic marks the snap, once, where the
  platform has one (iOS `sensoryFeedback(.selection, ...)` or
  `UISelectionFeedbackGenerator`, Android `performHapticFeedback`, Flutter
  `HapticFeedback.selectionClick`); none on the web or the desktop. Only a drag
  snaps: arrow keys, steppers, and screen reader adjust actions still reach
  the values beside the baseline.
- **Say the default in the readout.** `14 px · default 12` while the value
  differs, `12 px` when it matches. The readout stays hidden from assistive
  technology.

Every such row has a **↺** button, shown only while its value differs from the
baseline, with the accessible name `Reset <Label> to default, <value>`
("Reset Corner radius to default, 12 pt"). On the web, macOS, and Windows,
double-clicking the control's label does the same, as a shortcut, never the
only path. After a reset the ↺ goes away, so move focus to that control's
slider (or stepper): focus stays in the panel, and the panel's Undo shortcut
still reaches it.

A per-control reset is an ordinary edit through the same path as any other
(`references/candidates.md`, "Edits, Undo, Redo, and Reset"): one Undo step,
and it ends the current slider run, so it never merges with a drag. With a
pinned look outlined, ↺ forks it like any edit: the look loses its outline, the
reset value becomes an unsaved edit that Save & pin keeps as a new look, and
the pinned look stays as it was. When ↺ makes the unsaved edits match the chip
they were forked from again, they are dropped and that chip is outlined again;
on Shipped, that is a look whose values all match the baseline.

The marker, snap, captions, and swatch are display only: they never enter a
look's values, Copy values, or a saved profile.

Not covered, with no marker and no ↺:

- Text-length samples and forced UI state: they are not a look's values. Mark
  the option that shows the feature's own data or state, **Real data** or
  **Live state**, and list it first.
- Speed, Replay, and the shown chip: preview settings.
- The Design picker: Shipped is already its first option.
- The target picker: it drives the app's real setting.
- Presets: they are buttons, not values.

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
  card size), list it in the report. It will not follow the selected look and
  may jump.

Speed, the shown chip, and Replay are preview settings: they never enter
a look's values, Copy values, or a saved profile.
