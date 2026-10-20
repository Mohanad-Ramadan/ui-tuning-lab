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

require_text examples/swiftui-popover-palette.md 'guard !showLab, baseline == nil else { return }' 'iOS activation preserves its original baseline'
require_text examples/web-floating-panel.md 'role="dialog"' 'web popover exposes dialog semantics'
require_text examples/web-floating-panel.md 'aria-labelledby="tuning-lab-title"' 'web dialog has a labelled heading'
require_text examples/web-floating-panel.md 'firstControl.current?.focus()' 'web dialog receives initial focus'
require_text examples/web-floating-panel.md 'trigger.current?.focus()' 'web dismissal restores trigger focus'
require_text examples/web-floating-panel.md 'cancelAnimationFrame(focusFrame)' 'web cleanup cancels pending initial-focus work'
require_text examples/web-floating-panel.md 'value={config.gap}' 'web lab controls every config field'
require_text examples/web-floating-panel.md 'uiTuningLab.default' 'web save uses the uiTuningLab namespace'
require_text examples/animation-spring.md 'lab.replayToken += 1' 'SwiftUI motion lab can replay'
require_text examples/animation-spring.md 'motion.duration /= speed' 'SwiftUI motion lab slows the preview by stretching duration'
require_text examples/animation-spring.md 'Toggle("Show baseline"' 'SwiftUI motion lab flips to the baseline'
require_text examples/animation-spring.md 'accessibilityReduceMotion' 'SwiftUI motion respects Reduce Motion'
require_text examples/animation-spring.md 'key={replay}' 'web motion lab can replay'
require_text examples/animation-spring.md 'durationMs: source.durationMs / speed' 'web motion lab slows the preview by stretching duration'
require_text examples/animation-spring.md 'aria-pressed={showBaseline}' 'web motion lab flips to the baseline'
require_text examples/animation-spring.md 'prefers-reduced-motion: reduce' 'web motion respects reduced motion'

if grep -rn 'variantLab' "$ROOT/SKILL.md" "$ROOT/examples" "$ROOT/references" "$ROOT/validation" >/dev/null; then
  not_ok 'no legacy variantLab namespace remains'
else
  ok 'no legacy variantLab namespace remains'
fi

[ "$failures" -eq 0 ]
