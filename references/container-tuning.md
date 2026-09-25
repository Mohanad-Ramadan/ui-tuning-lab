# Container Tuning — experimental

Status: opt-in, detached-only. Tuning the lab container itself changes the
system under test, so detached tuning is approximate. Final sign-off always
requires one screenshot or clip captured in the real container.

## Rules

1. Host controls detached: separate scene, window, or side panel. Never
   inside the container being tuned.
2. Sequence, never simultaneous. `both` means feature attached first,
   container detached second, then one in-situ check. Two labs at once
   fight over focus and persistence.
3. Baseline includes container chrome: geometry, detent, position, shortcut.
   Reset must restore it.
4. Self-measure ban (concrete): no `ResizeObserver` or `onGeometryChange`
   targeting the lab container itself. Measure only the feature view via a
   passed `DOMRect` / `CGRect`. Asserted in verify.
5. Cannot validate from outside: light-dismiss, scrim opacity, arrow
   occlusion, detent snap, focus trap, trait and safe-area shifts. These
   get their verdict only from the in-situ check.

## Trait-shift warning

A separate scene or window carries different traits: size class, safe area,
keyboard behavior, key and responder status, stacking and backdrop. Detached
approval of container chrome is a draft, never a pass.
