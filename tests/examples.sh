#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SKILL="$ROOT/skills/ui-tuning-lab"
. "$ROOT/tests/lib/extract.sh"
VERIFY="$SKILL/scripts/verify.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ui-tuning-lab-examples.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
EXAMPLES='swiftui-popover-palette.md macos-panel-minimal.md web-floating-panel.md animation-spring.md'
failures=0

ok() { printf 'ok - %s\n' "$1"; }
not_ok() { printf 'not ok - %s\n' "$1"; [ -z "${2:-}" ] || printf '%s\n' "$2"; failures=$((failures + 1)); }

require_text() {
  if grep -qF "$2" "$SKILL/$1"; then ok "$3"; else not_ok "$3"; fi
}

# require_in <extracted-file> <text> <name>: assert against the code a variant
# actually produces, so a feature that lives only in another variant cannot pass.
require_in() {
  if grep -qF "$2" "$1"; then ok "$3"; else not_ok "$3"; fi
}

lint_status() {
  set +e
  output=$("$VERIFY" source-gates "$1" 2>&1)
  status=$?
  set -e
}

# The default variant is what users copy when persistence was not requested.
for example in $EXAMPLES; do
  dir="$WORK/${example%.md}-ephemeral"
  extract_example "$SKILL/examples/$example" "$dir"
  if [ -z "$(ls "$dir")" ]; then
    not_ok "$example has no tagged source files"
  # The result file (uiTuningLab.result, .ui-tuning-lab/result.json) is the one
  # write an ephemeral lab makes; pins must not reach storage.
  elif grep -Eq 'UITuningLabProfile|uiTuningLab\.candidates|candidates/|Button\("Save"|>Save</button>|func save\(|function save\(' "$dir"/*; then
    not_ok "$example default source includes persistence"
  else
    ok "$example default source is ephemeral"
  fi
done

expect_mutant_fails() {
  lint_status "$1"
  if [ "$status" -eq 1 ]; then ok "$2 fails source-gates"; else not_ok "$2 fails source-gates (exit $status)" "$output"; fi
}

# Every variant must pass source-gates, and removing its gate must fail it.
# Swift and web files are mutated and linted separately so one language's
# failure cannot mask the other's.
for example in $EXAMPLES; do
  for variant in $(example_variants "$SKILL/examples/$example"); do
    label="$example [$variant]"
    dir="$WORK/${example%.md}-$variant"
    extract_example "$SKILL/examples/$example" "$dir" "$variant"
    lint_status "$dir"
    if [ "$status" -eq 0 ]; then ok "$label passes source-gates"; else not_ok "$label passes source-gates (exit $status)" "$output"; fi

    if [ "$variant" != default ]; then
      if diff -rq "$WORK/${example%.md}-default" "$dir" >/dev/null; then
        not_ok "$label differs from the default variant"
      else
        ok "$label differs from the default variant"
      fi
    fi

    for language in swift web; do
      copy="$WORK/${example%.md}-$variant-strip-$language"
      mkdir -p "$copy"
      case "$language" in
        swift) find "$dir" -name '*.swift' -exec cp {} "$copy" \; ;;
        web) find "$dir" -name '*.tsx' -exec cp {} "$copy" \; ;;
      esac
      [ -n "$(ls "$copy")" ] || continue
      for file in "$copy"/*; do
        sed -e '/^[[:space:]]*#if DEBUG[[:space:]]*$/d' -e '/^[[:space:]]*#else[[:space:]]*$/d' \
            -e '/^[[:space:]]*#endif[[:space:]]*$/d' -e 's/if (import\.meta\.env\.DEV) {/if (true) {/' \
            "$file" > "$file.tmp" && mv "$file.tmp" "$file"
      done
      expect_mutant_fails "$copy" "$label $language strip-gates mutant"
    done

    for module_path in "$dir"/*.ui-tuning-lab.tsx; do
      [ -e "$module_path" ] || continue
      copy="$WORK/${example%.md}-$variant-static-import"
      cp -R "$dir" "$copy"
      module=$(basename "$module_path" .tsx)
      host="$copy/${module%.ui-tuning-lab}.tsx"
      { printf 'import UITuningLabStatic from "./%s";\nvoid UITuningLabStatic;\n' "$module"; cat "$host"; } > "$host.tmp" && mv "$host.tmp" "$host"
      expect_mutant_fails "$copy" "$label static-import mutant"
    done
  done
done

require_text examples/swiftui-popover-palette.md 'UITuningLabControls(style: $style, baseline: .appDefault)' 'iOS baseline is the declared default'
require_text examples/macos-panel-minimal.md 'baseline: .appDefault)' 'macOS baseline is the declared default'
require_text examples/web-floating-panel.md 'const baseline: CardConfig = appDefault;' 'web baseline is the declared default'
require_text examples/animation-spring.md 'const baseline: EntranceMotion = appDefault;' 'web motion baseline is the declared default'
require_text examples/animation-spring.md 'uiTuningLab.rendered(motion)' 'SwiftUI motion renders the selected look'
require_text examples/swiftui-popover-palette.md '.presentationBackgroundInteraction(.enabled(upThrough: .medium))' 'iOS sheet leaves the feature usable'
require_text examples/swiftui-popover-palette.md 'Button("Close") { dismiss() }' 'iOS lab has a Close button'

# The default variant must carry the full triad: agent path, human path, and
# visible fallback. These checks read the extracted variant, not the merged
# Markdown, so an activation path that exists only in the shake variant fails.
ios_default="$WORK/swiftui-popover-palette-default"
ios_shake="$WORK/swiftui-popover-palette-shake"
require_in "$ios_default/UITuningLabLaunch.swift" 'UserDefaults.standard.bool(forKey: "UITuningLabOpen")' 'iOS default agent path honors the launch argument value'
require_in "$ios_default/UITuningLabLaunch.swift" 'defer { pending = false }' 'iOS default agent path is consumed once per launch'
require_in "$ios_default/FeatureScreen.swift" 'if UITuningLabLaunch.consumeRequest() { showUITuningLab = true }' 'iOS default host opens from the agent path'
require_in "$ios_default/FeatureScreen.swift" 'Button("Card Lab", action: openUITuningLab)' 'iOS default host keeps a visible fallback'
if grep -q 'UITuningLabShake' "$ios_default"/*; then
  not_ok 'iOS default host is decoupled from shake'
else
  ok 'iOS default host is decoupled from shake'
fi
require_in "$ios_shake/FeatureScreen.swift" 'UITuningLabShakeReader' 'iOS shake variant attaches the responder shim'
require_in "$ios_shake/FeatureScreen.swift" 'if UITuningLabLaunch.consumeRequest() { showUITuningLab = true }' 'iOS shake variant shares the agent path'
require_in "$ios_shake/UITuningLabShake.swift" 'super.motionEnded(motion, with: event)' 'iOS shake shim preserves system shake handling'
require_in "$ios_shake/UITuningLabShake.swift" 'return responder is UITextInput' 'iOS shake shim leaves text input shake-to-undo alone'
require_in "$ios_shake/UITuningLabShake.swift" 'becomeFirstResponder()' 'iOS shake shim re-arms after the lab closes'
require_in "$ios_shake/UITuningLabShake.swift" 'self?.armIfNeeded(attempts: attempts - 1)' 'iOS shake shim retries re-arming after a dismissal'
require_in "$ios_shake/UITuningLabShake.swift" 'window.uiTuningLabFirstResponder == nil' 'iOS shake shim never takes focus from another responder'
require_in "$ios_shake/FeatureScreen.swift" '.accessibilityLabel("Open UI tuning lab")' 'iOS shake fallback is accessible'

# The SwiftUI motion example is a default host too, so it needs the same triad.
motion_default="$WORK/animation-spring-default"
require_in "$motion_default/UITuningLabLaunch.swift" 'UserDefaults.standard.bool(forKey: "UITuningLabOpen")' 'SwiftUI motion default agent path honors the launch argument value'
require_in "$motion_default/EntranceScreen.swift" 'if UITuningLabLaunch.consumeRequest() { showUITuningLab = true }' 'SwiftUI motion default host opens from the agent path'
require_in "$motion_default/EntranceScreen.swift" 'Button("Entrance Lab", action: openUITuningLab)' 'SwiftUI motion default host keeps a visible fallback'

# macOS pairs the launch argument with the existing menu command and shortcut.
macos_default="$WORK/macos-panel-minimal-default"
require_in "$macos_default/UITuningLabLaunch.swift" 'UserDefaults.standard.bool(forKey: "UITuningLabOpen")' 'macOS default agent path honors the launch argument value'
require_in "$macos_default/ExampleApp.swift" '.onAppear { if UITuningLabLaunch.consumeRequest() { model.uiTuningLab.show() } }' 'macOS default host opens one panel from the agent path'
require_in "$macos_default/UITuningLabCoordinator.swift" '.keyboardShortcut("l", modifiers: [.command, .shift])' 'macOS default host keeps the human path'

# Web labs parse the agent query only inside the development-only module.
for dir in "$WORK/web-floating-panel-default" "$WORK/web-floating-panel-persist"; do
  require_in "$dir/FeatureScreen.ui-tuning-lab.tsx" 'get("ui-tuning-lab") === "1"' "$(basename "$dir") web lab parses the agent query"
  require_in "$dir/FeatureScreen.ui-tuning-lab.tsx" 'useEffect(clearLaunchRequest, []);' "$(basename "$dir") web lab consumes the agent query once"
  require_in "$dir/FeatureScreen.ui-tuning-lab.tsx" 'style={triggerStyle}>Card Lab</button>' "$(basename "$dir") web lab keeps a visible fallback"
done
require_in "$WORK/animation-spring-default/EntranceScreen.ui-tuning-lab.tsx" 'get("ui-tuning-lab") === "1"' 'web motion lab parses the agent query'
require_in "$WORK/animation-spring-default/EntranceScreen.ui-tuning-lab.tsx" 'useEffect(clearLaunchRequest, []);' 'web motion lab consumes the agent query once'
if grep -q 'URLSearchParams' "$WORK/web-floating-panel-default/FeatureScreen.tsx" \
    "$WORK/animation-spring-default/EntranceScreen.tsx"; then
  not_ok 'web agent query is parsed only inside the development-gated lab module'
else
  ok 'web agent query is parsed only inside the development-gated lab module'
fi
if grep -qE 'CFBundleURLSchemes|UIApplication\.shared\.open' "$SKILL/examples/swiftui-popover-palette.md"; then
  not_ok 'iOS agent path does not register a URL scheme'
else
  ok 'iOS agent path does not register a URL scheme'
fi
# A baseline taken from the screen at open becomes the draft after a reopen.
if grep -nE 'setBaseline\(|uiTuningLabBaseline|baseline = (style|config|motion)|baseline: *(model\.)?(style|config|motion)\b|baseline \?\? ' "$SKILL"/examples/*.md >/dev/null; then
  not_ok 'no example captures the baseline from the screen at open'
else
  ok 'no example captures the baseline from the screen at open'
fi
require_text examples/web-floating-panel.md 'role="dialog"' 'web popover exposes dialog semantics'
require_text examples/web-floating-panel.md 'aria-labelledby="ui-tuning-lab-title"' 'web dialog has a labelled heading'
require_text examples/web-floating-panel.md '{...popoverManual}' 'web lab stays open while the feature is used'
require_text examples/web-floating-panel.md 'document.addEventListener("keydown", onKeyDown);' 'web lab closes on Escape wherever focus is'
require_text examples/web-floating-panel.md 'useLayoutEffect(() => { latest.current = { candidates, selected }; });' 'web close path reads current pins, not stale state'
require_text examples/macos-panel-minimal.md '@ObservedObject var model: FeatureSceneModel' 'macOS panel observes the model so it redraws'
if grep -q 'get: { \[weak self\] in self?\.' "$SKILL/examples/macos-panel-minimal.md"; then
  not_ok 'macOS panel does not use a closure Binding to plain properties'
else
  ok 'macOS panel does not use a closure Binding to plain properties'
fi
require_text examples/web-floating-panel.md 'maxHeight: "calc(100dvh - 88px)"' 'web panel stays inside the viewport'
require_text examples/web-floating-panel.md 'border: "1px solid GrayText", background: "Canvas"' 'web panel has an outline against a matching background'
require_text examples/animation-spring.md 'border: "1px solid GrayText", background: "Canvas"' 'web motion panel has an outline against a matching background'
require_text examples/flutter-overlay.md 'side: BorderSide(color: Theme.of(overlayContext).colorScheme.outline)' 'Flutter panel has an outline against a matching background'
require_text examples/flutter-overlay.md 'side: BorderSide(color: Theme.of(context).colorScheme.outline)' 'Flutter result bar keeps the outline'
require_text examples/android-compose-sheet.md 'border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)' 'Compose panel has an outline against a matching background'
require_text examples/web-floating-panel.md '<output aria-hidden="true">{config.radius}px</output>' 'web sliders show their value'
require_text examples/web-floating-panel.md 'firstControl.current?.focus()' 'web dialog receives initial focus'
require_text examples/web-floating-panel.md 'trigger.current?.focus()' 'web dismissal restores trigger focus'
require_text examples/web-floating-panel.md 'cancelAnimationFrame(focusFrame)' 'web cleanup cancels pending initial-focus work'
require_text examples/web-floating-panel.md 'value={config.gap}' 'web lab controls every config field'
require_text examples/web-floating-panel.md 'uiTuningLab.candidates.' 'web candidates use the uiTuningLab namespace'
require_text examples/swiftui-popover-palette.md '.onDisappear { candidates.leave() }' 'iOS closing keeps the selected look and logs an edited pin'
require_text examples/macos-panel-minimal.md 'candidates.leave()' 'macOS closing keeps the selected look and logs an edited pin'
require_text examples/macos-panel-minimal.md '.frame(width: 320, height: 420, alignment: .top)' 'macOS panel keeps its size after Change'
require_text examples/macos-panel-minimal.md 'override func cancelOperation(_ sender: Any?) { close() }' 'macOS panel closes on Escape'
require_text examples/web-floating-panel.md 'when the browser has no Popover API. The feature keeps the selected look.' 'web closing keeps the selected look'
require_text examples/animation-spring.md 'lab.replayToken += 1' 'SwiftUI motion lab can replay'
require_text examples/animation-spring.md 'motion.duration /= speed' 'SwiftUI motion lab slows the preview by stretching duration'
require_text examples/animation-spring.md 'accessibilityReduceMotion' 'SwiftUI motion respects Reduce Motion'
require_text examples/animation-spring.md 'key={replay}' 'web motion lab can replay'
require_text examples/animation-spring.md 'durationMs: source.durationMs / speed' 'web motion lab slows the preview by stretching duration'
require_text examples/animation-spring.md 'prefers-reduced-motion: reduce' 'web motion respects reduced motion'

# Landing: every lab can copy its changed values, per language.
for example in $EXAMPLES; do
  dir="$WORK/${example%.md}-default"
  if ls "$dir"/*.swift >/dev/null 2>&1; then
    if grep -q 'Button("Copy values")' "$dir"/*.swift && grep -q 'uiTuningLabCopyValues(from: baseline' "$dir"/*.swift \
        && grep -q 'UITUNINGLAB_VALUES' "$dir/UITuningLabValues.swift"; then
      ok "$example Swift lab copies and logs changed values"
    else
      not_ok "$example Swift lab copies and logs changed values"
    fi
  fi
  if ls "$dir"/*.ui-tuning-lab.tsx >/dev/null 2>&1; then
    if grep -q 'onClick={copyValues}>Copy values' "$dir"/*.ui-tuning-lab.tsx \
        && grep -q 'console.info(`UITUNINGLAB_VALUES' "$dir"/*.ui-tuning-lab.tsx \
        && grep -q 'changedValues(baseline' "$dir"/*.ui-tuning-lab.tsx; then
      ok "$example web lab copies and logs changed values"
    else
      not_ok "$example web lab copies and logs changed values"
    fi
  fi
done

# The shared Swift helper must be the same file in every Swift example.
reference_helper="$WORK/swiftui-popover-palette-default/UITuningLabValues.swift"
for example in macos-panel-minimal animation-spring; do
  if cmp -s "$reference_helper" "$WORK/$example-default/UITuningLabValues.swift"; then
    ok "$example.md shares the canonical UITuningLabValues.swift"
  else
    not_ok "$example.md shares the canonical UITuningLabValues.swift"
  fi
done

# Saved profiles: load is validated, and the envelope matches the template.
template_fields=$(jq -r 'keys[]' "$SKILL/assets/profile.template.json" | sort | tr '\n' ' ')
for example in swiftui-popover-palette macos-panel-minimal web-floating-panel; do
  dir="$WORK/$example-persist"
  if grep -Eq 'schemaVersion (==|!==) 2' "$dir"/*; then
    ok "$example.md persist variant loads candidates with a schema check"
  else
    not_ok "$example.md persist variant loads candidates with a schema check"
  fi
  if grep -Eq 'candidates' "$dir"/* && ! grep -Eq 'Button\("Save"\)|>Save</button>' "$dir"/*; then
    ok "$example.md persist variant stores candidates instead of one Save slot"
  else
    not_ok "$example.md persist variant stores candidates instead of one Save slot"
  fi
  fields=$(awk '
    /^struct UITuningLabProfile: Codable \{$/ || /^type UITuningLabProfile = \{$/ { inside = 1; next }
    inside && (/^\}/ || /^    static/) { exit }
    inside && match($0, /^    var [A-Za-z]+/) { print substr($0, 9, RLENGTH - 8) }
    inside && match($0, /^  [A-Za-z]+:/) { print substr($0, 3, RLENGTH - 3) }
  ' "$dir"/* | sort | tr '\n' ' ')
  if [ "$fields" = "$template_fields" ]; then
    ok "$example.md profile fields match assets/profile.template.json"
  else
    not_ok "$example.md profile fields match assets/profile.template.json" "got: $fields; want: $template_fields"
  fi
done

# Chips (Look N), Save & copy, Apply (hidden after the first), and the result file
# are in every variant users copy (references/candidates.md), the ephemeral
# default included.
for example in $EXAMPLES; do
  for variant in $(example_variants "$SKILL/examples/$example"); do
    dir="$WORK/${example%.md}-$variant"
    label="$example [$variant]"
    for needle in 'Shipped' 'Save & copy' 'Apply' 'Save & copy to keep a look · Apply to finish' \
        'Save & copy, then paste it in chat' 'Applied: ' 'Saved ' 'Look ' 'look-' \
        'paste it in chat so the agent applies it' 'land ' 'result' 'UITUNINGLAB_CANDIDATE' 'UITUNINGLAB_CANDIDATE_REMOVED' 'UITUNINGLAB_DONE' \
        'only on the selected look'; do
      if grep -rqF "$needle" "$dir"; then ok "$label has $needle"; else not_ok "$label has $needle"; fi
    done
    # Apply is shown only until the first Apply.
    if grep -rqE 'applies ===? 0' "$dir"; then ok "$label hides Apply after the first"; else not_ok "$label hides Apply after the first"; fi
    # Duplicate and auto-named pins are gone: a chip appears only through Save & copy.
    if grep -rqE 'Duplicate|duplicate\(|nextName\(|FavoriteName|"tweak"' "$dir"; then
      not_ok "$label has no Duplicate or auto-named pins" "$(grep -rnE 'Duplicate|duplicate\(|nextName\(|FavoriteName|"tweak"' "$dir")"
    else
      ok "$label has no Duplicate or auto-named pins"
    fi
    # There is no draft, stash, or Reset: the selected chip is the look shown,
    # and selection is an outline, never a "<source> + edits" label.
    retired='\+ edits|draftMatch|stashedDraft|Pin looks to compare|"Reset"|>Reset<'
    if grep -rqE "$retired" "$dir"; then
      not_ok "$label has no draft, stash, or Reset" "$(grep -rnE "$retired" "$dir")"
    else
      ok "$label has no draft, stash, or Reset"
    fi
    # The old labels and glyphs are gone from the panel.
    if grep -rqE '★|✓|"Now"|>Now<|Use this|"Original"|>Original<' "$dir"; then
      not_ok "$label has no retired panel labels" "$(grep -rnE '★|✓|"Now"|>Now<|Use this|"Original"|>Original<' "$dir")"
    else
      ok "$label has no retired panel labels"
    fi
  done
done

# The React Native adaptation is not compiled here, but its host is TypeScript,
# so the linter can check that the lab module loads only under __DEV__.
rn="$WORK/react-native-overlay"
mkdir -p "$rn"
awk -v d="$rn" '/^```(tsx|ts)$/ { inside = 1; n++; out = d "/block" n ".tsx"; next } /^```$/ { inside = 0 } inside { print > out }' \
  "$SKILL/examples/react-native-overlay.md"
rn_host=$(grep -l 'require("./' "$rn"/*.tsx 2>/dev/null | head -1)
if [ -n "$rn_host" ] && "$VERIFY" source-gates "$rn_host" >/dev/null 2>&1; then
  ok "react-native-overlay.md host passes source-gates"
else
  not_ok "react-native-overlay.md host passes source-gates"
fi
if grep -q 'borderColor: "#8a8a8a"' "$SKILL/examples/react-native-overlay.md"; then
  ok "react-native-overlay.md panel has an outline against a matching background"
else
  not_ok "react-native-overlay.md panel has an outline against a matching background"
fi

if grep -rn 'variantLab' "$SKILL/SKILL.md" "$SKILL/examples" "$SKILL/references" "$ROOT/validation" >/dev/null; then
  not_ok 'no legacy variantLab namespace remains'
else
  ok 'no legacy variantLab namespace remains'
fi

[ "$failures" -eq 0 ]
