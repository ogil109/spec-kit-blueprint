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
  cfg="$ROOT/.specify/extensions/blueprint-index/blueprint-config.yml"
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

# ── check: tiered blueprint coherence gate (CI-friendly) ──────────────────────
# HARD (blocks merge): the map factually CONTRADICTS reality — a built spec the map
#   doesn't index (drift), or a section pointing at code that's been deleted
#   (dangling). These are precise / low-false-positive.
# SOFT (advisory, does NOT block unless --strict): the map MIGHT be behind — code
#   changed under a mapped area (stale), a section not yet processed (unmanaged), or
#   no baseline yet (unstamped). These are coarse; most are still-true at map altitude,
#   so blocking every code change here is the friction teams reject. Reconcile with
#   remap/init instead. `--strict` promotes soft → blocking for teams that want it.
if [ "$CMD" = "check" ]; then
  jesc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
  # Records are \x1f-delimited (ASCII Unit Separator), NOT tab: tab is a whitespace
  # IFS char, so `read` collapses consecutive tabs and drops empty fields — which
  # silently shifted every field of an issue with an empty target (only `unmanaged`).
  # \x1f is non-whitespace (empty fields preserved) and never appears in paths/prose.
  US=$'\x1f'
  ISSUES=()   # each record: severity \x1f type \x1f target \x1f detail \x1f remedy_run \x1f remedy_kind
  add() { ISSUES+=("$1$US$2$US$3$US$4$US$5$US$6"); }

  [ "$UNMANAGED_COUNT" -gt 0 ] && \
    add soft unmanaged "" "${UNMANAGED_COUNT} section(s) not processed by the extension" "/speckit.blueprint-index.init" authored
  if [ "${#DISTILL_DRIFT[@]}" -gt 0 ]; then
    for s in "${DISTILL_DRIFT[@]}"; do
      add hard drift "$s" "built spec not in the map" "/speckit.blueprint-index.distill $s" authored
    done
  fi
  if is_git; then
    while IFS= read -r m; do
      [ -n "$m" ] || continue
      p="$(marker_path "$m")"; s="$(marker_sha "$m")"; cur="$(current_sha "$p")"
      if [ -z "$cur" ]; then
        add hard dangling "$p" "map points at code that no longer exists" "/speckit.blueprint-index.remap $p" authored
      elif [ "$s" = "NONE" ]; then
        add soft unstamped "$p" "no git baseline recorded yet" "blueprint-state.sh restamp --path $p" deterministic
      elif [ "$cur" != "$s" ]; then
        # abbreviate like git: a full 40-char pair is unreadable in a CI log line
        add soft stale "$p" "code changed since mapped (${s:0:8} -> ${cur:0:8})" "/speckit.blueprint-index.remap $p" authored
      fi
    done < <(code_markers)

    # unmapped code (coverage): tracked code under a mapped root that NO section covers.
    # Deterministic + git-based (git ls-files → respects .gitignore). Reported at the
    # shallowest uncovered directory; a dir that only *contains* mapped areas (a covered
    # parent) is not flagged. SOFT — a new module may be intentional WIP.
    mapped_paths=(); while IFS= read -r mk; do [ -n "$mk" ] && mapped_paths+=("$(marker_path "$mk")"); done < <(code_markers)
    if [ "${#mapped_paths[@]}" -gt 0 ]; then
      roots=$(printf '%s\n' "${mapped_paths[@]}" | sed -E 's#/.*##' | sort -u)
      uncovered=$(git -C "$ROOT" ls-files -- $roots 2>/dev/null | while IFS= read -r f; do
        skip=0
        for p in "${mapped_paths[@]}"; do case "$f" in "$p"|"$p"/*) skip=1; break;; esac; done   # covered file
        [ "$skip" = 1 ] && continue
        d=$(dirname "$f")
        for p in "${mapped_paths[@]}"; do case "$p" in "$d"|"$d"/*) skip=1; break;; esac; done     # covered-parent dir
        [ "$skip" = 1 ] || echo "$d"
      done | sort -u)
      for d in $uncovered; do
        keep=1; for o in $uncovered; do [ "$o" != "$d" ] && case "$d" in "$o"/*) keep=0; break;; esac; done
        [ "$keep" = 1 ] && add soft unmapped "$d" "tracked code no section maps" "/speckit.blueprint-index.init --from-code $d" authored
      done
    fi
  else
    echo "note: not a git repository — code-staleness/coverage checks skipped" >&2
  fi

  hard_n=0; soft_n=0
  for rec in "${ISSUES[@]:-}"; do [ -n "$rec" ] || continue
    case "$rec" in hard*) hard_n=$((hard_n+1)) ;; soft*) soft_n=$((soft_n+1)) ;; esac
  done
  insync=false; [ "$hard_n" -eq 0 ] && [ "$soft_n" -eq 0 ] && insync=true
  # exit code (first-class signal): block on hard, or on soft too under --strict
  rc=0; { [ "$hard_n" -gt 0 ] || { [ "$STRICT" = "1" ] && [ "$soft_n" -gt 0 ]; }; } && rc=1

  if [ "$FMT" = json ]; then
    printf '{"blueprint_schema":"1","command":"check","blueprint":"%s","in_sync":%s,"blocking":%d,"advisory":%d,"strict":%s,"issues":[' \
      "$(jesc "${BLUEPRINT#"$ROOT/"}")" "$insync" "$hard_n" "$soft_n" "$([ "$STRICT" = 1 ] && echo true || echo false)"
    first=1
    for rec in "${ISSUES[@]:-}"; do [ -n "$rec" ] || continue
      IFS="$US" read -r sev typ tgt det run kind <<<"$rec"
      [ $first -eq 1 ] || printf ','; first=0
      printf '{"severity":"%s","type":"%s","target":"%s","detail":"%s","remedy":{"run":"%s","kind":"%s"}}' \
        "$sev" "$typ" "$(jesc "$tgt")" "$(jesc "$det")" "$(jesc "$run")" "$kind"
    done
    printf ']}\n'
    exit $rc
  fi

  # human
  if [ "$insync" = true ]; then echo "blueprint in sync ✓"; exit 0; fi
  if [ "$hard_n" -gt 0 ]; then
    echo "HARD — the map contradicts reality (blocks merge):"
    for rec in "${ISSUES[@]:-}"; do [ -n "$rec" ] || continue
      IFS="$US" read -r sev typ tgt det run kind <<<"$rec"
      [ "$sev" = hard ] && printf '  %-9s %s %s   → %s\n' "$(echo "$typ"|tr a-z A-Z)" "$tgt" "$det" "$run"
    done
  fi
  if [ "$soft_n" -gt 0 ]; then
    [ "$hard_n" -gt 0 ] && echo
    echo "SOFT — the map may be behind (advisory$([ "$STRICT" = 1 ] && echo "; blocking under --strict")):"
    for rec in "${ISSUES[@]:-}"; do [ -n "$rec" ] || continue
      IFS="$US" read -r sev typ tgt det run kind <<<"$rec"
      [ "$sev" = soft ] && printf '  %-9s %s %s   → %s\n' "$(echo "$typ"|tr a-z A-Z)" "$tgt" "$det" "$run"
    done
  fi
  echo
  echo "${hard_n} blocking, ${soft_n} advisory$([ "$rc" = 0 ] && [ "$soft_n" -gt 0 ] && echo " — not blocking (use --strict to block)")"
  exit $rc
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
[ -f "$BLUEPRINT" ] && echo "  sections:  ${DETAILED_COUNT} detailed, ${SETTLED_COUNT} settled, ${CONTEXT_COUNT} context, ${UNMANAGED_COUNT} unmanaged (not yet processed by init)"
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
  for s in "${DISTILL_DRIFT[@]}"; do echo "  - $s  → /speckit.blueprint-index.distill $s"; done
fi
echo
echo "Next action: $NEXT_PHASE ${NEXT_SLUG:+($NEXT_SLUG)}"
echo "  ($NEXT_REASON)"
