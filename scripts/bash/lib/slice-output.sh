#!/usr/bin/env bash
# lib/slice-output.sh — the `slice` command's own products: oversize
# advisories for existing sections, the unique excluded roster, and the
# JSON/human emission of the partition.
# ── advisories: existing code sections that outgrew the thresholds ────────────
ADVISORIES=()
if [ "$ALL" = "0" ] && [ -n "$BLUEPRINT" ] && [ -f "$BLUEPRINT" ]; then
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    n=$(git -C "$ROOT" ls-files -- "$p" 2>/dev/null | wc -l | tr -d ' ')
    [ "$n" -gt "$MAX_FILES" ] && ADVISORIES+=("$p$US$n")
  done < <(grep -oE '<!-- blueprint:code path=[^ ]+' "$BLUEPRINT" 2>/dev/null \
             | sed -E 's/.*path=//' | LC_ALL=C sort -u)
fi

# unique excluded records, stable order
EXCL_UNIQ="$(printf '%s\n' "${EXCLUDED[@]:-}" | grep -v '^$' | LC_ALL=C sort -u || true)"

# ── output ────────────────────────────────────────────────────────────────────

if [ "$FMT" = json ]; then
  printf '{"blueprint_slice_schema":"1","command":"slice","root":"%s","config":{"max_files":%s,"min_files":%s},"scope":"%s","respect_existing":%s,"subtracted_files":%s,"sections":[' \
    "$(jesc "$ROOT")" "$MAX_FILES" "$MIN_FILES" "$(jesc "$SCOPE")" \
    "$([ "$ALL" = 0 ] && echo true || echo false)" "$SUBTRACTED"
  first=1
  while IFS="$US" read -r kind path rem rule count markers; do
    [ -n "$kind" ] || continue
    [ $first -eq 1 ] || printf ','; first=0
    printf '{"kind":"%s","path":"%s","remainder":%s,"rule":"%s","files":%s,"markers":[' \
      "$kind" "$(jesc "$path")" "$([ "$rem" = 1 ] && echo true || echo false)" "$rule" "$count"
    mfirst=1
    for m in $markers; do
      [ $mfirst -eq 1 ] || printf ','; mfirst=0
      printf '"%s"' "$(jesc "$m")"
    done
    printf ']}'
  done <<<"$PART"
  printf '],"root_files":['
  first=1
  for f in "${ROOT_FILES[@]:-}"; do
    [ -n "$f" ] || continue
    [ $first -eq 1 ] || printf ','; first=0
    printf '"%s"' "$(jesc "$f")"
  done
  printf '],"excluded":['
  first=1
  while IFS="$US" read -r path pat; do
    [ -n "$path" ] || continue
    [ $first -eq 1 ] || printf ','; first=0
    printf '{"path":"%s","pattern":"%s"}' "$(jesc "$path")" "$(jesc "$pat")"
  done <<<"$EXCL_UNIQ"
  printf '],"advisories":['
  first=1
  for a in "${ADVISORIES[@]:-}"; do
    [ -n "$a" ] || continue
    IFS="$US" read -r p n <<<"$a"
    [ $first -eq 1 ] || printf ','; first=0
    printf '{"type":"oversize","path":"%s","files":%s,"max_files":%s}' "$(jesc "$p")" "$n" "$MAX_FILES"
  done
  printf ']}\n'
  exit 0
fi

# human
echo "blueprint-slice — deterministic partition (max_files=$MAX_FILES, min_files=$MIN_FILES)"
[ -n "$SCOPE" ] && echo "  scope: $SCOPE"
[ "$ALL" = 0 ] && [ "$SUBTRACTED" -gt 0 ] && echo "  (subtracted $SUBTRACTED file(s) already covered by existing markers)"
echo
while IFS="$US" read -r kind path rem rule count markers; do
  [ -n "$kind" ] || continue
  nm=$(set -- $markers; echo $#)
  label="$path"; [ "$rem" = 1 ] && label="$path (remainder, $nm markers)"
  printf '  %-8s %-52s %6s files  [%s]\n' "$(echo "$kind" | tr a-z A-Z)" "$label" "$count" "$rule"
done <<<"$PART"
if [ "${#ROOT_FILES[@]}" -gt 0 ]; then
  echo
  echo "  root-level files (outside coverage by design): ${#ROOT_FILES[@]}"
fi
if [ -n "$EXCL_UNIQ" ]; then
  echo "  excluded:"
  while IFS="$US" read -r path pat; do
    [ -n "$path" ] || continue
    printf '    %-20s (pattern: %s)\n' "$path" "$pat"
  done <<<"$EXCL_UNIQ"
fi
for a in "${ADVISORIES[@]:-}"; do
  [ -n "$a" ] || continue
  IFS="$US" read -r p n <<<"$a"
  echo "  advisory: existing section $p now spans $n files (> max_files=$MAX_FILES) — consider splitting"
done

# `source` returns the status of the last command above; a region whose final
# line is a legitimately-failing test must not kill the entry under set -e.
:
