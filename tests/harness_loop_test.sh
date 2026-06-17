#!/usr/bin/env bash
# Tests the AUTONOMOUS HARNESS loop (docs/autonomous-harness.md): the core promise that
# an agent looping on the oracle takes MULTIPLE specs sequentially through the waterfall
# without drifting. This implements that loop in bash and runs it against the REAL oracle
# on a REAL evolving multi-slice project. Each phase "executes" by producing exactly the
# artifact the matching spec-kit command would leave on disk (spec.md, plan.md, tasks.md,
# checked tasks, a distilled blueprint section). We test the ORCHESTRATION the harness
# relies on (ordering, sequencing, termination, parking) — not the agent's authoring.
set -uo pipefail

ORACLE="$(cd "$(dirname "$0")/.." && pwd)/blueprint/scripts/bash/blueprint-state.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

field() { echo "$1" | sed -E "s/.*\"$2\": ?\"?([^\",}]*)\"?.*/\1/"; }

# --- phase executors: produce what each real spec-kit command would leave on disk ----
mk_specify() { # root slug needs_clarify
  mkdir -p "$1/specs/$2"
  if [ "$3" = "1" ]; then printf 'spec body\n[NEEDS CLARIFICATION: scope?]\n' > "$1/specs/$2/spec.md"
  else printf 'spec body\n' > "$1/specs/$2/spec.md"; fi
}
mk_clarify()   { sed -i '/NEEDS CLARIFICATION/d' "$1/specs/$2/spec.md"; }
mk_plan()      { : > "$1/specs/$2/plan.md"; }
mk_tasks()     { printf -- '- [ ] t1\n' > "$1/specs/$2/tasks.md"; }
mk_implement() { printf -- '- [x] t1\n' > "$1/specs/$2/tasks.md"; }
mk_distill()   { # blueprint slug — flip that section's banner to settled+pointer
  sed -i -E "s|^>[[:space:]]*\*\*Detailed.*\(slug: ${2}\).*|> **Distilled — owned by \`specs/${2}\`.**|" "$1"
}
# pick the next Detailed section (banner carries "(slug: NNN-x)") with no spec dir yet
next_detailed_slug() {
  local bp="$1" root="$2" line slug
  while IFS= read -r line; do
    slug=$(echo "$line" | sed -nE 's/.*\(slug: ([^)]*)\).*/\1/p')
    [ -n "$slug" ] || continue
    [ -d "$root/specs/$slug" ] || { echo "$slug"; return; }
  done < <(grep -E '^>[[:space:]]*\*\*Detailed.*\(slug:' "$bp")
  echo ""
}

# --- the harness loop (mirrors docs/autonomous-harness.md) ---------------------------
# args: root blueprint max_steps stop_before slug_filter
# globals: CLAR (slugs that get a clarify marker), PARK (slugs that park at clarify)
loop() {
  local root="$1" bp="$2" max="$3" stopb="$4" sfilter="$5"
  local steps=0 seq="" parked="" out phase slug hn tslug nc skipargs
  while :; do
    skipargs=(); for p in $parked; do skipargs+=(--skip "$p"); done
    out=$(bash "$ORACLE" next --json --root "$root" --blueprint "$bp" "${skipargs[@]}" 2>&1)
    phase=$(field "$out" phase); slug=$(field "$out" slug); hn=$(field "$out" has_next)
    [ "$hn" = "true" ] || { seq+=" done"; break; }
    [ -n "$stopb" ] && [ "$phase" = "$stopb" ] && { seq+=" stop_before:$phase"; break; }
    [ "$steps" -ge "$max" ] && { seq+=" max_steps"; break; }

    if [ "$phase" = "specify" ]; then
      if [ -n "$sfilter" ]; then
        [ -d "$root/specs/$sfilter" ] && { seq+=" slugdone"; break; }
        tslug="$sfilter"
      else
        tslug=$(next_detailed_slug "$bp" "$root")
      fi
      [ -n "$tslug" ] || { seq+=" nodetailed"; break; }
      nc=0; case " $CLAR " in *" $tslug "*) nc=1 ;; esac
      mk_specify "$root" "$tslug" "$nc"; seq+=" specify:$tslug"
    else
      [ -n "$sfilter" ] && [ "$slug" != "$sfilter" ] && { seq+=" slugdone"; break; }
      case "$phase" in
        clarify)
          case " $PARK " in
            *" $slug "*) parked="$parked $slug"; seq+=" park:$slug" ;;
            *) mk_clarify "$root" "$slug"; seq+=" clarify:$slug" ;;
          esac ;;
        plan)      mk_plan "$root" "$slug";      seq+=" plan:$slug" ;;
        tasks)     mk_tasks "$root" "$slug";     seq+=" tasks:$slug" ;;
        implement) mk_implement "$root" "$slug"; seq+=" implement:$slug" ;;
        distill)   mk_distill "$bp" "$slug";     seq+=" distill:$slug" ;;
      esac
    fi
    steps=$((steps+1))
  done
  echo "${seq# }"
}

# --- fixtures + assertions -----------------------------------------------------------
newproj() { # name -> root with a 2-section detailed blueprint
  local d="$TMP/$1"; mkdir -p "$d/specs" "$d/.specify"
  cat > "$d/blueprint.md" <<'BP'
# Demo Blueprint
## 1. Auth
> **Detailed (unspecced)** — holding pen. (slug: 001-auth)
body
## 2. Billing
> **Detailed (unspecced)** — holding pen. (slug: 002-billing)
body
BP
  echo "$d"
}
assert_eq() { # label got want
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  FAIL %s\n        want: %s\n        got:  %s\n' "$1" "$3" "$2"; fi
}

# Scenario 1 — two slices, clean: each goes specify→plan→tasks→implement→distill, in order, to done
CLAR=""; PARK=""
r=$(newproj clean)
got=$(loop "$r" "$r/blueprint.md" 50 "" "")
assert_eq "two slices sequence cleanly to done" "$got" \
  "specify:001-auth plan:001-auth tasks:001-auth implement:001-auth distill:001-auth specify:002-billing plan:002-billing tasks:002-billing implement:002-billing distill:002-billing done"

# Scenario 2 — first slice needs clarification: clarify slots in after specify, before plan
CLAR="001-auth"; PARK=""
r=$(newproj clar)
got=$(loop "$r" "$r/blueprint.md" 50 "" "")
assert_eq "clarify slots in after specify" "$got" \
  "specify:001-auth clarify:001-auth plan:001-auth tasks:001-auth implement:001-auth distill:001-auth specify:002-billing plan:002-billing tasks:002-billing implement:002-billing distill:002-billing done"

# Scenario 3 — stop_before=implement: sets up through tasks, stops at the implement boundary
CLAR=""; PARK=""
r=$(newproj stopb)
got=$(loop "$r" "$r/blueprint.md" 50 "implement" "")
assert_eq "stop_before=implement halts at boundary" "$got" \
  "specify:001-auth plan:001-auth tasks:001-auth stop_before:implement"

# Scenario 4 — slug=001-auth: advance only that slice, then stop (don't touch 002)
CLAR=""; PARK=""
r=$(newproj slug)
got=$(loop "$r" "$r/blueprint.md" 50 "" "001-auth")
assert_eq "slug scoping advances one slice only" "$got" \
  "specify:001-auth plan:001-auth tasks:001-auth implement:001-auth distill:001-auth slugdone"

# Scenario 5 — parking: 001 blocks at clarify; the loop parks it and still finishes 002
CLAR="001-auth"; PARK="001-auth"
r=$(newproj park)
got=$(loop "$r" "$r/blueprint.md" 50 "" "")
assert_eq "park blocked slice, keep building the rest" "$got" \
  "specify:001-auth park:001-auth specify:002-billing plan:002-billing tasks:002-billing implement:002-billing distill:002-billing nodetailed"

echo
echo "harness loop: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
