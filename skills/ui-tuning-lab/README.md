# ui-tuning-lab

An agent skill for tuning UI by feel. The agent adds a temporary,
development-only control panel beside a real screen: sliders, presets, chips to
compare looks, and Replay and Speed for motion. When you choose a look, it
writes those values into the feature's defaults and removes the panel.

Start with `SKILL.md`; it routes to everything else. Source, issues, and
release notes: https://github.com/Mohanad-Ramadan/ui-tuning-lab

## How a lab works

- **Shipped** is the declared default and is read-only; editing it starts a pin.
  The selected chip is outlined and is what the feature shows, so switching
  chips is the comparison.
- **Duplicate** branches the selected pin; **Choose** hands it to the agent
  through the log, a result file, and a `land <name>` code on the clipboard.
- Every lab opens through an agent path, one or more human fast paths the user
  picks, and a visible fallback. Shake is offered only when inspection proves it
  free.
- Pins stay in memory unless you ask to save them. Saved ones live under
  `uiTuningLab.*` or `.ui-tuning-lab/`, and finalists kept at landing are
  seeded into the lab next time.

## Guarantees

- Development, DEBUG, internal, or tester builds only; activation is
  development-only too.
- The Shipped chip always shows the declared default, however often the lab
  reopens.
- Persistence is off by default; pins are written to namespaced storage only
  when requested.
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

Used in real apps on web (React), iOS, and macOS (SwiftUI). Android (Compose),
Flutter, React Native, and Windows (WinUI) are newer adaptations whose examples
have not been compiled yet; visionOS, Linux, and HarmonyOS are adapted from the
nearest example. Every platform still gets the whole lab.

## License

MIT. See `LICENSE.txt`.
