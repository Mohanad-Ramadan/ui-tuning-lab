# Behavior evals, run 1 (2026-10-21)

Skill commit `3d23b79`, package fingerprint `1b1a444351352f93`. Each run used a
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

## Trigger eval: not run

The first attempt is in `results/invalid/`: every query failed because the local
`claude` CLI was not logged in ("OAuth session expired"), so the 0% trigger rate
says nothing about the description. Rerun after `claude` is logged in:

```sh
cd <skill-creator-dir> && python3 -m scripts.run_eval --eval-set <repo>/evals/trigger-eval.json \
  --skill-path <repo> --model claude-opus-5-5 --runs-per-query 3
```

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
