# Shared helpers for tests that exercise example code as users copy it.
#
# A code block becomes a file when the line directly above its fence is
#   <!-- file: Name.ext -->                  (default variant)
#   <!-- file: Name.ext variant=persist -->  (replaces Name.ext in that variant)
# Untagged blocks are prose excerpts and are ignored.

# extract_example <example.md> <out-dir> [variant]
extract_example() {
  md=$1
  out=$2
  variant=${3:-default}
  mkdir -p "$out"
  extract_pass "$md" "$out" default || return
  [ "$variant" = default ] || extract_pass "$md" "$out" "$variant" || return
  # <!-- copy: assets/<path> --> adds a shared asset file, as users copy it.
  root=$(CDPATH= cd -- "$(dirname "$md")/.." && pwd)
  for src in $(sed -n 's/^<!-- copy: \([^ ]*\) -->$/\1/p' "$md"); do
    [ -f "$root/$src" ] || { echo "$md: missing asset $src" >&2; return 2; }
    cp "$root/$src" "$out/"
  done
}

# Malformed tags fail loudly (exit 2) so a variant can never pass vacuously.
extract_pass() {
  awk -v out="$2" -v want="$3" '
    function fail(message) {
      print FILENAME ":" FNR ": " message > "/dev/stderr"
      failed = 1; exit 2
    }
    { sub(/\r$/, ""); line = $0; sub(/[ \t]+$/, "", line) }
    pending {
      if (line !~ /^```[A-Za-z]+$/) fail("file tag must be directly followed by an opening fence")
      pending = 0
      if (tag == want) {
        if (name in written) fail("duplicate file " name " in variant " want)
        written[name] = 1; active = 1; path = out "/" name; printf "" > path
      } else skipping = 1
      next
    }
    line ~ /^<!-- file: / && !active && !skipping {
      fields = split(line, f, " ")
      if (fields < 4 || f[fields] != "-->") fail("malformed file tag")
      name = f[3]; tag = "default"
      if (fields == 5 && f[4] ~ /^variant=[A-Za-z0-9_-]+$/) tag = substr(f[4], 9)
      else if (fields != 4) fail("malformed file tag")
      pending = 1; next
    }
    line == "```" && (active || skipping) { if (active) close(path); active = 0; skipping = 0; next }
    active { print > path }
    END {
      if (failed) exit 2
      if (pending || active || skipping) fail("unterminated tagged block")
    }
  ' "$1"
}

# example_variants <example.md>: default followed by every named variant.
example_variants() {
  echo default
  sed -n 's/^<!-- file: [^ ]* variant=\([A-Za-z0-9_-]*\) -->$/\1/p' "$1" | sort -u
}
