# Example — Android drawer (minimal tier)

Conditional `ModalBottomSheet` removed from composition on hide.
Smoke-tested: open, toggle one variant, dismiss, confirm no coroutines
or back-handler survive.

Key points: `if (showSheet) { ModalBottomSheet(...) }`,
`rememberModalBottomSheetState`, `BuildConfig.DEBUG` gate, shake or
dev-drawer entry. Never a persistent scaffold for the lab.
