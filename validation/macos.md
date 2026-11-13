# macOS Validation Receipt

- Status: PENDING
- Commit: not recorded
- Build/archive identifier: not recorded
- Hardware and macOS version: not tested
- Tester: not recorded
- Date: not recorded

## Required checks

- [ ] Baseline equivalence; compact and spacious variants; the Shipped chip shows the baseline exactly.
- [ ] Copy values copies and logs only changed fields; landing writes them into the feature defaults; removal leaves `source-gates` at N/A.
 **Not run:** the model as of 1.7.0.
- [ ] Undo, Redo, and Reset act only on unsaved edits and stop at the chip they were forked from, outlined again; every slider shows a tick at the Shipped value and snaps to it, and a changed control's ↺ puts that control alone back to Shipped as one Undo step. **Not run:** added for 1.6.0.
- [ ] If persistence was requested, Save & pin writes one namespaced candidate that passes `verify.sh profile`, × deletes only it, reopening lists the stored looks, and a failed write is shown and keeps the look in the panel.
- [ ] Menu command, shortcut, launch argument, and any visible fallback activate the lab; each is inert in the archived Release app.
- [ ] Focus returns after close, and multiple windows stay isolated.
- [ ] Keyboard navigation and VoiceOver.
- [ ] Closing releases panel content, observers, timers, tasks, and registrations.
- [ ] Archived Release app contains no command, panel, strings, resources, or working activation path.

## Evidence

For an ephemeral lab, replace the storage checkbox with
`N/A: persistence not requested` and attach evidence that no storage action or
storage writer is present. All other applicable checks remain required.

- Static checks: PENDING
- Hands-on screenshots/video/logs: PENDING
- Archive inspection commands/output: PENDING

## Limitations and result

No pilot has been run yet.
