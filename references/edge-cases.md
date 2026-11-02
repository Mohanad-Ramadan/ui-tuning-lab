# Edge Cases

Use the four guarantees in `SKILL.md` to decide unlisted cases. Stop for a
production leak, destructive persistence, or an irrecoverable baseline; otherwise
choose the safest local default and describe it in the task report, not by editing
this installed skill.

Common checks:

- Preserve baseline and unsaved draft across rotation, resizing, trait, locale,
  dark-mode, Dynamic Type, and safe-area changes.
- Keep focus, selection, keyboard, gesture, and screen-reader ownership intact
  when applying a variant.
- Give the lab three activation paths (`references/activation.md`). Shake yields
  to a focused text input's undo, and the visible fallback stays reachable.
- Re-arm the human path after the lab closes. If it was a first-responder shim,
  regain first responder without stealing focus from a text field.
- With more than one lab, scope activation to the visible feature or offer a
  picker; never open an arbitrary lab.
- Do not add an iOS URL scheme for the agent. A scheme registered in `Info.plist`
  survives Release even when its handler does not.
- When activation is remembered, a changed screen (a new text field, a toolbar)
  can invalidate it: report the conflict before changing the stored choice.
- On compact iOS, account for popover-to-sheet adaptation.
- Ignore lab chrome when measuring the feature.
- Make hot reload registration idempotent.
- On save failure, show the error and retain the draft.
- On corrupt or incompatible saved data, keep the file untouched, keep the
  current draft, and report the incompatibility.
- Reset needs no confirmation: the baseline is always one click away, and Copy
  values preserves a draft worth keeping. Confirm only before Load saved replaces
  a draft that differs from the baseline, if the user asked for that.
