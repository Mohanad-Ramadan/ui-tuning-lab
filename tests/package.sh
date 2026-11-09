#!/bin/sh
# The packaged skill must be self-contained: every path SKILL.md and the
# references point to exists inside it, and nothing repository-only ships.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ui-tuning-lab-package.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
failures=0
ok() { printf 'ok - %s\n' "$1"; }
not_ok() { printf 'not ok - %s\n' "$1"; failures=$((failures + 1)); }

sh "$ROOT/tools/package.sh" "$WORK" >/dev/null
PACKAGE="$WORK/ui-tuning-lab"

# `npx skills add` installs the whole skill folder from GitHub, so its tracked
# files must be only these.
extra=$(git -C "$ROOT" ls-files skills/ui-tuning-lab | cut -d/ -f3 | sort -u |
  grep -vxE 'SKILL\.md|README\.md|LICENSE\.txt|VERSION|assets|examples|references|scripts' || true)
if [ -z "$extra" ]; then ok "skill folder holds only shipped files"; else not_ok "skill folder holds only shipped files: $extra"; fi

if [ -e "$ROOT/SKILL.md" ]; then not_ok "no SKILL.md at the repository root"; else ok "no SKILL.md at the repository root"; fi

if cmp -s "$ROOT/LICENSE.txt" "$PACKAGE/LICENSE.txt"; then ok "shipped license matches the repository license"; else not_ok "shipped license matches the repository license"; fi

version=$(cat "$PACKAGE/VERSION")
if grep -q "^  version: \"$version\"$" "$PACKAGE/SKILL.md"; then ok "SKILL.md metadata version matches VERSION"; else not_ok "SKILL.md metadata version matches VERSION"; fi

# Paths named in shipped Markdown must resolve inside the package. Receipts may
# cite validation evidence, which stays in the repository by design.
missing=$(sed 's|<skill-dir>/||g' "$PACKAGE"/SKILL.md "$PACKAGE"/README.md "$PACKAGE"/references/*.md \
    "$PACKAGE"/examples/*.md |
  grep -oE '`(references|examples|assets|profiles|scripts|validation)/[A-Za-z0-9_./-]+' |
  tr -d '`' | grep -v '^validation/evidence/' | sort -u | while read -r path; do
    [ -e "$PACKAGE/$path" ] || echo "$path"
  done)
if [ -z "$missing" ]; then ok "every referenced path exists in the package"; else not_ok "referenced paths missing from the package: $missing"; fi

if sh "$PACKAGE/scripts/verify.sh" profile "$PACKAGE/assets/profile.template.json" >/dev/null 2>&1; then
  ok "packaged verify.sh runs from the package"
else
  not_ok "packaged verify.sh runs from the package"
fi

if grep -rnE 'TODO|"you"|Proprietary' "$PACKAGE/SKILL.md" "$PACKAGE/LICENSE.txt" "$PACKAGE/README.md" >/dev/null; then
  not_ok "no placeholder metadata ships"
else
  ok "no placeholder metadata ships"
fi

[ "$failures" -eq 0 ]
