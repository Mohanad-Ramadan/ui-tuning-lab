#!/bin/sh
# Static checks for UI Tuning Lab configuration and source gating.
# These checks do not inspect compiled or bundled release artifacts.
set -eu

usage() {
  echo "Usage: $0 config <lab.json> | profile <profile.json> | source-gates <file-or-directory>" >&2
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

# Every lab-owned type, module, and storage key carries one of these markers.
LAB_PATTERN='UITuningLab|uiTuningLab|ui-tuning-lab'

# Checks shared by lab configs and saved profiles (references/config-schema.md).
require_json_v1() {
  file=$1
  kind=$2
  [ -f "$file" ] || fail "$kind not found: $file"
  command -v jq >/dev/null 2>&1 || fail "$kind validation requires jq"
  jq -e . "$file" >/dev/null 2>&1 || fail "invalid JSON: $file"
  compact_json=$(tr '\n\r\t' '   ' < "$file")
  # jq 1.7+ prints the top-level literal as written; the grep also covers older
  # jq versions, which print 1.0 as 1.
  [ "$(jq -c '.schemaVersion' "$file")" = 1 ] &&
    printf '%s\n' "$compact_json" | grep -Eq '"schemaVersion"[[:space:]]*:[[:space:]]*1[[:space:]]*[,}]' || \
    fail "schemaVersion must use the integer literal 1: $file"
}

reject_placeholders() {
  # Whole-word TODO only, so real names such as TodoListScreen stay valid.
  jq -e '[.. | strings | select(test("REPLACE-ME"; "i") or test("\\bTODO\\b") or test("^<[^>]+>$"))] | length == 0' \
    "$1" >/dev/null 2>&1 || fail "placeholder value found: $1"
}

validate_config() {
  file=$1
  require_json_v1 "$file" config
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
    has("persist") and (.persist == "none" or .persist == "namespaced-save") and
    has("profile") and (.profile | type == "string" and length > 0)
  ' "$file" >/dev/null 2>&1 || fail "missing or invalid required configuration fields: $file"
  # Activation is optional; when present it is an object with exactly three
  # non-blank tokens. human may also be a non-empty array of distinct tokens.
  # A separate check keeps its error distinguishable.
  jq -e '
    def token: type == "string" and test("\\S");
    (has("activation") | not) or
    (.activation | type == "object" and
      (keys | sort) == ["agent", "fallback", "human"] and
      (.human | token or
        (type == "array" and length > 0 and all(.[]; token) and
          (unique | length) == length)) and
      (.agent | token) and
      (.fallback | token))
  ' "$file" >/dev/null 2>&1 || \
    fail "invalid activation: expected an object with non-blank human (one token or a list of distinct tokens), agent, and fallback strings: $file"
  reject_placeholders "$file"
  echo "PASS: valid lab configuration: $file"
}

validate_profile() {
  file=$1
  require_json_v1 "$file" profile
  jq -e '
    type == "object" and
    (keys | sort) == (["container", "name", "notes", "overrides", "platform", "schemaVersion", "scope"]) and
    (.schemaVersion == 1) and
    (.name | type == "string" and test("^[a-z0-9]+(-[a-z0-9]+)*$")) and
    (.platform == "ios" or .platform == "macos" or .platform == "web") and
    (.container | type == "string" and length > 0) and
    (.scope | type == "array" and length > 0 and all(.[]; type == "string" and length > 0)) and
    (.overrides | type == "object" and length > 0) and
    (.notes | type == "string")
  ' "$file" >/dev/null 2>&1 || fail "missing, extra, or invalid profile fields: $file"
  reject_placeholders "$file"
  echo "PASS: valid saved profile: $file"
}

lint_swift() {
  file=$1
  awk -v lab="$LAB_PATTERN" '
    function debug_if(line, s) {
      s = tolower(line)
      return (s ~ /^[[:space:]]*#[[:space:]]*ifdef[[:space:]]+debug[[:space:]]*$/ ||
              s ~ /^[[:space:]]*#[[:space:]]*if[[:space:]]+debug([[:space:]]*&&[[:space:]]*[a-z_][a-z0-9_]*)*[[:space:]]*$/)
    }
    function debug_elseif(line, s) {
      s = tolower(line)
      return (s ~ /^[[:space:]]*#[[:space:]]*(elseif|elif)[[:space:]]+debug([[:space:]]*&&[[:space:]]*[a-z_][a-z0-9_]*)*[[:space:]]*$/)
    }
    function check_reference(    guarded) {
      if ($0 !~ lab) return
      guarded = depth > 0 ? safe[depth] : 0
      if (!guarded) { print FILENAME ":" FNR ":" $0; violations = 1 }
    }
    BEGIN { depth = 0; violations = 0; in_string = 0 }
    # Directive-like lines inside a multi-line string literal are text, not gates.
    {
      quotes = gsub(/"""/, "&")
      if (in_string || quotes % 2) {
        if (quotes % 2) in_string = !in_string
        check_reference(); next
      }
    }
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
    { check_reference() }
    END {
      if (in_string) { print FILENAME ":EOF: unterminated multi-line string"; violations = 1 }
      if (depth != 0) { print FILENAME ":EOF: unbalanced #if/#endif"; violations = 1 }
      exit violations
    }
  ' "$file"
}

lint_web() {
  file=$1
  awk -v lab="$LAB_PATTERN" '
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
    BEGIN { depth = 0; safe_depth = 0; pending_gate = 0; in_template = 0; violations = 0; squote = sprintf("%c", 39) }
    {
      raw = $0; text = trim(raw)
      # A multi-line template literal is text: its braces are not structure.
      # A line that opens or closes one may not contain braces at all.
      scratch = raw; backticks = gsub(/`/, "", scratch)
      if (backticks % 2) {
        in_template = !in_template
        if (raw ~ /[{}]/) {
          print FILENAME ":" FNR ": ambiguous brace beside a multi-line template literal"
          violations = 1; safe_depth = 0
        }
      } else if (in_template) {
        # Scope is unknowable here (a stray backtick may have opened this span),
        # so any lab reference fails closed.
        if (raw ~ lab) { print FILENAME ":" FNR ": lab reference inside multi-line template literal"; violations = 1 }
        next
      }
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
      # Escaped braces and braces in a regex character class are regex text.
      regex_brace = (raw ~ /\\[{}]/ || raw ~ /\/\[[^]]*[{}]/ || raw ~ /\/[{}]/)
      ambiguous = (raw ~ /\/\*|\*\// || comment_brace || regex_brace ||
                   brace_in_quote(raw, "\"") || brace_in_quote(raw, squote) || brace_in_quote(raw, "`"))
      if (ambiguous) {
        print FILENAME ":" FNR ": ambiguous brace in string, comment, or regex"
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
        if (substr(raw, i) ~ ("^(" lab ")") && safe_depth == 0) {
          print FILENAME ":" FNR ":" raw
          violations = 1
          break
        }
      }
    }
    END {
      if (pending_gate) { print FILENAME ":EOF: development guard missing {"; violations = 1 }
      if (in_template) { print FILENAME ":EOF: unterminated template literal"; violations = 1 }
      if (depth != 0) { print FILENAME ":EOF: unbalanced braces"; violations = 1 }
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
  modules=0
  old_ifs=$IFS
  IFS='
'
  for file in $files; do
    case "$file" in
      *.swift)
        supported=$((supported + 1))
        if grep -qE "$LAB_PATTERN" "$file"; then
          references=$((references + 1)); lint_swift "$file" || failed=1
        fi
        ;;
      *.ui-tuning-lab.js|*.ui-tuning-lab.jsx|*.ui-tuning-lab.ts|*.ui-tuning-lab.tsx)
        # A lab module is development-only as a whole; every import of it is
        # linted in the importing file instead.
        supported=$((supported + 1)); modules=$((modules + 1))
        ;;
      *.js|*.jsx|*.ts|*.tsx)
        supported=$((supported + 1))
        if grep -qE "$LAB_PATTERN" "$file"; then
          references=$((references + 1)); lint_web "$file" || failed=1
        fi
        ;;
    esac
  done
  IFS=$old_ifs
  [ "$supported" -gt 0 ] || not_applicable "no supported Swift or web source files in $target"
  if [ "$references" -eq 0 ]; then
    [ "$modules" -eq 0 ] || not_applicable "lab modules found but nothing imports them in $target"
    not_applicable "supported sources contain no lab references in $target"
  fi
  [ "$failed" -eq 0 ] || fail "ungated lab references found"
  echo "PASS: supported source gates found around lab references in $target"
  echo "NOTE: source lint is not proof of absence from a compiled release artifact"
}

[ "$#" -eq 2 ] || usage
case "$1" in
  config) validate_config "$2" ;;
  profile) validate_profile "$2" ;;
  source-gates) lint_sources "$2" ;;
  *) usage ;;
esac
