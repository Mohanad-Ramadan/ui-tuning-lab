# Configuration Schema

There are two JSON documents, with different jobs. Neither is needed for an
ephemeral lab.

| Document | Purpose | Written by | Location | Validator |
|---|---|---|---|---|
| Lab config | A reusable lab definition: target, scope, baseline, presets | The agent, when a lab is meant to be reused | `.ui-tuning-lab/lab.json` in the project | `verify.sh config` |
| Saved profile | Values the user saved from a running lab | The lab's explicit Save action | `.ui-tuning-lab/<name>.json` (Application Support on Apple platforms) or `uiTuningLab.<name>` in web storage | `verify.sh profile` |

Both use `schemaVersion: 1`, written as the integer literal `1`. Both reject
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
| `profile` | string | the saved-profile name Save writes |

## Saved profile

Template: `assets/profile.template.json`. The examples' `UITuningLabProfile`
types have exactly these fields.

| Field | Type | Rule |
|---|---|---|
| `schemaVersion` | integer | `1` |
| `name` | string | kebab-case |
| `platform` | string | `ios`, `macos`, or `web` |
| `container` | string | the host surface used when saving |
| `scope` | string array | non-empty |
| `overrides` | object | non-empty; the full draft configuration at save time |
| `notes` | string | may be empty |

`verify.sh profile` rejects any other field. A lab loading a profile must check
`schemaVersion`, `platform`, and the shape of `overrides`; the example loaders
ignore unknown fields and do not range-check values, so validate a hand-edited
file with `verify.sh profile` before loading it. On any mismatch the lab shows an
error, keeps the current draft, and leaves the stored profile untouched
(`references/edge-cases.md`). Loading applies `overrides` to the draft only; the
baseline does not change, so Reset still returns to it.

Validate a web profile by copying the stored value to a file first. Validate an
Apple profile from the app container, for example
`xcrun simctl get_app_container booted <bundle-id> data` followed by
`Library/Application Support/.ui-tuning-lab/default.json`.
