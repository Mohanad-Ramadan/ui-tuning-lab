# Reusable Profile Template

Create a profile only when the user asks to save or reuse a tuning result. Keep
the ephemeral draft in memory otherwise.

Required fields (exactly these; see `references/config-schema.md`):

- `name`: kebab-case identifier.
- `platform`: `ios`, `macos`, or `web` while those candidates are being tested.
- `container`: actual host surface used by the app.
- `scope`: requested tuning dimensions.
- `schemaVersion`: currently `1`.
- `overrides`: the full draft configuration at save time, applied to the draft on load.
- `notes`: constraints or restore instructions; an empty string when there are none.

Keep environment details and validation evidence in the platform receipt rather
than the profile. Write profiles only after an explicit Save action, under
`.ui-tuning-lab/` (or `uiTuningLab.<name>` in web storage), using an atomic
replacement. Never write production settings. Check a saved file with
`sh <skill-dir>/scripts/verify.sh profile <file>`.
