#!/usr/bin/env bash
# blueprint-slice — the deterministic brownfield partitioner (the on-ramp oracle).
#
# Computes the code-owned SECTION SET for a blueprint purely from `git ls-files`
# plus checked-in config: same repo state + same config => byte-identical output.
# The agent authoring an on-ramp consumes this partition — it writes each
# section's prose, but it does not choose, merge, drop, or resize the sections.
# That split (deterministic enumeration first, subjective interpretation second)
# is what makes two independent on-ramp runs land on the same map structure.
#
# Language-agnostic by construction: the only evidence consumed is path names,
# tracked-file counts, and the *presence* of build-manifest filenames
# (boundary_files) — no file is ever opened or parsed.
#
# Usage:
#   blueprint-slice.sh [slice] [--json|--human]
#     [--root <dir>] [--blueprint <path>] [--scope <dir>] [--all]
#
#   --scope <dir>  partition just this directory (the `init --from-code <dir>`
#                  partial on-ramp). Determinism makes the result a subset of
#                  the full partition.
#   --all          ignore existing blueprint markers (pure-function view).
#                  Default: paths already covered by code/context markers are
#                  subtracted, so re-running proposes only ADDITIVE sections and
#                  never silently repartitions an existing map; existing code
#                  sections that now exceed max_files surface as advisories.
#
# Config (blueprint-config.yml — the checked-in record of every human override;
# see config-template.yml for semantics and defaults):
#   slice.max_files, slice.min_files, slice.boundary_files[], slice.context_dirs[]
#   coverage.exclude[]
set -euo pipefail

ROOT=""
BLUEPRINT=""
SCOPE=""
ALL=0
CMD="${1:-slice}"; shift || true
JSON=0; HUMAN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1 ;;
    --human) HUMAN=1 ;;
    --root) ROOT="$2"; shift ;;
    --blueprint) BLUEPRINT="$2"; shift ;;
    --scope) SCOPE="${2%/}"; shift ;;
    --all) ALL=1 ;;
  esac
  shift
done
if [ "$JSON" = "1" ]; then FMT=json
elif [ "$HUMAN" = "1" ]; then FMT=human
elif [ -t 1 ]; then FMT=human
else FMT=json; fi
[ "$CMD" = "slice" ] || { echo "unknown command: $CMD (only: slice)" >&2; exit 2; }

# ── locate repo root (same rule as the state oracle) ──────────────────────────
if [ -z "$ROOT" ]; then
  d="$(pwd)"
  while [ "$d" != "/" ]; do
    [ -d "$d/.specify" ] && ROOT="$d" && break
    d="$(dirname "$d")"
  done
  [ -z "$ROOT" ] && ROOT="$(pwd)"
fi
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repository: $ROOT" >&2; exit 1; }

CFG="$ROOT/.specify/extensions/blueprint-index/blueprint-config.yml"

# ── locate the blueprint doc (optional here; used for subtraction + exclusion) ─
if [ -z "$BLUEPRINT" ] && [ -f "$CFG" ]; then
  p=$(grep -E '^[[:space:]]*path:' "$CFG" | head -1 | sed -E 's/^[[:space:]]*path:[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/' || true)
  [ -n "$p" ] && [ -f "$ROOT/$p" ] && BLUEPRINT="$ROOT/$p"
fi
if [ -z "$BLUEPRINT" ] || [ ! -f "$BLUEPRINT" ]; then
  for cand in docs/blueprint.md docs/overview.md .specify/memory/blueprint.md; do
    [ -f "$ROOT/$cand" ] && BLUEPRINT="$ROOT/$cand" && break
  done
fi

# ── config (YAML subset: two levels, scalars + string lists) ──────────────────
cfg_val() { # <top> <key> → scalar value (empty if absent)
  [ -f "$CFG" ] || return 0
  awk -v top="$1" -v key="$2" '
    /^[^[:space:]#]/ { in_top = ($0 ~ "^" top ":[[:space:]]*$") }
    in_top && $0 ~ "^[[:space:]]+" key ":" {
      sub("^[[:space:]]+" key ":[[:space:]]*", ""); sub(/[[:space:]]+#.*$/, "")
      gsub(/"/, ""); print; exit
    }' "$CFG"
}
cfg_list() { # <top> <key> → list items, one per line (empty if absent)
  [ -f "$CFG" ] || return 0
  awk -v top="$1" -v key="$2" '
    /^[^[:space:]#]/ { in_top = ($0 ~ "^" top ":[[:space:]]*$"); in_list = 0 }
    in_top && $0 ~ "^[[:space:]]+" key ":[[:space:]]*$" { in_list = 1; next }
    in_top && in_list {
      if ($0 ~ /^[[:space:]]+-[[:space:]]+/) {
        sub(/^[[:space:]]+-[[:space:]]+/, ""); sub(/[[:space:]]+#.*$/, ""); gsub(/"/, ""); print
      } else if ($0 ~ /^[[:space:]]*(#|$)/) { } else { in_list = 0 }
    }' "$CFG"
}

MAX_FILES="$(cfg_val slice max_files)"; MAX_FILES="${MAX_FILES:-400}"
MIN_FILES="$(cfg_val slice min_files)"; MIN_FILES="${MIN_FILES:-3}"
BOUNDARY="$(cfg_list slice boundary_files)"
[ -z "$BOUNDARY" ] && BOUNDARY="pyproject.toml
setup.py
package.json
Cargo.toml
go.mod
pom.xml
build.gradle
CMakeLists.txt
composer.json
Gemfile"
CONTEXT_DIRS="$(cfg_list slice context_dirs)"
[ -z "$CONTEXT_DIRS" ] && CONTEXT_DIRS="docs
doc
documentation"
PIN_DIRS="$(cfg_list slice pin_dirs | sed 's|/$||')"
EXCLUDES="$(cfg_list coverage exclude)"
[ -z "$EXCLUDES" ] && EXCLUDES=".*
specs"

# ── existing coverage (markers are the record; subtracted unless --all) ───────
covered=()
if [ "$ALL" = "0" ] && [ -n "$BLUEPRINT" ] && [ -f "$BLUEPRINT" ]; then
  while IFS= read -r p; do [ -n "$p" ] && covered+=("$p"); done < <(
    grep -oE '<!-- blueprint:(code|context) path=[^ ]+' "$BLUEPRINT" 2>/dev/null \
      | sed -E 's/.*path=//' | LC_ALL=C sort -u)
fi

excl=(); while IFS= read -r g; do [ -n "$g" ] && excl+=("$g"); done <<<"$EXCLUDES"
BP_REL=""; [ -n "$BLUEPRINT" ] && BP_REL="${BLUEPRINT#"$ROOT/"}"

# ── the file stream: filter in bash (globs), partition in awk (deterministic) ─
US=$'\x1f'
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
        -v pins="$(printf '%s' "$PIN_DIRS" | tr '\n' '\037')" '
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
  if (d in pset)                          { print "code" US d US "0" US "pinned" US n US d; return }
  if (mod && n <= max && !(d in pnested)) { print "code" US d US "0" US "module" US n US d; return }
  if (!mod && !(d in nested) && !(d in pnested) && n <= max) \
                                          { print "code" US d US "0" US "fits"   US n US d; return }
  nk = split(childdirs[d], kids, US)
  if (nk == 0 && n > max)                 { print "code" US d US "0" US "flat"   US n US d; return }
  remm = ""; remc = 0
  for (i = 1; i <= nk; i++) {
    c = kids[i]
    if ((c in pset) || (c in pnested) || (c in boundary_at) || (c in nested) || cnt[c] >= min) partition(c)
    else { remm = (remm == "" ? c : remm " " c); remc += cnt[c] }
  }
  nfl = split(dfiles[d], dfl, US)
  for (i = 1; i <= nfl; i++) { remm = (remm == "" ? dfl[i] : remm " " dfl[i]); remc++ }
  if (remm != "") print "code" US d US "1" US "remainder" US remc US remm
}' "$FEED")"

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
jesc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

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
