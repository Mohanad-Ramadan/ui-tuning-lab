# Evals, run 2 (2026-11-13)

E1 to E4 ran against the working tree on top of `1d22d24` (1.7.0, plus the
handover-step restructure in `SKILL.md`), one run per configuration, with
skill-creator's with-skill and no-skill setup. Each agent got a fresh copy of
`pilots/web-vite`; the with-skill agents read only a copy of the packaged
skill. The run directories (`evals/workspace/`) are not committed, so the
evidence below is what the grader observed, not a link.

| Eval | With skill | Without skill |
|---|---|---|
| E1 ephemeral-web-lab | 10/10 | 1/10 |
| E2 tune-land-remove | 6/6 | 5/6 |
| E3 ios-lab-with-save (Sonnet) | 7/7 | 1/7 |
| E4 macos-panel-lab (Sonnet) | 7/7 | 1/7 |

## E1 ephemeral-web-lab

With the skill, every assertion in `evals/evals.json` passed. The grader drove
the generated lab in headless Chromium instead of reading the agent's report:

- an edit on Shipped left no chip pressed and added none; Save & pin added
  Custom-1; Compact then Save & pin added Compact-1; an edit on Compact-1
  pinned as Compact-2;
- an edited slider read `14 px · default 12` and showed
  `Reset Radius to default, 12 px`;
- Apply logged `UITUNINGLAB_DONE` (winner `compact-2`), POSTed it to
  `http://localhost:47321/pick`, wrote `localStorage` `uiTuningLab.result`
  (the only key), and ended the agent's background `wait-for-pick.py`;
- `verify.sh source-gates src` PASS; `npm run build` output held no lab
  markers, labels, or the waiter port.

The agent smoke-opened the lab once, started the waiter, and handed over with
**How to try it** without tuning.

Without the skill, the agent built a two-slider panel with Copy values and
Reset behind a `import.meta.env.DEV` ternary. Only "the production bundle has
no lab strings" passed, and it passes trivially when no marker exists.

## E2 tune-land-remove

The starting lab was the recorded pre-1.1 pilot lab
(`validation/evidence/web/pilot-lab.diff`), not a 1.7.0 lab. Both
configurations set `cardDefaults` to radius 20 and gap 12, left padding at 16,
deleted the lab module, and returned `HomeScreen.tsx` to its original bytes.
The no-skill run gave no baseline-to-winner table. This eval barely separates
the two configurations.

## E3 ios-lab-with-save

Run on Sonnet in both configurations (E1 and E2 used the session's stronger
model), against `pilots/ios-swiftui`, new in this run: one SwiftUI card palette
screen whose radius, spacing, and padding come from `CardStyle.shipped`.

With the skill, all 7 assertions passed. Lab types carry the `UITuningLab`
prefix and each lab file is inside `#if DEBUG`; Save & pin writes one
`schemaVersion: 2` profile per pinned look, atomically, under Application
Support `.ui-tuning-lab/candidates/`, with stored names reserved so no file is
reused; loading checks schema version, platform, name, and `savedAt`, and adds
looks as chips without touching the baseline. The panel has the chip row, Save
& pin, Apply (writing `.ui-tuning-lab/result.json`), and the hint. The agent
built only Debug; the grader built Debug and Release for the simulator.

Without the skill, the agent added an always-on Tune sheet that saves a
favourite to the `UserDefaults` key `CardStyle.favourite` and applies it at
launch. It ships in Release and writes a production key, the two failures the
skill's gates exist to prevent. Only the build assertion passed.

Neither agent could tap in the simulator, so no hands-on check ran in either
configuration.

## E4 macos-panel-lab

New in this run, on Sonnet, against `pilots/macos-swiftui` (the iOS pilot's
screen in a macOS window). With the skill, all 7 assertions passed: four lab
files inside `#if DEBUG`; a `UITuningLabNSPanel` created on first open whose
content is released on close; a DEBUG `Development > Card Lab` command on
Command-Shift-L plus `-UITuningLabOpen`; presets, default ticks and ↺, chips,
Undo, Redo, Reset, Save & pin, Apply, and the hint; `result.json` under
Application Support `<bundle-id>/.ui-tuning-lab/` as the only write; the waiter
started with `--log macos`. The grader built Debug and Release and found no lab
strings in the Release binary.

Without the skill, the agent added a `Window("Tuning")` scene that opens on
every launch, ships in Release, and has three sliders, Reset, and Copy values.
Only the build assertion passed.

Neither agent could take screenshots (no screen-recording permission), so no
hands-on check ran.

## Caveats

- One run per configuration: no variance, and no time or token figures.
- Graded by the orchestrating agent with scripts and the browser run above,
  not by an independent grader.
- The owner reviewed all four outputs in the viewer and left no comments.
