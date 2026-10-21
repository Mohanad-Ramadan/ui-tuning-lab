# Evals, run 1 (2026-10-21)

E1 and E2 ran at `3d23b79` (fingerprint `1b1a444351352f93`) and again at
`b06291f` (fingerprint `c421465931259a76`) with the same results. Each run used a
fresh agent that could read only the packaged skill and the pilot app.

## E1 ephemeral-web-lab: 6/6 pass

| Assertion | Result | Evidence |
|---|---|---|
| Lab code lives in a `*.ui-tuning-lab.tsx` module | pass | `validation/evidence/web/pilot-lab.diff` adds `src/HomeScreen.ui-tuning-lab.tsx` |
| The host loads the lab only via `import()` inside `if (import.meta.env.DEV) {` | pass | `pilot-lab.diff`, `HomeScreen.tsx` hunk |
| `source-gates` on the feature directory exits 0 | pass | pilot agent output: PASS, exit 0 |
| At least two presets, Show baseline, Reset, and Copy values | pass | `accessibility-tree.txt` |
| No `localStorage`, `sessionStorage`, or IndexedDB writes | pass | 0 matches in `pilot-lab.diff` |
| `vite build` output contains no lab markers | pass | pilot agent grep of `dist`, empty |

## E2 tune-land-remove: 6/6 pass

| Assertion | Result | Evidence |
|---|---|---|
| The default declaration has radius 20 and gap 12 | pass | `landing.diff` |
| No other field of the default declaration changed | pass | `landing.diff` (padding stays 16) |
| The response includes a field / baseline / winner table | pass | landing agent report |
| No `*.ui-tuning-lab.*` file remains | pass | `git status` after landing |
| `source-gates` reports "N/A: supported sources contain no lab references" | pass | `landing-checks.txt` |
| grep for TuningLab, tuning-lab, and Tune finds nothing | pass | `landing-checks.txt` |

## E3 ios-lab-with-save: not run

There is no iOS pilot app in this repository yet.

## Trigger eval: 10/10 triggered, 0/12 false triggers (`results/trigger-3.json`)

Run with `evals/run_trigger.py` at `b06291f`: Claude Code 2.1.304, model
`claude-opus-5-5`, 1 run per query, at most 4 turns, from an empty scratch
project with the packaged skill installed as a project skill and the shell,
edit, and web tools disabled. All 10 should-trigger queries invoked the skill as
their first tool call; none of the 12 near-misses invoked it. Two near-misses
called a different skill (performance profiling, artifacts), which is correct.

Two earlier runs are in `results/invalid/` and say nothing about the description:

- `trigger-1`: the `claude` CLI was not logged in, so every call failed.
- `trigger-2`: the CLI on `PATH` (2.1.275) rejects `claude-opus-5-5` ("version
  2.1.280 or newer is required").

`run_trigger.py` replaces skill-creator's `run_eval` here for two reasons.
`run_eval` counts only the first tool call, and global instructions that say to
explore first make the model look around before invoking any skill. It also runs
`claude -p` from the home directory, where it read the user's real projects
during a probe. Rerun with:

```sh
python3 evals/run_trigger.py --claude "<claude 2.1.280+>" --model claude-opus-5-5 --runs 3
```

Caveat: one run per query, to stay within the account's usage limits. Three
runs per query would measure flakiness.

## Agent feedback from these runs: resolved after `3d23b79`

None of these blocked either agent. All six are fixed in documentation and
examples in the commit after `c9bfc0f`:

- The landing protocol now says to undo other host changes, such as a constant
  lifted into state, and suggests `git diff` to find them.
- It uses values the user already pasted and a remove-or-keep answer the user
  already gave, instead of re-asking.
- "Values not copied" is described as Swift-only, and the ephemeral web labs no
  longer carry an unused `error` flag on their status.
- `control-mapping.md` now allows two to three times the baseline, which matches
  the examples.
- `verify-protocol.md` names concrete activation paths to try against a
  production bundle, and says the release checks are optional after removal.
- The removal grep is two portable commands (`grep -rnE` for the markers,
  `grep -rnw Tune`) instead of the non-portable `\bTune\b`.
