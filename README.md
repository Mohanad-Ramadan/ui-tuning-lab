# ui-tuning-lab

A development-only skill for adding a temporary control surface to a real app
screen so visual and interaction variants can be compared live.

The workflow is inspect-first: it derives the platform, gate, container,
configuration, and baseline from the project and asks at most one material
question. Ephemeral labs need no configuration file. Reusable profiles use a
validated `.ui-tuning-lab/lab.json` and explicit namespaced saves.

## Guarantees

- Development, DEBUG, internal, or tester builds only.
- Exact baseline capture and reset.
- Persistence off by default; explicit namespaced Save when requested.
- Closing releases all lab-owned UI, timers, observers, listeners, and tasks.

## Verification

```sh
sh tests/verify.sh
sh tests/examples.sh
sh tests/compile.sh
scripts/verify.sh config path/to/lab.json
scripts/verify.sh profile path/to/saved-profile.json
scripts/verify.sh source-gates path/to/source
```

`tests/examples.sh` lints every example variant and checks that removing its gate
fails the linter. `tests/compile.sh` typechecks every example: Swift for iOS and
macOS in both DEBUG and Release, and TypeScript against the pinned toolchain in
`tests/compile/web/`. It exits `3` with `SKIP` when a toolchain is missing.

Source lint cannot prove production absence. Approval requires inspection of the
compiled archive or production bundle using `references/verify-protocol.md` and
evidence in the target project's task report or a copied receipt. The bundled
`validation/` receipts are reserved for this skill's platform pilots.

`source-gates` exits `3` with `N/A:` when the path contains no supported Swift or
web files, or when supported files contain no lab reference. This is deliberately
distinct from PASS: there was nothing relevant to validate.

## Status

iOS, macOS, and web guidance is **candidate**, pending hands-on validation against
one commit. Android, Windows, Flutter, React Native, visionOS, Linux, and HarmonyOS
are unvalidated adaptation notes. Nothing here records a completed platform pilot.

`VERSION`, release notes, author metadata, and license remain unchanged during
the private refactor and validation cycle. Publishing is a separate explicit step.
