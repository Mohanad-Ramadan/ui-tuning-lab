#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
failures=0

require_text() {
  file=$1
  pattern=$2
  label=$3
  if grep -qF "$pattern" "$ROOT/$file"; then
    printf 'ok - %s\n' "$label"
  else
    printf 'not ok - %s\n' "$label"
    failures=$((failures + 1))
  fi
}

# Exercise the source users copy for the default workflow, not surrounding prose.
check_ephemeral_source() {
  file=$1
  source=$(awk '
    /^```(swift|tsx)$/ && !seen { active = 1; seen = 1; next }
    /^```$/ && active { exit }
    active { print }
  ' "$ROOT/$file")
  if [ -z "$source" ]; then
    printf 'not ok - %s has no default source snippet\n' "$file"
    failures=$((failures + 1))
  elif printf '%s\n' "$source" | grep -Eq 'LabProfile|saveProfile|localStorage|applicationSupportDirectory|Button\("Save"|>Save</button>|let save:|function save\('; then
    printf 'not ok - %s default source includes persistence\n' "$file"
    failures=$((failures + 1))
  else
    printf 'ok - %s default source is ephemeral\n' "$file"
  fi
}

for file in examples/swiftui-popover-palette.md examples/macos-panel-minimal.md examples/web-floating-panel.md; do
  check_ephemeral_source "$file"
done

# Profile declarations in optional Swift snippets must also compile only in DEBUG.
for file in examples/swiftui-popover-palette.md examples/macos-panel-minimal.md; do
  if awk '
    /^```swift$/ { active = 1; debug = 0; next }
    /^```$/ { active = 0; next }
    active && /^#if DEBUG$/ { debug++; next }
    active && /^#endif$/ { debug--; next }
    active && /struct LabProfile:/ { found = 1; if (debug < 1) bad = 1 }
    END { exit (!found || bad) }
  ' "$ROOT/$file"; then
    printf 'ok - %s optional profile is DEBUG-only\n' "$file"
  else
    printf 'not ok - %s optional profile lacks DEBUG gate\n' "$file"
    failures=$((failures + 1))
  fi
done

require_text examples/swiftui-popover-palette.md 'guard !showLab, baseline == nil else { return }' 'iOS activation preserves its original baseline'
require_text examples/web-floating-panel.md 'role="dialog"' 'web popover exposes dialog semantics'
require_text examples/web-floating-panel.md 'aria-labelledby="tuning-lab-title"' 'web dialog has a labelled heading'
require_text examples/web-floating-panel.md 'firstControl.current?.focus()' 'web dialog receives initial focus'
require_text examples/web-floating-panel.md 'trigger.current?.focus()' 'web dismissal restores trigger focus'
require_text examples/web-floating-panel.md 'cancelAnimationFrame(focusFrame)' 'web cleanup cancels pending initial-focus work'

[ "$failures" -eq 0 ]
