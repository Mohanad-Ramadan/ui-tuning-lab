---
name: ui-tuning-lab
description: "Trigger: live lab, visual variants, try options live. Use BEFORE tuning animation/layout/appearance/logic on the real screen in-app when you want to visualize and combine variants."
license: Proprietary — TODO: choose license
compatibility: Web, Apple (iOS/iPadOS/macOS/visionOS), Android, HarmonyOS, Windows, Linux, Flutter, RN; DEBUG/tester-gated, no prod dependency
metadata:
  author: "you"
  version: "1.0"
---

# UI Tuning Lab

Spin up a lightweight toggleable in-app lab on the real screen. Visualize, customize, and combine variants. Tune the feature or the container. Leave zero cost when closed.

## Activation Contract

Use when the user wants to try options live, compare variants, or tune animation, layout, logic, or appearance on the real screen.

Do NOT use for static one-shot edits with no comparison, backend-only work with no visible surface, or production settings pages. A lab is a development instrument, not a feature.

## Hard Rules

- INV-1 Lightest container only. Never use an expensive object that noticeably affects performance or memory unless the user explicitly asks.
- INV-2 Closed means unmounted. Unmounted or removed from the tree plus timers, observers, and listeners cancelled. `display:none` alone is not closed.
- INV-3 Absent from production. Gated to DEBUG, tester, or internal builds. Prove absence with `verify --prod`.
- INV-4 Explicit Save only. Never write on every edit. Capture enough context to reproduce a result, including schema version.
- INV-5 Baseline restorable. Record baseline before the lab opens. Opening at baseline must look and behave identically. Reset returns to it.
- INV-6 Namespaced persistence. Lab keys live under `variantLab.*` or `.ui-tuning-lab/`. Never touch production keys.

## Decision Gates

| Need | Load |
|---|---|
| Interview flow, questions, fallback | See `references/interview-protocol.md` |
| Platform container matrix | See `references/surface-matrix.md` |
| Tuning the container itself | See `references/container-tuning.md` |
| Config and profile schema | See `profiles/_template.md` + `assets/*.template.json` |
| Verification and teardown | See `references/verify-protocol.md` |
| Edge cases, listed and unlisted | See `references/edge-cases.md` |

## Execution Steps

1. Init. Detect platform, build variant, and read existing `.ui-tuning-lab/lab.json` if present.
2. Interview. Follow `references/interview-protocol.md`. Do not scaffold until valid `lab.json` plus baseline exist.
3. Build lab. Lightest container from the matrix. Controls outside the feature layout and interaction paths. Cap 5 active variants.
4. Variants. Combine via explicit profile, not full matrix. Coalesce rapid edits; defer expensive work until settle.
5. Save. Explicit operation only. Atomic local write off the interaction path. Show errors and saved result.
6. Verify. Baseline equivalence, meaningful variants, input and accessibility paths, capture behavior, gate absence in prod.
7. Teardown. Close removes everything. No timer, observer, or listener survives.

## Output Contract

Return: files created or modified; profile saved or reused; baseline location; verification evidence (baseline equivalence, closed-cost check, prod-absence check).

## References

- See `references/interview-protocol.md` for the questioning protocol.
- See `references/verify-protocol.md` for verification, teardown, and the prod gate.
- See `references/edge-cases.md` for the discretion protocol on unlisted edges.
- Run `scripts/verify.sh` for the lab.json gate, `scripts/verify.sh --prod` for release absence.
- See `profiles/_template.md` for the profile shape.
- See `CHANGELOG.md` for version history.
