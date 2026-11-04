# Candidates, Done, and Compare

A tuning session rarely ends with one value. The user tries a preset, nudges it,
likes it, tries something else, and wants to come back. Candidates keep those
finalists where both the user and the agent can see them, **Done** tells the
agent the session is over, and **Compare** flips between the finalists in the
real feature.

Every lab has all three, ephemeral labs included: candidates live in memory and
in the log, so nothing is written to storage unless persistence was requested.

## The panel

| Control | What it does |
|---|---|
| **Keep as candidate** | Snapshots the draft under a new name (`a`, `b`, … `z`, then `aa`, `ab`). Disabled while anything other than the draft is shown. |
| **Candidates list** | One row per candidate: its name, what it started from, **Load** (copies it into the draft; disabled while anything other than the draft is shown) and **Remove**. Hidden while empty. |
| **Compare** | A picker that appears once a candidate exists: **Draft** and each candidate. Choosing a candidate renders it in the real feature. |
| **Done** | Copies the draft's values, like Copy values, and logs the handoff line below. While Compare shows a candidate, Done first loads that candidate into the draft, so it is the winner. Disabled while Show baseline is on. The lab stays open. |
| **Hint** | A footer line pinned below the scrolling controls, so it is visible however long the panel grows: *Finished? Keep the ones you like, then press Done, or tell the agent "land b".* |

Rules:

- **Keep** skips a draft that matches the baseline ("Matches the baseline;
  nothing to keep") or an existing candidate ("Same as b"). It never renames or
  overwrites an existing candidate.
- **Names are never reused** within a run of the app: after Remove `a`, the
  next Keep is still a new name. In a persisted lab every name already in
  storage is taken too, including entries that were skipped as unreadable, and
  Keep checks that its file or key does not exist before writing. `draft` and
  `baseline` are never candidate names.
- **`basedOn`** records where the draft came from: the kebab-case name of the
  last preset applied (`ledger`), `baseline` after Reset or when the lab first
  opens, or the candidate's name after Load. It lives beside the draft, so a
  draft kept across close and reopen keeps its `basedOn`. Edits keep the same
  `basedOn`.
- **Compare** shares the Show baseline mechanism: the draft is stashed while a
  candidate or the baseline is shown, and restored when Draft is picked or the
  lab closes. Show baseline and Compare are exclusive: turning one on turns the
  other back to Draft. Editing while a candidate is shown follows the baseline
  rule (`references/control-mapping.md`): disable the controls, or switch back
  to the draft on the first edit.
- Removing the candidate being shown returns Compare to Draft.
- Keyboard shortcuts for Compare (for example Command-1 to Command-9 on macOS)
  are optional and only added when inspection shows they are free.

## Log lines

Each line is one sorted-key JSON object after the tag, with the same number
rounding as `UITUNINGLAB_VALUES`. `values` is always the diff against the
baseline, never the full configuration.

```text
UITUNINGLAB_CANDIDATE {"basedOn":"ledger","name":"b","values":{"cornerRadius":14}}
UITUNINGLAB_CANDIDATE_REMOVED {"name":"a"}
UITUNINGLAB_DONE {"candidates":[{"basedOn":"ledger","name":"b","values":{"cornerRadius":14}}],"values":{"cornerRadius":14},"winner":"b"}
```

- `winner` is the candidate the draft exactly matches when Done is pressed, or
  `null` when it matches none. `null` with a non-empty `candidates` list means
  "these are the finalists; decide with me".
- `candidates` holds every candidate still in the panel, oldest first, each
  with the same `basedOn`, `name`, and `values` as its `UITUNINGLAB_CANDIDATE`
  line, so the Done line alone is enough to land or keep any of them.
- Done with no candidates is the same as Copy values plus a finish signal.
- A candidate loaded from storage or seeded from the project when the lab opens
  logs its own `UITUNINGLAB_CANDIDATE` line, so the log always shows every
  candidate in the panel.

Read them like `UITUNINGLAB_VALUES` (`references/landing-protocol.md`, step 1),
over a window that covers the whole session (`--last 1h`, or `--start` at the
time the lab opened) rather than the 10 minutes that suffice for a single Copy
values. The Done line alone is enough. Before Done is pressed (the user says
"land b" in chat instead), rebuild the list from the `UITUNINGLAB_CANDIDATE`
and `UITUNINGLAB_CANDIDATE_REMOVED` lines: the latest `UITUNINGLAB_CANDIDATE`
line for a name wins, unless a later `UITUNINGLAB_CANDIDATE_REMOVED` names it.
An ephemeral lab starts again at `a` after a relaunch, so when two runs used the
same name, ask the user to press Done rather than guessing.

## Waiting for Done

After opening the lab for the user on Apple platforms, the agent can wait for
Done instead of waiting for a message. Start a background command that exits on
the first Done line after it starts, and say so in **How to try it**. Poll
`log show` rather than piping `log stream` into `grep -m1`: a stream keeps
running after grep exits, so that pipeline never finishes. Call it as
`/usr/bin/log`: in zsh, a bare `log` is a shell builtin.

```sh
# macOS. For the iOS Simulator, replace `/usr/bin/log show` with `xcrun simctl spawn booted log show`.
start=$(date '+%Y-%m-%d %H:%M:%S')
until line=$(/usr/bin/log show --start "$start" --style compact \
    --predicate 'subsystem == "ui-tuning-lab" AND eventMessage CONTAINS "UITUNINGLAB_DONE"' |
    grep -m1 UITUNINGLAB_DONE); do sleep 3; done
printf '%s\n' "$line"
```

When it exits, its output is the Done line itself: start landing from it. If the
user writes before pressing Done, stop the command and follow their message. The
web has no console stream the agent can wait on: read the console when the user
next writes, which the hint already asks them to do. Without a background
runner, the hint is the whole mechanism.

## Persistence

Only when persistence was requested, the lab also writes each candidate as a
saved profile with `schemaVersion: 2` (`references/config-schema.md`), one per
name, and loads them into the list when it opens:

| Platform | Location |
|---|---|
| iOS | Application Support `.ui-tuning-lab/candidates/<name>.json` in the app container |
| macOS | Application Support `<bundle-id>/.ui-tuning-lab/candidates/<name>.json`; a non-sandboxed app shares Application Support with every other app, so the bundle ID keeps labs apart |
| Web | `uiTuningLab.candidates.<name>` in `localStorage` |

`savedAt` keeps fractional seconds, so two quick Keeps load in the order they
were made. Remove deletes that candidate's file or key and nothing else. A
failed write refuses the Keep: the status line shows the error and the
candidate is not added, so the panel never shows a candidate that storage does
not hold. An entry that fails to decode, has the wrong `schemaVersion` or
`platform`, or whose `name` does not match its file or key, is reported in the
status line, skipped, and left untouched; its name stays taken. A stored
candidate that now matches the baseline is skipped and reported the same way.

## Keeping finalists for later

App storage is per install and per origin, and the agent cannot always reach it.
The project is the durable place. At landing, when candidates other than the
winner exist, ask once, together with the remove-or-keep question, whether to
keep the finalists. If yes:

1. Write each one as a `schemaVersion: 2` profile in the project's
   `.ui-tuning-lab/candidates/<name>.json`, with `overrides` holding the full
   configuration (baseline plus the candidate's `values`), and validate it with
   `sh <skill-dir>/scripts/verify.sh profile <file>`. Keep each candidate's
   `basedOn`, and its `savedAt` when it has one; otherwise use the landing time.
2. List their names in `.ui-tuning-lab/lab.json` under `candidates`, writing a
   lab config if none exists.
3. Ask before committing `.ui-tuning-lab/`; it is never shipped.

When a later session reopens the lab, seed it with those candidates: pass them
as the lab's initial candidates in the gated lab code, so Compare works at once
with no app storage. Each seeded candidate's `values` is its `overrides` diffed
against the current baseline; one that now matches the baseline is dropped and
reported. "Test b and c together" then means: rebuild the lab with b and c
seeded and open it on Compare.
