# ui-tuning-lab

An agent skill for tuning UI by feel. The agent adds a temporary,
development-only control panel beside a real screen: sliders, presets, a flip
back to the original, and Replay and Speed for motion. When you pick a winner,
it writes those values into the feature's defaults and removes the panel.

The workflow is inspect-first: the agent derives the platform, gate, container,
activation, configuration, and baseline from the project and asks at most one
material setup question, plus how the lab should open. Activation has an agent
path, one or more human fast paths the user picks, and a visible fallback; shake
is offered only when inspection proves it free. Ephemeral labs need
no configuration file. Every lab lets you pin finalists (Pin), flip between
them with the chips (Shipped and each pin; the selected one is outlined, and
unpinned edits stay under the chip they started from), and press Choose to hand the pick to the agent; a footer hint says how
to finish. Pins stay in memory unless you ask to save them; saved ones live under `uiTuningLab.*` or `.ui-tuning-lab/`,
and finalists you keep at landing are seeded into the lab next time.

Start with `SKILL.md`; it routes to everything else.

## Guarantees

- Development, DEBUG, internal, or tester builds only.
- Every lab opens through an agent path, one or more human fast paths, and a visible
  fallback; activation is development-only.
- Reset always returns to the declared default, however often the lab reopens.
- Persistence off by default; candidates are written to namespaced storage only when requested.
- Closing releases all lab-owned UI, timers, observers, listeners, and tasks.

## Checks an installed copy can run

`<skill-dir>` is where the skill is installed.

```sh
sh <skill-dir>/scripts/verify.sh source-gates path/to/source
sh <skill-dir>/scripts/verify.sh config path/to/lab.json
sh <skill-dir>/scripts/verify.sh profile path/to/saved-profile.json
```

Source lint cannot prove production absence. Inspect the compiled archive or
production bundle too (`references/verify-protocol.md`).
`source-gates` exits `3` with `N/A:` when the path contains no supported Swift or
web files, or no lab reference. That is deliberately distinct from PASS.

## Status

Used in real apps on web (React), iOS, and macOS (SwiftUI), with a recorded web
pilot in `validation/`. Android (Compose), Flutter, React Native, and Windows
(WinUI) are newer adaptations whose examples have not been compiled here yet;
visionOS, Linux, and HarmonyOS are adapted from the nearest example. Issues and
pull requests from any platform are welcome: that is how the newer ones mature.

## License

MIT. See `LICENSE.txt`.

## Developing this skill (repository only)

These files are not in the installed package.

```sh
sh tests/verify.sh      # linter and validator fixtures
sh tests/examples.sh    # every iOS, macOS, and web example variant linted, plus gate-stripped mutants, and the React Native host
sh tests/compile.sh     # Swift (iOS, macOS; DEBUG and Release) and TypeScript typecheck
sh tests/package.sh     # the package is self-contained
sh tools/package.sh     # builds dist/ui-tuning-lab/ and dist/ui-tuning-lab-<version>.zip
```

`tests/compile.sh` exits `3` with `SKIP` when a toolchain is missing. The web
pilot lives in `pilots/web-vite/`, its cross-engine checks in
`tests/pilot-web/check.mjs`, and evals in `evals/`. The package contains
`SKILL.md`, `README.md`, `references/`, `examples/`, `assets/`, `scripts/`, and
the license; the changelog, validation receipts, tests, tools, pilots, and evals
stay here.
