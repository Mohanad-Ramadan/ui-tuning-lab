# Changelog — ui-tuning-lab

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
