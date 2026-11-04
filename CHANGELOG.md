# Changelog — ui-tuning-lab

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
