# Looks, Save & copy, and Apply

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

Every lab has all of this, ephemeral labs included: saved looks live in memory
and in the log. The one write an ephemeral lab makes is the result file below.

## The panel

| Control | What it does |
|---|---|
| **Toggle** | The pill, button, or menu item that opens the lab is named after the feature: **Nav Lab**, **Card Lab**. |
| **Chips** | One row under the header: **Shipped** (the baseline), then each saved look, labeled **Look 1**, **Look 2**, … in save order. Tapping a chip shows it in the real feature. The selected chip is always the look the feature shows; it has a visible outline, like any selected option, and is marked selected for assistive tech. While Shipped has unsaved edits, no chip is outlined. Selection is never shown by label text. Example: Shipped · Look 1 · Look 2 |
| **Controls** | Presets, sliders, toggles. Always enabled; they show and edit the selected look. Presets are actions, never outlined. |
| **Save & copy** | There from the first open for the whole life of the lab. Keeps the current look: unsaved edits on Shipped become the next **Look N** and it is selected; a selected look is saved as it is (no new chip). Copies `land look-N` and logs the look's `UITUNINGLAB_CANDIDATE` line, with a status such as `Saved Look 2 · copied land look-2`. Before the first Apply that is all: no Done line, no result file, no beacon, so the agent's waiter is not woken. After the first Apply it also hands the pick over like Apply (Done line, result file, beacon, result bar). Disabled on Shipped with no edits. |
| **Apply** | Visible until the first Apply, then hidden for the rest of the lab's life (Change does not bring it back). Keeps unsaved edits on Shipped as the next Look N first, then picks the selected chip (`original` for Shipped with no edits) and finishes: logs the result, sends it to the agent's waiter, writes the result file, copies `land <name>` to the clipboard, and shrinks the panel to one bar. Change brings back the same panel at its full size, controls included. |
| **Result bar** | `Applied: Look 2 · Change` after Apply; `Copied land look-3: paste it in chat so the agent applies it · Change` after a later Save & copy (`Tell the agent: land look-3` when the clipboard failed). Under it, a smaller line says where the pick was saved: `Saved Look 3 in .ui-tuning-lab/result.json` (web: `Saved Look 3 in localStorage uiTuningLab.result`), or the failure status when the write failed, never a false Saved. Change reopens the panel. Picking again replaces the result: the newest pick wins. No confirmation step. |
| **× on the selected look** | Shown only on the selected saved look, never on Shipped or an unselected chip, so nothing is removed by accident. Removes it, with an accessible name such as "Remove Look 2", and selects Shipped. |
| **⋯ menu** | Copy values (the selected look). |
| **Hint** | One line pinned at the bottom: *Save & copy to keep a look · Apply to finish*; after the first Apply, *Save & copy, then paste it in chat* |

Labels are plain words: no star or check-mark glyphs anywhere in the panel.

Rules:

- No chip appears or is renamed on its own: a look becomes a chip only through
  Save & copy (or Apply). There is no compare mode; the feature always renders
  the selected look, so switching chips is the comparison.
- A saved look changes in place while it is selected, with no unsaved marker,
  and keeps its edits when the user switches away and comes back.
- Shipped is read-only. Moving a control or applying a preset while Shipped is
  selected shows the edit live as unsaved changes, with no chip outlined; Save &
  copy keeps them as the next Look N. Tapping a chip first drops them.
- Closing the lab leaves the feature on the selected look; reopening keeps the
  looks and the selection. Shipped is one tap away, so there is no Reset.
- `basedOn` records where a look came from: `baseline` when it was started from
  Shipped, or the kebab-case preset key when a preset was last applied to it.
- Keyboard shortcuts for the chips (Command-1 to Command-9 on macOS) are optional
  and only added when inspection shows they are free.

## Names

A saved look is numbered in save order, so the chip is short and the name works
as a code in chat (`land look-2`):

1. Its name is `look-N`, shown on the chip as **Look N**. N is one past the
   highest `look-N` already issued, so new looks continue past seeded or stored
   ones.
2. A name is never renamed and never reused within a run of the app (a removed
   number stays taken). In a persisted lab, every name already in storage is
   taken too.
3. Finalists kept in the project keep their names when seeded; a name that is
   not `look-N` shows as it is.

## Log lines

Each line is one sorted-key JSON object after the tag, with the same number
rounding as `UITUNINGLAB_VALUES`. `values` is always the diff against the
baseline, never the full configuration.

```text
UITUNINGLAB_CANDIDATE {"basedOn":"compact","name":"look-2","values":{"cornerRadius":14,"design":"capsule"}}
UITUNINGLAB_CANDIDATE_REMOVED {"name":"look-1"}
UITUNINGLAB_DONE {"candidates":[{"basedOn":"compact","name":"look-2","values":{"cornerRadius":14,"design":"capsule"}}],"values":{"cornerRadius":14,"design":"capsule"},"winner":"look-2"}
```

- A look logs `UITUNINGLAB_CANDIDATE` on Save & copy (and when Apply keeps
  unsaved edits), and again with its current values when it is left after an
  edit (another chip is selected, the lab closes, Save & copy, or Apply). The
  latest line for a name wins.
- **Apply** (and Save & copy after the first Apply) logs `UITUNINGLAB_DONE`.
  `winner` is the selected look, or
  `original` when Shipped was selected (land nothing); `values` is the winner's
  values (`{}` for `original`). The Shipped chip's wire name is `original`.
  Older labs could log winner `draft`; treat its `values` like a look's.
- `candidates` holds every look still in the panel, oldest first, so the line
  alone is enough to land or keep any of them.
- A look loaded from storage or seeded from the project logs its own
  `UITUNINGLAB_CANDIDATE` line when the lab opens.
- When the user names a look in chat before picking ("land look-2"),
  rebuild the list from the `UITUNINGLAB_CANDIDATE` and
  `UITUNINGLAB_CANDIDATE_REMOVED` lines: the latest line for a name wins, unless
  a later removal names it. An ephemeral lab restarts its names after a relaunch,
  so when two runs used the same name, ask the user to pick again.

## The result file

**Apply** (and Save & copy after the first Apply) also writes the `UITUNINGLAB_DONE` object, plus `savedAt` (ISO-8601
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

Apply also POSTs its Done line to `http://localhost:47321/pick`
(development builds only, fire and forget, errors ignored), where the agent's
waiter (`scripts/wait-for-pick.py`) listens while it also polls the log. Start
the waiter in the background at handover, every time, and say in **How to try
it** that Apply sends the pick by itself (`references/platform-handoff.md`,
"Wait for Done"). When it exits, its output is the result: land from it at once.
If the user writes first, stop it and follow their message. The waiter
catches the first Apply only: after it the agent is no longer listening, so a
later pick arrives as the `land <name>` the user pastes from Save & copy, and is
landed the same way (chat wins, `references/landing-protocol.md` step 1). When
the user says they picked but no line arrived, read the result file. When neither is reachable (a cloud device), the user pastes the
`land <name>` line the lab copied.

## Persistence

Only when persistence was requested, the lab also writes each saved look as a
profile with `schemaVersion: 2` (`references/config-schema.md`), one per
name, and loads them into the list when it opens:

| Platform | Location |
|---|---|
| iOS | Application Support `.ui-tuning-lab/candidates/<name>.json` in the app container |
| macOS | Application Support `<bundle-id>/.ui-tuning-lab/candidates/<name>.json`; a non-sandboxed app shares Application Support with every other app, so the bundle ID keeps labs apart |
| Web | `uiTuningLab.candidates.<name>` in `localStorage` |
| Other platforms | `references/platform-handoff.md`, "Where persisted candidates live" |

A look is written whenever it logs: on Save & copy, and again when it is left
after an in-place edit. A rewrite keeps the first `savedAt`, which keeps
fractional seconds, so looks load in the order they were saved. Remove deletes
that candidate's file or key and nothing else. A failed write shows in the
status line; the look stays in the panel and in the log. An entry that fails to decode, has the wrong
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
