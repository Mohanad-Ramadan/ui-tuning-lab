# Changelog — ui-tuning-lab

## 1.1.0 — unreleased

- New `references/activation.md`: every lab has an agent path, a human fast path,
  and a mandatory visible fallback. Shake is recommended only when inspection
  proves it free; a focused text field keeps the system's shake-to-undo.
- iOS: the `-UITuningLabOpen 1` launch argument gives the agent a deterministic
  entry point; a DEBUG-only first-responder shim handles shake; the visible pill
  is the fallback. No URL scheme is registered in Release.
- Every default example now carries the full triad: an agent path, a human path,
  and a visible fallback. iOS uses the `-UITuningLabOpen 1` launch argument,
  macOS reads it on window appear alongside the DEBUG menu command, and web labs
  parse `?ui-tuning-lab=1` only inside the development-gated module.
- New `variant=shake` in `examples/swiftui-popover-palette.md`, which both the
  example lint and compile suites discover automatically.
- Optional `activation` object in `.ui-tuning-lab/lab.json` remembers the chosen
  entry points. `verify.sh config` validates it; saved profiles still reject it.
- Verification, edge cases, landing removal, the surface matrix, and the
  validation receipts cover activation, re-arming, multi-lab selection, and
  release absence.

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
