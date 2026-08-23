#!/usr/bin/env bash
# lib/state-frontier.sh — the deterministic waterfall frontier: per-spec phase
# from artifacts, section provenance from markers, and the single next action.
# Expects: ROOT, BLUEPRINT, SKIP_SLUGS. Sets: INFLIGHT_*, DISTILL_DRIFT,
# BUILT_COUNT, *_COUNT, BACKLOG_COUNT, NEXT_*, HAS_NEXT.
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
  if grep -qE '^[[:space:]]*-[[:space:]]*\[ \]' "$dir/tasks.md" 2>/dev/null; then echo "implement"; return; fi
  echo "built"
}

slug_of() { basename "$1"; }

is_distilled() {  # does the blueprint already point to this spec slug?
  local slug="$1"
  [ -f "$BLUEPRINT" ] || { echo 0; return; }
  if grep -q "specs/$slug" "$BLUEPRINT" 2>/dev/null; then echo 1; else echo 0; fi
}

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
#   <!-- blueprint:section state=detailed -->                        (holding pen)
#   <!-- blueprint:section state=distilled owner=specs/<slug> -->    (owned by a spec)
#   <!-- blueprint:section state=code -->                            (owned by code)
#   <!-- blueprint:section state=context -->                         (framing/cross-cutting;
#                                       managed, but not a buildable slice — never backlog)
# Markers are AUTHORITATIVE — they are the extension's record of what it has processed.
# A level-2 heading with NO marker is UNMANAGED (external / not yet run through init)
# and counts as pending backlog, so a raw or hand-edited doc never silently reads as
# "done" just because a human left a section un-marked. Prose banners are cosmetic.
DETAILED_COUNT=0; SETTLED_COUNT=0; CONTEXT_COUNT=0; UNMANAGED_COUNT=0
if [ -f "$BLUEPRINT" ]; then
  DETAILED_COUNT=$(grep -cE '<!-- blueprint:section state=detailed' "$BLUEPRINT" 2>/dev/null || true)
  SETTLED_COUNT=$(grep -cE '<!-- blueprint:section state=(distilled|code)' "$BLUEPRINT" 2>/dev/null || true)
  CONTEXT_COUNT=$(grep -cE '<!-- blueprint:section state=context' "$BLUEPRINT" 2>/dev/null || true)
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
  NEXT_REASON="blueprint not yet processed by the extension — run /speckit.blueprint-index.init (${UNMANAGED_COUNT} unmanaged section(s))"
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
  NEXT_PHASE="specify"; NEXT_REASON="blueprint has no subsystem sections yet — add some, or run /speckit.blueprint-index.init"
fi
HAS_NEXT=true; [ "$NEXT_PHASE" = "done" ] && HAS_NEXT=false


# `source` returns the status of the last command above; a region whose final
# line is a legitimately-failing test must not kill the entry under set -e.
:
