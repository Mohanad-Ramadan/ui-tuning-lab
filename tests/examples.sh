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

for file in examples/swiftui-popover-palette.md examples/macos-panel-minimal.md examples/web-floating-panel.md; do
  require_text "$file" 'schemaVersion' "$file uses the shared profile schema"
  require_text "$file" 'overrides' "$file saves overrides in a profile envelope"
done

require_text examples/swiftui-popover-palette.md 'guard !showLab, baseline == nil else { return }' 'iOS activation preserves its original baseline'
require_text examples/web-floating-panel.md 'role="dialog"' 'web popover exposes dialog semantics'
require_text examples/web-floating-panel.md 'aria-labelledby="tuning-lab-title"' 'web dialog has a labelled heading'
require_text examples/web-floating-panel.md 'firstControl.current?.focus()' 'web dialog receives initial focus'
require_text examples/web-floating-panel.md 'trigger.current?.focus()' 'web dismissal restores trigger focus'
require_text examples/web-floating-panel.md 'cancelAnimationFrame(focusFrame)' 'web cleanup cancels pending initial-focus work'

[ "$failures" -eq 0 ]
