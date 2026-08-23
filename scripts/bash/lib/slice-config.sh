#!/usr/bin/env bash
# lib/slice-config.sh — the YAML-subset config readers (cfg_val/cfg_list) and
# the slice settings with their shipped defaults. Expects: CFG. Sets:
# MAX_FILES, MIN_FILES, BOUNDARY, CONTEXT_DIRS, PIN_DIRS, EXCLUDES.
# ── config (YAML subset: two levels, scalars + string lists) ──────────────────
cfg_val() { # <top> <key> → scalar value (empty if absent)
  [ -f "$CFG" ] || return 0
  awk -v top="$1" -v key="$2" '
    /^[^[:space:]#]/ { in_top = ($0 ~ "^" top ":[[:space:]]*$") }
    in_top && $0 ~ "^[[:space:]]+" key ":" {
      sub("^[[:space:]]+" key ":[[:space:]]*", ""); sub(/[[:space:]]+#.*$/, "")
      gsub(/"/, ""); print; exit
    }' "$CFG"
}
cfg_list() { # <top> <key> → list items, one per line (empty if absent)
  [ -f "$CFG" ] || return 0
  awk -v top="$1" -v key="$2" '
    /^[^[:space:]#]/ { in_top = ($0 ~ "^" top ":[[:space:]]*$"); in_list = 0 }
    in_top && $0 ~ "^[[:space:]]+" key ":[[:space:]]*$" { in_list = 1; next }
    in_top && in_list {
      if ($0 ~ /^[[:space:]]+-[[:space:]]+/) {
        sub(/^[[:space:]]+-[[:space:]]+/, ""); sub(/[[:space:]]+#.*$/, ""); gsub(/"/, ""); print
      } else if ($0 ~ /^[[:space:]]*(#|$)/) { } else { in_list = 0 }
    }' "$CFG"
}

MAX_FILES="$(cfg_val slice max_files)"; MAX_FILES="${MAX_FILES:-400}"
MIN_FILES="$(cfg_val slice min_files)"; MIN_FILES="${MIN_FILES:-3}"
BOUNDARY="$(cfg_list slice boundary_files)"
[ -z "$BOUNDARY" ] && BOUNDARY="pyproject.toml
setup.py
package.json
Cargo.toml
go.mod
pom.xml
build.gradle
CMakeLists.txt
composer.json
Gemfile"
CONTEXT_DIRS="$(cfg_list slice context_dirs)"
[ -z "$CONTEXT_DIRS" ] && CONTEXT_DIRS="docs
doc
documentation"
PIN_DIRS="$(cfg_list slice pin_dirs | sed 's|/$||')"
EXCLUDES="$(cfg_list coverage exclude)"
[ -z "$EXCLUDES" ] && EXCLUDES=".*
specs"


# `source` returns the status of the last command above; a region whose final
# line is a legitimately-failing test must not kill the entry under set -e.
:
