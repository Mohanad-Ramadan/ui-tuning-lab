#!/bin/sh
# Build the publishable skill from the files an installed copy needs. Tests,
# pilots, evals, and validation evidence stay in the repository.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
OUT=${1:-"$ROOT/dist"}
VERSION=$(cat "$ROOT/VERSION")
PACKAGE="$OUT/ui-tuning-lab"

SHIPPED='SKILL.md
README.md
LICENSE.txt
CHANGELOG.md
VERSION
assets
examples
profiles
references
scripts
validation/README.md
validation/receipt-template.md
validation/ios.md
validation/macos.md
validation/web.md'

rm -rf "$PACKAGE" "$OUT/ui-tuning-lab-$VERSION.zip"
mkdir -p "$PACKAGE/validation"
printf '%s\n' "$SHIPPED" | while read -r path; do
  case "$path" in
    */*) cp -R "$ROOT/$path" "$PACKAGE/$path" ;;
    *) cp -R "$ROOT/$path" "$PACKAGE/" ;;
  esac
done
find "$PACKAGE" -name '.DS_Store' -delete
(cd "$OUT" && zip -qr "ui-tuning-lab-$VERSION.zip" ui-tuning-lab)
echo "$PACKAGE"
echo "$OUT/ui-tuning-lab-$VERSION.zip"
