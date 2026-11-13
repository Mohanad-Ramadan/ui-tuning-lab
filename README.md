# ui-tuning-lab

[![skills.sh](https://skills.sh/b/Mohanad-Ramadan/ui-tuning-lab)](https://skills.sh/Mohanad-Ramadan/ui-tuning-lab)

An agent skill for tuning UI by feel. Ask your coding agent to "dial in this
card's spacing" or "give me three better versions of this list", and it adds a
temporary, development-only control panel beside the real screen in your
running app. You drag sliders, try presets, and compare looks on the real
feature. When you choose one, the agent writes those values into the feature's
defaults and removes the panel. Nothing about the lab ships.

## Install

```sh
npx skills add Mohanad-Ramadan/ui-tuning-lab
```

This works with Claude Code, Codex, Cursor, and the other agents the
[skills CLI](https://github.com/vercel-labs/skills) supports. Add `-g` to
install it for every project. To install by hand, copy `skills/ui-tuning-lab/`
into your agent's skills directory (for Claude Code, `~/.claude/skills/`).

## What you get

- **A panel beside the real feature**, not a mockup: presets, direct controls,
  and Replay and Speed for motion.
- **Looks you compare by switching chips.** Shipped is the declared default,
  and every chip is read-only: an edit forks the chip into unsaved changes, and
  Save & pin keeps them as a new chip named after its preset (Brass-1,
  Custom-1; an edit on Brass-1 pins as Brass-2). A pinned look never changes.
  Undo, Redo, and Reset step back through your unsaved changes.
- **Every control shows its default.** Sliders mark the Shipped value with a
  tick and snap onto it as you drag; a changed control reads
  `14 px · default 12` and gets a ↺ that puts it alone back to Shipped.
- **Alternative designs** as a Design picker in the same panel, with the
  original as the baseline.
- **A finish with no copy-paste.** Apply hands the selected look to the agent
  through the log, a result file, and a `land <name>` code on the clipboard.
- **Opening without hunting.** Every lab has a path the agent can open it
  through, one or more fast paths you pick (a shortcut, a gesture, a menu item),
  and a visible fallback.

## Guarantees

- The lab exists only in development, DEBUG, internal, or tester builds, and
  the agent checks the release build or production bundle for leftovers.
- Opening the lab changes nothing on screen, and the Shipped chip always shows
  the declared default.
- Nothing is saved unless you ask. Saved looks live only under `uiTuningLab.*`
  or `.ui-tuning-lab/`, never a production key.
- Closing releases every view, timer, observer, listener, and task the lab owns.

## Platforms

Used in real apps on web (React), iOS, and macOS (SwiftUI), with a recorded web
pilot in `validation/`. React Native's example is typechecked but not run on a device. Android
(Compose), Flutter, and Windows (WinUI) are newer adaptations whose examples
have not been compiled here yet;
visionOS, Linux, and HarmonyOS are adapted from the nearest example. Issues and
pull requests from any platform are welcome: that is how the newer ones mature.

## Repository layout

`skills/ui-tuning-lab/` is the skill, exactly as it installs. Start with its
`SKILL.md`, which routes to everything else. Everything else in this repository
is for developing the skill and is not installed.

```sh
sh tests/verify.sh      # linter and validator fixtures
sh tests/examples.sh    # every iOS, macOS, and web example variant linted, plus gate-stripped mutants, and the React Native host
sh tests/compile.sh     # Swift (iOS, macOS; DEBUG and Release) and TypeScript typecheck
sh tests/package.sh     # the skill folder is self-contained and holds only shipped files
sh tools/package.sh     # builds dist/ui-tuning-lab/ and dist/ui-tuning-lab-<version>.zip
```

`tests/compile.sh` exits `3` with `SKIP` when a toolchain is missing. The
pilots in `pilots/` are small apps the evals run against: `web-vite/`,
`ios-swiftui/` and `macos-swiftui/` (generated with xcodegen), and
`react-native/` (typecheck only). The web pilot's cross-engine checks are in
`tests/pilot-web/check.mjs` (run with `sh tests/pilot-web/run.sh`); evals are
in `evals/`, platform receipts in `validation/`, and release notes in
`CHANGELOG.md`.

## License

MIT. See `LICENSE.txt`.
