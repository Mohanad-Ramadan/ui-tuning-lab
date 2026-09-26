# Validation

Platform guidance remains candidate until `ios.md`, `macos.md`, and `web.md` all
record PASS against the same commit. Copy `receipt-template.md` for additional
platforms rather than weakening these checks.

A receipt is evidence, not a forecast. Use `PENDING` for every unrun check and
`FAIL` for an observed failure. Either blocks approval. Record commands, artifact
identity, and links to screenshots, video, logs, or inspection output. Never copy
results between commits.

Publishing remains separate and requires explicit approval after all three
receipts pass against one commit.
