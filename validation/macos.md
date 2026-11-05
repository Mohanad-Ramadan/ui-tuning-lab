# macOS Validation Receipt

- Status: PENDING
- Commit: not recorded
- Build/archive identifier: not recorded
- Hardware and macOS version: not tested
- Tester: not recorded
- Date: not recorded

## Required checks

- [ ] Baseline equivalence; compact and spacious variants; exact reset.
- [ ] Copy values copies and logs only changed fields; landing writes them into the feature defaults; removal leaves `source-gates` at N/A.
- [ ] Candidates, Compare, and Done (`references/candidates.md`): Keep as candidate logs `UITUNINGLAB_CANDIDATE` and skips duplicates; Compare renders each candidate and Draft restores the draft; Done logs a `UITUNINGLAB_DONE` line carrying the winner and every candidate; the finish hint is visible. **Not run:** added for 1.2.0.
- [ ] If persistence was requested, Keep writes one namespaced candidate that passes `verify.sh profile`, Remove deletes only it, reopening lists stored candidates, and a failed write retains the draft.
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
