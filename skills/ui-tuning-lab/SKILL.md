---
name: ui-tuning-lab
description: "Adds a temporary, development-only control panel beside a real screen in the running app, with sliders, presets, a flip back to the original, and side-by-side candidates, then writes the winning values or design back into code. Use when the user wants to tune, tweak, or dial in animation, spacing, colors, layout, or UI states by eye; add live sliders or knobs to a running app; or try several alternative designs of a screen or component and pick one. Works with web (React), iOS and macOS (SwiftUI), Android (Compose), Flutter, React Native, Windows (WinUI), and other UI stacks."
license: MIT
metadata:
  author: "Mohanad Ramadan"
  version: "1.6.0"
---

# UI Tuning Lab

Put a small control panel next to the real feature, running in the real app, so
the user can drag sliders, try presets, flip back to the original, and replay
motion until it feels right. When they pick a winner, write those values into
the feature's defaults and take the panel away. Nothing about the lab ships.

A good lab feels like this:

- Opening it changes nothing on screen: the feature renders exactly as before.
- **It opens without hunting.** The agent can open it deterministically, the
  human has a fast path, and a visible fallback is always there.
- **It is handed over, not demoed.** The agent builds it, confirms it opens
  once, and gives it to the user; it does not tune it, tour the presets, or
  screenshot the options first. A self-review pass runs only when the user asks
  for one.
- Every control edits the same configuration the feature renders, live.
- **It reads as its own surface.** The panel has a visible outline against the
  screen, even when the app's background is the same color; a shadow alone does
  not count.
- **Chips** are Shipped and each pinned look, named after its preset and
  numbered (**Brass-1**, **Brass-2**, **Custom-1**); the selected chip is
  outlined and is always what the feature shows, so switching chips is the
  comparison. The controls edit the selected look; on Shipped, which is
  read-only, they make unsaved changes that no chip holds until Save & pin. No
  chip appears or is renamed on its own. **Replay** and **Speed** make motion
  judgeable.
- **Undo**, **Redo**, and **Reset** step through the selected look's edits
  since its last save, or drop them all.
- **Every control shows its default**, the Shipped value: a tick on a slider
  (a drag snaps to it), a caption on a toggle or option, a swatch beside a
  color. Its **↺** puts that one control back to Shipped as one Undo step.
- **Save & pin** keeps edits on Shipped as a new chip; on a pinned look the
  button reads **Save** and keeps its edits. Both copy `land <name>`.
  **Apply** picks the selected chip and hands it to the agent, with no paste:
  log line, result file, and a `land <name>` code on the clipboard. Apply hides
  after its first use. One hint line says how to finish.

## Every platform gets the whole lab

Every UI stack gets the same lab. On Android, Flutter, React Native, Windows,
or a stack with no example at all, build: the
panel, presets, direct controls with their default markers and ↺, the chips,
Undo, Redo, Reset, Save & pin and Save, Apply, the ⋯ menu with Copy values, the hint, and the three activation
paths.
Start from the platform's example, or the nearest one when there is none, and
keep every guarantee in the safety checklist. Never replace the lab with a row
of buttons in the screen, and never drop controls because the platform is new;
if a piece truly cannot be built, say which and why in the report.

When the user asks for alternative designs ("three better versions of this
list"), the variants are part of the lab, not a substitute for it: a **Design**
picker in the panel, with the original as the baseline
(`references/design-variants.md`).

## Workflow

1. **Inspect.** Find the platform, build system, the feature's configuration
   model, the development gate, the native transient surface, the activation
   surface, and test commands. Reuse an existing debug menu or panel library
   when the project has one (`references/setup-protocol.md`). Check whether the
   toolchain runs here (`which flutter`, `xcodebuild -version`, `adb`, `node`);
   when the app only builds in CI or a cloud device service, follow
   "No local toolchain" in `references/platform-handoff.md`. Search the project
   for labs already in place (files and host references marked `UITuningLab`,
   `uiTuningLab`, or `ui-tuning-lab`) before writing anything
   (`references/setup-protocol.md`, "Labs already in the project").
2. **Decide quietly.** Infer target, scope, container, gate, activation, and
   persistence; persistence is off unless the user asked to save. Ask at most one
   focused setup question, only when the answer changes the implementation.
   Always ask how the lab should open, letting the user pick more than one human
   path, unless the request or a fitting remembered `activation` already says,
   or the visible pill is the only human path inspection found;
   it does not use up the setup question, and both go in one prompt
   (`references/activation.md`). When inspection found a lab for another
   feature, always ask what to do with it, in the same prompt; this does not use
   up the setup question either. Never decide on your own to keep, extend, or
   remove another lab.
3. **Build the lab.** Start from the matching file in `examples/`. Choose
   activation per `references/activation.md`: an agent path, one or more human
   paths, and a visible fallback. Wrap only the feature, lifting a constant config into state
   if needed, and keep the panel beside the feature and open while it is used
   (`references/setup-protocol.md`, "Wire the host"). The baseline is the
   feature's declared default (what ships), never the value on screen when the
   lab opens: a look kept from an earlier open must still count as a change.
   Pick controls from `references/control-mapping.md`:
   at least two presets, direct controls with their default markers and ↺
   (`references/control-mapping.md`, "Default marker and per-control reset"),
   the chips, Undo, Redo, Reset,
   Save & pin and Save, Apply, the ⋯ menu (Copy values), and the hint, plus
   Replay and Speed for motion
   (`references/candidates.md`). Saved looks stay in memory and the log; the
   only write is the result file, and looks go to storage only when persistence
   was requested
   (`references/config-schema.md`). When `.ui-tuning-lab/lab.json` lists kept
   `candidates`, seed the lab with them.
4. **Hand it over, then tune with the user.** Build, typecheck, and run the gate
   lint. Then make sure the app on screen is the build you just made: quit any
   copy that is already running, launch the new build, and confirm the running
   process started after the build finished (`references/setup-protocol.md`,
   "Run the fresh build"). An app that was open before the build still shows the
   old code, with no lab in it. Open the lab once through the agent path to
   confirm it renders and opens, then close it and stop. Leave the fresh build
   running for the user. A lab with designs is the one exception:
   select each design once through the agent path and confirm by screenshot
   that the feature visibly changes and is not covered by the panel, then
   return to Shipped (`references/design-variants.md`, "Check each design
   renders"). Do not iterate the controls, flip the chips,
   Save & pin, Apply, compare candidates, or capture screenshots before the
   user has seen it: the user tunes, and a self-review pass runs only when they
   ask for one ("check it yourself first"). Then, in this order: start
   `python3 <skill-dir>/scripts/wait-for-pick.py` with the platform's flag **in
   the background** (`references/platform-handoff.md`, "Wait for Done"), hand
   over with **How to try it**, and end the turn without a question. Apply
   reaches the waiter directly, so it exits and you resume the moment the user
   presses it: land from its `UITUNINGLAB_DONE` line right away, without asking
   them to confirm. Skipping the waiter is what makes the user type "done". The
   waiter catches only the first Apply; after it Apply is hidden, and a later
   pick arrives as a `land <name>` pasted from Save & pin or Save, landed the
   same way. Save & pin and Save before the first Apply only keep a look; they
   do not wake the waiter. If
   the user is not available, stop here and
   report the lab as built, with the smoke launch and every hands-on check listed
   as not run; static and release-artifact checks are still yours to run (step
   6). When the app builds only in CI or a cloud device service, the smoke launch
   is reported as not run and the lab still ships complete; ask before pushing,
   and the pick reaches you as a pasted `land <name>` line
   (`references/platform-handoff.md`, "No local toolchain").
5. **Land the winner.** Take the candidate or values the user names in chat,
   else the newest `UITUNINGLAB_DONE` or `UITUNINGLAB_VALUES` line
   (`references/landing-protocol.md`, step 1), write the values into the
   feature's defaults, show a baseline-to-winner table, offer to keep the other
   finalists for later, then remove the lab (default) or keep it
   (`references/landing-protocol.md`).
6. **Verify and report.** Run the static and release-artifact checks yourself,
   then report what passed, what failed, and what was not run. Hands-on checks
   run during or after the user's tuning session, not before handover: record
   which the agent ran and which the user ran, and count the smoke launch as one
   check ("opens and renders"), not as the whole hands-on list.

## Naming rule

The source linter finds lab code by marker, so every lab file, every lab symbol
that host code references, and every storage key contains `UITuningLab`,
`uiTuningLab`, or `ui-tuning-lab`. Private helpers inside a lab file or lab
module (presets, a diff function) need no marker: the file itself is gated.

- **Swift:** wrap each lab file in `#if DEBUG`, and mark the host's DEBUG-only
  state too (`showUITuningLab`, `uiTuningLabBaseline`).
- **Web:** keep lab code in `*.ui-tuning-lab.tsx` modules. Load them only with a
  dynamic `import()` by relative path inside `if (import.meta.env.DEV) {` (Vite)
  or `if (process.env.NODE_ENV !== "production") {` (webpack, Next.js), or with
  `require()` inside `if (__DEV__) {` (React Native). A static import fails the
  linter. The host variable (`TuningLabHost`) stays
  unmarked because it is declared outside the gate.

## Safety checklist

`<skill-dir>` is this skill's installed directory.

| Guarantee | How it is checked |
|---|---|
| **Internal only.** The lab exists only in DEBUG, development, or tester builds. | `sh <skill-dir>/scripts/verify.sh source-gates <dir>` PASSes on a directory holding the feature and lab files (for Kotlin, Dart, and C#, which it cannot read, the manual gate check in `references/platform-handoff.md` instead), and the Release archive or production bundle contains no lab code or activation path (`references/verify-protocol.md`). |
| **Activatable only in development.** The lab opens through the documented agent path, the chosen human path, and a visible fallback; none survives Release. | Hands-on, during the tuning session with the user: every documented path opens the lab, a focused text field keeps shake-to-undo, and the fallback is reachable. Release archive: launch arguments, URL schemes, shake selectors, notification names, key commands, and fallback labels are absent or inert (`references/verify-protocol.md`). |
| **Reversible.** The Shipped chip shows the baseline (the declared default) exactly, behavior included. | Hands-on, during the tuning session with the user: open, change everything, close, reopen, select Shipped, and compare with the unmodified app. On a pinned look, change one control and press its ↺: the value equals Shipped's, and Undo brings the change back. |
| **Explicit persistence.** The only write an ephemeral lab makes is the result file on Apply (and on Save & pin or Save after it); saved looks live only in memory and the log unless the user asked to save them; every write goes only to `uiTuningLab.*` or `.ui-tuning-lab/`, never a production key. | An ephemeral lab's only storage writer is the result file; a saved file passes `sh <skill-dir>/scripts/verify.sh profile <file>`. |
| **Complete teardown.** Closing unmounts or releases the lab and every timer, observer, listener, task, and render tree it owns. | Hands-on, during or after the tuning session with the user: close, then confirm with instruments, logging, or DevTools that nothing lab-owned remains. |

`source-gates` is a lint: a PASS does not prove the release build is clean, so
still search the release build. `N/A` means it found no lab code it can read; for
Swift or web code that usually means the naming rule was skipped. Validate a reusable lab definition with
`sh <skill-dir>/scripts/verify.sh config .ui-tuning-lab/lab.json`.

Stop and report instead of proceeding when the development gate cannot be
established, the baseline cannot be captured without changing production data, or
a save would overwrite a production key.

## Route to details

- `references/setup-protocol.md`: inspection, reusing existing tools, when to ask.
- `references/activation.md`: how the lab opens: agent path, human path, fallback,
  and remembering the choice.
- `references/surface-matrix.md`: native containers, gates, and activation per
  platform.
- `references/ios-hosting.md`: iOS panels, activation, Xcode targets, and UIKit or
  hybrid apps.
- `references/control-mapping.md`: which control for which value; required
  controls; default markers and per-control reset.
- `references/design-variants.md`: alternative designs of a feature as a
  Design picker in the lab, and landing the winning design's code.
- `references/candidates.md`: chips, Undo, Redo, Reset, Save & pin, Save, Apply, look names, the
  result file, waiting for the pick, and keeping finalists for later.
- `references/platform-handoff.md`: per platform, how lab lines are logged and
  read, how to wait for Done, where the result file and looks are stored,
  and manual gate
  checks for languages the linter cannot read.
- `references/landing-protocol.md`: reading values, writing defaults, removal.
- `references/config-schema.md`: `lab.json`, candidates, and saved profiles.
- `references/verify-protocol.md`: static, hands-on, and release-artifact checks.
- `references/edge-cases.md`: rotation, focus, hot reload, corrupt saved data.
- `references/container-tuning.md`: only when tuning the host container itself.
- `examples/`: worked starting points per platform; adapt them to the app.

## Report

Return the files changed; the chosen container, gate, activation paths, and
baseline source; any production-side change (such as a constant lifted into
state); any save location; every other lab still in the project and what the
user chose for it; and the commands run with their results. After landing, add the values
table, the declaration changed, and whether the lab was removed or kept; before
landing, say the lab is in place and awaiting a winner. Keep static lint,
hands-on checks, and release-artifact inspection separate, and never mark an
unrun check as passed. Hands-on checks are the ones run during the user's tuning
session or a self-review they asked for; say who ran each. For each activation
path the agent could not exercise
(shake in the Simulator, a gesture, a hardware shortcut), name the gesture or
keys in **How to try it**. Name the current keys, read from the host the user is
looking at, never from memory: some hosts hide shake behind a shortcut only
(`references/activation.md`, "Tell the user how to shake").

Before landing, open the report with **How to try it**: two or three short
lines, a hint for a developer, not a tutorial. Say how to open the lab (the
fastest path, then the fallback, such as "shake, or tap Card Lab in the
bottom-right corner"), and give the flow in one line ("tune a look, Save & pin
to compare, Undo or Reset to back out, then Apply"). End with how the pick reaches you: "Apply sends it to
me; I'll land it right away" when the waiter is running, or a pasted
`land <name>` line when it cannot run. Mention a setting outside the lab only when the lab
depends on it. The panel's own hint line covers the rest, so do not walk
through the presets, sliders, or chips.
