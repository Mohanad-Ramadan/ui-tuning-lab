# iOS/iPadOS Validation Receipt

- Status: PENDING
- Commit: not recorded
- Build/archive identifier: not recorded
- Devices and OS versions: compact iPhone and iPad required; not tested
- Tester: not recorded
- Date: not recorded

## Required checks

- [ ] Baseline equivalence; compact and relaxed variants; exact reset.
- [ ] Copy values copies and logs only changed fields; landing writes them into the feature defaults; removal leaves `source-gates` at N/A.
- [ ] If persistence was requested, explicit namespaced Save and Load saved success, and failure-with-draft-retention.
- [ ] Rotation and compact/regular presentation adaptation.
- [ ] Dynamic Type, VoiceOver, Reduce Motion, keyboard/focus, gestures, dismissal.
- [ ] Closing releases the controls and all lab-owned work.
- [ ] Archived Release product contains no lab UI, strings, resources, or working activation path.

## Evidence

For an ephemeral lab, replace the Save checkbox with
`N/A: persistence not requested` and attach evidence that no Save action or
storage writer is present. All other applicable checks remain required.

- Static checks: PENDING
- Hands-on screenshots/video/logs: PENDING
- Archive inspection commands/output: PENDING

## Limitations and result

No pilot has been run. PENDING blocks verified status and publication.
