#!/usr/bin/env bash
# lib/state-restamp.sh — `restamp`: the one deterministic remedy; refreshes
# code-marker baselines to the current git tree/blob SHAs. Exits when invoked.
# Expects: ROOT, BLUEPRINT, PATH_FILTER.
# ── restamp: refresh the git baseline for code markers (all, or one --path) ────
# Run as part of remap, after a section's prose has been re-derived from the code.
if [ "$CMD" = "restamp" ]; then
  is_git || { echo "not a git repository — cannot restamp"; exit 1; }
  [ -f "$BLUEPRINT" ] || { echo "no blueprint at: ${BLUEPRINT:-<none>}"; exit 1; }
  updated=0
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    p="$(marker_path "$m")"
    [ -n "$PATH_FILTER" ] && [ "$PATH_FILTER" != "$p" ] && continue
    cur="$(current_sha "$p")"
    [ -z "$cur" ] && { echo "skip (missing in git): $p"; continue; }
    esc="$(printf '%s' "$p" | sed 's/[|]/\\|/g')"
    # No `sed -i`: BSD sed requires a backup-suffix argument after -i and would
    # consume `-E` as one, silently disabling extended regex and failing on \1.
    # A temp-file rewrite is portable across GNU and BSD sed.
    sed -E "s|(<!-- blueprint:code path=${esc} sha=)[^ ]+( -->)|\1${cur}\2|" "$BLUEPRINT" > "$BLUEPRINT.tmp" \
      && mv "$BLUEPRINT.tmp" "$BLUEPRINT"
    echo "stamped $p → $cur"; updated=$((updated+1))
  done < <(code_markers)
  echo "restamped $updated marker(s)"; exit 0
fi


# `source` returns the status of the last command above; a region whose final
# line is a legitimately-failing test must not kill the entry under set -e.
:
