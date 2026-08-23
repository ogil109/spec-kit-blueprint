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
#   blueprint-slice.sh verify [--json|--human] [--root <dir>] [--blueprint <path>]
#   blueprint-slice.sh render --facts <file> [--root <dir>] [--blueprint <path>]
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
#   verify         structure-conformance check: recompute the partition and diff
#                  it against the (section, kind, marker) structure actually
#                  written in the map. The agent is INSTRUCTED to copy the
#                  partition verbatim — verify makes that a machine-checked
#                  property instead of prompt discipline: a merged, dropped,
#                  renamed, regrouped, or freehand-invented section shows up as
#                  a deterministic pair diff (exit 1). Markers owned by
#                  distilled/detailed sections are a spec's implementation
#                  footprint, outside the slicer's jurisdiction: their paths are
#                  subtracted from the recompute and ignored in the diff.
#
#   scaffold       emit the map itself, deterministically: the full template-
#                  conformant skeleton (title, how-this-works header, status
#                  TOC, every section with markers + banner + a TODO(prose)
#                  placeholder) when no blueprint exists, or just the missing
#                  additive section blocks (to append) when one does. The agent
#                  never writes structure at all — its ONLY edit is replacing
#                  the TODO(prose) placeholders — so structure cannot vary
#                  between on-ramp runs even before verify checks it. Output is
#                  byte-identical for the same repo state + config.
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
FACTS=""
CMD="${1:-slice}"; shift || true
JSON=0; HUMAN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1 ;;
    --human) HUMAN=1 ;;
    --root) ROOT="$2"; shift ;;
    --blueprint) BLUEPRINT="$2"; shift ;;
    --scope) SCOPE="${2%/}"; shift ;;
    --facts) FACTS="$2"; shift ;;
    --all) ALL=1 ;;
  esac
  shift
done
if [ "$JSON" = "1" ]; then FMT=json
elif [ "$HUMAN" = "1" ]; then FMT=human
elif [ -t 1 ]; then FMT=human
else FMT=json; fi
case "$CMD" in slice|verify|scaffold|render) ;; *) echo "unknown command: $CMD (only: slice, verify, scaffold, render)" >&2; exit 2 ;; esac

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
  # Canonical location first (matches the config default); docs/ candidates are legacy homes.
  for cand in .specify/memory/blueprint.md docs/blueprint.md docs/overview.md; do
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

US=$'\x1f'

# ── render: deterministic prose + relations from a validated FACTS file ───────
# The agent's single output is a line-based facts file; the renderer validates
# every claim (sections exist, evidence tracked and covered by the right
# section's markers, endpoints managed) and then writes BOTH the section prose
# and the relation markers from the same facts — so they cannot contradict, and
# two recovery runs are comparable by diffing facts, not prose. Format:
#   blueprint-facts 1
#   section <path>              (an existing code/context section)
#   role <role sentence(s)>
#   facet <Label> | <text> | <evidence-path>
#   neighbor <uses|crosscuts> | <to-section> | <why> | <evidence-path>
#   note <free text>            (repeatable)
#   concern <name>              (creates/replaces a context section; space-free name)
# '#' lines and blanks are ignored. Sections not named keep their current prose.
if [ "$CMD" = "render" ]; then
  [ -n "$FACTS" ] && [ -f "$FACTS" ] || { echo "render: --facts <file> required" >&2; exit 2; }
  { [ -n "$BLUEPRINT" ] && [ -f "$BLUEPRINT" ]; } || { echo "render: no blueprint found (scaffold first)" >&2; exit 1; }
  current_sha() { git -C "$ROOT" rev-parse --verify --quiet "HEAD:$1" 2>/dev/null || true; }
  # evidence may be <path> or <path>#<pattern>; a pattern makes the claim
  # FALSIFIABLE — the fixed string must be present in the file at HEAD, checked
  # here and re-checked forever by the gate (semantic rot: import removed, file
  # kept). validate_ev <who> <evidence> <jurisdiction-heading-or-empty>
  validate_ev() {
    local who="$1" ev="$2" juris="$3" evpath evpat
    evpath="${ev%%#*}"; evpat=""
    case "$ev" in *"#"*) evpat="${ev#*#}" ;; esac
    if [ -z "$(current_sha "$evpath")" ]; then err "$who evidence not tracked in git: $evpath"; return; fi
    if [ -n "$juris" ] && ! covered_by "$evpath" "$juris"; then err "$who evidence outside '$juris' markers: $evpath"; fi
    if [ -n "$evpat" ] && ! git -C "$ROOT" show "HEAD:$evpath" 2>/dev/null | grep -qF -- "$evpat"; then
      err "$who evidence pattern not found in $evpath: '$evpat'"
    fi
  }

  # map structure: managed headings, their states, and their marker paths
  MAPSTRUCT="$(awk -v US="$US" '
    /^## / { h = $0; sub(/^##[[:space:]]+/, "", h); sub(/ \(remainder\)$/, "", h); heading = h; next }
    /<!-- blueprint:section state=/ { s = $0; sub(/.*state=/, "", s); sub(/[[:space:]].*/, "", s)
                                      print "H" US s US heading; next }
    /<!-- blueprint:code path=/     { p = $0; sub(/.*path=/, "", p); sub(/[[:space:]].*/, "", p)
                                      print "M" US heading US p; next }
    /<!-- blueprint:context path=/  { p = $0; sub(/.*path=/, "", p); sub(/[[:space:]].*/, "", p)
                                      print "M" US heading US p; next }
  ' "$BLUEPRINT")"
  sec_state() { printf '%s\n' "$MAPSTRUCT" | awk -F"$US" -v h="$1" '$1=="H" && $3==h { print $2; exit }'; }
  sec_markers() { printf '%s\n' "$MAPSTRUCT" | awk -F"$US" -v h="$1" '$1=="M" && $2==h { print $3 }'; }
  covered_by() { # evidence heading → 0 if covered by one of heading's markers
    local ev="$1" h="$2" m
    while IFS= read -r m; do
      [ -n "$m" ] || continue
      case "$ev" in "$m"|"$m"/*) return 0 ;; esac
    done < <(sec_markers "$h")
    return 1
  }

  # parse facts (syntax) → records: S/C/R/F/N/T <US>-joined
  RECS="$(awk -v US="$US" '
    NR == 1 { if ($0 != "blueprint-facts 1") { print "E" US NR US "first line must be: blueprint-facts 1" }; next }
    /^[[:space:]]*(#|$)/ { next }
    /^section /  { s = $0; sub(/^section /, "", s);  print "S" US s; next }
    /^concern /  { s = $0; sub(/^concern /, "", s);  print "C" US s; next }
    /^role /     { s = $0; sub(/^role /, "", s);     print "R" US s; next }
    /^note /     { s = $0; sub(/^note /, "", s);     print "T" US s; next }
    /^facet /    { s = $0; sub(/^facet /, "", s); n = split(s, a, / \| /)
                   if (n != 3) { print "E" US NR US "facet needs: <Label> | <text> | <evidence>" }
                   else print "F" US a[1] US a[2] US a[3]; next }
    /^neighbor / { s = $0; sub(/^neighbor /, "", s); n = split(s, a, / \| /)
                   if (n != 4) { print "E" US NR US "neighbor needs: <kind> | <to> | <why> | <evidence>" }
                   else print "N" US a[1] US a[2] US a[3] US a[4]; next }
    { print "E" US NR US "unrecognized line: " $0 }
  ' "$FACTS")"

  # semantic validation + collection
  ERRS=(); CUR=""; CURKIND=""   # CURKIND: section|concern
  SECTIONS=(); CONCERNS=(); EDGES=()   # EDGES: from US kind US to US why US ev
  BLOCKS="$(mktemp)"; NEWDOC="$(mktemp)"; trap 'rm -f "$BLOCKS" "$NEWDOC"' EXIT
  err() { ERRS+=("$1"); }
  flushblock() { # emit accumulated block for CUR into BLOCKS
    [ -n "$CUR" ] || return 0
    [ -n "$CURROLE" ] || err "'$CUR': role is required"
    {
      printf '@@BEGIN%s%s\n' "$US" "$CUR"
      printf 'ROLE%s%s\n' "$US" "$CURROLE"
      printf 'KIND%s%s\n' "$US" "$CURKIND"
      printf 'STATE%s%s\n' "$US" "$CURSTATE"
      local i
      for i in "${CURFACETS[@]:-}"; do [ -n "$i" ] && printf 'FACET%s%s\n' "$US" "$i"; done
      for i in "${CURNOTES[@]:-}";  do [ -n "$i" ] && printf 'NOTE%s%s\n' "$US" "$i"; done
      printf '@@END\n'
    } >> "$BLOCKS"
  }
  newcur() { CUR="$1"; CURKIND="$2"; CURROLE=""; CURSTATE="$3"; CURFACETS=(); CURNOTES=(); }
  CURROLE=""; CURSTATE=""; CURFACETS=(); CURNOTES=()
  while IFS= read -r rec; do
    [ -n "$rec" ] || continue
    tag="${rec%%"$US"*}"; rest="${rec#*"$US"}"
    case "$tag" in
      E) err "facts line ${rest%%"$US"*}: ${rest#*"$US"}" ;;
      S) flushblock
         st="$(sec_state "$rest")"
         case "$st" in
           code|context) SECTIONS+=("$rest"); newcur "$rest" section "$st" ;;
           "") err "section '$rest' is not on the map (scaffold first; check the heading)"; newcur "$rest" section code ;;
           *)  err "section '$rest' is $st-owned — render only writes code/context sections"; newcur "$rest" section "$st" ;;
         esac ;;
      C) flushblock
         case "$rest" in
           *" "*) err "concern '$rest' must be a space-free name" ;;
           *) CONCERNS+=("$rest") ;;
         esac
         newcur "$rest" concern context ;;
      R) [ -n "$CUR" ] || { err "role before any section/concern"; continue; }
         CURROLE="$rest" ;;
      T) [ -n "$CUR" ] || { err "note before any section/concern"; continue; }
         CURNOTES+=("$rest") ;;
      F) [ -n "$CUR" ] || { err "facet before any section/concern"; continue; }
         ev="${rest##*"$US"}"
         juris=""; [ "$CURKIND" = "section" ] && juris="$CUR"
         validate_ev "'$CUR' facet" "$ev" "$juris"
         CURFACETS+=("$rest") ;;
      N) [ -n "$CUR" ] || { err "neighbor before any section/concern"; continue; }
         kind="${rest%%"$US"*}"; r2="${rest#*"$US"}"
         to="${r2%%"$US"*}"; r3="${r2#*"$US"}"
         why="${r3%%"$US"*}"; ev="${r3#*"$US"}"
         case "$kind" in uses|crosscuts) ;; *) err "'$CUR' neighbor kind must be uses|crosscuts: $kind"; continue ;; esac
         tost="$(sec_state "$to")"; tok=0
         [ -n "$tost" ] && tok=1
         for c in "${CONCERNS[@]:-}"; do [ "$c" = "$to" ] && tok=1; done
         [ "$tok" = 1 ] || err "'$CUR' neighbor endpoint not on the map: $to"
         juris=""
         if [ "$kind" = "uses" ] && [ "$CURKIND" = "section" ]; then juris="$CUR"
         elif [ "$kind" = "crosscuts" ] && [ -n "$tost" ]; then juris="$to"; fi
         validate_ev "'$CUR' $kind-edge" "$ev" "$juris"
         EDGES+=("$CUR$US$kind$US$to$US$why$US$ev") ;;
    esac
  done <<<"$RECS"
  flushblock

  if [ "${#ERRS[@]}" -gt 0 ]; then
    echo "render: ${#ERRS[@]} validation error(s) — nothing written:" >&2
    for e in "${ERRS[@]}"; do echo "  - $e" >&2; done
    exit 1
  fi

  # relations content: full-line ordinal sort, then dedupe by from|kind|to
  # keeping the first (= smallest full line) — fully deterministic, and the PS
  # port replicates it exactly.
  RELATIONS=""
  if [ "${#EDGES[@]}" -gt 0 ]; then
    RELATIONS="$(printf '%s\n' "${EDGES[@]}" | LC_ALL=C sort \
      | awk -F"$US" '!seen[$1 FS $2 FS $3]++ { print }')"
  fi

  # rewrite the doc from blocks + relations
  awk -v US="$US" -v blocks="$BLOCKS" -v rels="$RELATIONS" '
  function first_sentence(r,   i) {
    i = index(r, ". "); if (i) return substr(r, 1, i - 1)
    sub(/\.$/, "", r); return r
  }
  function render_body(h,   out, i, n, parts, lbl, txt) {
    out = "\n" role[h] ((nfacets[h] > 0) ? " At a glance:" : "") "\n"
    if (nfacets[h] > 0) {
      out = out "\n"
      for (i = 1; i <= nfacets[h]; i++) {
        n = split(facets[h, i], parts, US); lbl = parts[1]; txt = parts[2]
        out = out "- **" lbl "** — " txt "\n"
      }
    }
    if (nnotes[h] > 0) {
      out = out "\n"
      for (i = 1; i <= nnotes[h]; i++) out = out notes[h, i] "\n"
    }
    if (state[h] == "code")
      out = out "\nFor exact behavior, read the code under `" h "/`. Do not restate it here.\n"
    return out
  }
  BEGIN {
    # load blocks
    while ((getline line < blocks) > 0) {
      split(line, a, US)
      if (a[1] == "@@BEGIN")      { h = a[2]; nfacets[h] = 0; nnotes[h] = 0; known[h] = 1 }
      else if (a[1] == "ROLE")    { role[h] = a[2] }
      else if (a[1] == "KIND")    { bkind[h] = a[2] }
      else if (a[1] == "STATE")   { state[h] = a[2] }
      else if (a[1] == "FACET")   { facets[h, ++nfacets[h]] = a[2] US a[3] US a[4] }
      else if (a[1] == "NOTE")    { notes[h, ++nnotes[h]] = a[2] }
    }
    close(blocks)
    relhead = "## Architecture — subsystem relations"
    # build relations section text
    if (rels != "") {
      rtext = relhead "\n<!-- blueprint:section state=context -->\n\n"
      rtext = rtext "Rendered from the recovery facts; every edge below is machine-validated by\n"
      rtext = rtext "the check gate (endpoints on the map, evidence tracked in git).\n\n"
      rtext = rtext "| from | kind | to | why |\n|---|---|---|---|\n"
      n = split(rels, rl, "\n")
      for (i = 1; i <= n; i++) { split(rl[i], e, US)
        rtext = rtext "| " e[1] " | " e[2] " | " e[3] " | " e[4] " |\n" }
      rtext = rtext "\n"
      for (i = 1; i <= n; i++) { split(rl[i], e, US)
        rtext = rtext "<!-- blueprint:relation from=" e[1] " to=" e[3] " kind=" e[2] " evidence=" e[5] " -->\n" }
    }
    mode = "copy"
  }
  {
    line = $0
    # TOC line rewrite for known sections
    if (line ~ /^- `/) {
      p = line; sub(/^- `/, "", p); sub(/`.*$/, "", p)
      if (p in known && bkind[p] == "section") {
        rem = (line ~ / \(remainder\)/) ? " (remainder)" : ""
        status = (state[p] == "context") ? "**context**" : "**code-owned**"
        print "- `" p "`" rem " — " first_sentence(role[p]) "; " status
        next
      }
    }
    if (line ~ /^## /) {
      h = line; sub(/^##[[:space:]]+/, "", h); sub(/ \(remainder\)$/, "", h)
      if (mode == "skiprel" || mode == "skipconcern") mode = "copy"   # region ended
      if (h == relhead_name()) { if (rels != "") { printf "%s", rtext; relprinted = 1; mode = "skiprel"; next } }
      if (h in known && bkind[h] == "concern") { printf "%s", concern_block(h); mode = "skipconcern"; next }
      if (h in known && bkind[h] == "section") { print line; mode = "header"; cur = h; next }
      print line; mode = "copy"; next
    }
    if (mode == "skiprel" || mode == "skipconcern") next
    if (mode == "header") {
      if (line ~ /^<!-- blueprint:/ || line ~ /^> /) { print line; next }
      mode = "prose"   # first non-header line: swallow until ---
    }
    if (mode == "prose") {
      if (line == "---") { printf "%s", render_body(cur); print "---"; mode = "copy" }
      next
    }
    print line
  }
  function relhead_name() { return "Architecture — subsystem relations" }
  function concern_block(h,   out) {
    out = "## " h "\n<!-- blueprint:section state=context -->\n"
    out = out render_body(h)
    out = out "\n---\n\n"
    return out
  }
  END {
    # a section without a terminating --- (hand-grown map): keep its body
    if (mode == "prose") printf "%s", render_body(cur)
  }
  ' "$BLUEPRINT" > "$NEWDOC"

  # append new concern sections + relations section when they did not exist yet
  for c in "${CONCERNS[@]:-}"; do
    [ -n "$c" ] || continue
    grep -qE "^## $c( |$)" "$BLUEPRINT" || {
      awk -v US="$US" -v blocks="$BLOCKS" -v target="$c" '
        BEGIN {
          while ((getline line < blocks) > 0) {
            split(line, a, US)
            if (a[1] == "@@BEGIN") h = a[2]
            else if (h == target && a[1] == "ROLE")  role = a[2]
            else if (h == target && a[1] == "FACET") facets[++nf] = a[2] US a[3] US a[4]
            else if (h == target && a[1] == "NOTE")  notes[++nn] = a[2]
          }
          printf "## %s\n<!-- blueprint:section state=context -->\n\n%s%s\n", target, role, (nf ? " At a glance:" : "")
          if (nf) { printf "\n"; for (i = 1; i <= nf; i++) { split(facets[i], p, US); printf "- **%s** — %s\n", p[1], p[2] } }
          if (nn) { printf "\n"; for (i = 1; i <= nn; i++) print notes[i] }
          printf "\n---\n\n"
        }' >> "$NEWDOC"
    }
  done
  if [ -n "$RELATIONS" ] && ! grep -q '^## Architecture — subsystem relations$' "$BLUEPRINT"; then
    {
      printf '## Architecture — subsystem relations\n<!-- blueprint:section state=context -->\n\n'
      printf 'Rendered from the recovery facts; every edge below is machine-validated by\n'
      printf 'the check gate (endpoints on the map, evidence tracked in git).\n\n'
      printf '| from | kind | to | why |\n|---|---|---|---|\n'
      printf '%s\n' "$RELATIONS" | awk -F"$US" '{ print "| " $1 " | " $2 " | " $3 " | " $4 " |" }'
      printf '\n'
      printf '%s\n' "$RELATIONS" | awk -F"$US" '{ print "<!-- blueprint:relation from=" $1 " to=" $3 " kind=" $2 " evidence=" $5 " -->" }'
    } >> "$NEWDOC"
  fi
  mv "$NEWDOC" "$BLUEPRINT"; trap 'rm -f "$BLOCKS"' EXIT
  nrel=0; [ -n "$RELATIONS" ] && nrel=$(printf '%s\n' "$RELATIONS" | grep -c .)
  echo "rendered ${#SECTIONS[@]} section(s), ${#CONCERNS[@]} concern(s), $nrel relation(s) → ${BLUEPRINT#"$ROOT/"}"
  echo "next: restamp, then verify + check"
  exit 0
fi

# ── verify: parse the map's actual structure (state, heading, kind, marker) ───
# Headings are normalized (strip "## ", strip a " (remainder)" suffix) so the
# expected heading for a slicer-owned section is exactly its path.
DOCPAIRS=""
if [ "$CMD" = "verify" ]; then
  { [ -n "$BLUEPRINT" ] && [ -f "$BLUEPRINT" ]; } || { echo "verify: no blueprint found" >&2; exit 1; }
  DOCPAIRS="$(awk -v US="$US" '
    /^## / { h = $0; sub(/^##[[:space:]]+/, "", h); sub(/ \(remainder\)$/, "", h); heading = h; state = ""; next }
    /<!-- blueprint:section state=/ { s = $0; sub(/.*state=/, "", s); sub(/[[:space:]].*/, "", s); state = s; next }
    /<!-- blueprint:code path=/     { p = $0; sub(/.*path=/, "", p); sub(/[[:space:]].*/, "", p); print state US heading US "code" US p; next }
    /<!-- blueprint:context path=/  { p = $0; sub(/.*path=/, "", p); sub(/[[:space:]].*/, "", p); print state US heading US "context" US p; next }
  ' "$BLUEPRINT")"
fi

# ── existing coverage (markers are the record; subtracted unless --all) ───────
# verify subtracts ONLY spec-owned markers (a distilled/detailed section's
# implementation footprint) and recomputes everything else, so the diff judges
# exactly the slicer-owned structure.
covered=()
if [ "$CMD" = "verify" ]; then
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
  jesc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
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
    printf '  the cut, edit blueprint-config.yml and re-derive; blueprint-slice.sh verify\n'
    printf '  machine-checks conformance.\n-->\n\n'
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
