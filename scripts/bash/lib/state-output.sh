#!/usr/bin/env bash
# lib/state-output.sh — `next` (machine/human) and the `status` dashboard.
# Pure presentation of what state-frontier.sh computed.
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

# `source` returns the status of the last command above; a region whose final
# line is a legitimately-failing test must not kill the entry under set -e.
:
