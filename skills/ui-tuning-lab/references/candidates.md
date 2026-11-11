# Looks, Save & pin, Save, and Apply

The user works on a few looks side by side, flips between them, and picks one.
The panel makes that a row of chips, an edit row, and two buttons, and the pick
reaches the agent on its own.

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
| **Chips** | One row under the header, scrolling sideways when it outgrows the panel (it never widens the panel): **Shipped** (the baseline), then each pinned look, labeled by where it came from and a number, in pin order (**Brass-1**, **Brass-2**, **Custom-1**; see Names). Tapping a chip shows it in the real feature. The selected chip is always the look the feature shows; it has a visible outline, like any selected option, and is marked selected for assistive tech. While Shipped has unsaved edits, no chip is outlined. Selection is never shown by label text. Example: Shipped · Brass-1 · Custom-1 |
| **Controls** | Presets, sliders, toggles. Always enabled; they show and edit the selected look. Presets are actions, never outlined. |
| **Edit row** | **Undo**, **Redo**, and **Reset**, in one row under the controls (next section). Each is disabled when it has nothing to do. |
| **Save & pin** | Shown while Shipped is selected. Keeps the unsaved edits on Shipped as a new pinned look, named from its preset (Names), selects it, copies `land <name>`, and logs the look's `UITUNINGLAB_CANDIDATE` line, with a status such as `Pinned Brass-1 · copied land brass-1`. Disabled on Shipped with no edits. |
| **Save** | Takes Save & pin's place while a pinned look is selected. Makes the look's current edits its new saved version, copies `land <name>`, and logs its `UITUNINGLAB_CANDIDATE` line: `Saved Brass-1 · copied land brass-1`. Disabled while the look has no edits since its last save, until the first Apply; after it, Save is how a pick reaches the chat, so it stays enabled. |
| **Save & pin and Save after the first Apply** | Before the first Apply they only keep a look: no Done line, no result file, no beacon, so the agent's waiter is not woken. After the first Apply they also hand the pick over like Apply (Done line, result file, beacon, result bar). |
| **Apply** | Visible until the first Apply, then hidden for the rest of the lab's life (Change does not bring it back). Saves first (unsaved edits on Shipped are pinned like Save & pin; a selected look's edits are saved like Save), then picks the selected chip (`original` for Shipped with no edits) and finishes: logs the result, sends it to the agent's waiter, writes the result file, copies `land <name>` to the clipboard, and shrinks the panel to one bar. Change brings back the same panel at its full size, controls included. |
| **Result bar** | `Applied: Brass-2 · Change` after Apply; `Copied land brass-3: paste it in chat so the agent applies it · Change` after a later Save & pin or Save (`Tell the agent: land brass-3` when the clipboard failed). Under it, a smaller line says where the pick was saved: `Saved Brass-3 in .ui-tuning-lab/result.json` (web: `Saved Brass-3 in localStorage uiTuningLab.result`), or the failure status when the write failed, never a false Saved. Change reopens the panel. Picking again replaces the result: the newest pick wins. No confirmation step. |
| **× on the selected look** | Shown only on the selected pinned look, never on Shipped or an unselected chip, so nothing is removed by accident. Removes it, with an accessible name such as "Remove Brass-2", and selects Shipped. |
| **⋯ menu** | Copy values (the selected look as shown, edits included). |
| **Hint** | One line pinned at the bottom: *Save & pin to keep a look · Apply to finish*; after the first Apply, *Save, then paste it in chat* |

Labels are plain words: no star or check-mark glyphs anywhere in the panel.

Rules:

- No chip appears or is renamed on its own: a look becomes a chip only through
  Save & pin (or Apply). There is no compare mode; the feature always renders
  the selected look, so switching chips is the comparison.
- A pinned look has a saved version and, on top of it, the edits made since.
  Editing a pinned look shows the edit live and enables Save, Undo, and Reset.
  Its edits stay with it when the user switches away and come back with it.
  There is no unsaved marker on the chip: an enabled Save is the signal.
- Shipped is read-only. Moving a control or applying a preset while Shipped is
  selected shows the edit live as unsaved changes, with no chip outlined;
  Save & pin keeps them as a new look. Tapping a chip, Shipped included, drops
  them, so tapping Shipped always shows the baseline exactly.
- Closing the lab leaves the feature on the selected look, edits included;
  reopening keeps the looks, their edits, their histories, and the selection.
- `basedOn` records where a look came from: `baseline` when it was started from
  Shipped, or the kebab-case key of the last preset (or, in a lab with designs,
  design) applied to it. It names the look when it is pinned and can change
  later; the name never does.
- Keyboard shortcuts for the chips (Command-1 to Command-9 on macOS) are optional
  and only added when inspection shows they are free.

## Edits, Undo, Redo, and Reset

Each look keeps its own history: Shipped's unsaved edits, and each pinned
look's edits since its last save. Reset and ↺ differ in what they go back to:
Reset takes the whole look to its last save, ↺ takes one control to the
baseline.

- **One step per change.** A preset, a toggle, or a picker choice is one step.
  A run of changes from the same control in a row (one slider drag, a stepper
  held down) is one step, so Undo never walks a slider back a pixel at a time.
  A change from another control starts a new step.
- **Undo** steps back one edit on the selected look. It stops at the last
  save: on a pinned look at its saved version, on Shipped at the baseline. It
  never reaches back past a save.
- **Redo** steps forward again. Any new edit clears what Redo could bring
  back.
- **Reset** takes the selected look back to its last save (Shipped: the
  baseline) in one step, and that step can be undone. Disabled when the look
  has no edits.
- **↺ on one control** is not Reset: it puts that control alone back to the
  baseline, what Shipped shows, never the look's last save
  (`references/control-mapping.md`, "Default marker and per-control reset").
  It is an ordinary edit: one step, which ends the current slider run, so the
  next drag is its own step. On Shipped, a look that matches the baseline again
  has no unsaved edits; on a pinned look it is an edit, which Save keeps.
- **Save & pin and Save** start a fresh history at the version they keep:
  after them Undo and Redo are disabled until the next edit.
- **Keyboard:** where the platform has a convention and the panel holds focus,
  Command-Z / Command-Shift-Z (Control-Z / Control-Y on Windows and the web,
  also Control-Shift-Z on the web) run Undo and Redo. Never take them while a
  text input outside the panel has focus, and never register them app-wide:
  the app's own undo wins outside the panel.
- Tapping a chip, removing a look, and Apply are not edits and never enter a
  history.

## Names

A pinned look is named after where it came from and numbered, so the chip is
short, says what the look is, and works as a code in chat (`land brass-2`):

1. Its prefix is its `basedOn` at the moment it is pinned: the preset's (or
   design's) kebab-case key, or `custom` for a look started from Shipped with
   no preset. Its name is `<prefix>-N`: `brass-1`, `warm-glow-2`, `custom-1`.
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

- A look logs `UITUNINGLAB_CANDIDATE` with its saved values whenever it is
  saved: Save & pin, Save, and Apply. Edits not saved yet are never logged.
  The latest line for a name wins.
- **Apply** (and Save & pin or Save after the first Apply) logs `UITUNINGLAB_DONE`.
  `winner` is the selected look, or
  `original` when Shipped was selected (land nothing); `values` is the winner's
  values (`{}` for `original`). The Shipped chip's wire name is `original`.
  Older labs could log winner `draft`; treat its `values` like a look's.
- `candidates` holds every look still in the panel, oldest first, with its
  saved values, so the line alone is enough to land or keep any of them.
- A look loaded from storage or seeded from the project logs its own
  `UITUNINGLAB_CANDIDATE` line when the lab opens.
- When the user names a look in chat before picking ("land brass-2"),
  rebuild the list from the `UITUNINGLAB_CANDIDATE` and
  `UITUNINGLAB_CANDIDATE_REMOVED` lines: the latest line for a name wins, unless
  a later removal names it. An ephemeral lab restarts its names after a relaunch,
  so when two runs used the same name, ask the user to pick again.

## The result file

**Apply** (and Save & pin or Save after the first Apply) also writes the `UITUNINGLAB_DONE` object, plus `savedAt` (ISO-8601
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
later pick arrives as the `land <name>` the user pastes from Save, and is
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

A look is written whenever it logs: on Save & pin, Save, and Apply. Unsaved
edits are never written. A rewrite keeps the first `savedAt`, which keeps
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
