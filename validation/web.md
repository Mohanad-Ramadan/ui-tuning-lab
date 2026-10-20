# Web Validation Receipt

- Status: PENDING
- Commit: not recorded
- Build/bundle identifier: not recorded
- Browsers/devices: Chromium, Safari, Firefox; desktop and mobile required; not tested
- Tester: not recorded
- Date: not recorded

## Required checks

- [ ] Baseline equivalence; compact and relaxed variants; exact reset.
- [ ] Copy values copies and logs only changed fields; landing writes them into the feature defaults; removal leaves `source-gates` at N/A.
- [ ] If persistence was requested, explicit `uiTuningLab.*` Save and Load saved success, and failure-with-draft-retention.
- [ ] Desktop/mobile layout, pointer/touch, keyboard, focus, and light-dismiss.
- [ ] Screen-reader behavior and reduced-motion behavior where applicable.
- [ ] Conditional unmount removes UI and listeners.
- [ ] Production assets/source maps contain no lab code and query, storage, keyboard, and menu activation paths fail.

## Evidence

For an ephemeral lab, replace the Save checkbox with
`N/A: persistence not requested` and attach evidence that no Save action or
storage writer is present. All other applicable checks remain required.

- Static checks: PENDING
- Hands-on screenshots/video/logs: PENDING
- Production bundle inspection commands/output: PENDING

## Limitations and result

No pilot has been run. PENDING blocks verified status and publication.
