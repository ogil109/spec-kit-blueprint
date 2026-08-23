#!/usr/bin/env bash
# blueprint-slice — the deterministic brownfield partitioner (the on-ramp oracle).
#
# Usage:
#   blueprint-slice.sh [slice] [--json|--human]
#     [--root <dir>] [--blueprint <path>] [--scope <dir>] [--all]
#   blueprint-slice.sh scaffold [--root <dir>] [--blueprint <path>] [--scope <dir>]
#   blueprint-slice.sh render   --facts <file> [--root <dir>] [--blueprint <path>]
#
# The model in one line: structure is machine-written (slice/scaffold; the
# check gate validates conformance), prose and relations are rendered from
# agent-emitted, machine-validated FACTS (render).
# Same repo state + same config => byte-identical output everywhere.
#
# This entry only parses arguments and sequences the lib/ modules; every piece
# of behavior lives in exactly one file under scripts/bash/lib/.
set -euo pipefail

ROOT=""
BLUEPRINT=""; BPFLAG=""
SCOPE=""
ALL=0
FACTS=""
CMD="${1:-slice}"; shift || true
JSON=0; HUMAN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1 ;;
    --human) HUMAN=1 ;;
    --root) ROOT="$2"; shift ;;
    --blueprint) BLUEPRINT="$2"; BPFLAG=1; shift ;;
    --scope) SCOPE="${2%/}"; shift ;;
    --facts) FACTS="$2"; shift ;;
    --all) ALL=1 ;;
  esac
  shift
done
if [ "$JSON" = "1" ]; then FMT=json
elif [ "$HUMAN" = "1" ]; then FMT=human
elif [ -t 1 ]; then FMT=human
else FMT=json; fi
case "$CMD" in slice|scaffold|render) ;; *) echo "unknown command: $CMD (only: slice, scaffold, render)" >&2; exit 2 ;; esac


LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"

source "$LIB/common-root.sh"       # sets ROOT
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repository: $ROOT" >&2; exit 1; }

CFG="$ROOT/.specify/extensions/blueprint-index/blueprint-config.yml"
source "$LIB/common-config.sh"     # validates the config (exits 2 on violations)


# ── locate the blueprint doc (optional here; used for subtraction + exclusion) ─
# An EXPLICIT --blueprint is authoritative and never silently replaced: a
# missing explicit target means a FRESH map there (scaffold) / no subtraction
# (slice) — falling back to auto-detect would quietly operate on a different
# file than the one named.
if [ -z "$BLUEPRINT" ] && [ -f "$CFG" ]; then
  p=$(grep -E '^[[:space:]]*path:' "$CFG" | head -1 | sed -E 's/^[[:space:]]*path:[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/' || true)
  [ -n "$p" ] && [ -f "$ROOT/$p" ] && BLUEPRINT="$ROOT/$p"
fi
if [ -z "$BPFLAG" ] && { [ -z "$BLUEPRINT" ] || [ ! -f "$BLUEPRINT" ]; }; then
  # Canonical location first (matches the config default); docs/ candidates are legacy homes.
  for cand in .specify/memory/blueprint.md docs/blueprint.md; do
    [ -f "$ROOT/$cand" ] && BLUEPRINT="$ROOT/$cand" && break
  done
fi


source "$LIB/common-git.sh"        # git + marker plumbing, US, jesc
source "$LIB/slice-config.sh"      # config readers + slice defaults
source "$LIB/slice-render.sh"      # facts -> map (exits when CMD=render)
source "$LIB/slice-covered.sh"     # DOCPAIRS, covered set, holes
source "$LIB/slice-partition.sh"   # the deterministic partition
source "$LIB/slice-scaffold.sh"    # skeleton emission (exits when CMD=scaffold)
source "$LIB/slice-output.sh"      # advisories + slice JSON/human
