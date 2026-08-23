#!/usr/bin/env bash
# lib/common-git.ssh — git + marker plumbing shared by every command.
# Sourced by both entries. Expects: ROOT, BLUEPRINT. Provides: is_git,
# current_sha, code/context/relation marker readers, marker field extractors,
# coverage excludes, the record separator US, and JSON escaping.
# ── code-staleness support (keep the blueprint honest vs out-of-band code edits) ─
# A code-owned section carries a machine marker recording the git baseline of the
# code it maps:   <!-- blueprint:code path=src/area sha=<git-sha> -->
# `check` flags a section whose code changed since (sha drift) or vanished; `remap`
# re-derives the section and `restamp` refreshes its baseline. This catches changes
# that never went through a spec — the spec-anchored oracle alone cannot see those.
is_git()      { git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; }
current_sha() { git -C "$ROOT" rev-parse --verify --quiet "HEAD:$1" 2>/dev/null || true; }  # tree/blob sha, empty if missing
code_markers(){ [ -f "$BLUEPRINT" ] && grep -oE '<!-- blueprint:code path=[^ ]+ sha=[^ ]+ -->' "$BLUEPRINT" 2>/dev/null || true; }
marker_path() { echo "$1" | sed -E 's/.*path=([^ ]+).*/\1/'; }
marker_sha()  { echo "$1" | sed -E 's/.*sha=([^ ]+).*/\1/'; }
# A context section may declare the paths it covers (docs trees etc.):
#   <!-- blueprint:context path=docs -->
# Context coverage has NO baseline and NO staleness — it says "this exists and is
# on the map, but it is not architecture-bearing buildable code".
context_markers(){ [ -f "$BLUEPRINT" ] && grep -oE '<!-- blueprint:context path=[^ ]+ -->' "$BLUEPRINT" 2>/dev/null || true; }
# Stage-2 architecture relations (agent-authored, oracle-validated):
#   <!-- blueprint:relation from=<section> to=<section> kind=<uses|crosscuts> evidence=<path> -->
# The oracle validates what is CHECKABLE about the agent's call — both endpoints
# are managed sections, the evidence path exists in git — so recovered
# architecture can't silently rot; the semantic truth of an edge stays judgment.
relation_markers(){ [ -f "$BLUEPRINT" ] && grep -oE '<!-- blueprint:relation from=[^ ]+ to=[^ ]+ kind=[^ ]+ evidence=[^ ]+ -->' "$BLUEPRINT" 2>/dev/null || true; }
# Paths the coverage scan never flags. From config (coverage.exclude), else the
# defaults: hidden top-level dirs, and specs/ (first-class spec-kit state, gated
# by distill drift instead). A pattern without "/" matches the FIRST path
# component; one containing "/" matches as a path prefix. Both are shell globs.
cov_excludes() {
  local cfg="$ROOT/.specify/extensions/blueprint-index/blueprint-config.yml" ex=""
  if [ -f "$cfg" ]; then
    ex=$(awk '
      /^[^[:space:]#]/ { in_top = ($0 ~ /^coverage:[[:space:]]*$/); in_list = 0 }
      in_top && $0 ~ /^[[:space:]]+exclude:[[:space:]]*$/ { in_list = 1; next }
      in_top && in_list {
        if ($0 ~ /^[[:space:]]+-[[:space:]]+/) {
          sub(/^[[:space:]]+-[[:space:]]+/, ""); sub(/[[:space:]]+#.*$/, ""); gsub(/"/, ""); print
        } else if ($0 ~ /^[[:space:]]*(#|$)/) { } else { in_list = 0 }
      }' "$cfg")
  fi
  if [ -n "$ex" ]; then printf '%s\n' "$ex"; else printf '.*\nspecs\n'; fi
}


# Non-whitespace record separator (empty fields survive `read`; never in paths).
US=$'\x1f'
# JSON string escaping, shared by every JSON emitter.
jesc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# `source` returns the status of the last command above; a region whose final
# line is a legitimately-failing test must not kill the entry under set -e.
:
