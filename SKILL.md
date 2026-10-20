---
name: ui-tuning-lab
description: "Trigger: live lab, visual variants, try options live. Use before tuning animation, layout, appearance, or visible logic on the real screen when live comparison is useful."
license: "Proprietary — TODO: choose license"
metadata:
  author: "you"
  version: "1.0"
---

# UI Tuning Lab

Build a temporary in-app control surface beside the real feature so variants
can be compared, combined, reset, and deliberately saved.

## Guarantees

Every lab must satisfy all four:

1. **Internal only.** Compile or mount the lab only in DEBUG, development, or
   tester builds. Source lint is advisory; inspect the final release artifact.
2. **Reversible.** Capture the feature's real configuration before opening.
   Reset restores that exact baseline, including behavior as well as appearance.
3. **Explicit persistence.** Default to no persistence. Save only on an explicit
   action and only under `uiTuningLab.*` or `.ui-tuning-lab/`; never reuse a
   production preference key.
4. **Complete teardown.** Closing unmounts or releases the lab and cancels every
   timer, observer, listener, task, and duplicate render tree it owns.

## Workflow

1. Inspect the project first: platform, build system, target feature, existing
   configuration model, natural development gate, native presentation surface,
   persistence conventions, and test commands.
2. Infer safe defaults: feature target, scopes named by the request, the
   platform-native container, persistence off, and one unnamed working draft.
3. Ask at most one focused question only when an unresolved choice materially
   changes the implementation. Otherwise state the inferred choices and proceed.
4. Capture the baseline from the same configuration object the feature renders.
   Keep draft edits separate; reset copies the baseline back into the draft.
5. Add at least two meaningful presets plus direct controls. Applying either must
   update that shared configuration rather than a preview-only duplicate. Add a
   **Copy values** action that copies and logs, as one
   `UITUNINGLAB_VALUES {...}` line, only the fields that differ from the baseline.
6. Add explicit Save and Load saved actions only when persistence was requested.
   Report write and load errors without losing the draft; loading never changes
   the baseline.
7. Land the winner when the user picks one: write the copied values into the
   feature's real defaults, show a baseline-to-winner table, then remove the lab
   or keep it, as the user chooses. Follow `references/landing-protocol.md`.
8. Verify baseline equivalence, variants, inputs, accessibility, dismissal, and
   teardown. Then inspect a release build or bundle for absence.

Name every lab-owned type, file, and storage key with a lab marker
(`UITuningLab`, `uiTuningLab`, or `ui-tuning-lab`) so the source linter can find
it. In Swift, also mark the host's DEBUG-only state and functions (for example
`showUITuningLab`, `uiTuningLabBaseline`), and wrap each lab file in `#if DEBUG`. On the web, keep lab code in
`*.ui-tuning-lab.tsx` modules and load them only through a dynamic `import()`
inside an `if (import.meta.env.DEV) {` block; a static import fails the linter.
The web host variable (`TuningLabHost` in the examples) stays unmarked because it
is declared outside the gate.
Import lab modules by relative path; the linter does not resolve aliases. After
building a lab, run `source-gates` on a directory that holds both the feature
files and the lab files; it must PASS. `N/A` means no marked reference was
found, usually because the naming rule was skipped. A PASS cannot prove that
every lab symbol was marked, so also keep the rule while writing the code.

An ephemeral lab needs no `lab.json`. Create `.ui-tuning-lab/lab.json` only for
a reusable lab, and check a saved profile only when persistence was requested
(`references/config-schema.md`):

```sh
scripts/verify.sh config .ui-tuning-lab/lab.json
scripts/verify.sh profile path/to/saved-profile.json
```

Use `scripts/verify.sh source-gates <source-path>` as an advisory lint check. It
does not prove absence from a release artifact. An `N/A` result means nothing
relevant was checked and must not be reported as a pass.

## Route to Details

- Read `references/setup-protocol.md` when project inspection leaves ambiguity.
- Read `references/surface-matrix.md` for candidate native containers and gates.
- Read `references/container-tuning.md` only when tuning the host itself.
- Read `references/landing-protocol.md` when the user picks a winner.
- Read `references/config-schema.md` before writing `lab.json` or a saved profile.
- Read `references/verify-protocol.md` before claiming validation.
- Use `assets/labconfig.template.json`, `assets/profile.template.json`, and
  `profiles/_template.md` only for a reusable lab or saved profile.
- Use the matching candidate in `examples/` as a starting point, not as evidence
  that the user's app has passed validation.

## Report

Return the files changed, inferred or chosen container and gate, baseline source,
save location if any, the landed values table and the declaration changed, whether
the lab was removed or kept, commands run, and verification evidence. Distinguish static
lint, hands-on checks, and release-artifact inspection. Never mark an unrun check
as passed.
