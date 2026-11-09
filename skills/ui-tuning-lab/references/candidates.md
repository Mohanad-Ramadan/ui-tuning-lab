# Looks, Duplicate, and Choose

The user works on a few looks side by side, flips between them, and picks one.
The panel makes that a row of chips and two buttons, and the pick reaches the
agent on its own.

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
| **Chips** | One row under the header: **Shipped** (the baseline), then each pin. Tapping a chip shows it in the real feature. Exactly one chip is selected, and it is always the look the feature shows; it has a visible outline, like any selected option, and is marked selected for assistive tech. Selection is never shown by label text. Example: Shipped · capsule · compact-2 |
| **Controls** | Presets, sliders, toggles. Always enabled; they show and edit the selected look. Presets are actions, never outlined. |
| **Duplicate** | Copies the selected pin into a new pin and selects it, so two versions can be compared. Disabled while Shipped is selected. |
| **Choose** | Picks the selected chip and finishes: logs the result, writes the result file, copies `land <name>` to the clipboard, and shrinks the panel to one bar. Change brings back the same panel at its full size, controls included. |
| **Result bar** | `Chosen: capsule · Change`. Change reopens the panel. Picking again replaces the result: the newest pick wins. No confirmation step. |
| **× on a pin chip** | Removes it, with an accessible name such as "Remove capsule". Removing the selected pin selects Shipped. |
| **⋯ menu** | Copy values (the selected look). |
| **Hint** | One line pinned at the bottom: *Duplicate to compare · Choose to finish* |

Labels are plain words: no star or check-mark glyphs anywhere in the panel.

Rules:

- There is no draft, no stash, and no compare mode. The lab holds the pins and
  one selection, and the feature always renders the selected look. Switching
  chips is the comparison.
- A pin is a look being worked on: while it is selected, every control edits it
  in place.
- Shipped is read-only. Moving a control or applying a preset while Shipped is
  selected starts a new pin from the result and selects it.
- Closing the lab leaves the feature on the selected look; reopening keeps the
  pins and the selection. Shipped is one tap away, so there is no Reset.
- `basedOn` records where a pin came from: `baseline` when it was started from
  Shipped, the kebab-case preset key when a preset was last applied to it, or the
  pin it was duplicated from.
- Keyboard shortcuts for the chips (Command-1 to Command-9 on macOS) are optional
  and only added when inspection shows they are free.

## Names

A pin is named after what it is, so the chip is readable and the name works as
a code in chat (`land capsule`):

1. A pin started from Shipped: in a design-variant lab, the design key when it
   is not `original` (`capsule`); otherwise the preset applied (`compact`);
   otherwise `tweak`. A duplicate: its source's name without a `-N` suffix.
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

- A pin logs `UITUNINGLAB_CANDIDATE` when it is created, and again with its
  current values when it is left after an edit (another chip is selected, the
  lab closes, or Choose). The latest line for a name wins.
- **Choose** logs `UITUNINGLAB_DONE`. `winner` is the selected pin, or
  `original` when Shipped was selected (land nothing); `values` is the winner's
  values (`{}` for `original`). The Shipped chip's wire name is `original`.
  Older labs could log winner `draft`; treat its `values` like a pin's.
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

A pin is written when it is created and again whenever it logs new values; a
rewrite keeps the first `savedAt`, which keeps fractional seconds, so pins load
in the order they were made. Remove deletes that candidate's file or key and
nothing else. A failed write shows in the status line; the pin stays in the
panel and in the log. An entry that fails to decode, has the wrong
`schemaVersion` or `platform`, or whose `name` does not match its file or key,
is reported in the status line, skipped, and left untouched; its name stays
taken.

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
as the lab's initial candidates in the gated lab code, so their chips are
there at once with no app storage. Each seeded candidate's `values` is its `overrides` diffed
against the current baseline; one that now matches the baseline is dropped and
reported. "Test b and c together" then means: rebuild the lab with b and c
seeded; switching between their chips is the comparison.
