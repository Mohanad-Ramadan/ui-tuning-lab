#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
VERIFY="$ROOT/scripts/verify.sh"
FIXTURES="$ROOT/tests/fixtures"
passes=0
failures=0

expect_pass() {
  name=$1
  shift
  if output=$("$@" 2>&1); then
    printf 'ok - %s\n' "$name"
    passes=$((passes + 1))
  else
    printf 'not ok - %s\n%s\n' "$name" "$output"
    failures=$((failures + 1))
  fi
}

expect_fail() {
  name=$1
  shift
  if output=$("$@" 2>&1); then
    printf 'not ok - %s (unexpected pass)\n%s\n' "$name" "$output"
    failures=$((failures + 1))
  else
    printf 'ok - %s\n' "$name"
    passes=$((passes + 1))
  fi
}

expect_na() {
  name=$1
  shift
  set +e
  output=$("$@" 2>&1)
  status=$?
  set -e
  if [ "$status" -eq 3 ] && printf '%s\n' "$output" | grep -q '^N/A:'; then
    printf 'ok - %s\n' "$name"
    passes=$((passes + 1))
  else
    printf 'not ok - %s (expected N/A exit 3, got %s)\n%s\n' "$name" "$status" "$output"
    failures=$((failures + 1))
  fi
}

expect_pass 'valid config' "$VERIFY" config "$FIXTURES/config/valid.json"
expect_fail 'malformed JSON' "$VERIFY" config "$FIXTURES/config/malformed.json"
expect_fail 'missing required key' "$VERIFY" config "$FIXTURES/config/missing-key.json"
expect_fail 'empty baseline' "$VERIFY" config "$FIXTURES/config/empty-baseline.json"
expect_fail 'placeholder value' "$VERIFY" config "$FIXTURES/config/placeholder.json"
expect_fail 'non-integer schema version' "$VERIFY" config "$FIXTURES/config/schema-version.json"
expect_fail 'decimal spelling of schema version' "$VERIFY" config "$FIXTURES/config/schema-version-decimal.json"
expect_fail 'empty scope entry' "$VERIFY" config "$FIXTURES/config/scope-entry.json"
expect_fail 'invalid persistence mode' "$VERIFY" config "$FIXTURES/config/persist.json"
expect_fail 'variant missing name' "$VERIFY" config "$FIXTURES/config/variant-name.json"
expect_fail 'variant overrides not object' "$VERIFY" config "$FIXTURES/config/variant-overrides.json"

expect_pass 'DEBUG-gated Swift reference' "$VERIFY" source-gates "$FIXTURES/source/gated.swift"
expect_fail 'ungated Swift reference' "$VERIFY" source-gates "$FIXTURES/source/ungated.swift"
expect_pass 'DEBUG conjunction Swift reference' "$VERIFY" source-gates "$FIXTURES/source/gated-conjunction.swift"
expect_fail 'DEBUG or RELEASE Swift reference' "$VERIFY" source-gates "$FIXTURES/source/debug-or-release.swift"
expect_fail 'DEBUG or true Swift reference' "$VERIFY" source-gates "$FIXTURES/source/debug-or-true.swift"
expect_pass 'DEBUG conjunction elseif Swift reference' "$VERIFY" source-gates "$FIXTURES/source/elseif-conjunction.swift"
expect_fail 'DEBUG or RELEASE elseif Swift reference' "$VERIFY" source-gates "$FIXTURES/source/elseif-or-release.swift"
expect_pass 'DEV-gated web reference' "$VERIFY" source-gates "$FIXTURES/source/gated.tsx"
expect_fail 'ungated web reference' "$VERIFY" source-gates "$FIXTURES/source/ungated.tsx"
expect_fail 'production-only web branch' "$VERIFY" source-gates "$FIXTURES/source/production-only.tsx"
expect_fail 'else branch of DEV gate' "$VERIFY" source-gates "$FIXTURES/source/dev-else.tsx"
expect_pass 'next-line brace DEV guard' "$VERIFY" source-gates "$FIXTURES/source/gated-next-line.tsx"
expect_pass 'nested block inside DEV guard' "$VERIFY" source-gates "$FIXTURES/source/gated-nested.tsx"
expect_fail 'same-line else branch of DEV gate' "$VERIFY" source-gates "$FIXTURES/source/dev-else-inline.tsx"
expect_fail 'brace in string cannot leak safe scope' "$VERIFY" source-gates "$FIXTURES/source/brace-string.tsx"
expect_fail 'brace in comment cannot leak safe scope' "$VERIFY" source-gates "$FIXTURES/source/brace-comment.tsx"
expect_na 'empty directory has no supported sources' "$VERIFY" source-gates "$FIXTURES/source/empty"
expect_na 'unsupported extension only' "$VERIFY" source-gates "$FIXTURES/source/no-reference.txt"
expect_na 'supported source with no lab reference' "$VERIFY" source-gates "$FIXTURES/source/no-reference.tsx"

printf '\n%s passed; %s failed\n' "$passes" "$failures"
[ "$failures" -eq 0 ]
