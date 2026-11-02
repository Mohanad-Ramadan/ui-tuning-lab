#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib/extract.sh"
VERIFY="$ROOT/scripts/verify.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ui-tuning-lab-examples.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
EXAMPLES='swiftui-popover-palette.md macos-panel-minimal.md web-floating-panel.md animation-spring.md'
failures=0

ok() { printf 'ok - %s\n' "$1"; }
not_ok() { printf 'not ok - %s\n' "$1"; [ -z "${2:-}" ] || printf '%s\n' "$2"; failures=$((failures + 1)); }

require_text() {
  if grep -qF "$2" "$ROOT/$1"; then ok "$3"; else not_ok "$3"; fi
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
  extract_example "$ROOT/examples/$example" "$dir"
  if [ -z "$(ls "$dir")" ]; then
    not_ok "$example has no tagged source files"
  elif grep -Eq 'UITuningLabProfile|localStorage|applicationSupportDirectory|Button\("Save"|>Save</button>|func save\(|function save\(' "$dir"/*; then
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
  for variant in $(example_variants "$ROOT/examples/$example"); do
    label="$example [$variant]"
    dir="$WORK/${example%.md}-$variant"
    extract_example "$ROOT/examples/$example" "$dir" "$variant"
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
require_text examples/animation-spring.md 'uiTuningLab.rendered(draft: motion, baseline: .appDefault)' 'SwiftUI motion baseline is the declared default'
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
require_in "$ios_default/FeatureScreen.swift" 'Button("Tune", action: openUITuningLab)' 'iOS default host keeps a visible fallback'
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
require_in "$motion_default/EntranceScreen.swift" 'Button("Tune", action: openUITuningLab)' 'SwiftUI motion default host keeps a visible fallback'

# macOS pairs the launch argument with the existing menu command and shortcut.
macos_default="$WORK/macos-panel-minimal-default"
require_in "$macos_default/UITuningLabLaunch.swift" 'UserDefaults.standard.bool(forKey: "UITuningLabOpen")' 'macOS default agent path honors the launch argument value'
require_in "$macos_default/ExampleApp.swift" '.onAppear { if UITuningLabLaunch.consumeRequest() { model.uiTuningLab.show() } }' 'macOS default host opens one panel from the agent path'
require_in "$macos_default/UITuningLabCoordinator.swift" '.keyboardShortcut("l", modifiers: [.command, .shift])' 'macOS default host keeps the human path'

# Web labs parse the agent query only inside the development-only module.
for dir in "$WORK/web-floating-panel-default" "$WORK/web-floating-panel-persist"; do
  require_in "$dir/FeatureScreen.ui-tuning-lab.tsx" 'get("ui-tuning-lab") === "1"' "$(basename "$dir") web lab parses the agent query"
  require_in "$dir/FeatureScreen.ui-tuning-lab.tsx" 'useEffect(clearLaunchRequest, []);' "$(basename "$dir") web lab consumes the agent query once"
  require_in "$dir/FeatureScreen.ui-tuning-lab.tsx" 'style={triggerStyle}>Tune</button>' "$(basename "$dir") web lab keeps a visible fallback"
done
require_in "$WORK/animation-spring-default/EntranceScreen.ui-tuning-lab.tsx" 'get("ui-tuning-lab") === "1"' 'web motion lab parses the agent query'
require_in "$WORK/animation-spring-default/EntranceScreen.ui-tuning-lab.tsx" 'useEffect(clearLaunchRequest, []);' 'web motion lab consumes the agent query once'
if grep -q 'URLSearchParams' "$WORK/web-floating-panel-default/FeatureScreen.tsx" \
    "$WORK/animation-spring-default/EntranceScreen.tsx"; then
  not_ok 'web agent query is parsed only inside the development-gated lab module'
else
  ok 'web agent query is parsed only inside the development-gated lab module'
fi
if grep -qE 'CFBundleURLSchemes|UIApplication\.shared\.open' "$ROOT/examples/swiftui-popover-palette.md"; then
  not_ok 'iOS agent path does not register a URL scheme'
else
  ok 'iOS agent path does not register a URL scheme'
fi
# A baseline taken from the screen at open becomes the draft after a reopen.
if grep -nE 'setBaseline\(|uiTuningLabBaseline|baseline = (style|config|motion)|baseline: *(model\.)?(style|config|motion)\b|baseline \?\? ' "$ROOT"/examples/*.md >/dev/null; then
  not_ok 'no example captures the baseline from the screen at open'
else
  ok 'no example captures the baseline from the screen at open'
fi
require_text examples/web-floating-panel.md 'role="dialog"' 'web popover exposes dialog semantics'
require_text examples/web-floating-panel.md 'aria-labelledby="ui-tuning-lab-title"' 'web dialog has a labelled heading'
require_text examples/web-floating-panel.md '{...popoverManual}' 'web lab stays open while the feature is used'
require_text examples/web-floating-panel.md 'document.addEventListener("keydown", onKeyDown);' 'web lab closes on Escape wherever focus is'
require_text examples/web-floating-panel.md 'useLayoutEffect(() => { setConfigRef.current = setConfig; });' 'web lab tolerates an unstable host setter'
require_text examples/macos-panel-minimal.md '@ObservedObject var model: FeatureSceneModel' 'macOS panel observes the model so it redraws'
if grep -q 'get: { \[weak self\] in self?\.' "$ROOT/examples/macos-panel-minimal.md"; then
  not_ok 'macOS panel does not use a closure Binding to plain properties'
else
  ok 'macOS panel does not use a closure Binding to plain properties'
fi
require_text examples/web-floating-panel.md 'maxHeight: "calc(100dvh - 88px)"' 'web panel stays inside the viewport'
require_text examples/web-floating-panel.md '<output aria-hidden="true">{config.radius}px</output>' 'web sliders show their value'
require_text examples/web-floating-panel.md 'firstControl.current?.focus()' 'web dialog receives initial focus'
require_text examples/web-floating-panel.md 'trigger.current?.focus()' 'web dismissal restores trigger focus'
require_text examples/web-floating-panel.md 'cancelAnimationFrame(focusFrame)' 'web cleanup cancels pending initial-focus work'
require_text examples/web-floating-panel.md 'value={config.gap}' 'web lab controls every config field'
require_text examples/web-floating-panel.md 'uiTuningLab.default' 'web save uses the uiTuningLab namespace'
for example in swiftui-popover-palette macos-panel-minimal; do
  require_text "examples/$example.md" 'Toggle("Show baseline", isOn: showingBaseline)' "$example.md lab flips to the baseline"
done
require_text examples/swiftui-popover-palette.md '.onDisappear { if let stashedDraft { style = stashedDraft } }' 'iOS closing restores the stashed draft'
require_text examples/macos-panel-minimal.md 'if let draft = lab.stashedDraft { model.style = draft }' 'macOS closing restores the stashed draft'
require_text examples/macos-panel-minimal.md 'override func cancelOperation(_ sender: Any?) { close() }' 'macOS panel closes on Escape'
require_text examples/web-floating-panel.md 'onClick={toggleBaseline}>Show baseline' 'web lab flips to the baseline'
require_text examples/web-floating-panel.md 'if (stashedDraft.current) setConfigRef.current(stashedDraft.current);' 'web closing restores the stashed draft'
require_text examples/animation-spring.md 'lab.replayToken += 1' 'SwiftUI motion lab can replay'
require_text examples/animation-spring.md 'motion.duration /= speed' 'SwiftUI motion lab slows the preview by stretching duration'
require_text examples/animation-spring.md 'Toggle("Show baseline"' 'SwiftUI motion lab flips to the baseline'
require_text examples/animation-spring.md 'accessibilityReduceMotion' 'SwiftUI motion respects Reduce Motion'
require_text examples/animation-spring.md 'key={replay}' 'web motion lab can replay'
require_text examples/animation-spring.md 'durationMs: source.durationMs / speed' 'web motion lab slows the preview by stretching duration'
require_text examples/animation-spring.md 'aria-pressed={showBaseline}' 'web motion lab flips to the baseline'
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
template_fields=$(jq -r 'keys[]' "$ROOT/assets/profile.template.json" | sort | tr '\n' ' ')
for example in swiftui-popover-palette macos-panel-minimal web-floating-panel; do
  dir="$WORK/$example-persist"
  if grep -q 'Load saved' "$dir"/* && grep -Eq 'schemaVersion (==|!==) 1' "$dir"/*; then
    ok "$example.md persist variant loads with a schema check"
  else
    not_ok "$example.md persist variant loads with a schema check"
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

if grep -rn 'variantLab' "$ROOT/SKILL.md" "$ROOT/examples" "$ROOT/references" "$ROOT/validation" >/dev/null; then
  not_ok 'no legacy variantLab namespace remains'
else
  ok 'no legacy variantLab namespace remains'
fi

[ "$failures" -eq 0 ]
