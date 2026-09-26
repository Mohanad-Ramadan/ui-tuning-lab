# Unvalidated adaptation — Android drawer

Conditional `ModalBottomSheet` removed from composition on hide.
This repository does not contain validation evidence for this adaptation. Confirm
open, variants, reset, explicit save, dismissal, accessibility, teardown, and
Release artifact absence in the target app before relying on it.

Key points: `if (showSheet) { ModalBottomSheet(...) }`,
`rememberModalBottomSheetState`, `BuildConfig.DEBUG` gate, shake or
dev-drawer entry. Never a persistent scaffold for the lab.
