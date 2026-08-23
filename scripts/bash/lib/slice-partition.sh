#!/usr/bin/env bash
# lib/slice-partition.sh — the deterministic partitioner: the bash-side file
# filter (excludes, root files, subtraction, scope) feeding the POSIX-awk
# partition (pinned/module/fits/descend+remainder/flat). Sets: PART,
# ROOT_FILES[], EXCLUDED[], SUBTRACTED.
# ── the file stream: filter in bash (globs), partition in awk (deterministic) ─
ROOT_FILES=()      # root-level loose files: reported, never partitioned
EXCLUDED=()        # "path<US>pattern" — what the excludes consciously removed
SUBTRACTED=0       # files already covered by existing markers

FEED="$(mktemp)"; trap 'rm -f "$FEED"' EXIT
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in
    *" "*) EXCLUDED+=("$f${US}unsupported-space"); continue ;;  # markers cannot encode spaces
    */*) ;;
    *) ROOT_FILES+=("$f"); continue ;;
  esac
  [ "$f" = "$BP_REL" ] && continue
  first="${f%%/*}"
  skip=0
  for g in "${excl[@]:-}"; do
    [ -n "$g" ] || continue
    case "$g" in
      */*) case "$f" in $g|$g/*) EXCLUDED+=("${g%%/*}$US$g"); skip=1; break ;; esac ;;
      *)   case "$first" in $g) EXCLUDED+=("$first$US$g"); skip=1; break ;; esac ;;
    esac
  done
  [ "$skip" = 1 ] && continue
  for p in "${covered[@]:-}"; do
    [ -n "$p" ] || continue
    case "$f" in "$p"|"$p"/*) SUBTRACTED=$((SUBTRACTED+1)); skip=1; break ;; esac
  done
  [ "$skip" = 1 ] && continue
  if [ -n "$SCOPE" ]; then case "$f" in "$SCOPE"/*) ;; *) continue ;; esac; fi
  printf '%s\n' "$f"
done < <(git -C "$ROOT" ls-files 2>/dev/null | LC_ALL=C sort) > "$FEED"

# ── partition (POSIX awk; input is sorted, so every emitted order is, too) ────
# Rules, in order, per directory d with tracked-subtree count n:
#   pinned    — d is in slice.pin_dirs: one atomic section regardless of size;
#               ancestors split down to reach it.
#   module    — a boundary file sits at d's root and n <= max_files: d is a
#               section regardless of min_files (a small module stays whole).
#   fits      — n <= max_files and no boundary file or pin deeper inside: one
#               section.
#   descend   — n > max_files, or a nested boundary/pin forces the split:
#               each child with a boundary, a nested boundary/pin, a pin, or
#               >= min_files partitions recursively; smaller children and d's
#               direct files fold into one REMAINDER section carrying one
#               marker per path (a section is a SET of paths — tree markers
#               for dirs, blob markers for files — so no marker ever covers a
#               child section).
#   flat      — n > max_files but there is nothing to descend into (one flat
#               directory of files): emitted whole; thresholds cannot split
#               what has no subdirectories.
PART="$(awk -v max="$MAX_FILES" -v min="$MIN_FILES" -v scope="$SCOPE" \
        -v bound="$(printf '%s' "$BOUNDARY" | tr '\n' '\037')" \
        -v ctx="$(printf '%s' "$CONTEXT_DIRS" | tr '\n' '\037')" \
        -v pins="$(printf '%s' "$PIN_DIRS" | tr '\n' '\037')" \
        -v holes="$HOLES" '
BEGIN {
  US = sprintf("%c", 31)
  nb = split(bound, ba, US); for (i = 1; i <= nb; i++) if (ba[i] != "") bset[ba[i]] = 1
  nc = split(ctx, ca, US);   for (i = 1; i <= nc; i++) if (ca[i] != "") cset[ca[i]] = 1
  np = split(pins, pa, US)
  for (i = 1; i <= np; i++) if (pa[i] != "") {
    pset[pa[i]] = 1
    m = split(pa[i], pp, "/"); q = ""
    for (j = 1; j < m; j++) { q = (q == "" ? pp[j] : q "/" pp[j]); pnested[q] = 1 }
  }
  # holes: proper ancestors of every subtracted (covered) path must descend so
  # no emitted tree marker spans covered territory. A hole itself holds no
  # remaining files, so partition() never visits it.
  nh = split(holes, ha, US)
  for (i = 1; i <= nh; i++) if (ha[i] != "") {
    m = split(ha[i], hp, "/"); q = ""
    for (j = 1; j < m; j++) { q = (q == "" ? hp[j] : q "/" hp[j]); hnested[q] = 1 }
  }
}
{
  f = $0
  n = split(f, parts, "/")
  path = ""
  for (i = 1; i < n; i++) {
    parent = path
    path = (path == "" ? parts[i] : path "/" parts[i])
    if (!(path in seen)) {
      seen[path] = 1
      if (parent == "") tops[++ntop] = path
      else childdirs[parent] = (childdirs[parent] == "" ? path : childdirs[parent] US path)
    }
    cnt[path]++
  }
  dir = (n > 1) ? substr(f, 1, length(f) - length(parts[n]) - 1) : ""
  dfiles[dir] = (dfiles[dir] == "" ? f : dfiles[dir] US f)
  if (parts[n] in bset && dir != "") {
    boundary_at[dir] = 1
    p = ""
    for (i = 1; i < n - 1; i++) { p = (p == "" ? parts[i] : p "/" parts[i]); nested[p] = 1 }
  }
}
END {
  if (scope != "") { if (scope in seen) partition(scope); exit }
  for (t = 1; t <= ntop; t++) {
    d = tops[t]
    if (d in cset) print "context" US d US "0" US "context-dir" US cnt[d] US d
    else partition(d)
  }
}
function partition(d,   n, mod, kids, nk, i, c, remm, remc, dfl, nfl) {
  n = cnt[d]; mod = (d in boundary_at)
  # a hole beneath d (hnested) vetoes every whole-tree emit — including a pin:
  # correctness (no marker spanning covered/spec-owned paths) beats pin intent.
  if ((d in pset) && !(d in hnested))     { print "code" US d US "0" US "pinned" US n US d; return }
  if (mod && n <= max && !(d in pnested) && !(d in hnested)) \
                                          { print "code" US d US "0" US "module" US n US d; return }
  if (!mod && !(d in nested) && !(d in pnested) && !(d in hnested) && n <= max) \
                                          { print "code" US d US "0" US "fits"   US n US d; return }
  nk = split(childdirs[d], kids, US)
  if (nk == 0 && n > max && !(d in hnested)) \
                                          { print "code" US d US "0" US "flat"   US n US d; return }
  remm = ""; remc = 0
  for (i = 1; i <= nk; i++) {
    c = kids[i]
    if ((c in pset) || (c in pnested) || (c in boundary_at) || (c in nested) || (c in hnested) || cnt[c] >= min) partition(c)
    else { remm = (remm == "" ? c : remm " " c); remc += cnt[c] }
  }
  nfl = split(dfiles[d], dfl, US)
  for (i = 1; i <= nfl; i++) { remm = (remm == "" ? dfl[i] : remm " " dfl[i]); remc++ }
  if (remm != "") print "code" US d US "1" US "remainder" US remc US remm
}' "$FEED")"


# `source` returns the status of the last command above; a region whose final
# line is a legitimately-failing test must not kill the entry under set -e.
:
