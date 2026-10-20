# Verification Protocol

Keep three kinds of evidence distinct:

1. **Static checks** validate reusable configuration and recognize a limited set
   of Swift/web source gates.
2. **Hands-on checks** exercise behavior, accessibility, inputs, and teardown in
   the running app.
3. **Release-artifact inspection** establishes that the compiled archive or
   production bundle contains no activatable lab. Static source lint cannot make
   this claim.

## Static checks

```sh
sh tests/verify.sh
scripts/verify.sh config .ui-tuning-lab/lab.json
scripts/verify.sh source-gates path/to/app/source
```

The source linter recognizes exact `#if DEBUG` / `#ifdef DEBUG` in Swift. It also
accepts positive identifier conjunctions such as `#if DEBUG && INTERNAL_LAB`.
OR expressions, negations, literals, and release-inclusive conditions fail closed;
the same restriction applies to `#elseif`. For web it recognizes block-form
`if (import.meta.env.DEV)` or a `process.env.NODE_ENV !=/!== "production"`
comparison in JavaScript/TypeScript. Production-only and `else` branches are not
safe. Other valid gate styles require manual review or an
app-specific test. A passing lint result means only that recognized source
references are guarded.

Web parsing deliberately accepts a narrow block form: the opening `{` must be on
the guard line or the next nonblank line. Nested blocks are tracked. Ambiguous
structural braces in strings or comments fail closed rather than extending safe
scope. Rewrite the guard into the supported form or review it manually; do not
treat an ambiguity failure as evidence of a production leak.

Exit `3` with an `N/A:` message means the target had no supported Swift/web files
or no matching lab references. It is not a pass and supplies no gating evidence.

## Hands-on checks

- Opening at baseline is visually and behaviorally equivalent to the feature
  without the lab.
- At least two presets differ meaningfully and all direct controls update the same
  configuration consumed by the feature.
- Reset restores the captured baseline exactly. When persistence was requested,
  an explicit Save writes only the requested namespaced profile and retains the
  draft on failure. Otherwise confirm that no Save action or storage writer is
  present and record the Save checks as `N/A: persistence not requested`, with
  evidence of that absence.
- Touch, pointer, keyboard, focus, selection, gestures, screen-reader navigation,
  large text, reduced motion, resizing, rotation, and dismissal remain usable as
  applicable.
- After close, instruments/logging show no lab-owned work or retained UI.

## Release-artifact inspection

- iOS/macOS: archive the Release scheme, inspect the built product for lab symbols,
  strings, commands, menu items, and resources, then launch that archived product
  and try every development activation path.
- Web: produce the production bundle, search emitted assets and source maps (when
  shipped) for lab code/strings, then serve the bundle and try query, storage,
  keyboard, and developer-menu activation paths.

Record the exact commands, artifact identity, observations, and evidence links in
the target project's task report or a receipt copied from
`validation/receipt-template.md` into that project. Do not update the installed
skill's receipts during ordinary app work; the bundled platform receipts are
reserved for pilots validating this skill itself.

Failed or unrun applicable checks remain blocking. Save checks may be marked
`N/A: persistence not requested` only with evidence that the lab has no Save
action or storage writer. All other required checks still need evidence.
