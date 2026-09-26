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
- On compact iOS, account for popover-to-sheet adaptation.
- Ignore lab chrome when measuring the feature.
- Make hot reload registration idempotent.
- On save failure, show the error and retain the draft.
- On corrupt or incompatible saved data, keep the file untouched, fall back to
  baseline, and report the incompatibility.
- Confirm before reset only when reset would discard an unsaved draft.
