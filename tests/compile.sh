#!/bin/sh
# Typecheck every example variant as users copy it. Swift is checked with and
# without DEBUG, so a lab reference left outside its gate breaks the Release
# build here. A missing toolchain is reported as SKIP (exit 3), never as a pass.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib/extract.sh"
WEB="$ROOT/tests/compile/web"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ui-tuning-lab-compile.XXXXXX")
trap 'rm -rf "$WORK" "$WEB/.work"' EXIT
trap 'exit 130' INT TERM
passes=0
failures=0
skips=0

report() {
  status=$1
  name=$2
  output=$3
  case "$status" in
    ok) printf 'ok - %s\n' "$name"; passes=$((passes + 1)) ;;
    skip) printf 'skip - %s: %s\n' "$name" "$output"; skips=$((skips + 1)) ;;
    *) printf 'not ok - %s\n%s\n' "$name" "$output"; failures=$((failures + 1)) ;;
  esac
}

# Swift examples and the SDK each one targets.
SWIFT_EXAMPLES='swiftui-popover-palette.md ios
macos-panel-minimal.md macos
animation-spring.md ios'
WEB_EXAMPLES='web-floating-panel.md
animation-spring.md'

swift_check() {
  platform=$1
  dir=$2
  label=$3
  case "$platform" in
    ios) sdk=iphonesimulator; target=arm64-apple-ios17.0-simulator ;;
    macos) sdk=macosx; target=arm64-apple-macos14 ;;
  esac
  if ! sdk_path=$(xcrun --sdk "$sdk" --show-sdk-path 2>/dev/null); then
    report skip "$label" "$sdk SDK not available"
    return
  fi
  for config in release debug; do
    flag=
    [ "$config" = debug ] && flag=-DDEBUG
    # Treat warnings as failures: users paste these files verbatim.
    if output=$(xcrun swiftc -typecheck -parse-as-library -warnings-as-errors \
        -sdk "$sdk_path" -target "$target" $flag "$dir"/*.swift 2>&1); then
      report ok "$label ($config)" ""
    else
      report fail "$label ($config)" "$output"
    fi
  done
}

web_ready() {
  [ -x "$WEB/node_modules/.bin/tsc" ] && return 0
  command -v npm >/dev/null 2>&1 || return 1
  npm ci --prefix "$WEB" --no-audit --no-fund >/dev/null 2>&1
}

web_check() {
  dir=$1
  label=$2
  cat > "$dir/tsconfig.json" <<EOF
{
  "extends": "$WEB/tsconfig.base.json",
  "include": ["*.ts", "*.tsx", "$WEB/env.d.ts"]
}
EOF
  if output=$("$WEB/node_modules/.bin/tsc" -p "$dir/tsconfig.json" 2>&1); then
    report ok "$label" ""
  else
    report fail "$label" "$output"
  fi
}

if command -v xcrun >/dev/null 2>&1 && xcrun --find swiftc >/dev/null 2>&1; then
  printf '%s\n' "$SWIFT_EXAMPLES" | while read -r example platform; do
    for variant in $(example_variants "$ROOT/examples/$example"); do
      dir="$WORK/swift-${example%.md}-$variant"
      extract_example "$ROOT/examples/$example" "$dir" "$variant"
      swift_check "$platform" "$dir" "$example [$variant] swift"
    done
  done > "$WORK/swift.log"
else
  echo "skip - Swift examples: xcrun swiftc not available" > "$WORK/swift.log"
fi
# The values helper is shared by every Swift example; run it, not just typecheck it.
if xcrun --find swiftc >/dev/null 2>&1; then
  helper="$WORK/values"
  extract_example "$ROOT/examples/macos-panel-minimal.md" "$helper"
  # Top-level statements are only allowed in a file named main.swift.
  cp "$ROOT/tests/compile/swift/values-check.swift" "$helper/main.swift"
  if output=$(xcrun swiftc -DDEBUG -o "$WORK/values-check" \
        "$helper/UITuningLabValues.swift" "$helper/main.swift" 2>&1 &&
      "$WORK/values-check" 2>&1); then
    echo "ok - UITuningLabValues.swift reports only rounded changed fields" >> "$WORK/swift.log"
  else
    printf 'not ok - UITuningLabValues.swift reports only rounded changed fields\n%s\n' "$output" >> "$WORK/swift.log"
  fi
fi
# The loop above runs in a subshell, so count its results from the log.
cat "$WORK/swift.log"
passes=$((passes + $(grep -c '^ok' "$WORK/swift.log" || true)))
failures=$((failures + $(grep -c '^not ok' "$WORK/swift.log" || true)))
skips=$((skips + $(grep -c '^skip' "$WORK/swift.log" || true)))

if web_ready; then
  for example in $WEB_EXAMPLES; do
    for variant in $(example_variants "$ROOT/examples/$example"); do
      # Sources sit under the toolchain directory so imports resolve its
      # node_modules.
      dir="$WEB/.work/${example%.md}-$variant"
      extract_example "$ROOT/examples/$example" "$dir" "$variant"
      rm -f "$dir"/*.swift
      [ -n "$(ls "$dir"/*.ts "$dir"/*.tsx 2>/dev/null)" ] || continue
      web_check "$dir" "$example [$variant] tsx"
    done
  done
else
  report skip "web examples" "TypeScript toolchain unavailable (npm ci failed in tests/compile/web)"
fi

printf '\n%s passed; %s failed; %s skipped\n' "$passes" "$failures" "$skips"
[ "$failures" -eq 0 ] || exit 1
if [ "$skips" -gt 0 ]; then
  echo "SKIP: some examples were not compiled; this is not a pass" >&2
  exit 3
fi
