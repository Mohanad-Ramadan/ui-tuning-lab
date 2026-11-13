#!/bin/sh
# Zip the publishable skill. skills/ui-tuning-lab/ is exactly what an installed
# copy gets (`npx skills add` copies that folder); tests, pilots, evals, and
# validation evidence stay at the repository root.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SKILL="$ROOT/skills/ui-tuning-lab"
OUT=${1:-"$ROOT/dist"}
VERSION=$(cat "$SKILL/VERSION")
PACKAGE="$OUT/ui-tuning-lab"

rm -rf "$PACKAGE" "$OUT/ui-tuning-lab-$VERSION.zip"
mkdir -p "$OUT"
cp -R "$SKILL" "$PACKAGE"
find "$PACKAGE" -name '.omc' -type d -prune -exec rm -rf {} +
find "$PACKAGE" -name '.DS_Store' -delete
(cd "$OUT" && zip -qr "ui-tuning-lab-$VERSION.zip" ui-tuning-lab)
echo "$PACKAGE"
echo "$OUT/ui-tuning-lab-$VERSION.zip"
