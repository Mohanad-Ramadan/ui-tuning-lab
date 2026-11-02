# ui-tuning-lab

An agent skill for tuning UI by feel. The agent adds a temporary,
development-only control panel beside a real screen: sliders, presets, a flip
back to the original, and Replay and Speed for motion. When you pick a winner,
it writes those values into the feature's defaults and removes the panel.

The workflow is inspect-first: the agent derives the platform, gate, container,
activation, configuration, and baseline from the project and asks at most one
material question. Activation has an agent path, a human fast path, and a visible
fallback; shake is used only when inspection proves it free. Ephemeral labs need
no configuration file. Saved profiles are opt-in and live under `uiTuningLab.*`
or `.ui-tuning-lab/`.

Start with `SKILL.md`; it routes to everything else.

## Guarantees

- Development, DEBUG, internal, or tester builds only.
- Every lab opens through an agent path, a human fast path, and a visible
  fallback; activation is development-only.
- Reset always returns to the declared default, however often the lab reopens.
- Persistence off by default; explicit namespaced Save when requested.
- Closing releases all lab-owned UI, timers, observers, listeners, and tasks.

## Checks an installed copy can run

`<skill-dir>` is where the skill is installed.

```sh
sh <skill-dir>/scripts/verify.sh source-gates path/to/source
sh <skill-dir>/scripts/verify.sh config path/to/lab.json
sh <skill-dir>/scripts/verify.sh profile path/to/saved-profile.json
```

Source lint cannot prove production absence. Approval requires inspecting the
compiled archive or production bundle (`references/verify-protocol.md`).
`source-gates` exits `3` with `N/A:` when the path contains no supported Swift or
web files, or no lab reference. That is deliberately distinct from PASS.

## Status

iOS, macOS, and web guidance is **candidate**. A platform becomes validated only
when its receipt in `validation/` records PASS against one commit. Android,
Windows, Flutter, React Native, visionOS, Linux, and HarmonyOS are unvalidated
adaptation notes.

## License

MIT. See `LICENSE.txt`.

## Developing this skill (repository only)

These files are not in the installed package.

```sh
sh tests/verify.sh      # linter and validator fixtures
sh tests/examples.sh    # every example variant linted, plus gate-stripped mutants
sh tests/compile.sh     # Swift (iOS, macOS; DEBUG and Release) and TypeScript typecheck
sh tests/package.sh     # the package is self-contained
sh tools/package.sh     # builds dist/ui-tuning-lab/ and dist/ui-tuning-lab-<version>.zip
```

`tests/compile.sh` exits `3` with `SKIP` when a toolchain is missing. The web
pilot lives in `pilots/web-vite/`, its cross-engine checks in
`tests/pilot-web/check.mjs`, and evals in `evals/`. The package contains
`SKILL.md`, `references/`, `examples/`, `assets/`, `profiles/`, `scripts/`, the
validation receipts, and the license; tests, tools, pilots, evals, and
validation evidence stay here.
