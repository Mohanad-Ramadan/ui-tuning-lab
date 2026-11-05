# Validation

These receipts record pilots of the skill itself in real apps. They are
evidence, not a release gate: the skill is published and improved in the open,
and issues and pull requests are how gaps get found and fixed. For work in an
app, copy `receipt-template.md` into the target project or include the evidence
in its task report; do not overwrite the installed skill's receipts.

A receipt reports what was observed. Use `PENDING` for an unrun check and
`FAIL` for an observed failure, record commands, artifact identity, and links to
screenshots, video, logs, or inspection output, and never copy results between
commits. A pilot that finds a problem leads to a fix release, not a withdrawn
one. Copy `receipt-template.md` for additional platforms.

Storage checks apply only when persistence was requested. For an ephemeral lab,
record `N/A: persistence not requested` with evidence that no storage action or
storage writer is present.

One check is required before every release, whatever the receipts say: on each
platform with a worked example, the release-artifact search
(`references/verify-protocol.md`, "Release-artifact inspection") finds no lab
code or activation path. A lab that leaks into users' production builds is the
one failure this skill must not ship.
