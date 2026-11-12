# Looks, Save & pin, and Apply

The user works on a few looks side by side, flips between them, and picks one.
The panel makes that a row of chips, an edit row, and two buttons, and the pick
reaches the agent on its own. A look never changes once it is pinned: editing
it forks a new, unsaved tune.

## Contents

- The panel
- Edits, Undo, Redo, and Reset
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
| **Chips** | One row under the header, scrolling sideways when it outgrows the panel (it never widens the panel): **Shipped** (the baseline), then each pinned look, labeled by where it came from and a number, in pin order (**Brass-1**, **Brass-2**, **Custom-1**; see Names). Tapping a chip shows it in the real feature, exactly as pinned, and drops any unsaved edits. The selected chip is the look the feature shows; it has a visible outline, like any selected option, and is marked selected for assistive tech. While there are unsaved edits, no chip is outlined. Selection is never shown by label text. Example: Shipped · Brass-1 · Custom-1 |
| **Controls** | Presets, sliders, toggles, pickers, and a lab's design choice. Always enabled; they show the look on screen. Every edit is an unsaved edit: on an outlined chip, Shipped or a pinned look, the first edit forks it (next section). Presets are actions, never outlined. |
| **Edit row** | **Undo**, **Redo**, and **Reset**, in one row under the controls (next section). Each is disabled when it has nothing to do. |
| **Save & pin** | The one save button; there is no Save. Always shown, enabled only while there are unsaved edits. Keeps them as a new pinned look, named from its `basedOn` (Names), selects and outlines it, copies `land <name>`, and logs the look's `UITUNINGLAB_CANDIDATE` line, with a status such as `Pinned Brass-2 · copied land brass-2`. The look it was forked from is unchanged. |
| **Save & pin after the first Apply** | Before the first Apply it only keeps a look: no Done line, no result file, no beacon, so the agent's waiter is not woken. After the first Apply it also hands the new look over like Apply (Done line, result file, beacon, result bar). |
| **Apply** | Visible until the first Apply, then hidden for the rest of the lab's life (Change does not bring it back). Pins unsaved edits first, like Save & pin; otherwise picks the selected chip (`original` for Shipped). Then finishes: logs the result, sends it to the agent's waiter, writes the result file, copies `land <name>` to the clipboard, and shrinks the panel to one bar. Change brings back the same panel at its full size, controls included. |
| **Result bar** | `Applied: Brass-2 · Change` after Apply; `Copied land brass-3: paste it in chat so the agent applies it · Change` after a later Save & pin (`Tell the agent: land brass-3` when the clipboard failed). Under it, a smaller line says where the pick was saved: `Saved Brass-3 in .ui-tuning-lab/result.json` (web: `Saved Brass-3 in localStorage uiTuningLab.result`), or the failure status when the write failed, never a false Saved. Change reopens the panel. Picking again replaces the result: the newest pick wins. No confirmation step. |
| **× on the selected look** | Shown only on the selected pinned look while it is outlined, never on Shipped, an unselected chip, or a look with unsaved edits forked from it, so nothing is removed by accident. Removes it, with an accessible name such as "Remove Brass-2", and selects Shipped. |
| **⋯ menu** | Copy values (the look as shown, unsaved edits included). |
| **Hint** | One line pinned at the bottom: *Save & pin to keep a look · Apply to finish*; after the first Apply, *Save & pin, then paste it in chat* |

Labels are plain words: no star or check-mark glyphs anywhere in the panel.

Rules:

- No chip appears or is renamed on its own: a look becomes a chip only through
  Save & pin (or Apply). There is no compare mode; the feature always renders
  the selected look, so switching chips is the comparison.
- Every chip is read-only: Shipped, and every pinned look, which is immutable
  once pinned. Any edit while a chip is outlined (a slider, toggle, preset,
  picker, design, or ↺) forks it: the chip loses its outline, and the edit
  becomes unsaved edits that start from that chip's values, shown live in the
  feature. The chip itself is unchanged. Edits on Shipped are the same case,
  forked from the baseline.
- There is one set of unsaved edits at a time, and it remembers the chip it
  was forked from (`original` for Shipped). Save & pin keeps it as a new look;
  tapping any chip, the one it was forked from included, drops it and shows that
  chip exactly. There is no unsaved marker on a chip: no outline and an enabled
  Save & pin are the signal.
- Unsaved edits that come back to exactly the values of the chip they were
  forked from (through Undo, Reset, ↺, or a control moved back) are no longer
  unsaved: that chip is outlined again, as if nothing had been edited.
- Closing the lab leaves the feature on the look shown, unsaved edits included;
  reopening keeps the looks, the unsaved edits with their history and the chip
  they were forked from, and the selection.
- `basedOn` records where a look came from: `baseline` when it was started from
  Shipped, or the kebab-case key of the last preset (or, in a lab with designs,
  design) applied to it. Unsaved edits start with the `basedOn` of the chip they
  were forked from (a fork of Brass-1 is `brass`, so Save & pin names it
  Brass-2; a fork of Custom-1 is `baseline`, so Custom-2), and a preset applied
  afterwards replaces it. A pinned look's `basedOn` and name never change.
- Keyboard shortcuts for the chips (Command-1 to Command-9 on macOS) are optional
  and only added when inspection shows they are free.

## Edits, Undo, Redo, and Reset

There is one history, and it belongs to the unsaved edits: it starts at the
chip they were forked from and ends when they are pinned or dropped. Pinned
looks have no edits and no history of their own. Reset and ↺ differ in what
they go back to: Reset takes the whole tune back to the chip it was forked
from, ↺ takes one control to the baseline.

- **One step per change.** A preset, a toggle, or a picker choice is one step.
  A run of changes from the same control in a row (one slider drag, a stepper
  held down) is one step, so Undo never walks a slider back a pixel at a time.
  A change from another control starts a new step.
- **Undo** steps back one unsaved edit. It stops at the chip the edits were
  forked from: undoing the first edit after a fork shows that chip exactly and
  outlines it again, with no unsaved edits. It never reaches back past a pin.
- **Redo** steps forward again. Any new edit clears what Redo could bring
  back.
- **Reset** drops the unsaved edits back to the chip they were forked from,
  outlined again, in one step, and that step can be undone. Disabled when
  there are no unsaved edits.
- **↺ on one control** is not Reset: it puts that control alone back to the
  baseline, what Shipped shows, never the look's last save
  (`references/control-mapping.md`, "Default marker and per-control reset").
  It is an ordinary edit: one step, which ends the current slider run, so the
  next drag is its own step. On a pinned look it forks unsaved edits like any
  other edit; when it makes them match the chip they were forked from again,
  that chip is outlined again (on Shipped: back at the baseline, no unsaved
  edits).
- **Save & pin** starts a fresh history at the look it pins: after it Undo
  and Redo are disabled until the next edit.
- **Keyboard:** where the platform has a convention and the panel holds focus,
  Command-Z / Command-Shift-Z (Control-Z / Control-Y on Windows and the web,
  also Control-Shift-Z on the web) run Undo and Redo. Never take them while a
  text input outside the panel has focus, and never register them app-wide:
  the app's own undo wins outside the panel.
- Tapping a chip, removing a look, and Apply are not edits and never enter a
  history. Tapping a chip clears the history along with the unsaved edits.

## Names

A pinned look is named after where it came from and numbered, so the chip is
short, says what the look is, and works as a code in chat (`land brass-2`):

1. Its prefix is its `basedOn` at the moment it is pinned: the preset's (or
   design's) kebab-case key, or `custom` for a look started from Shipped with
   no preset. Unsaved edits forked from a pinned look carry that look's
   `basedOn`, so a fork of Brass-1 pins as Brass-2. Its name is `<prefix>-N`: `brass-1`, `warm-glow-2`, `custom-1`.
2. N counts per prefix: one past the highest `<prefix>-N` already issued, so
   new looks continue past seeded or stored ones (`brass-3` after `brass-2`,
   while the first Custom look is still `custom-1`).
3. The chip shows the name with each word capitalized and the number kept
   after a hyphen: `brass-2` is **Brass-2**, `warm-glow-1` is **Warm Glow-1**.
   A name that does not end in `-N` shows as it is.
4. A name is never renamed and never reused within a run of the app (a removed
   number stays taken). In a persisted lab, every name already in storage is
   taken too.
5. Finalists kept in the project keep their names when seeded, older
   `look-N` names included (shown as **Look-2**).

## Log lines

Each line is one sorted-key JSON object after the tag, with the same number
rounding as `UITUNINGLAB_VALUES`. `values` is always the diff against the
baseline, never the full configuration.

```text
UITUNINGLAB_CANDIDATE {"basedOn":"compact","name":"compact-2","values":{"cornerRadius":14,"design":"capsule"}}
UITUNINGLAB_CANDIDATE_REMOVED {"name":"compact-1"}
UITUNINGLAB_DONE {"candidates":[{"basedOn":"compact","name":"compact-2","values":{"cornerRadius":14,"design":"capsule"}}],"values":{"cornerRadius":14,"design":"capsule"},"winner":"compact-2"}
```

- A look logs `UITUNINGLAB_CANDIDATE` with its values once, when it is
  pinned: by Save & pin, or by Apply with unsaved edits. Unsaved edits are
  never logged. A pinned look never changes, so it never logs again; the
  latest line for a name wins only across runs that reused it.
- **Apply** (and Save & pin after the first Apply) logs `UITUNINGLAB_DONE`.
  `winner` is the selected look, or
  `original` when Shipped was selected (land nothing); `values` is the winner's
  values (`{}` for `original`). The Shipped chip's wire name is `original`.
  Older labs could log winner `draft`; treat its `values` like a look's.
- `candidates` holds every look still in the panel, oldest first, with its
  values, so the line alone is enough to land or keep any of them.
- A look loaded from storage or seeded from the project logs its own
  `UITUNINGLAB_CANDIDATE` line when the lab opens.
- When the user names a look in chat before picking ("land brass-2"),
  rebuild the list from the `UITUNINGLAB_CANDIDATE` and
  `UITUNINGLAB_CANDIDATE_REMOVED` lines: the latest line for a name wins, unless
  a later removal names it. An ephemeral lab restarts its names after a relaunch,
  so when two runs used the same name, ask the user to pick again.

## The result file

**Apply** (and Save & pin after the first Apply) also writes the `UITUNINGLAB_DONE` object, plus `savedAt` (ISO-8601
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
later pick arrives as the `land <name>` the user pastes from Save & pin, and is
landed the same way (chat wins, `references/landing-protocol.md` step 1). When
the user says they picked but no line arrived, read the result file. When neither is reachable (a cloud device), the user pastes the
`land <name>` line the lab copied.

## Persistence

Only when persistence was requested, the lab also writes each pinned look as a
profile with `schemaVersion: 2` (`references/config-schema.md`), one per
name, and loads them into the list when it opens:

| Platform | Location |
|---|---|
| iOS | Application Support `.ui-tuning-lab/candidates/<name>.json` in the app container |
| macOS | Application Support `<bundle-id>/.ui-tuning-lab/candidates/<name>.json`; a non-sandboxed app shares Application Support with every other app, so the bundle ID keeps labs apart |
| Web | `uiTuningLab.candidates.<name>` in `localStorage` |
| Other platforms | `references/platform-handoff.md`, "Where persisted candidates live" |

A look is written once, when it is pinned and logs: on Save & pin, or Apply
with unsaved edits. Unsaved edits are never written, and nothing ever rewrites
an existing candidate file: a pinned look never changes. Its `savedAt` keeps
fractional seconds, so looks load in the order they were pinned. Remove deletes
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
