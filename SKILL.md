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
   action and only under `variantLab.*` or `.ui-tuning-lab/`; never reuse a
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
   update that shared configuration rather than a preview-only duplicate.
6. Add an explicit Save action only when persistence was requested. Report write
   errors without losing the draft.
7. Verify baseline equivalence, variants, inputs, accessibility, dismissal, and
   teardown. Then inspect a release build or bundle for absence.

An ephemeral lab needs no `lab.json`. Create `.ui-tuning-lab/lab.json` only for
a reusable or saved profile, then validate it with:

```sh
scripts/verify.sh config .ui-tuning-lab/lab.json
```

Use `scripts/verify.sh source-gates <source-path>` as an advisory lint check. It
does not prove absence from a release artifact. An `N/A` result means nothing
relevant was checked and must not be reported as a pass.

## Route to Details

- Read `references/setup-protocol.md` when project inspection leaves ambiguity.
- Read `references/surface-matrix.md` for candidate native containers and gates.
- Read `references/container-tuning.md` only when tuning the host itself.
- Read `references/verify-protocol.md` before claiming validation.
- Use `assets/labconfig.template.json` and `profiles/_template.md` only for a
  reusable profile.
- Use the matching candidate in `examples/` as a starting point, not as evidence
  that the user's app has passed validation.

## Report

Return the files changed, inferred or chosen container and gate, baseline source,
save location if any, commands run, and verification evidence. Distinguish static
lint, hands-on checks, and release-artifact inspection. Never mark an unrun check
as passed.
