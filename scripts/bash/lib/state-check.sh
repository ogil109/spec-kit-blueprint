#!/usr/bin/env bash
# lib/state-check.sh — the tiered coherence gate (`check`): HARD contradictions
# block, SOFT drift advises; coverage spans all top-level dirs; stage-2 relation
# markers are validated (endpoints, evidence, #pattern presence). Exits.
# Expects: everything state-frontier.sh sets, plus FMT/STRICT.
# ── check: tiered blueprint coherence gate (CI-friendly) ──────────────────────
# HARD (blocks merge): the map factually CONTRADICTS reality — a built spec the map
#   doesn't index (drift), or a section pointing at code that's been deleted
#   (dangling). These are precise / low-false-positive.
# SOFT (advisory, does NOT block unless --strict): the map MIGHT be behind — code
#   changed under a mapped area (stale), a section not yet processed (unmanaged), or
#   no baseline yet (unstamped). These are coarse; most are still-true at map altitude,
#   so blocking every code change here is the friction teams reject. Reconcile with
#   remap/init instead. `--strict` promotes soft → blocking for teams that want it.
if [ "$CMD" = "check" ]; then
  # Issue records are US-delimited (see lib/common-git.sh): tab is IFS whitespace
  # and once collapsed the empty target of an `unmanaged` issue, shifting fields.
  ISSUES=()   # each record: severity \x1f type \x1f target \x1f detail \x1f remedy_run \x1f remedy_kind
  add() { ISSUES+=("$1$US$2$US$3$US$4$US$5$US$6"); }

  [ "$UNMANAGED_COUNT" -gt 0 ] && \
    add soft unmanaged "" "${UNMANAGED_COUNT} section(s) not processed by the extension" "/speckit.blueprint-index.init" authored
  if [ "${#DISTILL_DRIFT[@]}" -gt 0 ]; then
    for s in "${DISTILL_DRIFT[@]}"; do
      add hard drift "$s" "built spec not in the map" "/speckit.blueprint-index.distill $s" authored
    done
  fi
  if is_git; then
    while IFS= read -r m; do
      [ -n "$m" ] || continue
      p="$(marker_path "$m")"; s="$(marker_sha "$m")"; cur="$(current_sha "$p")"
      if [ -z "$cur" ]; then
        add hard dangling "$p" "map points at code that no longer exists" "/speckit.blueprint-index.remap $p" authored
      elif [ "$s" = "NONE" ]; then
        add soft unstamped "$p" "no git baseline recorded yet" "blueprint-state.sh restamp --path $p" deterministic
      elif [ "$cur" != "$s" ]; then
        # abbreviate like git: a full 40-char pair is unreadable in a CI log line
        add soft stale "$p" "code changed since mapped (${s:0:8} -> ${cur:0:8})" "/speckit.blueprint-index.remap $p" authored
      fi
    done < <(code_markers)

    # unmapped code (coverage): every tracked file must be covered by a code
    # section, a context section, or an exclude pattern. The scan spans ALL
    # top-level directories — deriving the scan roots from already-mapped paths
    # (as before) meant a directory the on-ramp never touched could stay
    # invisible forever, reading as "clean" while whole trees (tests/, infra/)
    # were silently unmapped. Reported at the shallowest uncovered directory.
    # Root-level loose files (manifests, READMEs) are outside coverage by
    # design; the blueprint doc itself is always excluded. Only runs when a
    # blueprint exists — with no map at all, the actionable signal is "run
    # init", not one unmapped issue per directory.
    # SOFT — a new module may be intentional WIP.
    if [ -f "$BLUEPRINT" ]; then
    covered=(); while IFS= read -r mk; do [ -n "$mk" ] && covered+=("$(marker_path "$mk")"); done < <(code_markers; context_markers)
    excl=(); while IFS= read -r g; do [ -n "$g" ] && excl+=("$g"); done < <(cov_excludes)
    bp_rel="${BLUEPRINT#"$ROOT/"}"
    uncovered=$(git -C "$ROOT" ls-files 2>/dev/null | while IFS= read -r f; do
      case "$f" in */*) ;; *) continue ;; esac                 # root-level loose file
      [ "$f" = "$bp_rel" ] && continue                          # the map itself
      skip=0; first="${f%%/*}"
      for g in "${excl[@]:-}"; do
        [ -n "$g" ] || continue
        case "$g" in
          */*) case "$f" in $g|$g/*) skip=1; break ;; esac ;;
          *)   case "$first" in $g) skip=1; break ;; esac ;;
        esac
      done
      [ "$skip" = 1 ] && continue
      for p in "${covered[@]:-}"; do case "$f" in "$p"|"$p"/*) skip=1; break;; esac; done   # covered file
      [ "$skip" = 1 ] && continue
      d=$(dirname "$f")
      for p in "${covered[@]:-}"; do case "$p" in "$d"|"$d"/*) skip=1; break;; esac; done     # covered-parent dir
      [ "$skip" = 1 ] || echo "$d"
    done | sort -u)
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      keep=1
      while IFS= read -r o; do
        [ -n "$o" ] && [ "$o" != "$d" ] && case "$d" in "$o"/*) keep=0 ;; esac
      done <<<"$uncovered"
      [ "$keep" = 1 ] && add soft unmapped "$d" "tracked code no section maps" "/speckit.blueprint-index.init --from-code $d" authored
    done <<<"$uncovered"
    fi
  else
    echo "note: not a git repository — code-staleness/coverage checks skipped" >&2
  fi

  # relations (stage-2 architecture): validate the checkable half of every
  # agent-authored edge — both endpoints are managed sections on the map, and
  # the evidence path still exists in git. SOFT: a broken edge means the
  # recovered architecture is behind reality; the remedy re-runs the recovery
  # agent, which repairs (re-anchors/removes) rather than rewrites.
  if [ -f "$BLUEPRINT" ]; then
    sec_ids="$(awk '
      /^## / { h = $0; sub(/^##[[:space:]]+/, "", h); sub(/ \(remainder\)$/, "", h); heading = h; next }
      /<!-- blueprint:section/ { if (heading != "") print heading; heading = "" }
    ' "$BLUEPRINT")"
    while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      rfrom="$(echo "$rel" | sed -E 's/.*from=([^ ]+).*/\1/')"
      rto="$(echo "$rel" | sed -E 's/.*to=([^ ]+).*/\1/')"
      rev_="$(echo "$rel" | sed -E 's/.*evidence=([^ ]+).*/\1/')"
      revpath="${rev_%%#*}"; revpat=""
      case "$rev_" in *"#"*) revpat="${rev_#*#}" ;; esac
      for ep in "$rfrom" "$rto"; do
        printf '%s\n' "$sec_ids" | grep -qxF "$ep" || \
          add soft relation "$rfrom->$rto" "relation endpoint not on the map: $ep" "/speckit.blueprint-index.recover" authored
      done
      if is_git; then
        if [ -z "$(current_sha "$revpath")" ]; then
          add soft relation-evidence "$rfrom->$rto" "relation evidence path gone: $revpath" "/speckit.blueprint-index.recover" authored
        elif [ -n "$revpat" ] && ! git -C "$ROOT" show "HEAD:$revpath" 2>/dev/null | grep -F -- "$revpat" >/dev/null; then
          # (no `grep -q`: early exit SIGPIPEs git show on big files under pipefail)
          # the file survived but the demonstrating content did not — semantic rot
          add soft relation-evidence "$rfrom->$rto" "evidence no longer demonstrates the edge: '$revpat' not in $revpath" "/speckit.blueprint-index.recover" authored
        fi
      fi
    done < <(relation_markers)
  fi

  # structure (the folded conformance check, decision D2): for every heading
  # that is BOTH a computed section path and a code/context section in the doc,
  # the marker sets must match — a marker moved between sections (a merge) is
  # invisible to coverage because the files stay covered; this is the signal
  # that catches it. Headings that are not computed paths (hand-authored maps)
  # are never judged. SOFT: reconcile via scaffold/render or config.
  if [ -f "$BLUEPRINT" ] && [ -n "${PART:-}" ]; then
    STRUCT_DIFF="$(
      {
        while IFS="$US" read -r kind path rem rule count markers; do
          [ -n "$kind" ] || continue
          for m in $markers; do printf 'C%s%s%s%s\n' "$US" "$path" "$US" "$m"; done
        done <<<"$PART"
        printf '%s\n' "$DOCPAIRS" | awk -F"$US" -v US="$US" '($1=="code" || $1=="context") { print "D" US $2 US $4 }'
      } | LC_ALL=C sort | awk -F"$US" -v US="$US" '
        { key = $2 US $3; side = $1
          if (side == "C") { comp[key] = 1; chead[$2] = 1 }
          else             { doc[key] = 1;  dhead[$2] = 1 } }
        END {
          for (k in comp) { split(k, a, US)
            if ((a[1] in dhead) && !(k in doc)) print "missing" US a[1] US a[2] }
          for (k in doc)  { split(k, a, US)
            if ((a[1] in chead) && !(k in comp)) print "extra" US a[1] US a[2] }
        }' | LC_ALL=C sort)"
    while IFS="$US" read -r what sec mk; do
      [ -n "$what" ] || continue
      if [ "$what" = "missing" ]; then
        add soft structure "$sec" "computed marker absent from the section: $mk" "/speckit.blueprint-index.init --from-code $sec" authored
      else
        add soft structure "$sec" "marker not computed for this section (moved/freehand): $mk" "/speckit.blueprint-index.init --from-code $sec" authored
      fi
    done <<<"$STRUCT_DIFF"
  fi

  hard_n=0; soft_n=0
  for rec in "${ISSUES[@]:-}"; do [ -n "$rec" ] || continue
    case "$rec" in hard*) hard_n=$((hard_n+1)) ;; soft*) soft_n=$((soft_n+1)) ;; esac
  done
  insync=false; [ "$hard_n" -eq 0 ] && [ "$soft_n" -eq 0 ] && insync=true
  # exit code (first-class signal): block on hard, or on soft too under --strict
  rc=0; { [ "$hard_n" -gt 0 ] || { [ "$STRICT" = "1" ] && [ "$soft_n" -gt 0 ]; }; } && rc=1

  if [ "$FMT" = json ]; then
    printf '{"blueprint_schema":"1","command":"check","blueprint":"%s","in_sync":%s,"blocking":%d,"advisory":%d,"strict":%s,"issues":[' \
      "$(jesc "${BLUEPRINT#"$ROOT/"}")" "$insync" "$hard_n" "$soft_n" "$([ "$STRICT" = 1 ] && echo true || echo false)"
    first=1
    for rec in "${ISSUES[@]:-}"; do [ -n "$rec" ] || continue
      IFS="$US" read -r sev typ tgt det run kind <<<"$rec"
      [ $first -eq 1 ] || printf ','; first=0
      printf '{"severity":"%s","type":"%s","target":"%s","detail":"%s","remedy":{"run":"%s","kind":"%s"}}' \
        "$sev" "$typ" "$(jesc "$tgt")" "$(jesc "$det")" "$(jesc "$run")" "$kind"
    done
    printf ']}\n'
    exit $rc
  fi

  # human
  if [ "$insync" = true ]; then echo "blueprint in sync ✓"; exit 0; fi
  if [ "$hard_n" -gt 0 ]; then
    echo "HARD — the map contradicts reality (blocks merge):"
    for rec in "${ISSUES[@]:-}"; do [ -n "$rec" ] || continue
      IFS="$US" read -r sev typ tgt det run kind <<<"$rec"
      [ "$sev" = hard ] && printf '  %-9s %s %s   → %s\n' "$(echo "$typ"|tr a-z A-Z)" "$tgt" "$det" "$run"
    done
  fi
  if [ "$soft_n" -gt 0 ]; then
    [ "$hard_n" -gt 0 ] && echo
    echo "SOFT — the map may be behind (advisory$([ "$STRICT" = 1 ] && echo "; blocking under --strict")):"
    for rec in "${ISSUES[@]:-}"; do [ -n "$rec" ] || continue
      IFS="$US" read -r sev typ tgt det run kind <<<"$rec"
      [ "$sev" = soft ] && printf '  %-9s %s %s   → %s\n' "$(echo "$typ"|tr a-z A-Z)" "$tgt" "$det" "$run"
    done
  fi
  echo
  echo "${hard_n} blocking, ${soft_n} advisory$([ "$rc" = 0 ] && [ "$soft_n" -gt 0 ] && echo " — not blocking (use --strict to block)")"
  exit $rc
fi


# `source` returns the status of the last command above; a region whose final
# line is a legitimately-failing test must not kill the entry under set -e.
:
