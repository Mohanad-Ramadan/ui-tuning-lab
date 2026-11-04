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

expect_fail_message() {
  name=$1
  pattern=$2
  shift 2
  set +e
  output=$("$@" 2>&1)
  status=$?
  set -e
  if [ "$status" -ne 0 ] && printf '%s\n' "$output" | grep -q "$pattern"; then
    printf 'ok - %s\n' "$name"
    passes=$((passes + 1))
  else
    printf 'not ok - %s (expected a failure matching %s, got %s)\n%s\n' "$name" "$pattern" "$status" "$output"
    failures=$((failures + 1))
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
expect_fail 'session persistence is not a supported mode' "$VERIFY" config "$FIXTURES/config/persist-session.json"
expect_pass 'valid config with remembered activation' "$VERIFY" config "$FIXTURES/config/activation-valid.json"
expect_fail_message 'activation not an object' '^FAIL: invalid activation:' "$VERIFY" config "$FIXTURES/config/activation-not-object.json"
expect_fail_message 'activation missing a field' '^FAIL: invalid activation:' "$VERIFY" config "$FIXTURES/config/activation-missing-field.json"
expect_fail_message 'activation value not a string' '^FAIL: invalid activation:' "$VERIFY" config "$FIXTURES/config/activation-wrong-type.json"
expect_fail_message 'activation with an extra field' '^FAIL: invalid activation:' "$VERIFY" config "$FIXTURES/config/activation-extra-field.json"
expect_fail_message 'activation with an empty value' '^FAIL: invalid activation:' "$VERIFY" config "$FIXTURES/config/activation-empty.json"
expect_fail_message 'activation with a blank value' '^FAIL: invalid activation:' "$VERIFY" config "$FIXTURES/config/activation-blank.json"
expect_pass 'activation with several human paths' "$VERIFY" config "$FIXTURES/config/activation-human-list.json"
expect_fail_message 'activation with an empty human list' '^FAIL: invalid activation:' "$VERIFY" config "$FIXTURES/config/activation-human-list-empty.json"
expect_fail_message 'activation with a duplicate human path' '^FAIL: invalid activation:' "$VERIFY" config "$FIXTURES/config/activation-human-list-duplicate.json"
expect_fail_message 'activation with a blank human path in a list' '^FAIL: invalid activation:' "$VERIFY" config "$FIXTURES/config/activation-human-list-blank.json"
expect_fail_message 'activation with a non-string human path in a list' '^FAIL: invalid activation:' "$VERIFY" config "$FIXTURES/config/activation-human-list-wrong-type.json"
expect_pass 'config with kept candidates' "$VERIFY" config "$FIXTURES/config/candidates-valid.json"
expect_fail_message 'config with an empty candidates list' '^FAIL: invalid candidates:' "$VERIFY" config "$FIXTURES/config/candidates-empty.json"
expect_fail_message 'config with a duplicate candidate' '^FAIL: invalid candidates:' "$VERIFY" config "$FIXTURES/config/candidates-duplicate.json"
expect_fail_message 'config with a candidate name not kebab-case' '^FAIL: invalid candidates:' "$VERIFY" config "$FIXTURES/config/candidates-bad-name.json"
expect_fail_message 'config with a reserved candidate name' '^FAIL: invalid candidates:' "$VERIFY" config "$FIXTURES/config/candidates-reserved-name.json"
expect_fail_message 'config with candidates that are not a list' '^FAIL: invalid candidates:' "$VERIFY" config "$FIXTURES/config/candidates-not-list.json"
expect_pass 'lab config template is valid' "$VERIFY" config "$ROOT/assets/labconfig.template.json"
expect_pass 'valid profile' "$VERIFY" profile "$FIXTURES/profile/valid.json"
expect_pass 'profile template is valid' "$VERIFY" profile "$ROOT/assets/profile.template.json"
expect_fail 'profile missing a field' "$VERIFY" profile "$FIXTURES/profile/missing-key.json"
expect_fail 'profile with an extra field' "$VERIFY" profile "$FIXTURES/profile/extra-key.json"
expect_fail 'profile for an unsupported platform' "$VERIFY" profile "$FIXTURES/profile/bad-platform.json"
expect_fail 'profile name not kebab-case' "$VERIFY" profile "$FIXTURES/profile/bad-name.json"
expect_fail 'profile with empty overrides' "$VERIFY" profile "$FIXTURES/profile/empty-overrides.json"
expect_fail 'profile placeholder value' "$VERIFY" profile "$FIXTURES/profile/placeholder.json"
expect_pass 'real names containing Todo are not placeholders' "$VERIFY" profile "$FIXTURES/profile/todo-name.json"
expect_fail 'whole-word TODO is a placeholder' "$VERIFY" profile "$FIXTURES/profile/todo-note.json"
expect_fail 'nested schemaVersion cannot satisfy the top-level literal' "$VERIFY" profile "$FIXTURES/profile/nested-schema-version.json"
expect_pass 'valid candidate profile (schema 2)' "$VERIFY" profile "$FIXTURES/profile/candidate-valid.json"
expect_pass 'candidate savedAt may carry fractional seconds' "$VERIFY" profile "$FIXTURES/profile/candidate-fractional-seconds.json"
expect_fail 'candidate missing savedAt' "$VERIFY" profile "$FIXTURES/profile/candidate-missing-saved-at.json"
expect_fail 'candidate savedAt not ISO-8601 UTC' "$VERIFY" profile "$FIXTURES/profile/candidate-bad-saved-at.json"
expect_fail 'candidate basedOn not kebab-case' "$VERIFY" profile "$FIXTURES/profile/candidate-bad-based-on.json"
expect_fail_message 'unknown profile schema version' '^FAIL: schemaVersion must use the integer literal 1 or 2' "$VERIFY" profile "$FIXTURES/profile/schema-version-3.json"
expect_fail 'schema 1 profile rejects candidate fields' "$VERIFY" profile "$FIXTURES/profile/v1-with-candidate-fields.json"
expect_fail 'lab config is not a profile' "$VERIFY" profile "$FIXTURES/config/valid.json"

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
expect_fail 'NODE_ENV disjunction does not establish development scope' "$VERIFY" source-gates "$FIXTURES/source/node-env-or.tsx"
expect_fail 'reference after closing development scope' "$VERIFY" source-gates "$FIXTURES/source/after-close.tsx"
expect_fail 'guarded and unguarded references on same line' "$VERIFY" source-gates "$FIXTURES/source/before-and-after-close.tsx"
expect_pass 'standalone NODE_ENV development guards' "$VERIFY" source-gates "$FIXTURES/source/node-env-gated.tsx"
expect_pass 'nested development gates preserve outer scope' "$VERIFY" source-gates "$FIXTURES/source/gated-nested-dev.tsx"
expect_pass 'reference before closing development scope' "$VERIFY" source-gates "$FIXTURES/source/before-close.tsx"
expect_fail 'static import of a lab module' "$VERIFY" source-gates "$FIXTURES/source/static-import-lab-module.tsx"
expect_pass 'dynamic lab import inside DEV guard' "$VERIFY" source-gates "$FIXTURES/source/gated-dynamic-import.tsx"
expect_pass 'lab module body is exempt when its import is gated' "$VERIFY" source-gates "$FIXTURES/source/gated-module-pair"
expect_na 'lab module with no importer is not a pass' "$VERIFY" source-gates "$FIXTURES/source/lab-module-only"
expect_na 'generic LabPanel name is not a lab marker' "$VERIFY" source-gates "$FIXTURES/source/labpanel-unrelated.tsx"
expect_fail 'escaped regex brace cannot leak safe scope' "$VERIFY" source-gates "$FIXTURES/source/regex-brace.tsx"
expect_fail 'brace inside multi-line template cannot leak safe scope' "$VERIFY" source-gates "$FIXTURES/source/template-brace.tsx"
expect_fail 'reference inside multi-line template fails closed' "$VERIFY" source-gates "$FIXTURES/source/gated-template.tsx"
expect_fail 'stray backticks in comments cannot hide a static import' "$VERIFY" source-gates "$FIXTURES/source/backtick-comment.tsx"
expect_fail 'bare regex braces cannot leak safe scope' "$VERIFY" source-gates "$FIXTURES/source/bare-regex-brace.tsx"
expect_fail 'unclosed development guard' "$VERIFY" source-gates "$FIXTURES/source/unclosed-gate.tsx"
expect_fail 'directive inside Swift multi-line string is not a gate' "$VERIFY" source-gates "$FIXTURES/source/multiline-string.swift"
expect_fail 'unclosed Swift #if' "$VERIFY" source-gates "$FIXTURES/source/unclosed-if.swift"
expect_na 'empty directory has no supported sources' "$VERIFY" source-gates "$FIXTURES/source/empty"
expect_na 'unsupported extension only' "$VERIFY" source-gates "$FIXTURES/source/no-reference.txt"
expect_na 'supported source with no lab reference' "$VERIFY" source-gates "$FIXTURES/source/no-reference.tsx"

printf '\n%s passed; %s failed\n' "$passes" "$failures"
[ "$failures" -eq 0 ]
