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
- [ ] Reset exactly restores the baseline (the declared default), also after close and reopen.
- [ ] Copy values copies and logs only the changed fields, and landing writes them into the feature defaults.
- [ ] Candidates, Compare, and Done (`references/candidates.md`): Keep as candidate logs `UITUNINGLAB_CANDIDATE` and skips duplicates; Compare renders each candidate and Draft restores the draft; Done logs a `UITUNINGLAB_DONE` line carrying the winner and every candidate; the finish hint is visible.
- [ ] If persistence was requested, Keep writes one candidate under the documented namespace.
- [ ] If persistence was requested, a failed candidate write is visible and retains the draft.
- [ ] Primary pointer/touch, keyboard, focus, and gesture paths work.
- [ ] Applicable accessibility and reduced-motion paths work.
- [ ] Dismissal releases all lab-owned UI and work.
- [ ] Release artifact contains no activatable lab, launch argument, URL scheme, notification name, shake selector, key command, or fallback label.

## Evidence

For an ephemeral lab, replace both storage checkboxes with
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
