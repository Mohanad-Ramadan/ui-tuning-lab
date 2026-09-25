#!/bin/sh
# verify.sh — dependency-free checks (POSIX sh + grep only).
# Usage: ./scripts/verify.sh [--prod]
#   default: lab.json exists and carries schemaVersion
#   --prod:  fail if any lab reference exists in release configuration
set -eu

if [ "${1:-}" = "--prod" ]; then
  if grep -rEn "ui-tuning-lab|UITuningLab|LabPanel|\.ui-tuning-lab" \
    --include="*.js" --include="*.ts" --include="*.tsx" \
    --include="*.swift" --include="*.kt" --include="*.cs" \
    --include="*.dart" --exclude-dir=node_modules \
    --exclude-dir=.git --exclude-dir=build --exclude-dir=Release .; then
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
grep -q '"schemaVersion"' .ui-tuning-lab/lab.json || {
  echo "FAIL: lab.json has no schemaVersion"
  exit 1
}
echo "PASS: lab.json present with schemaVersion"
