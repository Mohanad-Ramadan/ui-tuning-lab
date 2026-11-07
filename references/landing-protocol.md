# Landing Protocol

A tuning session is finished when the chosen values live in the feature's real
defaults, not when the lab looks right. Land the winner as soon as the user picks
one ("keep this", "ship these values", "that's the one").

## Contents

- 1. Get the values
- 2. Write them into the defaults
- 3. Remove or keep the lab
- 4. Confirm

## 1. Get the values

Every lab has a **Copy values** action. It copies a JSON object containing only
the draft fields that differ from the baseline, and logs the same object
on one line:

```text
UITUNINGLAB_VALUES {"cornerRadius":20,"spacing":12}
```

Labs also log their pins and a `UITUNINGLAB_DONE` line when the user
presses Choose, and write the same object to the result file
(`references/candidates.md`). Use, in order:

1. What the user says in chat wins: values they pasted, or a name they gave
   (`land capsule`).
2. Otherwise the newest `UITUNINGLAB_DONE` line, else the result file. Land its
   `winner`: a pin's values, `draft` values (the draft chip), or nothing for
   `original` (the Shipped chip).
3. Otherwise the newest `UITUNINGLAB_VALUES` line.

Read the lines yourself rather than asking for a paste, with the platform's
command in `references/platform-handoff.md`, "Emit and read".

If no line is available, ask the user to press Copy values and paste the result.
`{}` means the draft matches the baseline, so there is nothing to land. `null`
means the draft cleared an optional field. In the Swift labs, a status starting
`Values not copied` means encoding failed (for example a non-finite number); fix
the value first. The web labs cannot hit that case, because their values are
plain numbers. A candidate's
`values`, like Copy values, holds only what differs from the baseline. If the
winner came from a saved profile, `overrides` holds the full configuration: land
only the fields that differ from the current defaults.

Speed, the baseline flip, and replay are preview settings. They are never part of
the values and never land.

## 2. Write them into the defaults

1. Find the declaration the baseline comes from, such as
   `CardStyle.appDefault` or `appDefault` in `CardFeature.tsx`.
2. Change only the fields in the JSON. Keep the file's units, literal style, and
   formatting, for example `20` rather than `20.0` where the file uses integers.
3. If a value is derived or shared (a design token, a theme constant used
   elsewhere), stop and ask whether to change the shared source or override it
   locally. Never change a shared token silently.
4. Show the result as a table:

| Field | Baseline | Winner |
|---|---|---|
| `cornerRadius` | 12 | 20 |
| `spacing` | 8 | 12 |

## 3. Remove or keep the lab

If the user has already said which they want ("get rid of the panel", "keep it
for now"), do that. Otherwise ask once, recommending removal unless the user
expects to tune again soon. When candidates other than the winner exist, the
same prompt asks whether to keep those finalists for later; keeping them writes
them into the project (`references/candidates.md`, "Keeping finalists for
later") and is independent of removing the lab:

- **Remove (default).** Delete the lab files (`UITuningLab*.swift`,
  `*.ui-tuning-lab.tsx`), the gated host code that opens them (the launch-argument
  handler, the shake shim, the `<Feature> Lab` trigger or fallback pill, the marked
  DEBUG-only state such as `showUITuningLab`, the web `TuningLabHost` block and
  its gated `import()`), and any lab-only helper. Delete the result file
  (`references/platform-handoff.md`, "The result file") when you can reach it. Undo every other host
  change the lab needed: if a constant was lifted into state so the lab could
  edit it, point the feature back at the constant, which now holds the winner.
  `git diff` against the commit before the lab is the quickest way to see what
  to revert. Leave saved profiles and `.ui-tuning-lab/` alone unless the user
  asks to delete them; they are not shipped. Removal is complete only when all three hold:
  1. `sh <skill-dir>/scripts/verify.sh source-gates <feature-dir>` reports
     `N/A: supported sources contain no lab references`. The other `N/A`
     message, no supported sources, means the wrong directory was checked.
  2. `grep -rnE 'TuningLab|tuning-lab|UITuningLabOpen|ui-tuning-lab=' <feature-dir>`
     finds nothing left from the lab, and a search for the fallback label (for
     example `grep -rn 'Card Lab'` or the pill's accessibility label) is clean too.
     Web host code is deliberately unmarked, so the linter alone cannot see it.
  3. The project builds, in both Debug and Release where they differ.

  The release-artifact checks in `references/verify-protocol.md` are for a lab
  that is still present. After removal they are optional: a passing source
  check plus a build is enough, because no lab code remains to leak.
- **Keep.** Leave the lab gated as it is. Its baseline is the declared default,
  so it now holds the landed values.

## 4. Confirm

Build or reload, and confirm the feature renders the winner with the lab closed
or removed. Check the rendered values, not just the source: for example, read
the computed style in the browser, or take a simulator screenshot. Report:

- the values table;
- the file and declaration changed;
- whether the lab was removed (with the `N/A` result) or kept;
- which finalists were kept in `.ui-tuning-lab/candidates/`, if any;
- anything not landed and why.
