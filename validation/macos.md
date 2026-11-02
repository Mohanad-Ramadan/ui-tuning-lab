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
- [ ] If persistence was requested, explicit namespaced Save and Load saved success, and failure-with-draft-retention.
- [ ] Menu command, shortcut, launch argument, and any visible fallback activate the lab; each is inert in the archived Release app.
- [ ] Focus returns after close, and multiple windows stay isolated.
- [ ] Keyboard navigation and VoiceOver.
- [ ] Closing releases panel content, observers, timers, tasks, and registrations.
- [ ] Archived Release app contains no command, panel, strings, resources, or working activation path.

## Evidence

For an ephemeral lab, replace the Save checkbox with
`N/A: persistence not requested` and attach evidence that no Save action or
storage writer is present. All other applicable checks remain required.

- Static checks: PENDING
- Hands-on screenshots/video/logs: PENDING
- Archive inspection commands/output: PENDING

## Limitations and result

No pilot has been run. PENDING blocks verified status and publication.
