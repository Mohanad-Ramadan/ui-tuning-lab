#!/bin/sh
# Static checks for UI Tuning Lab configuration and source gating.
# These checks do not inspect compiled or bundled release artifacts.
set -eu

usage() {
  echo "Usage: $0 config <lab.json> | source-gates <file-or-directory>" >&2
  exit 2
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

not_applicable() {
  echo "N/A: $*" >&2
  exit 3
}

validate_config() {
  file=$1
  [ -f "$file" ] || fail "config not found: $file"
  command -v jq >/dev/null 2>&1 || fail "config validation requires jq"
  jq -e . "$file" >/dev/null 2>&1 || fail "invalid JSON: $file"
  compact_json=$(tr '\n\r\t' '   ' < "$file")
  printf '%s\n' "$compact_json" | grep -Eq '"schemaVersion"[[:space:]]*:[[:space:]]*1[[:space:]]*[,}]' || \
    fail "schemaVersion must use the integer literal 1: $file"
  jq -e '
    type == "object" and
    has("schemaVersion") and (.schemaVersion == 1) and
    has("labTarget") and (.labTarget | type == "string" and length > 0) and
    has("scope") and (.scope | type == "array" and length > 0 and all(.[]; type == "string" and length > 0)) and
    has("container") and (.container | type == "string" and length > 0) and
    has("baseline") and (.baseline | type == "object" and length > 0) and
    has("variants") and (.variants | type == "array" and all(.[];
      type == "object" and
      has("name") and (.name | type == "string" and length > 0) and
      has("overrides") and (.overrides | type == "object"))) and
    has("persist") and (.persist == "none" or .persist == "session" or .persist == "namespaced-save") and
    has("profile") and (.profile | type == "string" and length > 0)
  ' "$file" >/dev/null 2>&1 || fail "missing or invalid required configuration fields: $file"
  jq -e '[.. | strings | select(test("REPLACE-ME|TODO|<[^>]+>"; "i"))] | length == 0' \
    "$file" >/dev/null 2>&1 || fail "placeholder value found: $file"
  echo "PASS: valid lab configuration: $file"
}

lint_swift() {
  file=$1
  awk '
    function debug_if(line, s) {
      s = tolower(line)
      return (s ~ /^[[:space:]]*#[[:space:]]*ifdef[[:space:]]+debug[[:space:]]*$/ ||
              s ~ /^[[:space:]]*#[[:space:]]*if[[:space:]]+debug([[:space:]]*&&[[:space:]]*[a-z_][a-z0-9_]*)*[[:space:]]*$/)
    }
    function debug_elseif(line, s) {
      s = tolower(line)
      return (s ~ /^[[:space:]]*#[[:space:]]*(elseif|elif)[[:space:]]+debug([[:space:]]*&&[[:space:]]*[a-z_][a-z0-9_]*)*[[:space:]]*$/)
    }
    BEGIN { depth = 0; violations = 0 }
    /^[[:space:]]*#[[:space:]]*if(def)?[[:space:]]+/ {
      parent = depth > 0 ? safe[depth] : 0
      depth++
      safe[depth] = parent || debug_if($0)
      next
    }
    /^[[:space:]]*#[[:space:]]*(else|elseif|elif)/ {
      parent = depth > 1 ? safe[depth - 1] : 0
      safe[depth] = parent || debug_elseif($0)
      next
    }
    /^[[:space:]]*#[[:space:]]*endif/ {
      delete safe[depth]; if (depth > 0) depth--
      next
    }
    /ui-tuning-lab|UITuningLab|LabPanel|\.ui-tuning-lab/ {
      guarded = depth > 0 ? safe[depth] : 0
      if (!guarded) { print FILENAME ":" FNR ":" $0; violations = 1 }
    }
    END { exit violations }
  ' "$file"
}

lint_web() {
  file=$1
  awk '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s
    }
    function dev_condition(s) {
      return (s ~ /^if[[:space:]]*\([[:space:]]*import\.meta\.env\.DEV[[:space:]]*\)$/ ||
              s ~ ("^if[[:space:]]*\\([[:space:]]*process\\.env\\.NODE_ENV[[:space:]]*!==?[[:space:]]*(\"production\"|" squote "production" squote ")[[:space:]]*\\)$"))
    }
    function brace_in_quote(s, q,    n,a,i) {
      n = split(s, a, q)
      for (i = 2; i <= n; i += 2) if (a[i] ~ /[{}]/) return 1
      return 0
    }
    BEGIN { depth = 0; safe_depth = 0; pending_gate = 0; violations = 0; squote = sprintf("%c", 39) }
    {
      raw = $0; text = trim(raw)
      if (pending_gate) {
        if (text == "") next
        if (text == "{") {
          depth++; if (safe_depth == 0) safe_depth = depth; pending_gate = 0; next
        }
        print FILENAME ":" FNR ": ambiguous development guard; expected { on the next line"
        violations = 1; pending_gate = 0; safe_depth = 0
      }

      inline_gate = 0
      if (text ~ /\{[[:space:]]*$/) {
        condition = text; sub(/\{[[:space:]]*$/, "", condition); condition = trim(condition)
        inline_gate = dev_condition(condition)
      } else if (dev_condition(text)) {
        pending_gate = 1; next
      }

      comment_at = index(raw, "//")
      comment_brace = comment_at > 0 && substr(raw, comment_at) ~ /[{}]/
      ambiguous = (raw ~ /\/\*|\*\// || comment_brace ||
                   brace_in_quote(raw, "\"") || brace_in_quote(raw, squote) || brace_in_quote(raw, "`"))
      if (ambiguous) {
        print FILENAME ":" FNR ": ambiguous brace in string or comment"
        violations = 1; safe_depth = 0
      }

      # Braces inside strings/comments have already been rejected above.
      # Walk in source order so a reference after } uses its actual scope.
      for (i = 1; i <= length(raw); i++) {
        character = substr(raw, i, 1)
        if (character == "{") {
          depth++
          if (inline_gate && safe_depth == 0) safe_depth = depth
          inline_gate = 0
        } else if (character == "}") {
          depth--
          if (depth < 0) { print FILENAME ":" FNR ": unmatched }"; violations = 1; depth = 0; safe_depth = 0 }
          if (safe_depth > 0 && depth < safe_depth) safe_depth = 0
        }
        if (substr(raw, i) ~ /^(ui-tuning-lab|UITuningLab|LabPanel|\.ui-tuning-lab)/ && safe_depth == 0) {
          print FILENAME ":" FNR ":" raw
          violations = 1
          break
        }
      }
    }
    END {
      if (pending_gate) { print FILENAME ":EOF: development guard missing {"; violations = 1 }
      exit violations
    }
  ' "$file"
}

lint_sources() {
  target=$1
  [ -e "$target" ] || fail "source path not found: $target"
  if [ -f "$target" ]; then
    files=$target
  else
    files=$(find "$target" -type f \
      \( -name '*.swift' -o -name '*.js' -o -name '*.jsx' -o -name '*.ts' -o -name '*.tsx' \) \
      ! -path '*/node_modules/*' ! -path '*/.git/*' ! -path '*/build/*' ! -path '*/dist/*')
  fi
  failed=0
  supported=0
  references=0
  old_ifs=$IFS
  IFS='
'
  for file in $files; do
    case "$file" in
      *.swift)
        supported=$((supported + 1))
        if grep -qE 'ui-tuning-lab|UITuningLab|LabPanel|\.ui-tuning-lab' "$file"; then
          references=$((references + 1)); lint_swift "$file" || failed=1
        fi
        ;;
      *.js|*.jsx|*.ts|*.tsx)
        supported=$((supported + 1))
        if grep -qE 'ui-tuning-lab|UITuningLab|LabPanel|\.ui-tuning-lab' "$file"; then
          references=$((references + 1)); lint_web "$file" || failed=1
        fi
        ;;
    esac
  done
  IFS=$old_ifs
  [ "$supported" -gt 0 ] || not_applicable "no supported Swift or web source files in $target"
  [ "$references" -gt 0 ] || not_applicable "supported sources contain no lab references in $target"
  [ "$failed" -eq 0 ] || fail "ungated lab references found"
  echo "PASS: supported source gates found around lab references in $target"
  echo "NOTE: source lint is not proof of absence from a compiled release artifact"
}

[ "$#" -eq 2 ] || usage
case "$1" in
  config) validate_config "$2" ;;
  source-gates) lint_sources "$2" ;;
  *) usage ;;
esac
