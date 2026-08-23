#!/usr/bin/env bash
# lib/slice-verify.sh — `verify`: diff the recomputed partition against the
# (section, kind, marker) structure actually written in the map; any deviation
# is a deterministic pair diff and exit 1. No-op unless CMD=verify; exits when
# it runs. Expects: PART, DOCPAIRS, US, jesc (lib/common-git.sh).
# ── verify: diff the computed structure against the map's actual structure ────
if [ "$CMD" = "verify" ]; then
  EXP="$(mktemp)"; ACT="$(mktemp)"
  trap 'rm -f "$FEED" "$EXP" "$ACT"' EXIT
  while IFS="$US" read -r kind path rem rule count markers; do
    [ -n "$kind" ] || continue
    for m in $markers; do printf '%s\n' "$path$US$kind$US$m"; done
  done <<<"$PART" | LC_ALL=C sort > "$EXP"
  printf '%s\n' "$DOCPAIRS" \
    | awk -F"$US" -v US="$US" '($1=="code" || $1=="context") { print $2 US $3 US $4 }' \
    | LC_ALL=C sort -u > "$ACT"
  MISSING="$(LC_ALL=C comm -23 "$EXP" "$ACT")"
  UNEXPECTED="$(LC_ALL=C comm -13 "$EXP" "$ACT")"
  ok=true; { [ -n "$MISSING" ] || [ -n "$UNEXPECTED" ]; } && ok=false
  if [ "$FMT" = json ]; then
    printf '{"blueprint_slice_schema":"1","command":"verify","blueprint":"%s","structure_ok":%s,"missing":[' \
      "$(jesc "${BLUEPRINT#"$ROOT/"}")" "$ok"
    first=1
    while IFS="$US" read -r sec kind m; do
      [ -n "$sec" ] || continue
      [ $first -eq 1 ] || printf ','; first=0
      printf '{"section":"%s","kind":"%s","marker":"%s"}' "$(jesc "$sec")" "$kind" "$(jesc "$m")"
    done <<<"$MISSING"
    printf '],"unexpected":['
    first=1
    while IFS="$US" read -r sec kind m; do
      [ -n "$sec" ] || continue
      [ $first -eq 1 ] || printf ','; first=0
      printf '{"section":"%s","kind":"%s","marker":"%s"}' "$(jesc "$sec")" "$kind" "$(jesc "$m")"
    done <<<"$UNEXPECTED"
    printf ']}\n'
  else
    echo "blueprint-slice verify — map structure vs computed partition"
    if [ "$ok" = true ]; then
      n=$(grep -c . "$EXP" || true)
      echo "  structure conforms ✓ ($n marker(s) exactly as computed)"
    else
      if [ -n "$MISSING" ]; then
        echo "  MISSING — computed by the partition, absent from the map:"
        while IFS="$US" read -r sec kind m; do
          [ -n "$sec" ] && printf '    %-8s %-40s marker: %s\n' "$kind" "$sec" "$m"
        done <<<"$MISSING"
      fi
      if [ -n "$UNEXPECTED" ]; then
        echo "  UNEXPECTED — in the map, not computed (freehand / merged / renamed):"
        while IFS="$US" read -r sec kind m; do
          [ -n "$sec" ] && printf '    %-8s %-40s marker: %s\n' "$kind" "$sec" "$m"
        done <<<"$UNEXPECTED"
      fi
      echo "  fix: restore the computed structure, or change blueprint-config.yml and re-run the slicer"
    fi
  fi
  [ "$ok" = true ] && exit 0 || exit 1
fi


# `source` returns the status of the last command above; a region whose final
# line is a legitimately-failing test must not kill the entry under set -e.
:
