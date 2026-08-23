#!/usr/bin/env bash
# lib/slice-render.sh — `render`: parse + validate a facts file (every claim
# machine-checked: sections exist, evidence tracked and under the right
# markers, #patterns present at HEAD, endpoints managed, no duplicates), then
# write section prose, TOC entries, and the merged relations home from one
# validated source. No-op unless CMD=render; exits when it runs.
# Expects: ROOT, BLUEPRINT, FACTS, US, current_sha (lib/common-git.sh).
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
# '#' lines and blanks are ignored. Sections not named keep their current prose.
if [ "$CMD" = "render" ]; then
  [ -n "$FACTS" ] && [ -f "$FACTS" ] || { echo "render: --facts <file> required" >&2; exit 2; }
  { [ -n "$BLUEPRINT" ] && [ -f "$BLUEPRINT" ]; } || { echo "render: no blueprint found (scaffold first)" >&2; exit 1; }
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
    # no `grep -q`: early exit SIGPIPEs `git show` on files larger than a pipe
    # buffer, and pipefail then reports a FOUND pattern as missing. Let grep
    # consume its whole input; the pipeline status is then grep's own 0/1.
    if [ -n "$evpat" ] && ! git -C "$ROOT" show "HEAD:$evpath" 2>/dev/null | grep -F -- "$evpat" >/dev/null; then
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
    /^concern /  { print "E" US NR US "the concern directive was removed — model cross-cutting facilities as sections with crosscuts edges"; next }
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
  ERRS=(); CUR=""
  SECTIONS=(); EDGES=()   # EDGES: from US kind US to US why US ev
  BLOCKS="$(mktemp)"; NEWDOC="$(mktemp)"; trap 'rm -f "$BLOCKS" "$NEWDOC"' EXIT
  err() { ERRS+=("$1"); }
  flushblock() { # emit accumulated block for CUR into BLOCKS
    [ -n "$CUR" ] || return 0
    [ -n "$CURROLE" ] || err "'$CUR': role is required"
    {
      printf '@@BEGIN%s%s\n' "$US" "$CUR"
      printf 'ROLE%s%s\n' "$US" "$CURROLE"
      printf 'STATE%s%s\n' "$US" "$CURSTATE"
      local i
      for i in "${CURFACETS[@]:-}"; do [ -n "$i" ] && printf 'FACET%s%s\n' "$US" "$i"; done
      for i in "${CURNOTES[@]:-}";  do [ -n "$i" ] && printf 'NOTE%s%s\n' "$US" "$i"; done
      printf '@@END\n'
    } >> "$BLOCKS"
  }
  newcur() { CUR="$1"; CURROLE=""; CURSTATE="$2"; CURFACETS=(); CURNOTES=(); }
  CURROLE=""; CURSTATE=""; CURFACETS=(); CURNOTES=()
  while IFS= read -r rec; do
    [ -n "$rec" ] || continue
    tag="${rec%%"$US"*}"; rest="${rec#*"$US"}"
    case "$tag" in
      E) err "facts line ${rest%%"$US"*}: ${rest#*"$US"}" ;;
      S) flushblock
         dup=0; for x in "${SECTIONS[@]:-}"; do [ "$x" = "$rest" ] && dup=1; done
         [ "$dup" = 1 ] && err "duplicate block for '$rest' — a facts file declares each section once"
         st="$(sec_state "$rest")"
         case "$st" in
           code|context) SECTIONS+=("$rest"); newcur "$rest" "$st" ;;
           "") err "section '$rest' is not on the map (scaffold first; check the heading)"; newcur "$rest" code ;;
           *)  err "section '$rest' is $st-owned — render only writes code/context sections"; newcur "$rest" "$st" ;;
         esac ;;
      R) [ -n "$CUR" ] || { err "role before any section"; continue; }
         CURROLE="$rest" ;;
      T) [ -n "$CUR" ] || { err "note before any section"; continue; }
         CURNOTES+=("$rest") ;;
      F) [ -n "$CUR" ] || { err "facet before any section"; continue; }
         ev="${rest##*"$US"}"
         validate_ev "'$CUR' facet" "$ev" "$CUR"
         CURFACETS+=("$rest") ;;
      N) [ -n "$CUR" ] || { err "neighbor before any section"; continue; }
         kind="${rest%%"$US"*}"; r2="${rest#*"$US"}"
         to="${r2%%"$US"*}"; r3="${r2#*"$US"}"
         why="${r3%%"$US"*}"; ev="${r3#*"$US"}"
         case "$kind" in uses|crosscuts) ;; *) err "'$CUR' neighbor kind must be uses|crosscuts: $kind"; continue ;; esac
         tost="$(sec_state "$to")"
         [ -n "$tost" ] || err "'$CUR' neighbor endpoint not on the map: $to"
         juris="$CUR"
         if [ "$kind" = "crosscuts" ]; then juris="$to"; [ -z "$tost" ] && juris=""; fi
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

  # Edge repair is per-block and INTERNAL: a facts block is authoritative for
  # its section's outgoing edges; edges from sections not named in the facts
  # are preserved by round-tripping the machine-written relations home (markers
  # give from/kind/to/evidence, the table row gives the why — render is the
  # only writer of that section, so its own format is a reliable source).
  # Preserved edges whose endpoints left the map are dropped (the gate would
  # only ever flag them; repair cannot re-assert a section that is gone).
  OWNED="$US"
  for s in "${SECTIONS[@]:-}"; do [ -n "$s" ] && OWNED="$OWNED$s$US"; done
  DROPPED=0
  while IFS= read -r ex; do
    [ -n "$ex" ] || continue
    exfrom="${ex%%"$US"*}"; exrest="${ex#*"$US"}"
    exkind="${exrest%%"$US"*}"; exrest2="${exrest#*"$US"}"
    exto="${exrest2%%"$US"*}"
    case "$OWNED" in *"$US$exfrom$US"*) continue ;; esac        # facts own this from-section
    tost1="$(sec_state "$exfrom")"; tost2="$(sec_state "$exto")"
    { [ -n "$tost1" ] && [ -n "$tost2" ]; } || { DROPPED=$((DROPPED+1)); continue; }
    EDGES+=("$ex")
  done < <(awk -v US="$US" '
    /^## / { inrel = ($0 == "## Architecture — subsystem relations"); next }
    inrel && /^\| / && $0 !~ /^\| from \|/ && $0 !~ /^\|---/ {
      row = $0; sub(/^\| /, "", row); sub(/ \|$/, "", row)
      n = split(row, f, / \| /)
      if (n == 4) why[f[1] US f[2] US f[3]] = f[4]
      next
    }
    inrel && /<!-- blueprint:relation / {
      m = $0
      sub(/.*from=/, "", m); from = m; sub(/ .*/, "", from)
      m = $0; sub(/.*to=/, "", m); to = m; sub(/ .*/, "", to)
      m = $0; sub(/.*kind=/, "", m); kind = m; sub(/ .*/, "", kind)
      m = $0; sub(/.*evidence=/, "", m); ev = m; sub(/ .*/, "", ev)
      print from US kind US to US why[from US kind US to] US ev
    }
  ' "$BLUEPRINT")

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
    nkn = 0
    while ((getline line < blocks) > 0) {
      split(line, a, US)
      if (a[1] == "@@BEGIN")      { h = a[2]; nfacets[h] = 0; nnotes[h] = 0; known[h] = 1; kn[++nkn] = h }
      else if (a[1] == "ROLE")    { role[h] = a[2] }
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
      toc_seen = 1; toc_present[p] = 1
      if (p in known) {
        rem = (line ~ / \(remainder\)/) ? " (remainder)" : ""
        status = (state[p] == "context") ? "**context**" : "**code-owned**"
        print "- `" p "`" rem " — " first_sentence(role[p]) "; " status
        next
      }
    }
    # the map indexes itself: a facts block with no TOC entry (a section
    # re-onboarded additively) is appended to the
    # TOC when the entry list ends — otherwise the index silently drifts from
    # the content it indexes.
    if (in_toc && toc_seen && !toc_flushed && line ~ /^[[:space:]]*$/) {
      for (i = 1; i <= nkn; i++) {
        p = kn[i]
        if (!(p in toc_present)) {
          status = (state[p] == "context") ? "**context**" : "**code-owned**"
          print "- `" p "` — " first_sentence(role[p]) "; " status
        }
      }
      toc_flushed = 1
    }
    if (line ~ /^## /) {
      in_toc = ($0 == "## Table of Contents")
      h = line; sub(/^##[[:space:]]+/, "", h); sub(/ \(remainder\)$/, "", h)
      if (mode == "skiprel") mode = "copy"   # region ended
      if (h == relhead_name()) { if (rels != "") { printf "%s", rtext; mode = "skiprel"; next } }
      if (h in known) { print line; mode = "header"; cur = h; next }
      print line; mode = "copy"; next
    }
    if (mode == "skiprel") next
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
  END {
    # a section without a terminating --- (hand-grown map): keep its body
    if (mode == "prose") printf "%s", render_body(cur)
  }
  ' "$BLUEPRINT" > "$NEWDOC"

  # append the relations section when it did not exist yet
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
  dropnote=""; [ "$DROPPED" -gt 0 ] && dropnote=" (dropped $DROPPED dangling edge(s))"
  echo "rendered ${#SECTIONS[@]} section(s), $nrel relation(s)$dropnote → ${BLUEPRINT#"$ROOT/"}"
  echo "next: restamp, then verify + check"
  exit 0
fi


# `source` returns the status of the last command above; a region whose final
# line is a legitimately-failing test must not kill the entry under set -e.
:
