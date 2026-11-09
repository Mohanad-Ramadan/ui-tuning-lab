# Changelog — ui-tuning-lab

## 1.3.0 — unreleased

### Selection is an outline, and Change no longer loses the controls

- **Bug fix (macOS):** after Choose and Change, the lab window came back only as
  tall as its header and chips, with no controls. A desktop window follows its
  content's ideal size, and a panel built on a `ScrollView` has almost none, so
  the window collapsed with the result bar and stayed collapsed. The panel
  branch now carries its own size (`.frame(width: 320, height: 420)`), and the
  verify protocol checks the frame after Change.
- The "<source> + edits" chip is gone. Chips are Shipped and each pin; the
  selected chip is outlined (and so is the preset the draft started from), like
  any selected option. Unpinned edits stay under their home chip: the chip the
  draft matches, else the pin it was copied from, else Shipped. Tapping another
  chip stashes them until the home chip is tapped again. To compare unpinned
  edits with Shipped, Pin them first.
- Choose picks what the feature shows. The wire format is unchanged: Shipped logs
  `original`, a pin its name, unpinned edits `draft`.

### Plainer labels

- The panel's labels are plain words with no glyphs. The toggle is named after
  the feature ("Card Lab", "Nav Lab") instead of "Tune"; the Original chip is
  **Shipped**; Keep is **Pin**; Use this is **Choose**; the result bar reads
  "Chosen: capsule · Change"; the hint reads *Pin looks to compare · Choose to
  finish*. Saved looks are called pins.
- The fixed Now chip is gone, and so is any chip for unpinned edits (see
  "Selection is an outline" below). Pin is disabled while there is nothing
  unpinned. Reset returns the draft to Shipped. Every example and the shared
  Swift asset implement it.
- The wire format is unchanged: the Shipped chip still logs winner `original`,
  unpinned edits `draft`, and every log tag, key, and file path stays the same.

### Labs already in the project

- Inspection now searches for labs left by earlier work. A lab for the same
  feature is extended; a lab for another feature always prompts the user to
  remove it, land it first, or keep both, even when the request says "the
  existing lab". The report names every other lab still active.

### Simpler finish, automatic handoff

- The panel finishes with two buttons and a chip row. Chips (Original, Now, and
  each favorite) replace Show baseline, Compare, and Load; **★ Keep** replaces
  Keep as candidate; **✓ Use this** replaces Done and picks what is shown, then
  shrinks the panel to a "✓ Sent" bar. No confirmation: the newest pick wins.
  Reset and Copy values move to a ⋯ menu. The hint is one line.
- Favorites are named after what they are (`capsule`, `compact-2`), so a name
  works as a code in chat.
- ✓ Use this also writes `.ui-tuning-lab/result.json` (web:
  `uiTuningLab.result`) in development builds and copies `land <name>`, so the
  agent reads the pick after the app quits, and a cloud-device user pastes one
  short line.

### Leaner package

- Maintainer notes are gone from what the agent reads: no "unvalidated / not
  compiled" banners, "Assumptions" sections became direct **Version notes**,
  and the stub examples, `profiles/`, `validation/`, and the changelog no
  longer ship.
- The Swift values and candidates file shared by every Swift example is one
  asset, `assets/swift/UITuningLabValues.swift`, copied unchanged.
- Long references open with a Contents list; duplicated log tables, wait
  scripts, and activation memory now live in one place. The description is in
  third person.

### From the Flutter rerun

- The pill and panel pin to the screen, separate from the wrap around the
  feature; the Flutter example uses one always-shown `OverlayPortal`.
- Phones dock the panel full width at the bottom (at most 45% tall); the lab
  hides while its tab or route is offstage; right-to-left apps keep their
  direction.
- Each design's knobs start from that design's declared defaults; Original
  stays untunable when the user asked only for new designs.
- A CI workflow with build or launch inputs carries the agent path.
- The activation question is skipped when the pill is the only human path.

Fixes from a Flutter session where the agent read "unvalidated adaptation" as
"unsupported", skipped the panel, and put design chips into the screen.

- `SKILL.md` gains "Every platform gets the whole lab": unvalidated means not
  yet proven, never unsupported. Android, Flutter, React Native, Windows, and
  stacks with no example get the full panel, handoff, and activation, adapted
  from the nearest example.
- New `references/design-variants.md`: alternative designs ("three better
  versions of this list") are a **Design** picker in the panel, with the
  original as the baseline and `design` as a value in Copy values, candidates,
  Compare, and Done. Landing moves the winning variant's code into the
  production widget. Never chips or tabs inserted into the screen. The trigger
  description now covers this request.
- `references/platform-handoff.md` gains "No local toolchain" for apps that
  build only in CI or a cloud device service: build the whole lab, ask before
  pushing, hand Done over through chat, and run the release search in the
  pipeline or report it as not run. Inspection now checks whether the
  toolchain runs here.
- `examples/flutter-overlay.md` shows design variants and the remote-build
  handoff.
- Fixed a broken code fence in `references/platform-handoff.md`.
- Receipts in `validation/` are evidence, not a release gate: publishing no
  longer waits for every platform receipt to pass. The one check required
  before every release is the release-artifact search proving no lab code
  ships. README status now describes platforms in plain terms.

### The panel reads as its own surface

- The panel and the result bar carry a hairline outline in the platform's
  stronger separator token, so the lab stays distinguishable when the screen
  behind it has the same background and a shadow alone vanishes. Web
  (`GrayText` on `Canvas`), Flutter, Compose, and React Native draw it; native
  chrome (an iOS sheet, a macOS panel window, a WinUI `Flyout`) is verified
  instead of double-bordered. The rule lives in `references/setup-protocol.md`
  ("Make the panel its own surface") and `SKILL.md`, with a hands-on check in
  `references/verify-protocol.md` and regression assertions in
  `tests/examples.sh`.
- Shadows stay as they are and stay static: a cached shadow costs no frames,
  while animating elevation or adding a backdrop blur would. The outline is the
  cue that does not depend on a theme's shadow.

### Hand over, don't demo the lab

- The lab is handed over after one smoke launch: build, typecheck, and run the
  gate lint, open it once through the agent path to confirm it renders and
  opens, then stop. The agent no longer iterates the controls, flips the chips,
  Pin, Choose, Reset, compares candidates, or screenshots each option before the
  user has seen it; that burned the time the user wanted to spend tuning. A
  self-review pass runs only when the user asks for one.
- Hands-on checks are reported as run by the agent or by the user, never as a
  pre-handover gate, and the smoke launch counts as one check ("opens and
  renders"), not as the whole list.

## 1.2.0 — unreleased

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

## 1.1.0 — unreleased

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

## 1.0.0 — unreleased

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
