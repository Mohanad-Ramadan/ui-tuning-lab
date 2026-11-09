# Pins and Choose

The user flips between looks, pins the ones they like, and picks one. The panel
makes that two buttons and a row of chips, and the pick reaches the agent on its
own.

## Contents

- The panel
- Names
- Log lines
- The result file
- Waiting for the pick
- Persistence
- Keeping finalists for later

Every lab has all of this, ephemeral labs included: pins live in memory and in
the log. The one write an ephemeral lab makes is the result file below.

## The panel

| Control | What it does |
|---|---|
| **Toggle** | The pill, button, or menu item that opens the lab is named after the feature: **Nav Lab**, **Card Lab**. |
| **Chips** | One row under the header: **Shipped** (the baseline), then each pin. Tapping a chip shows it in the real feature. The selected chip has a visible outline, like any selected option; a label such as "+ edits" is never used to say what is selected. Example: Shipped · capsule · compact-2 |
| **Presets** | The preset buttons in the controls are outlined while the draft, with or without edits, started from that preset. |
| **Pin** | Pins the draft: the new pin gets a chip and is selected. Disabled while there is nothing unpinned, that is, while the draft matches Shipped or a pin (a status may say "Same as Shipped" or "Same as capsule"). |
| **Choose** | Picks what the feature shows (Shipped, a pin, or the draft while it holds unpinned edits) and finishes: logs the result, writes the result file, copies `land <name>` to the clipboard, and shrinks the panel to one bar. Change brings back the same panel at its original size, controls included. |
| **Result bar** | `Chosen: capsule · Change`. Change reopens the panel. Picking again replaces the result: the newest pick wins. No confirmation step. |
| **× on a pin chip** | Removes it, with an accessible name such as "Remove capsule". |
| **⋯ menu** | Reset (the draft back to Shipped, which is shown and selected) and Copy values. |
| **Hint** | One line pinned below the controls: *Pin looks to compare · Choose to finish* |

Labels are plain words: no star or check-mark glyphs anywhere in the panel.

Rules:

- There is exactly one draft, the working copy the controls edit. Pins are
  frozen snapshots; Shipped is read-only, so the controls are disabled while it
  is shown. Moving a control while a pin is shown first copies that pin into the
  draft, so a pin can be refined; the pin itself does not change.
- The draft has no chip of its own. It sits under its **home** chip: the chip it
  matches (Shipped or a pin), else the pin it was copied from, else Shipped.
  That chip is the selected one while the draft is shown, with or without
  unpinned edits; the controls stay live, and moving one starts from that look.
  To compare unpinned edits with Shipped, Pin them first.
- Show baseline, Compare, and Load are not separate controls: the chips are all
  three. The draft is stashed while another chip is shown and restored when its
  home chip is tapped again or the lab closes.
- `basedOn` records where the draft came from: the kebab-case name of the last
  preset applied, `baseline` after Reset or when the lab first opens, or a pin's
  name after it was copied into the draft. Edits keep the same `basedOn`.
- Keyboard shortcuts for the chips (Command-1 to Command-9 on macOS) are optional
  and only added when inspection shows they are free.

## Names

A pin is named after what it is, so the chip is readable and the name works as
a code in chat (`land capsule`):

1. In a design-variant lab, the design key when it is not `original`
   (`capsule`); otherwise the last preset applied (`compact`); otherwise `tweak`.
2. If the name is taken, add `-2`, `-3`, … (`capsule-2`).
3. Names are kebab-case, never reused within a run of the app (a removed name
   stays taken), and never `draft`, `now`, `original`, or `baseline`. In a
   persisted lab, every name already in storage is taken too.

## Log lines

Each line is one sorted-key JSON object after the tag, with the same number
rounding as `UITUNINGLAB_VALUES`. `values` is always the diff against the
baseline, never the full configuration.

```text
UITUNINGLAB_CANDIDATE {"basedOn":"compact","name":"capsule","values":{"cornerRadius":14,"design":"capsule"}}
UITUNINGLAB_CANDIDATE_REMOVED {"name":"tweak"}
UITUNINGLAB_DONE {"candidates":[{"basedOn":"compact","name":"capsule","values":{"cornerRadius":14,"design":"capsule"}}],"values":{"cornerRadius":14,"design":"capsule"},"winner":"capsule"}
```

- **Choose** logs `UITUNINGLAB_DONE`. `winner` is the pin that was shown,
  `original` when Shipped was shown (land nothing), or `draft` when the draft
  was shown holding unpinned edits; `values` is the winner's values (`{}` for
  `original`). The wire names predate the labels: the Shipped chip logs winner
  `original` and unpinned edits log `draft`.
- `candidates` holds every pin still in the panel, oldest first, so the line
  alone is enough to land or keep any of them.
- A pin loaded from storage or seeded from the project logs its own
  `UITUNINGLAB_CANDIDATE` line when the lab opens.
- When the user names a pin in chat before picking ("land capsule"),
  rebuild the list from the `UITUNINGLAB_CANDIDATE` and
  `UITUNINGLAB_CANDIDATE_REMOVED` lines: the latest line for a name wins, unless
  a later removal names it. An ephemeral lab restarts its names after a relaunch,
  so when two runs used the same name, ask the user to pick again.

## The result file

**Choose** also writes the `UITUNINGLAB_DONE` object, plus `savedAt` (ISO-8601
UTC), to the app's own storage, so the pick survives quitting the app and the
agent can read it without a log:

- one file, `.ui-tuning-lab/result.json` (web: the `localStorage` key
  `uiTuningLab.result`), replaced atomically on every pick;
- development builds only, inside the lab's gate;
- where the platform needs a dependency the app lacks for this (Flutter
  `path_provider`, React Native AsyncStorage), skip the file and rely on the log
  and the clipboard code; never add a dependency for it. The same goes for the
  clipboard: where the app has no clipboard module (core React Native), show
  `land <name>` as selectable text in the result bar instead.

Locations and the command to read it per platform are in
`references/platform-handoff.md`, "The result file". At landing, delete the file
when the agent can reach it.

## Waiting for the pick

Where the agent can read the device's log, wait for `UITUNINGLAB_DONE` in the
background instead of waiting for a message, and say so in **How to try it**
(`references/platform-handoff.md`, "Wait for Done"). When it exits, its output is
the result: land from it. If the user writes first, stop it and follow their
message. When the user says they picked but no line arrived, read the result
file. When neither is reachable (a cloud device), the user pastes the
`land <name>` line the lab copied.

## Persistence

Only when persistence was requested, the lab also writes each pin as a saved
profile with `schemaVersion: 2` (`references/config-schema.md`), one per
name, and loads them into the list when it opens:

| Platform | Location |
|---|---|
| iOS | Application Support `.ui-tuning-lab/candidates/<name>.json` in the app container |
| macOS | Application Support `<bundle-id>/.ui-tuning-lab/candidates/<name>.json`; a non-sandboxed app shares Application Support with every other app, so the bundle ID keeps labs apart |
| Web | `uiTuningLab.candidates.<name>` in `localStorage` |
| Other platforms | `references/platform-handoff.md`, "Where persisted candidates live" |

`savedAt` keeps fractional seconds, so two quick Pins load in the order they
were made. Remove deletes that candidate's file or key and nothing else. A
failed write refuses the Pin: the status line shows the error and the
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
