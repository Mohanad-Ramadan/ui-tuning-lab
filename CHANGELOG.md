# Changelog — ui-tuning-lab

## 1.3.0 — 2026-11-10

First public release, installable with
`npx skills add Mohanad-Ramadan/ui-tuning-lab`. Versions 1.0.0 to 1.2.0 below
were never published; this entry describes the lab as it ships.

### Install layout

- The skill lives in `skills/ui-tuning-lab/`, which is exactly what
  `npx skills add` installs. Tests, pilots, evals, validation receipts, and this
  changelog stay at the repository root and are no longer copied into installs.
  `tests/package.sh` fails if anything else lands in the skill folder or the
  `SKILL.md` metadata version drifts from `VERSION`.

### Looks you edit in place

- Chips are **Shipped** and each pin. Exactly one is selected, outlined, and
  shown in the feature, so switching chips is the comparison. There is no
  draft, no stash, no Reset, and no compare mode.
- The controls edit the selected pin in place. Shipped is read-only: editing it
  starts a new pin named after the design, the preset, or `tweak`. Pins are
  named after what they are (`capsule`, `compact-2`), so a name works as a code
  in chat.
- **Duplicate** branches the selected pin. **Choose** picks the selected chip,
  writes `.ui-tuning-lab/result.json` (web: `uiTuningLab.result`) in development
  builds, and copies `land <name>`, so the agent reads the pick after the app
  quits and a cloud-device user pastes one short line. The panel then shrinks to
  "Chosen: capsule · Change"; Change brings the whole panel back.
- Copy values sits in a ⋯ menu. The hint reads *Duplicate to compare · Choose
  to finish*. The toggle is named after the feature ("Card Lab").
- A pin logs `UITUNINGLAB_CANDIDATE` when created and again when it is left
  after an edit; persisting labs rewrite its profile at the same moments. The
  Shipped chip still logs winner `original`; an older lab's `draft` winner
  lands like a pin.
- Candidate names are never `draft`, `now`, `original`, or `baseline`, and
  `verify.sh config` now rejects all four in `lab.json`.

### The panel reads as its own surface

- The panel and the result bar carry a hairline outline in the platform's
  stronger separator token, so the lab stays distinguishable when the screen
  behind it has the same background. Native chrome (an iOS sheet, a macOS panel
  window, a WinUI `Flyout`) is verified instead of double-bordered. Shadows stay
  static: animating elevation or adding a blur would cost frames.
- **Bug fix (macOS):** Shipped no longer stays outlined after an edit, and the
  panel is a plain stack instead of a `Form`, whose two-column layout pushed the
  controls right, showed each label twice, and floated the hint mid-window. The
  panel keeps a fixed size.

### Hand over, don't demo

- The lab is handed over after one smoke launch: build, typecheck, run the gate
  lint, open it once through the agent path, then stop. The agent does not tune
  it, tour the presets, or screenshot the options first; a self-review pass runs
  only when the user asks for one.
- Hands-on checks are reported as run by the agent or by the user, and the
  smoke launch counts as one check ("opens and renders").

### Every platform gets the whole lab

- Android, Flutter, React Native, Windows, and stacks with no example get the
  full panel, handoff, and activation, adapted from the nearest example. Not
  yet compiled means not yet proven, never unsupported.
- Alternative designs ("three better versions of this list") are a **Design**
  picker in the panel, with the original as the baseline
  (`references/design-variants.md`). Landing moves the winning design's code
  into the production view.
- `references/platform-handoff.md` gains "No local toolchain" for apps that
  build only in CI or a cloud device service.
- Flutter: the pill and panel pin to the screen through one always-shown
  `OverlayPortal`; phones dock the panel at the bottom (at most 45% tall); the
  lab hides while its route is offstage; right-to-left apps keep their
  direction.

### Labs already in the project

- Inspection searches for labs left by earlier work. A lab for the same feature
  is extended; a lab for another feature always prompts the user to remove it,
  land it first, or keep both. The report names every other lab still active.

### Leaner package

- The Swift values and candidates file shared by every Swift example is one
  asset, `assets/swift/UITuningLabValues.swift`.
- Long references open with a Contents list; duplicated log tables, wait
  scripts, and activation memory live in one place. Maintainer notes no longer
  ship.
- `tests/pilot-web/run.sh` builds the web example into the pilot and runs the
  cross-browser check against it.

## 1.2.0 — pre-release (not published)

- New `references/candidates.md`. Every lab, ephemeral ones included, has
  **Keep as candidate** (finalists named `a`, `b`, … with the preset each came
  from), a candidates list with Load and Remove, **Compare** to flip the real
  feature between Draft and each candidate, **Done**, and an always-visible
  footer hint that says how to finish.
- New log lines `UITUNINGLAB_CANDIDATE`, `UITUNINGLAB_CANDIDATE_REMOVED`, and
  `UITUNINGLAB_DONE`. The Done line carries the winner (or `null`) and every
  candidate with its values, so it alone is enough to land.
- On Apple platforms the agent can wait for Done by polling `/usr/bin/log show`
  in the background instead of waiting for a message (a `log stream | grep -m1`
  pipeline never exits, and zsh shadows `log` with a builtin).
- Saved profiles gain `schemaVersion: 2` (candidates), adding `basedOn` and
  `savedAt`; `schemaVersion: 1` files still validate. Persisted labs store one
  file or key per candidate (`.ui-tuning-lab/candidates/<name>.json`,
  `uiTuningLab.candidates.<name>`) instead of a single Save slot.
- At landing the agent offers to keep the other finalists in the project's
  `.ui-tuning-lab/candidates/`, lists them in `lab.json` under the new optional
  `candidates` field, and seeds them into the lab when it is reopened.
  `verify.sh config` validates the field.
- Landing takes what the user names in chat first, then the newest
  `UITUNINGLAB_DONE` or `UITUNINGLAB_VALUES` line, over a one-hour log window.
- Candidate names are never reused within a run, and a persisted lab never
  overwrites a stored entry, readable or not.
- Shake keys are no longer written into the skill. When writing **How to try
  it**, the agent shakes with its own simulator tool if it can, and otherwise
  reads the current keys from the host the user is looking at (Simulator.app's
  menu and any `NSUserKeyEquivalents` remap, or the agent panel's own
  shortcuts) and names them, with the visible fallback last.

### Other platforms

- New `references/platform-handoff.md`: for every platform, how lab lines are
  logged and read, how to wait for Done (`adb logcat -d -T` polling on
  Android), where persisted candidates live, and manual gate checks for Kotlin,
  Dart, and C#, which `source-gates` cannot read.
- Unvalidated adaptation examples for Android (Compose), Flutter, React Native,
  and Windows (WinUI 3), each with the full activation triad and handoff.
  Nothing in them is compiled in this repository.
- Saved profiles accept `visionos`, `android`, `flutter`, `react-native`,
  `windows`, `linux`, and `harmonyos`; Flutter and React Native use the
  framework value so a candidate moves between devices.
- Reusing a panel library keeps Keep as candidate, Compare, and Done, or the
  report says which one the library cannot host.
- `source-gates` accepts React Native's `if (__DEV__) {` around a `require()`
  of the lab module, rejects `import()` under that gate (web bundlers do not
  inline `__DEV__`), and fails a file that defines or assigns `__DEV__`.
- Release searches look for the `UITUNINGLAB_` and `ui-tuning-lab` strings as
  well as the class marker, since minifiers rename identifiers.

## 1.1.0 — pre-release (not published)

- New `references/activation.md`: every lab has an agent path, a human fast path,
  and a mandatory visible fallback. Shake is recommended only when inspection
  proves it free; a focused text field keeps the system's shake-to-undo.
- iOS: the `-UITuningLabOpen 1` launch argument gives the agent a deterministic
  entry point. The toolbar Tune button is the default human path and fallback;
  in the shake variant, a DEBUG-only first-responder shim handles shake and a
  visible pill is the fallback. No URL scheme is registered in Release.
- Every default example now carries the full triad: an agent path, a human path,
  and a visible fallback. iOS uses the `-UITuningLabOpen 1` launch argument,
  macOS opens one panel when the first window appears alongside the DEBUG menu
  command, and web labs parse `?ui-tuning-lab=1` only inside the
  development-gated module. Each agent request is honored once per launch, and
  `-UITuningLabOpen 0` stays closed.
- New `variant=shake` in `examples/swiftui-popover-palette.md`, which both the
  example lint and compile suites discover automatically.
- Optional `activation` object in `.ui-tuning-lab/lab.json` remembers the chosen
  entry points. `verify.sh config` validates it and rejects blank tokens; saved
  profiles still reject it.
- The agent always asks how the lab should open, even when a toolbar or debug
  menu exists, unless the request or a fitting remembered `activation` already
  answers it. The question sits beside the one setup question, in the same
  prompt, and lets the user pick several human paths, such as shake plus the
  toolbar Tune button. `activation.human` accepts a list of distinct tokens.
- Verification, edge cases, landing removal, the surface matrix, and the
  validation receipts cover activation, re-arming, multi-lab selection, and
  release absence.
- Labs pin to a corner no other dev overlay holds, keep any target picker
  (theme, mode, variant) inside the panel, and stay usable over app modals.
  The fallback pill is hit-tested, not just opened by the agent path, and the
  pre-landing report opens with **How to try it**.

## 1.0.0 — pre-release (not published)

First public release candidate.

- Workflow covers the whole loop: build the lab, tune, land the winning values
  in the feature's defaults, then remove or keep the lab.
- Every lab has presets, Show baseline, Reset, and Copy values; motion labs add
  Replay and Speed. New `references/control-mapping.md`,
  `references/landing-protocol.md`, and `references/config-schema.md`.
- New `examples/animation-spring.md` (SwiftUI and web).
- Saved profiles can be loaded back; `verify.sh profile` validates them.
  `persist: "session"` was removed. Storage namespace is `uiTuningLab.*`.
- `verify.sh source-gates` finds lab code by marker (`UITuningLab`,
  `uiTuningLab`, `ui-tuning-lab`), treats `*.ui-tuning-lab.*` web modules as
  development-only, and fails closed on ambiguous structure.
- Every example variant is linted and mutated; Swift examples are typechecked
  in DEBUG and Release, web examples with TypeScript.
- Reuse existing debug menus and panel libraries when the project has them.
- MIT license.

## 0.9 → 1.0 rename — 2026-09-26

- Renamed `live-ui-lab` to `ui-tuning-lab` to avoid collisions with
  `sjunepark/ui-lab` and `VariantLab`. No alias is kept.
