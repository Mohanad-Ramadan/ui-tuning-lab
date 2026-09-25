# Edge Cases

## Listed

- Notch, safe area, Dynamic Type, RTL, locale, dark mode shifts.
- Orientation change mid-session; draft survives, baseline intact.
- Focus, selection, or gesture ownership lost on variant switch.
- Sheet coercion on compact iOS (popover becomes fullscreen sheet).
- Bottom sheet or dialog covering the lab FAB on Android: dismiss first.
- Overlay measuring itself: ignore everything tagged for the lab.
- Hot-reload double registration of toggles and listeners.
- Capture failure offline or on full disk: error shown, draft kept.
- Corrupted profile or schema mismatch: fall back to baseline, report.
- Reset requested with unsaved draft: confirm before destroying.

## Unlisted — discretion protocol

For anything not listed above:

1. STOP only if the risk is data loss, production leak, or irreversible
   change. Otherwise proceed with the safest default and log it here.
2. Cite the invariant IDs (INV-1..INV-6). Non-negotiables are never voted
   on: no teardown bypass, no production gating bypass, no unnamespaced
   writes, no write-on-edit. Refuse with the ID, do not offer a workaround.
3. Discretion covers unlisted feature edges only — never container choice,
   persistence location, or production gating.
4. Never mark an invariant-violating option `(Recommended)`. Label it
   `violates INV-X` in the tradeoff table.
5. Log the edge in this file. CHANGELOG changes on release only, not per
   edge. `VERSION` bumps on release only.
