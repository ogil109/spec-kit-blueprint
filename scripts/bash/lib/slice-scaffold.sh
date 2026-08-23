#!/usr/bin/env bash
# lib/slice-scaffold.sh — `scaffold`: emit the map skeleton itself (title,
# how-this-works header, status TOC, sections + markers + banners +
# TODO(prose) placeholders), or only the missing additive blocks against an
# existing map. Byte-identical for the same repo state + config. No-op unless
# CMD=scaffold; exits when it runs. Conformance of the written map is
# validated by the check gate's structure issues.
# ── scaffold: emit the map (or the missing blocks) — structure by machine ─────
# Byte-identical for the same repo state + config: no dates, no judgment. The
# TODO(prose) placeholders are the agent's ONLY edit surface.
if [ "$CMD" = "scaffold" ]; then
  emit_section() { # kind path rem markers...
    local kind="$1" path="$2" rem="$3" markers="$4" m
    printf '## %s%s\n' "$path" "$([ "$rem" = 1 ] && echo ' (remainder)')"
    if [ "$kind" = "code" ]; then
      printf '<!-- blueprint:section state=code -->\n'
      printf '> **Distilled — owned by code at `%s/`.** (no spec yet) The implementation\n' "$path"
      printf '> is the source of truth; this section maps it. To change it, `/speckit.specify`\n'
      printf '> the area as usual and `distill` it when the spec ships.\n'
      for m in $markers; do printf '<!-- blueprint:code path=%s sha=NONE -->\n' "$m"; done
    else
      printf '<!-- blueprint:section state=context -->\n'
      printf '> Framing / documentation tree — on the map, not a buildable slice.\n'
      for m in $markers; do printf '<!-- blueprint:context path=%s -->\n' "$m"; done
    fi
    printf '\nTODO(prose): pending render — emit a facts entry for `%s` (see the\n' "$path"
    printf 'recover command) and run blueprint-slice render; do not edit by hand.\n\n---\n\n'
  }
  # -s, not -f: `scaffold > map.md` creates the empty redirect target before the
  # script runs — an empty blueprint must still get the full skeleton + header.
  if [ -z "$BP_REL" ] || [ ! -s "$BLUEPRINT" ]; then
    # full skeleton. Project name from the origin remote (clone-directory names
    # are an environment leak two clones of the same repo would disagree on);
    # falls back to the directory name when there is no remote.
    proj="$(git -C "$ROOT" remote get-url origin 2>/dev/null | sed -E 's#/*$##; s#\.git$##; s#.*[/:]##' || true)"
    [ -n "$proj" ] || proj="$(basename "$ROOT")"
    printf '# %s Blueprint\n\n' "$proj"
    printf '**Status**: Living document — the authoritative backlog + architecture map for this project.\n\n'
    printf '<!--\n  HOW THIS DOCUMENT WORKS\n  =======================\n'
    printf '  Decreasing-detail map. Sections are DETAILED (backlog: design pending), SETTLED\n'
    printf '  (digest + pointer; owner is a feature spec specs/<slug> or the CODE itself —\n'
    printf '  brownfield), or CONTEXT (framing; never backlog). Ground truth is the filesystem;\n'
    printf '  the machine-readable provenance markers under each heading are what the oracle\n'
    printf '  reads — banners and prose are cosmetic. To change a code-owned slice:\n'
    printf '  /speckit.specify it as usual; distill collapses its section when the spec ships.\n'
    printf '  STRUCTURE IS COMPUTED (blueprint-slice.sh scaffold), never improvised: to change\n'
    printf '  the cut, edit blueprint-config.yml and re-derive; the check gate validates\n'
    printf '  structural conformance.\n-->\n\n'
    printf '## Table of Contents\n\n'
    while IFS="$US" read -r kind path rem rule count markers; do
      [ -n "$kind" ] || continue
      status="**code-owned**"; [ "$kind" = "context" ] && status="**context**"
      printf -- '- `%s`%s — TODO(prose): one line; %s\n' "$path" "$([ "$rem" = 1 ] && echo ' (remainder)')" "$status"
    done <<<"$PART"
    printf '\n---\n\n'
  fi
  emitted=0
  while IFS="$US" read -r kind path rem rule count markers; do
    [ -n "$kind" ] || continue
    emit_section "$kind" "$path" "$rem" "$markers"; emitted=$((emitted+1))
  done <<<"$PART"
  [ "$emitted" = 0 ] && echo "note: nothing to scaffold — every tracked path is already covered" >&2
  exit 0
fi


# `source` returns the status of the last command above; a region whose final
# line is a legitimately-failing test must not kill the entry under set -e.
:
