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

`<skill-dir>` is this skill's installed directory.

```sh
sh <skill-dir>/scripts/verify.sh config .ui-tuning-lab/lab.json
sh <skill-dir>/scripts/verify.sh profile path/to/saved-profile.json
sh <skill-dir>/scripts/verify.sh source-gates path/to/app/source
```

The linter treats a line as a lab reference when it contains `UITuningLab`,
`uiTuningLab`, or `ui-tuning-lab`. Generic names such as `LabPanel` are not
markers, so lab code that skips the naming rule is invisible to it: the result is
`N/A` when nothing else is marked, and an unmarked symbol is silently ignored when
other references are present. Lint a directory containing both the importer and
the lab module; linting a lone lab module reports `N/A`. Imports through path
aliases are not resolved, so import lab modules by relative path.

Web files named `*.ui-tuning-lab.{ts,tsx,js,jsx}` are development-only lab
modules: their contents are not linted, and every import of them is linted in the
importing file instead. A lab reference inside a multi-line template literal
always fails, because its scope cannot be determined. A directory containing only lab modules, with nothing
importing them, is `N/A`, not a pass.

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
structural braces in strings, comments, escaped or character-class regex text, or
on a line that opens or closes a multi-line template literal fail closed rather
than extending safe scope. Unbalanced braces at end of file also fail. In Swift,
`#if` lines inside a multi-line string are text, and an unbalanced `#if`/`#endif`
fails. Rewrite the guard into the supported form or review it manually; do not
treat an ambiguity failure as evidence of a production leak.

Exit `3` with an `N/A:` message means the target had no supported Swift/web files
or no matching lab references. It is not a pass and supplies no gating evidence.

## Hands-on checks

- Opening at baseline is visually and behaviorally equivalent to the feature
  without the lab.
- Every documented activation path opens the lab: the agent path (on iOS, launch
  with `-UITuningLabOpen 1`), the chosen human path, and the visible fallback. With
  a text input focused, shake still reaches the system's undo and does not open
  the lab. After the lab closes, the human path works again without a relaunch.
  VoiceOver or Switch Control can reach the fallback. When more than one lab
  exists, each path opens the intended one, never an arbitrary one.
- At least two presets differ meaningfully and all direct controls update the same
  configuration consumed by the feature.
- Reset restores the baseline (the declared default) exactly, including after the
  lab has been closed and reopened with a draft still applied.
- Copy values copies, and logs as one `UITUNINGLAB_VALUES` line, only the fields
  that differ from the baseline; `{}` when nothing changed. Landing writes those
  values into the feature defaults (`references/landing-protocol.md`).
- When persistence was requested, an explicit Save writes only the requested
  namespaced profile, which passes `verify.sh profile`, and retains the draft on
  failure. Load saved applies the stored overrides to the draft without changing
  the baseline, and reports incompatible data without modifying it. Otherwise,
  confirm that no Save action or storage writer is present and record the Save checks as `N/A: persistence not requested`, with
  evidence of that absence.
- Touch, pointer, keyboard, focus, selection, gestures, screen-reader navigation,
  large text, reduced motion, resizing, rotation, and dismissal remain usable as
  applicable.
- After close, instruments/logging show no lab-owned work or retained UI.

## Release-artifact inspection

- iOS/macOS: archive the Release scheme, inspect the built product for lab symbols,
  strings, commands, menu items, launch arguments, and resources, then launch that
  archived product and try every development activation path, including the
  `-UITuningLabOpen 1` launch argument, a focused text field followed by shake,
  any debug menu command or key equivalent, the fallback control's label, and any
  URL scheme or notification name the lab registered.
- Web: produce the production bundle, then search every emitted asset and source
  map (when shipped) for the lab markers and for lab-only strings such as the
  fallback and preset labels. Do not rely on a missing lab chunk: bundlers often
  emit a single file, so the absence of a separate chunk proves nothing. Then
  serve the bundle (`vite preview`, `next start`, or the app's own static server)
  and try every way the lab opens in development, plus the obvious guesses:
  - the fallback control and any menu entry the lab added;
  - query strings: `?ui-tuning-lab=1`, `?uiTuningLab=1`, `?tune=1`, `?debug=1`;
  - storage: set `uiTuningLab.open` and `uiTuningLab.default` in `localStorage`
    and reload;
  - keyboard: any shortcut the lab registered, plus `Control+Shift+L` and
    `Meta+Shift+L`.

  Each must leave no activation control, panel, `[popover]`, or `[role=dialog]`
  from the lab. These checks apply while a lab is present; after the lab is
  removed, the landing protocol's source check and build are enough.

Record the exact commands, artifact identity, observations, and evidence links in
the target project's task report or a receipt copied from
`validation/receipt-template.md` into that project. Do not update the installed
skill's receipts during ordinary app work; the bundled platform receipts are
reserved for pilots validating this skill itself.

Failed or unrun applicable checks remain blocking. Save checks may be marked
`N/A: persistence not requested` only with evidence that the lab has no Save
action or storage writer. All other required checks still need evidence.
