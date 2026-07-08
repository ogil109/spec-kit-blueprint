#!/usr/bin/env bash
# blueprint-state — the deterministic state oracle + coherence gate for the blueprint.
#
# Computes, purely from the filesystem (specs/ = ground truth, the blueprint doc
# = the index), the next actionable step in the waterfall. No LLM judgment in the
# parts that must be reliable across a long unattended run.
#
# Usage:
#   blueprint-state.sh status                 # human-readable worklist
#   blueprint-state.sh next [--json]          # the single next action (drives the loop)
#
# Env / args:
#   --root <dir>        repo root (default: search upward for .specify, else cwd)
#   --blueprint <path>  blueprint doc (default: from config, else docs/overview.md
#                       or docs/blueprint.md or .specify/memory/blueprint.md)
set -euo pipefail

ROOT=""
BLUEPRINT=""
SKIP_SLUGS=""
PATH_FILTER=""
CMD="${1:-status}"; shift || true
JSON=0
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1 ;;
    --root) ROOT="$2"; shift ;;
    --blueprint) BLUEPRINT="$2"; shift ;;
    --skip) SKIP_SLUGS="$SKIP_SLUGS $2"; shift ;;   # exclude a slug (e.g. a parked slice); repeatable
    --path) PATH_FILTER="$2"; shift ;;              # restamp: limit to one code path
  esac
  shift
done

# ── locate repo root ──────────────────────────────────────────────────────────
if [ -z "$ROOT" ]; then
  d="$(pwd)"
  while [ "$d" != "/" ]; do
    [ -d "$d/.specify" ] && ROOT="$d" && break
    d="$(dirname "$d")"
  done
  [ -z "$ROOT" ] && ROOT="$(pwd)"
fi

# ── locate the blueprint doc ──────────────────────────────────────────────────
if [ -z "$BLUEPRINT" ]; then
  cfg="$ROOT/.specify/extensions/blueprint/blueprint-config.yml"
  if [ -f "$cfg" ]; then
    p=$(grep -E '^\s*path:' "$cfg" | head -1 | sed -E 's/^\s*path:\s*"?([^"]*)"?\s*$/\1/')
    [ -n "$p" ] && BLUEPRINT="$ROOT/$p"
  fi
fi
if [ -z "$BLUEPRINT" ] || [ ! -f "$BLUEPRINT" ]; then
  for cand in docs/blueprint.md docs/overview.md .specify/memory/blueprint.md; do
    [ -f "$ROOT/$cand" ] && BLUEPRINT="$ROOT/$cand" && break
  done
fi

SPECS_DIR="$ROOT/specs"

# ── per-spec phase frontier (deterministic from artifacts) ────────────────────
# Build chain: specify → clarify → plan → tasks → implement → (analyze) → done
# Doc track (orthogonal): if a spec exists but the blueprint doesn't point to it
#                         yet, it has "distill drift".
spec_phase() {
  local dir="$1"
  [ -f "$dir/spec.md" ] || { echo "specify"; return; }
  if grep -q '\[NEEDS CLARIFICATION' "$dir/spec.md" 2>/dev/null; then echo "clarify"; return; fi
  [ -f "$dir/plan.md" ]  || { echo "plan";  return; }
  [ -f "$dir/tasks.md" ] || { echo "tasks"; return; }
  # implement: tasks.md exists but still has unchecked items → implementing
  if grep -qE '^\s*-\s*\[ \]' "$dir/tasks.md" 2>/dev/null; then echo "implement"; return; fi
  echo "built"
}

slug_of() { basename "$1"; }

is_distilled() {  # does the blueprint already point to this spec slug?
  local slug="$1"
  [ -f "$BLUEPRINT" ] || { echo 0; return; }
  if grep -q "specs/$slug" "$BLUEPRINT" 2>/dev/null; then echo 1; else echo 0; fi
}

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

# ── gather state ──────────────────────────────────────────────────────────────
INFLIGHT_SLUG=(); INFLIGHT_PHASE=()
DISTILL_DRIFT=()
BUILT_COUNT=0
if [ -d "$SPECS_DIR" ]; then
  for dir in "$SPECS_DIR"/*/; do
    [ -d "$dir" ] || continue
    slug="$(slug_of "${dir%/}")"
    case " $SKIP_SLUGS " in *" $slug "*) continue ;; esac   # parked/excluded slice
    phase="$(spec_phase "${dir%/}")"
    distilled="$(is_distilled "$slug")"
    if [ "$phase" != "built" ]; then
      INFLIGHT_SLUG+=("$slug"); INFLIGHT_PHASE+=("$phase")
    else
      BUILT_COUNT=$((BUILT_COUNT+1))
      # Distill drift is a BUILT slice the blueprint hasn't collapsed yet — so the
      # waterfall distills as the LAST step of a slice (after implement), not the
      # moment its spec.md appears. An in-flight slice is advanced, never distilled.
      [ "$distilled" = "0" ] && DISTILL_DRIFT+=("$slug")
    fi
  done
fi

# ── section provenance (deterministic: read machine markers, not prose banners) ─
# The extension stamps every section it manages with a marker under its heading:
#   <!-- blueprint:section state=detailed -->
#   <!-- blueprint:section state=distilled owner=specs/<slug> -->
#   <!-- blueprint:section state=code -->
# Markers are AUTHORITATIVE — they are the extension's record of what it has processed.
# A level-2 heading with NO marker is UNMANAGED (external / not yet run through init)
# and counts as pending backlog, so a raw or hand-edited doc never silently reads as
# "done" just because a human left a section un-marked. Prose banners are cosmetic.
DETAILED_COUNT=0; SETTLED_COUNT=0; UNMANAGED_COUNT=0
if [ -f "$BLUEPRINT" ]; then
  DETAILED_COUNT=$(grep -cE '<!-- blueprint:section state=detailed' "$BLUEPRINT" 2>/dev/null || true)
  SETTLED_COUNT=$(grep -cE '<!-- blueprint:section state=(distilled|code)' "$BLUEPRINT" 2>/dev/null || true)
  UNMANAGED_COUNT=$(awk '
    /^## / { if (s && !m && !x) u++; h=tolower($0);
             x=(h ~ /table of contents/ || h ~ /how this/ || h ~ /changelog/); s=1; m=0; next }
    /<!-- blueprint:section/ { m=1 }
    END { if (s && !m && !x) u++; print u+0 }' "$BLUEPRINT")
fi
BACKLOG_COUNT=$((DETAILED_COUNT + UNMANAGED_COUNT))

# ── compute the single next action ────────────────────────────────────────────
# Priority (autonomous waterfall — keep the blueprint honest, finish started work
# before opening new work):
#   1. distill drift  (spec exists, blueprint hasn't collapsed its section)
#   2. advance the in-flight slice through its build chain (depth-first)
#   3. specify the next backlog subsystem (agent selects from the blueprint)
NEXT_PHASE="done"; NEXT_SLUG=""; NEXT_REASON="backlog empty — nothing in specs/, nothing in flight"
if [ "${#DISTILL_DRIFT[@]}" -gt 0 ]; then
  NEXT_PHASE="distill"; NEXT_SLUG="${DISTILL_DRIFT[0]}"
  NEXT_REASON="spec exists but blueprint still holds its detail"
elif [ "${#INFLIGHT_SLUG[@]}" -gt 0 ]; then
  NEXT_PHASE="${INFLIGHT_PHASE[0]}"; NEXT_SLUG="${INFLIGHT_SLUG[0]}"
  NEXT_REASON="in-flight slice; next build phase by artifact frontier"
elif [ -f "$BLUEPRINT" ] && [ "$DETAILED_COUNT" -eq 0 ] && [ "$SETTLED_COUNT" -eq 0 ] && [ "$UNMANAGED_COUNT" -gt 0 ]; then
  # The doc has sections but the extension has never processed it (zero markers) —
  # e.g. a raw master doc. Don't guess its state; initialize it first.
  NEXT_PHASE="init"
  NEXT_REASON="blueprint not yet processed by the extension — run /speckit.blueprint.init (${UNMANAGED_COUNT} unmanaged section(s))"
elif [ -f "$BLUEPRINT" ] && [ "$BACKLOG_COUNT" -gt 0 ]; then
  # Backlog exists: a detailed (managed) section, or an unmanaged heading init hasn't
  # processed yet. Which to specify is the agent's judgment.
  NEXT_PHASE="specify"; NEXT_SLUG=""
  NEXT_REASON="no in-flight work; specify the next detailed subsystem from the blueprint"
elif [ -f "$BLUEPRINT" ] && [ "$SETTLED_COUNT" -gt 0 ]; then
  # Every managed section is settled (owned by a spec or by code), nothing in flight.
  NEXT_REASON="all sections settled (owned by a spec or by code) — no pending design (run /speckit.specify to start a slice, then distill it)"
elif [ -f "$BLUEPRINT" ]; then
  # File exists but has no sections at all — an empty blueprint.
  NEXT_PHASE="specify"; NEXT_REASON="blueprint has no subsystem sections yet — add some, or run /speckit.blueprint.init"
fi
HAS_NEXT=true; [ "$NEXT_PHASE" = "done" ] && HAS_NEXT=false

# ── check: blueprint coherence gate (CI-friendly; exits nonzero on any drift) ──
# Two drift sources, one gate: (1) a built spec the blueprint hasn't collapsed
# (distill drift), (2) a code-owned section whose code moved/vanished since mapping.
if [ "$CMD" = "check" ]; then
  issues=0
  if [ "$UNMANAGED_COUNT" -gt 0 ]; then
    echo "UNMANAGED  ${UNMANAGED_COUNT} section(s) the extension hasn't processed (external/manual)   → blueprint.init"
    issues=$((issues+1))
  fi
  if [ "${#DISTILL_DRIFT[@]}" -gt 0 ]; then
    for s in "${DISTILL_DRIFT[@]}"; do
      echo "DRIFT      built spec not reflected in blueprint: $s   → blueprint.distill $s"
      issues=$((issues+1))
    done
  fi
  if is_git; then
    while IFS= read -r m; do
      [ -n "$m" ] || continue
      p="$(marker_path "$m")"; s="$(marker_sha "$m")"; cur="$(current_sha "$p")"
      if [ -z "$cur" ]; then
        echo "DANGLING   blueprint maps code that no longer exists: $p   → blueprint.remap"
        issues=$((issues+1))
      elif [ "$s" = "NONE" ]; then
        echo "UNSTAMPED  no baseline recorded yet for: $p   → blueprint.remap $p"
        issues=$((issues+1))
      elif [ "$cur" != "$s" ]; then
        echo "STALE      code changed since mapped: $p ($s → $cur)   → blueprint.remap $p"
        issues=$((issues+1))
      fi
    done < <(code_markers)
  else
    echo "note: not a git repository — skipping code-staleness checks"
  fi
  if [ "$issues" -eq 0 ]; then echo "blueprint in sync ✓"; exit 0; fi
  echo; echo "$issues issue(s) — blueprint is out of sync"; exit 1
fi

# ── restamp: refresh the git baseline for code markers (all, or one --path) ────
# Run as part of remap, after a section's prose has been re-derived from the code.
if [ "$CMD" = "restamp" ]; then
  is_git || { echo "not a git repository — cannot restamp"; exit 1; }
  [ -f "$BLUEPRINT" ] || { echo "no blueprint at: ${BLUEPRINT:-<none>}"; exit 1; }
  updated=0
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    p="$(marker_path "$m")"
    [ -n "$PATH_FILTER" ] && [ "$PATH_FILTER" != "$p" ] && continue
    cur="$(current_sha "$p")"
    [ -z "$cur" ] && { echo "skip (missing in git): $p"; continue; }
    esc="$(printf '%s' "$p" | sed 's/[|]/\\|/g')"
    sed -i -E "s|(<!-- blueprint:code path=${esc} sha=)[^ ]+( -->)|\1${cur}\2|" "$BLUEPRINT"
    echo "stamped $p → $cur"; updated=$((updated+1))
  done < <(code_markers)
  echo "restamped $updated marker(s)"; exit 0
fi

# ── output ────────────────────────────────────────────────────────────────────
if [ "$CMD" = "next" ]; then
  if [ "$JSON" = "1" ]; then
    printf '{"has_next": %s, "phase": "%s", "slug": "%s", "reason": "%s", "blueprint": "%s"}\n' \
      "$HAS_NEXT" "$NEXT_PHASE" "$NEXT_SLUG" "$NEXT_REASON" "${BLUEPRINT#"$ROOT/"}"
  else
    echo "next: $NEXT_PHASE ${NEXT_SLUG:+($NEXT_SLUG)} — $NEXT_REASON"
  fi
  exit 0
fi

# status (human)
echo "Blueprint waterfall — state"
echo "  root:      $ROOT"
echo "  blueprint: ${BLUEPRINT:-<none — run blueprint.init>} ${BLUEPRINT:+(${BUILT_COUNT} built, $(( ${#INFLIGHT_SLUG[@]} )) in-flight)}"
[ -f "$BLUEPRINT" ] && echo "  sections:  ${DETAILED_COUNT} detailed, ${SETTLED_COUNT} settled, ${UNMANAGED_COUNT} unmanaged (not yet processed by init)"
echo
echo "In-flight (spec exists, build not complete):"
if [ "${#INFLIGHT_SLUG[@]}" -eq 0 ]; then echo "  (none)"; else
  for i in "${!INFLIGHT_SLUG[@]}"; do
    echo "  - ${INFLIGHT_SLUG[$i]}  → next: ${INFLIGHT_PHASE[$i]}"
  done
fi
echo
echo "Distill drift (spec exists, blueprint not yet collapsed):"
if [ "${#DISTILL_DRIFT[@]}" -eq 0 ]; then echo "  (none — blueprint in sync)"; else
  for s in "${DISTILL_DRIFT[@]}"; do echo "  - $s  → /speckit.blueprint.distill $s"; done
fi
echo
echo "Next action: $NEXT_PHASE ${NEXT_SLUG:+($NEXT_SLUG)}"
echo "  ($NEXT_REASON)"
