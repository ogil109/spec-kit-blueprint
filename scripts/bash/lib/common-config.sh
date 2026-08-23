#!/usr/bin/env bash
# lib/common-config.sh — configuration validation, shared by both entries.
# The config steers the entire partition; it is validated like every other
# input surface (unknown keys, wrong types, and misindented lists are hard
# errors — silent acceptance is a defect). Silent when the config is clean.
# Expects: CFG. Exits 2 on any violation, listing all of them.
cfg_validate() {
  [ -f "$CFG" ] || return 0
  local errs
  errs="$(awk '
    BEGIN {
      valid["blueprint"] = " path "
      valid["distill"]   = " require_confirmation "
      valid["slice"]     = " max_files min_files boundary_files context_dirs pin_dirs "
      valid["coverage"]  = " exclude "
      lists = " boundary_files context_dirs pin_dirs exclude "
      nums  = " max_files min_files "
      bools = " require_confirmation "
      top = ""; lastlist = ""
    }
    function flushlist() {
      if (lastlist != "" && items[lastlist] == 0)
        print "list key '\''" lastlist "'\'' has no parseable items (check indentation)"
      lastlist = ""
    }
    { line = $0 }
    /^[[:space:]]*(#|$)/ { next }
    /^[^[:space:]]/ {
      flushlist()
      if (line !~ /:/) { print "unrecognized top-level line " NR ": " line; top = ""; next }
      t = line; sub(/:.*$/, "", t); sub(/[[:space:]]+$/, "", t)
      if (!(t in valid)) { print "unknown section '\''" t "'\'' (valid: blueprint, distill, slice, coverage)"; top = ""; next }
      top = t; next
    }
    top == "" { next }
    /^[[:space:]]+-[[:space:]]+/ {
      if (lastlist != "") { items[lastlist]++ }
      else { print "list item outside any list key (line " NR ")" }
      next
    }
    /^[[:space:]]+[A-Za-z_]+:/ {
      flushlist()
      k = line; sub(/^[[:space:]]+/, "", k); sub(/:.*$/, "", k)
      if (valid[top] !~ (" " k " ")) { print "unknown key '\''" k "'\'' under '\''" top "'\'' (valid:" valid[top] ")"; next }
      v = line; sub(/^[[:space:]]+[A-Za-z_]+:[[:space:]]*/, "", v); sub(/[[:space:]]+#.*$/, "", v); gsub(/"/, "", v)
      if (lists ~ (" " k " ")) {
        if (v == "")        { lastlist = k; items[k] = 0 }
        else if (v == "[]") { }
        else { print "key '\''" k "'\'' expects a block list (- items) or [], got: " v }
        next
      }
      if (nums ~ (" " k " "))  { if (v !~ /^[1-9][0-9]*$/) print "key '\''" k "'\'' must be a positive integer, got: '\''" v "'\''"; next }
      if (bools ~ (" " k " ")) { if (v != "true" && v != "false") print "key '\''" k "'\'' must be true or false, got: '\''" v "'\''"; next }
      if (k == "path" && v == "") print "key '\''path'\'' is empty"
      next
    }
    { print "unrecognized line " NR ": " line }
    END { flushlist() }
  ' "$CFG")"
  if [ -n "$errs" ]; then
    echo "invalid blueprint-config.yml — nothing run:" >&2
    printf '%s\n' "$errs" | sed 's/^/  - /' >&2
    exit 2
  fi
}
cfg_validate

# `source` returns the status of the last command above; a region whose final
# line is a legitimately-failing test must not kill the entry under set -e.
:
