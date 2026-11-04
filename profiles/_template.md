# Reusable Profile Template

Create a profile only when the user asks to save or reuse a tuning result: a
candidate written by a persisted lab, or a finalist kept in the project at
landing (`references/candidates.md`). Keep the ephemeral draft and candidates in
memory otherwise.

Required fields (exactly these; see `references/config-schema.md`):

- `name`: kebab-case identifier.
- `platform`: `ios`, `macos`, or `web` while those candidates are being tested.
- `container`: actual host surface used by the app.
- `scope`: requested tuning dimensions.
- `schemaVersion`: `2` for a candidate (`1` is the legacy single save, without
  `basedOn` and `savedAt`).
- `overrides`: the full draft configuration at save time, applied to the draft on load.
- `notes`: constraints or restore instructions; an empty string when there are none.
- `basedOn`: kebab-case preset, `baseline`, or candidate name it started from.
- `savedAt`: ISO-8601 UTC time it was kept.

Keep environment details and validation evidence in the platform receipt rather
than the profile. Write a profile only for Keep as candidate in a persisted lab,
or when keeping finalists at landing, under `.ui-tuning-lab/candidates/<name>.json`
(or `uiTuningLab.candidates.<name>` in web storage), atomically and never over
an existing entry. Never write production settings. Check a saved file with
`sh <skill-dir>/scripts/verify.sh profile <file>`.
