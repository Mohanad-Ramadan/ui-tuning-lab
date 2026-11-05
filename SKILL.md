---
name: ui-tuning-lab
description: "Adds a temporary, development-only control panel beside a real screen in the running app, with sliders, presets, a flip back to the original, and side-by-side candidates, then writes the winning values or design back into code. Use when the user wants to tune, tweak, or dial in animation, spacing, colors, layout, or UI states by eye; add live sliders or knobs to a running app; or try several alternative designs of a screen or component and pick one. Works with web (React), iOS and macOS (SwiftUI), Android (Compose), Flutter, React Native, Windows (WinUI), and other UI stacks."
license: MIT
metadata:
  author: "Mohanad Ramadan"
  version: "1.3.0"
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
- Every control edits the same configuration the feature renders, live.
- **Show baseline** flips the real feature back to the original and returns to
  the draft; **Replay** and **Speed** make motion judgeable.
- **Copy values** hands over only what changed, and the agent lands it in code.
- **Keep as candidate** shortlists finalists, **Compare** flips between them in
  the real feature, and **Done** tells the agent the session is over. A footer
  hint says how to finish, so the user never has to guess.

## Every platform gets the whole lab

Every UI stack gets the same lab. On Android, Flutter, React Native, Windows,
or a stack with no example at all, build: the
panel, presets, direct controls, Show baseline, Reset, Copy values, Keep as
candidate, Compare, Done, the finish hint, and the three activation paths.
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
   "No local toolchain" in `references/platform-handoff.md`.
2. **Decide quietly.** Infer target, scope, container, gate, activation, and
   persistence; persistence is off unless the user asked to save. Ask at most one
   focused setup question, only when the answer changes the implementation.
   Always ask how the lab should open, letting the user pick more than one human
   path, unless the request or a fitting remembered `activation` already says,
   or the visible pill is the only human path inspection found;
   it does not use up the setup question, and both go in one prompt
   (`references/activation.md`).
3. **Build the lab.** Start from the matching file in `examples/`. Choose
   activation per `references/activation.md`: an agent path, one or more human
   paths, and a visible fallback. Wrap only the feature, lifting a constant config into state
   if needed, and keep the panel beside the feature and open while it is used
   (`references/setup-protocol.md`, "Wire the host"). The baseline is the
   feature's declared default (what ships), never the value on screen when the
   lab opens: a draft kept from an earlier open must still count as a change.
   Keep the draft separate. Pick controls from `references/control-mapping.md`:
   at least two presets, direct controls, Show baseline, Reset, Copy values,
   Keep as candidate, Compare, Done, and the finish hint, plus Replay and Speed
   for motion (`references/candidates.md`). Candidates stay in memory and the
   log; write them to storage only when persistence was requested
   (`references/config-schema.md`). When `.ui-tuning-lab/lab.json` lists kept
   `candidates`, seed the lab with them.
4. **Tune with the user.** Open the lab in the running app and iterate. If the
   user is not available, stop here and report the lab as built, with every
   hands-on check listed as not run. You can still run the release-artifact
   checks yourself: build, search the output, serve it, and try activation
   paths. Wait for Done with a background poll of the platform's log where
   one exists (`references/platform-handoff.md`, "Wait for Done"). When the app
   builds only in CI or a cloud device service, the lab still ships complete;
   ask before pushing, and Done reaches you through chat
   (`references/platform-handoff.md`, "No local toolchain").
5. **Land the winner.** Take the candidate or values the user names in chat,
   else the newest `UITUNINGLAB_DONE` or `UITUNINGLAB_VALUES` line
   (`references/landing-protocol.md`, step 1), write the values into the
   feature's defaults, show a baseline-to-winner table, offer to keep the other
   finalists for later, then remove the lab (default) or keep it
   (`references/landing-protocol.md`).
6. **Verify.** Run the checks below and report what passed, what failed, and what
   was not run.

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
| **Activatable only in development.** The lab opens through the documented agent path, the chosen human path, and a visible fallback; none survives Release. | Hands-on: every documented path opens the lab, a focused text field keeps shake-to-undo, and the fallback is reachable. Release archive: launch arguments, URL schemes, shake selectors, notification names, key commands, and fallback labels are absent or inert (`references/verify-protocol.md`). |
| **Reversible.** Reset restores the baseline (the declared default) exactly, behavior included. | Hands-on: open, change everything, close, reopen, Reset, and compare with the unmodified app. |
| **Explicit persistence.** Nothing is written unless the user asked; candidates in an ephemeral lab live only in memory and the log; saves go only to `uiTuningLab.*` or `.ui-tuning-lab/`, never a production key. | No storage writer in an ephemeral lab; a saved file passes `sh <skill-dir>/scripts/verify.sh profile <file>`. |
| **Complete teardown.** Closing unmounts or releases the lab and every timer, observer, listener, task, and render tree it owns. | Hands-on: close, then confirm with instruments, logging, or DevTools that nothing lab-owned remains. |

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
- `references/control-mapping.md`: which control for which value; required controls.
- `references/design-variants.md`: alternative designs of a feature as a
  Design picker in the lab, and landing the winning design's code.
- `references/candidates.md`: Keep as candidate, Compare, Done, the finish hint,
  waiting for Done, and keeping finalists for a later session.
- `references/platform-handoff.md`: per platform, how lab lines are logged and
  read, how to wait for Done, where candidates are stored, and manual gate
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
state); any save location; and the commands run with their results. After landing, add the values
table, the declaration changed, and whether the lab was removed or kept; before
landing, say the lab is in place and awaiting a winner. Keep static
lint, hands-on checks, and release-artifact inspection separate, and never mark an
unrun check as passed. For each activation path the agent could not exercise
(shake in the Simulator, a gesture, a hardware shortcut), give the user the
exact steps to try it. Name the current keys, read from the host the user is
looking at, never from memory: some hosts hide shake behind a shortcut only
(`references/activation.md`, "Tell the user how to shake").

Before landing, open the report with **How to try it**: where the pill or
command is (which corner, which menu), then three to five numbered steps from
opening the lab to pressing **Done**: try presets, Keep as candidate for each
finalist, Compare them, then Done (or say "land b"). With design variants, the
first step is picking each design in the panel's Design picker. Say whether the
agent is waiting for Done on its own or needs a message. Name every
choice the user makes inside the lab (pick a theme, switch mode) and anything
that still lives elsewhere in the app, so nothing about the setup is a surprise.
