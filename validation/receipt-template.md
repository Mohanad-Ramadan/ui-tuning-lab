# Platform Validation Receipt

- Status: PENDING
- Platform:
- Commit:
- Build/artifact identifier:
- Device, OS, browser:
- Tester:
- Date:

## Checks

- [ ] Baseline is visually and behaviorally equivalent.
- [ ] Two meaningful variants update the rendered feature.
- [ ] Every documented activation path opens the lab: the agent path, the chosen human path, and the visible fallback.
- [ ] A focused text input keeps its own shake or gesture behavior, and the human path re-arms after the lab closes.
- [ ] The visible fallback is reachable with the platform's screen reader or switch control.
- [ ] With multiple labs, each path opens the intended one.
- [ ] The Shipped chip shows the baseline (the declared default) exactly, also after close and reopen.
- [ ] Copy values copies and logs only the changed fields, and landing writes them into the feature defaults.
- [ ] Chips, Save & pin, and Apply (`references/candidates.md`): at most one chip is outlined and it is what the feature shows; an edit forks the outlined chip into unsaved edits with no chip outlined, and the pinned look is unchanged when tapped; Save & pin adds a new chip (Brass-1, then Brass-2 from a fork of it), logs `UITUNINGLAB_CANDIDATE`, and copies `land <name>`; there is no Save button; Apply logs a `UITUNINGLAB_DONE` line carrying the winner and every look, ends the agent's waiter, writes the result file, copies `land <name>`, and shrinks the panel to the result bar; Change restores the full panel without Apply; the hint is visible.
- [ ] Undo, Redo, and Reset act only on unsaved edits and stop at the chip they were forked from, outlined again; every slider shows a tick at the Shipped value and snaps to it, and a changed control's ↺ puts that control alone back to Shipped as one Undo step.
- [ ] If persistence was requested, Save & pin writes one namespaced candidate that passes `verify.sh profile`, × deletes only it, reopening lists the stored looks, and a failed write is shown and keeps the look in the panel.
- [ ] Primary pointer/touch, keyboard, focus, and gesture paths work.
- [ ] Applicable accessibility and reduced-motion paths work.
- [ ] Dismissal releases all lab-owned UI and work.
- [ ] Release artifact contains no activatable lab, launch argument, URL scheme, notification name, shake selector, key command, or fallback label.

## Evidence

For an ephemeral lab, replace the storage checkbox with
`N/A: persistence not requested` and attach evidence that no storage action or
storage writer is present. Do not mark an unrun applicable check as N/A.

- Static-check commands/output:
- Hands-on screenshots/video/logs:
- Release-artifact inspection commands/output:

## Limitations and failures

- None recorded; checks remain PENDING until evidence is attached.

## Result

PENDING — any unchecked, failed, or untested applicable item blocks approval.
Documented N/A storage checks do not block an ephemeral lab.
