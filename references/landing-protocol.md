# Landing Protocol

A tuning session is finished when the chosen values live in the feature's real
defaults, not when the lab looks right. Land the winner as soon as the user picks
one ("keep this", "ship these values", "that's the one").

## 1. Get the values

Every lab has a **Copy values** action. It copies a JSON object containing only
the draft fields that differ from the captured baseline, and logs the same object
on one line:

```text
UITUNINGLAB_VALUES {"cornerRadius":20,"spacing":12}
```

Read the most recent line yourself rather than asking the user to paste it:

| Platform | Where to read it |
|---|---|
| Web | the browser console, for example the built-in browser's console messages filtered by `UITUNINGLAB_VALUES` |
| iOS Simulator | `xcrun simctl spawn booted log show --last 10m --style compact --predicate 'subsystem == "ui-tuning-lab" AND eventMessage CONTAINS "UITUNINGLAB_VALUES"'` |
| macOS | `log show --last 10m --style compact --predicate 'subsystem == "ui-tuning-lab" AND eventMessage CONTAINS "UITUNINGLAB_VALUES"'` |

If no line is available, ask the user to press Copy values and paste the result.
`{}` means the draft matches the baseline, so there is nothing to land. `null`
means the draft cleared an optional field. A status starting `Values not copied`
means encoding failed (for example a non-finite number); fix the value first. If the
winner came from a saved profile, `overrides` holds the full configuration: land
only the fields that differ from the current defaults.

Speed, the baseline flip, and replay are preview settings. They are never part of
the values and never land.

## 2. Write them into the defaults

1. Find the declaration the baseline was captured from, such as
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

Ask once, recommending removal unless the user expects to tune again soon:

- **Remove (default).** Delete the lab files (`UITuningLab*.swift`,
  `*.ui-tuning-lab.tsx`), the gated host code that opens them (the Tune trigger,
  the marked DEBUG-only state such as `showUITuningLab`, the web `TuningLabHost`
  block and its gated `import()`), and any lab-only helper. Leave saved profiles
  and `.ui-tuning-lab/` alone unless the user asks to delete them; they are not
  shipped. Removal is complete only when all three hold:
  1. `sh <skill-dir>/scripts/verify.sh source-gates <feature-dir>` reports
     `N/A: supported sources contain no lab references`. The other `N/A`
     message, no supported sources, means the wrong directory was checked.
  2. `grep -rnE 'TuningLab|tuning-lab|\bTune\b' <feature-dir>` finds nothing left
     from the lab. Web host code is deliberately unmarked, so the linter alone
     cannot see it.
  3. The project builds, in both Debug and Release where they differ.
- **Keep.** Leave the lab gated as it is. Its baseline now captures the new
  defaults on the next open.

## 4. Confirm

Build or reload, and confirm the feature renders the winner with the lab closed
or removed. Report:

- the values table;
- the file and declaration changed;
- whether the lab was removed (with the `N/A` result) or kept;
- anything not landed and why.
