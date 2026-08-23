#!/usr/bin/env bash
# lib/slice-covered.sh — what the partition must subtract: the map's parsed
# structure when the gate's structure check runs (DOCPAIRS; STRUCT=1), the
# covered-path set per command mode, and
# the HOLES that force ancestors to descend so no emitted marker can span
# covered territory. Sets: DOCPAIRS, covered[], BP_REL, HOLES.
# ── structure mode: parse the map's actual structure (state, heading, kind, marker)
# Headings are normalized (strip "## ", strip a " (remainder)" suffix) so the
# expected heading for a slicer-owned section is exactly its path.
DOCPAIRS=""
if [ "${STRUCT:-0}" = "1" ]; then
  { [ -n "$BLUEPRINT" ] && [ -f "$BLUEPRINT" ]; } || { echo "structure check: no blueprint found" >&2; exit 1; }
  DOCPAIRS="$(awk -v US="$US" '
    /^## / { h = $0; sub(/^##[[:space:]]+/, "", h); sub(/ \(remainder\)$/, "", h); heading = h; state = ""; next }
    /<!-- blueprint:section state=/ { s = $0; sub(/.*state=/, "", s); sub(/[[:space:]].*/, "", s); state = s; next }
    /<!-- blueprint:code path=/     { p = $0; sub(/.*path=/, "", p); sub(/[[:space:]].*/, "", p); print state US heading US "code" US p; next }
    /<!-- blueprint:context path=/  { p = $0; sub(/.*path=/, "", p); sub(/[[:space:]].*/, "", p); print state US heading US "context" US p; next }
  ' "$BLUEPRINT")"
fi

# ── existing coverage (markers are the record; subtracted unless --all) ───────
# structure mode subtracts ONLY spec-owned markers (a distilled/detailed section's
# implementation footprint) and recomputes everything else, so the diff judges
# exactly the slicer-owned structure.
covered=()
if [ "${STRUCT:-0}" = "1" ]; then
  while IFS= read -r p; do [ -n "$p" ] && covered+=("$p"); done < <(
    printf '%s\n' "$DOCPAIRS" \
      | awk -F"$US" '($1=="distilled" || $1=="detailed") && $3=="code" { print $4 }' \
      | LC_ALL=C sort -u)
elif [ "$ALL" = "0" ] && [ -n "$BLUEPRINT" ] && [ -f "$BLUEPRINT" ]; then
  while IFS= read -r p; do [ -n "$p" ] && covered+=("$p"); done < <(
    grep -oE '<!-- blueprint:(code|context) path=[^ ]+' "$BLUEPRINT" 2>/dev/null \
      | sed -E 's/.*path=//' | LC_ALL=C sort -u)
fi

excl=(); while IFS= read -r g; do [ -n "$g" ] && excl+=("$g"); done <<<"$EXCLUDES"
BP_REL=""; [ -n "$BLUEPRINT" ] && BP_REL="${BLUEPRINT#"$ROOT/"}"

# Subtracted (covered) paths are passed to the partitioner as HOLES: their
# ancestors are forced to descend, so an emitted tree marker can never span
# covered territory. Without this, removing a covered child can shrink its
# parent under max_files and the parent is emitted WHOLE — a marker overlapping
# paths another section (or a spec) already owns.
HOLES="$(printf '%s\n' "${covered[@]:-}" | grep -v '^$' | tr '\n' '\037' || true)"


# `source` returns the status of the last command above; a region whose final
# line is a legitimately-failing test must not kill the entry under set -e.
:
