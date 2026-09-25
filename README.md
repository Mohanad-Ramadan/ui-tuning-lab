# ui-tuning-lab

Spin up a lightweight, toggleable in-app lab on the real screen. Visualize,
customize, and combine variants while tuning animation, layout, logic, or
appearance — on Web, iOS/iPadOS, macOS, Android, Windows, Flutter, and RN.

Core guarantees:

- Lightest native container per platform only. Closed lab costs nothing:
  unmounted, timers and observers cancelled, listeners released.
- Absent from production. Gated to DEBUG, tester, or internal builds.
- Explicit Save only. Baseline recorded first and always restorable.
- Agent-proof interview before any lab code is generated.

## Install

Copy this folder into your agent's skills directory, e.g.:

```bash
cp -r ui-tuning-lab ~/.agents/skills/
# or per-project
cp -r ui-tuning-lab .agents/skills/
```

Then invoke `ui-tuning-lab` before tuning any visible surface.

## Layout

- `SKILL.md` — orchestrator: activation, hard rules (INV-1..6), gates, steps.
- `references/interview-protocol.md` — Q0–Q7 batched interview + fallback.
- `profiles/_template.md` — uniform profile shape.
- `assets/*.template.json` — LabConfig and profile starters (`schemaVersion: 1`).
- `CHANGELOG.md` / `VERSION` — semver history, bumped on release only.

## Status

v1.0.0 skeleton. Phase 2 adds `surface-matrix`, `container-tuning`,
`verify-protocol`, tiered per-platform examples, and `verify --prod`.

## License

Apache-2.0. See `LICENSE.txt`.
