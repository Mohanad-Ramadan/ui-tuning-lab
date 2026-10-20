# Validation

These bundled receipts track pilots validating the skill itself. For work in an
app, copy `receipt-template.md` into the target project or include the evidence
in its task report; do not overwrite the installed skill's receipts.

Platform guidance remains candidate until `ios.md`, `macos.md`, and `web.md` all
record PASS against the same commit. Copy `receipt-template.md` for additional
platforms rather than weakening these checks.

A receipt is evidence, not a forecast. Use `PENDING` for every unrun check and
`FAIL` for an observed failure. Either blocks approval. Record commands, artifact
identity, and links to screenshots, video, logs, or inspection output. Never copy
results between commits.

Save checks apply only when persistence was requested. For an ephemeral lab,
record `N/A: persistence not requested` with evidence that no Save action or
storage writer is present. Other applicable checks still require PASS evidence.

Publishing remains separate and requires explicit approval after all three
receipts pass against one commit.
