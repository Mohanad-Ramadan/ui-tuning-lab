# Edge Cases

Use the four guarantees in `SKILL.md` to decide unlisted cases. Stop for a
production leak, destructive persistence, or an irrecoverable baseline; otherwise
choose the safest local default and describe it in the task report, not by editing
this installed skill.

Common checks:

- Preserve the baseline, the pins, and the selected chip across rotation, resizing, trait, locale,
  dark-mode, Dynamic Type, and safe-area changes.
- Keep focus, selection, keyboard, gesture, and screen-reader ownership intact
  when applying a variant.
- Give the lab three activation paths (`references/activation.md`). Shake yields
  to a focused text input's undo, and the visible fallback stays reachable.
- Re-arm the human path after the lab closes. If it was a first-responder shim,
  regain first responder without stealing focus from a text field.
- A lab for another feature already in the project is the user's call: ask
  whether to remove it, land it first, or keep both before writing the new lab
  (`references/setup-protocol.md`, "Labs already in the project").
- With more than one lab, scope activation to the visible feature or offer a
  picker; never open an arbitrary lab.
- Another development overlay (router or query devtools, a framework dev
  indicator) can sit in the lab's corner and cover the pill. Hit-test the
  fallback, and move the lab, not the other tool.
- A screen whose background matches the panel's surface erases a shadow-only
  boundary, and a flat theme drops the shadow too. Keep the panel's hairline
  outline in both light and dark mode, and on the result bar
  (`references/setup-protocol.md`, "Wire the host").
- An app modal (a settings sheet, a dialog) makes the rest of the page inert
  while it is open, the lab included. Keep the lab in the top layer with
  `pointer-events: auto`, and move any picker the tuning depends on into the lab
  (`references/setup-protocol.md`, "Wire the host").
- Do not add an iOS URL scheme for the agent. A scheme registered in `Info.plist`
  survives Release even when its handler does not.
- When activation is remembered, a changed screen (a new text field, a toolbar)
  can invalidate it: report the conflict before changing the stored choice.
- On compact iOS, account for popover-to-sheet adaptation.
- Ignore lab chrome when measuring the feature.
- Make hot reload registration idempotent.
- On save failure, show the error and keep the pin in the panel.
- On corrupt or incompatible saved data, keep the file untouched, keep the
  current look, and report the incompatibility.
- Choose and × need no confirmation: Shipped is one tap away, Duplicate keeps
  a version worth keeping, and a new pick replaces the old one.
- A seeded candidate that now matches the baseline, or whose fields no longer
  exist in the configuration, is dropped from the lab and reported, never
  silently rewritten.
- The log is the agent's only view of an ephemeral lab's candidates. When the
  log no longer reaches back to the lab's opening (a relaunch, a cleared
  console), read the result file, or ask the user to press Choose again: it
  carries every pin still in the panel, with its values.
