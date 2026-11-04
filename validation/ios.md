# iOS/iPadOS Validation Receipt

- Status: PENDING
- Commit: not recorded
- Build/archive identifier: not recorded
- Devices and OS versions: compact iPhone and iPad required; not tested
- Tester: not recorded
- Date: not recorded

## Required checks

- [ ] Baseline equivalence; compact and relaxed variants; exact reset.
- [ ] Agent path: `-UITuningLabOpen 1` opens the lab; the argument, handler, and strings are absent from the archived Release product.
- [ ] Human path: the chosen gesture or control opens the lab; with a text field focused, shake performs the system undo; the path re-arms after the lab closes.
- [ ] The visible fallback opens the lab and is reachable with VoiceOver and Switch Control.
- [ ] With more than one lab, each path opens the intended lab; a remembered activation that conflicts with the screen is reported.
- [ ] Copy values copies and logs only changed fields; landing writes them into the feature defaults; removal leaves `source-gates` at N/A.
- [ ] Candidates, Compare, and Done (`references/candidates.md`): Keep as candidate logs `UITUNINGLAB_CANDIDATE` and skips duplicates; Compare renders each candidate and Draft restores the draft; Done logs a `UITUNINGLAB_DONE` line carrying the winner and every candidate; the finish hint is visible. **Not run:** added for 1.2.0.
- [ ] If persistence was requested, Keep writes one namespaced candidate that passes `verify.sh profile`, Remove deletes only it, reopening lists stored candidates, and a failed write retains the draft.
- [ ] Rotation and compact/regular presentation adaptation.
- [ ] Dynamic Type, VoiceOver, Reduce Motion, keyboard/focus, gestures, dismissal.
- [ ] Closing releases the controls and all lab-owned work.
- [ ] Archived Release product contains no lab UI, strings, resources, or working activation path.

## Evidence

For an ephemeral lab, replace the storage checkbox with
`N/A: persistence not requested` and attach evidence that no storage action or
storage writer is present. All other applicable checks remain required.

- Static checks: PENDING
- Hands-on screenshots/video/logs: PENDING
- Archive inspection commands/output: PENDING

## Limitations and result

No pilot has been run. PENDING blocks verified status and publication.
