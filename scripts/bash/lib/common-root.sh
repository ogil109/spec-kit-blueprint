#!/usr/bin/env bash
# lib/common-root.sh — repo-root resolution (nearest ancestor with .specify).
# Sourced by both entries before anything touches the filesystem. Sets: ROOT.
# ── locate repo root ──────────────────────────────────────────────────────────
if [ -z "$ROOT" ]; then
  d="$(pwd)"
  while [ "$d" != "/" ]; do
    [ -d "$d/.specify" ] && ROOT="$d" && break
    d="$(dirname "$d")"
  done
  [ -z "$ROOT" ] && ROOT="$(pwd)"
fi


# `source` returns the status of the last command above; a region whose final
# line is a legitimately-failing test must not kill the entry under set -e.
:
