# Verify Protocol

Bounded passes, not loops. Build fully, inspect once batched (desktop plus
mobile on web; shipped device classes on native), fix the batch, confirm at
most once, then stop.

## Checklist

1. Baseline equivalence: opening the lab at baseline changes nothing visible.
2. Meaningful variants: each variant visibly differs; cap 5 active.
3. Input paths: tap, click, keyboard, focus, selection, gestures still work.
4. Accessibility: labels, focus order, ESC or light-dismiss, Reduce Motion
   alternative for animation variants.
5. Numeric limits: sliders and inputs clamp; requested vs effective
   (viewport-clamped) values stay distinct where it matters.
6. A/B slots: switching applies a complete config without destroying an
   unsaved draft.
7. Capture: explicit Save writes atomically off the interaction path and
   reports errors plus the saved result.
8. Gate absence: the lab is absent from production builds (see below).

## Teardown checklist (per platform)

Confirm no timer, display link, observer, listener, or duplicate render tree
survives closing. Web: unmounted, not `display:none`. SwiftUI: presentation
binding false, no polling. macOS: panel ordered out. Android: removed from
composition. Windows: flyout closed, no presenter. Flutter: entry removed.
RN: overlay null, sensor stopped by the native manager.

## Prod gate

Run `scripts/verify.sh --prod` from the repo root. It is a source-hygiene
check (not a build-artifact inspection): it fails on any UNGATED lab
reference (`ui-tuning-lab`, `UITuningLab`, `LabPanel`, `.ui-tuning-lab`).
References inside correctly `#if DEBUG` / `#ifdef DEBUG` … `#endif`
blocks (any case for DEBUG, with nesting and `#else`/`#elif` handling —
the `#else` branch is still checked) are allowed. No green gate, no ship.

## Perf budget

Open under 100ms. No new dependency over 50KB. Zero network. No timers
when closed. "Lightest" is measured against these, not asserted.

## Uninstall

Delete the lab call site and its profile files, rerun the prod gate.
A clean gate is the proof of removal.
