#!/usr/bin/env bash
# blueprint-state — the deterministic state oracle + coherence gate for the blueprint.
#
# Computes, purely from the filesystem (specs/ = ground truth, the blueprint doc
# = the index), the next actionable step in the waterfall, and gates the map's
# coherence. No LLM judgment in the parts that must be reliable unattended.
#
# Usage:
#   blueprint-state.sh status                 # human-readable worklist
#   blueprint-state.sh next [--json]          # the single next action (drives the loop)
#   blueprint-state.sh check [--json|--strict]# the tiered CI gate
#   blueprint-state.sh restamp [--path <p>]   # deterministic baseline refresh
#
# Env / args:
#   --root <dir>        repo root (default: search upward for .specify, else cwd)
#   --blueprint <path>  blueprint doc (default: from config, else the canonical
#                       .specify/memory/blueprint.md, else docs/blueprint.md)
#
# This entry only parses arguments and sequences the lib/ modules; every piece
# of behavior lives in exactly one file under scripts/bash/lib/.
set -euo pipefail

ROOT=""
BLUEPRINT=""
SKIP_SLUGS=""
PATH_FILTER=""
STRICT=0
CMD="${1:-status}"; shift || true
JSON=0
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1 ;;
    --root) ROOT="$2"; shift ;;
    --blueprint) BLUEPRINT="$2"; shift ;;
    --skip) SKIP_SLUGS="$SKIP_SLUGS $2"; shift ;;   # exclude a slug (e.g. a parked slice); repeatable
    --path) PATH_FILTER="$2"; shift ;;              # restamp: limit to one code path
    --strict) STRICT=1 ;;                           # check: make advisory (soft) issues blocking too
    --human) HUMAN=1 ;;                             # force human-readable output (default when a TTY)
  esac
  shift
done
HUMAN=${HUMAN:-0}
# Output format (git/ls convention): explicit flag wins; else JSON when piped, human on a TTY.
if [ "$JSON" = "1" ]; then FMT=json
elif [ "$HUMAN" = "1" ]; then FMT=human
elif [ -t 1 ]; then FMT=human
else FMT=json; fi


LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"

source "$LIB/common-root.sh"       # sets ROOT
CFG="$ROOT/.specify/extensions/blueprint-index/blueprint-config.yml"
source "$LIB/common-config.sh"     # validates the config (exits 2 on violations)
# ── locate the blueprint doc ──────────────────────────────────────────────────
# POSIX character classes only ([[:space:]], never the GNU whitespace shorthand):
# GNU regex shorthands are not POSIX ERE — BSD sed (macOS) passes the line through
# UNCHANGED on a failed match, silently corrupting the resolved path.
# tests/portability_lint_test.sh guards this class.
if [ -z "$BLUEPRINT" ]; then
  cfg="$ROOT/.specify/extensions/blueprint-index/blueprint-config.yml"
  if [ -f "$cfg" ]; then
    # `|| true`: under `set -euo pipefail` a config with no `path:` key would
    # otherwise kill the whole script via grep's exit 1 — a config that only
    # sets other keys is legal.
    p=$(grep -E '^[[:space:]]*path:' "$cfg" | head -1 | sed -E 's/^[[:space:]]*path:[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/' || true)
    if [ -n "$p" ]; then
      BLUEPRINT="$ROOT/$p"
      # A configured path that doesn't resolve must be loud: silently falling back
      # to the auto-detect candidates means a team's real blueprint is ignored.
      [ -f "$BLUEPRINT" ] || echo "warning: configured blueprint.path '$p' not found — falling back to auto-detect" >&2
    fi
  fi
fi
if [ -z "$BLUEPRINT" ] || [ ! -f "$BLUEPRINT" ]; then
  # Canonical location first (matches the config default and extension defaults);
  # the docs/ candidates are legacy/alternative homes.
  for cand in .specify/memory/blueprint.md docs/blueprint.md; do
    [ -f "$ROOT/$cand" ] && BLUEPRINT="$ROOT/$cand" && break
  done
fi


source "$LIB/common-git.sh"        # git + marker plumbing, US, jesc
source "$LIB/state-frontier.sh"    # frontier, provenance, next action
source "$LIB/state-check.sh"       # the gate (exits when CMD=check)
source "$LIB/state-restamp.sh"     # baseline refresh (exits when CMD=restamp)
source "$LIB/state-output.sh"      # next/status presentation
