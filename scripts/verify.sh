#!/bin/sh
# verify.sh — dependency-free checks (POSIX sh + grep only).
# Usage: ./scripts/verify.sh [--prod]
#   default: lab.json exists and carries schemaVersion
#   --prod:  fail if any lab reference exists in release configuration
set -eu

if [ "${1:-}" = "--prod" ]; then
  # Source-hygiene gate: fail only on UNGATED lab references.
  # Lines inside correctly DEBUG-gated blocks are allowed:
  #   #if DEBUG / #ifdef DEBUG (any case for DEBUG) ... #endif
  # with nesting plus #else/#elif handling (the #else branch IS checked).
  # POSIX sh + grep only.
  pattern='ui-tuning-lab|UITuningLab|LabPanel|\.ui-tuning-lab'
  candidates=$(grep -rlE "$pattern" \
    --include="*.js" --include="*.ts" --include="*.tsx" \
    --include="*.swift" --include="*.kt" --include="*.cs" \
    --include="*.dart" --exclude-dir=node_modules \
    --exclude-dir=.git --exclude-dir=build --exclude-dir=Release . 2>/dev/null || true)
  if [ -z "$candidates" ]; then
    echo "PASS: no lab references in release scope"
    exit 0
  fi
  fail=0
  IFS='
'
  for f in $candidates; do
    depth=0
    lineno=0
    while IFS= read -r line || [ -n "$line" ]; do
      lineno=$((lineno + 1))
      if printf '%s\n' "$line" | grep -qiE '^[[:space:]]*#[[:space:]]*if(def)?[[:space:]]+debug([^A-Za-z0-9_]|$)'; then
        depth=$((depth + 1))
        continue
      fi
      if [ "$depth" -gt 0 ]; then
        if printf '%s\n' "$line" | grep -qiE '^[[:space:]]*#[[:space:]]*if([^A-Za-z0-9_]|$)'; then
          depth=$((depth + 1))
          continue
        fi
        if printf '%s\n' "$line" | grep -qiE '^[[:space:]]*#[[:space:]]*endif([^A-Za-z0-9_]|$)'; then
          depth=$((depth - 1))
          continue
        fi
        if [ "$depth" -eq 1 ] && printf '%s\n' "$line" | grep -qiE '^[[:space:]]*#[[:space:]]*el(se|if)([^A-Za-z0-9_]|$)'; then
          depth=0
          continue
        fi
        continue
      fi
      if printf '%s\n' "$line" | grep -qE "$pattern"; then
        printf '%s:%s:%s\n' "$f" "$lineno" "$line"
        fail=1
      fi
    done < "$f"
  done
  unset IFS
  if [ "$fail" -ne 0 ]; then
    echo "FAIL: lab references found in release scope"
    exit 1
  fi
  echo "PASS: no lab references in release scope"
  exit 0
fi

test -f .ui-tuning-lab/lab.json || {
  echo "FAIL: .ui-tuning-lab/lab.json missing — run the interview first"
  exit 1
}
for _key in schemaVersion labTarget scope container baseline; do
  grep -q "\"$_key\"" .ui-tuning-lab/lab.json || {
    echo "FAIL: lab.json missing required key: $_key"
    exit 1
  }
done
unset _key
if grep -qE '"baseline"[[:space:]]*:[[:space:]]*\{[[:space:]]*\}' .ui-tuning-lab/lab.json; then
  echo "FAIL: lab.json baseline must be a non-empty object — replace template placeholder"
  exit 1
fi
if command -v jq >/dev/null 2>&1; then
  jq -e . .ui-tuning-lab/lab.json >/dev/null 2>&1 || {
    echo "FAIL: lab.json is not valid JSON"
    exit 1
  }
  jq -e 'has("schemaVersion") and has("labTarget") and has("scope") and has("container") and has("baseline") and has("variants")' .ui-tuning-lab/lab.json >/dev/null 2>&1 || {
    echo "FAIL: lab.json missing required keys (jq check)"
    exit 1
  }
  jq -e '(.baseline | type == "object") and ((.baseline | length) > 0)' .ui-tuning-lab/lab.json >/dev/null 2>&1 || {
    echo "FAIL: lab.json baseline must be a non-empty object"
    exit 1
  }
  jq -e '(.variants | type == "array")' .ui-tuning-lab/lab.json >/dev/null 2>&1 || {
    echo "FAIL: lab.json variants must be an array"
    exit 1
  }
fi
echo "PASS: lab.json present with required keys (schemaVersion, labTarget, scope, container, baseline)"
