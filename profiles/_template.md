# Reusable Profile Template

Create a profile only when the user asks to save or reuse a tuning result. Keep
the ephemeral draft in memory otherwise.

Required fields:

- `name`: kebab-case identifier.
- `platform`: `ios`, `macos`, or `web` while those candidates are being tested.
- `container`: actual host surface used by the app.
- `scope`: requested tuning dimensions.
- `schemaVersion`: currently `1`.
- `overrides`: saved values applied to the shared feature configuration.
- `notes`: optional constraints or restore instructions.

Keep environment details and validation evidence in the platform receipt rather
than the profile. Write profiles only after an explicit Save action, under
`.ui-tuning-lab/`, using an atomic replacement. Never write production settings.
