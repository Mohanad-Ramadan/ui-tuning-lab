# Configuration Schema

There are two JSON documents, with different jobs. Neither is needed for an
ephemeral lab.

| Document | Purpose | Written by | Location | Validator |
|---|---|---|---|---|
| Lab config | A reusable lab definition: target, scope, baseline, presets, optional activation | The agent, when a lab is meant to be reused | `.ui-tuning-lab/lab.json` in the project | `verify.sh config` |
| Saved profile | Values the user kept from a running lab: a candidate (`schemaVersion: 2`) or a legacy single save (`schemaVersion: 1`) | The lab's Keep as candidate action when persistence was requested, or the agent keeping finalists at landing | `.ui-tuning-lab/candidates/<name>.json` (in the project, or in Application Support on Apple platforms) or `uiTuningLab.candidates.<name>` in web storage | `verify.sh profile` |

A lab config uses `schemaVersion: 1`; a saved profile uses `2` (a candidate) or
`1` (a legacy single save). Either is written as an integer literal. Both reject
placeholder strings (`REPLACE-ME`, `TODO`, `<...>`).

## Lab config

Template: `assets/labconfig.template.json`.

| Field | Type | Rule |
|---|---|---|
| `schemaVersion` | integer | `1` |
| `labTarget` | string | `feature`, or `container` when tuning the host itself |
| `scope` | string array | non-empty; the requested dimensions (`animation`, `layout`, `appearance`, `logic`) |
| `container` | string | the host surface the lab uses |
| `baseline` | object | non-empty; the feature's declared default |
| `variants` | array | each `{ "name": string, "overrides": object }` |
| `persist` | string | `none` or `namespaced-save` |
| `profile` | string | the legacy single-save name; kept for compatibility |
| `activation` | object | optional; `{ "human": string or string[], "agent": string, "fallback": string }`, each token non-blank; `human` as an array is non-empty with distinct tokens, for a lab that opens several ways. Records the chosen entry points (`references/activation.md`). `verify.sh config` validates it when present; configs without it remain valid. |
| `candidates` | string array | optional; non-empty, distinct kebab-case names, never `draft` or `baseline`, of the finalists kept in `.ui-tuning-lab/candidates/` (`references/candidates.md`). `verify.sh config` validates it when present. |

`activation` is memory for reuse, not a requirement. Write it only when the user
asks to remember how the lab opens, or confirms when a reusable config already
exists. It never goes in a saved profile: `verify.sh profile` rejects extra
fields.

## Saved profile

Template: `assets/profile.template.json`, a candidate. The examples'
`UITuningLabProfile` types have exactly these fields.

| Field | Type | Rule |
|---|---|---|
| `schemaVersion` | integer | `2` for a candidate; `1` for a legacy single save, which has none of the candidate-only fields |
| `name` | string | kebab-case |
| `platform` | string | `ios`, `macos`, `web`, `visionos`, `android`, `flutter`, `react-native`, `windows`, `linux`, or `harmonyos`; Flutter and React Native use the framework value (`references/platform-handoff.md`) |
| `container` | string | the host surface used when saving |
| `scope` | string array | non-empty |
| `overrides` | object | non-empty; the full draft configuration at save time, including `design` for a design-variant lab (`references/design-variants.md`) |
| `notes` | string | may be empty |
| `basedOn` | string | candidates only; kebab-case: the preset it started from, `baseline`, or another candidate's name |
| `savedAt` | string | candidates only; ISO-8601 UTC, for example `2026-11-04T14:23:24Z` |

`verify.sh profile` rejects any other field. A lab loading a profile must check
`schemaVersion`, `platform`, and the shape of `overrides`; the example loaders
ignore unknown fields and do not range-check values, so validate a hand-edited
file with `verify.sh profile` before loading it. On any mismatch the lab shows an
error, keeps the current draft, and leaves the stored profile untouched
(`references/edge-cases.md`). Loading applies `overrides` to the draft only; the
baseline does not change, so Reset still returns to it.

Validate a web profile by copying the stored value to a file first. Validate an
iOS profile from the app container, for example
`xcrun simctl get_app_container booted <bundle-id> data` followed by
`Library/Application Support/.ui-tuning-lab/candidates/<name>.json`. On macOS
it is `Application Support/<bundle-id>/.ui-tuning-lab/candidates/<name>.json`,
under `~/Library` or, for a sandboxed app, its container's `Data/Library`.
