#!/usr/bin/env bash
# Static portability lint for the shipped bash scripts.
#
# CI runs on GNU userland, so BSD-only failures (macOS sed/grep) can never be
# caught by executing the oracle there. This guard catches the *class* statically:
#   - GNU regex shorthands (\s \d \w) are not POSIX ERE. BSD grep may tolerate
#     them; BSD sed does NOT — a failed match passes the line through UNCHANGED,
#     which corrupts silently instead of erroring. Use [[:space:]] etc.
#   - `sed -i` is not portable: BSD sed requires a backup-suffix argument after
#     -i and will consume the next flag (e.g. -E) as one, silently changing
#     regex dialect. Rewrite via a temp file + mv instead.
# Both patterns shipped as real, user-reported bugs in v0.2.0.
set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts/bash"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n%s\n' "$1" "$2"; }

for f in "$SCRIPTS_DIR"/*.sh "$SCRIPTS_DIR"/lib/*.sh; do
  name="$(basename "$f")"

  # GNU-only regex shorthands: a literal backslash followed by s, d, or w.
  hits="$(grep -nE '\\[sdw]' "$f" || true)"
  if [ -z "$hits" ]; then ok "$name: no GNU-only \\s/\\d/\\w regex shorthands"
  else bad "$name: GNU-only regex shorthand (use POSIX [[:space:]] etc.)" "$hits"; fi

  # In-place sed: BSD sed's -i takes a mandatory suffix argument.
  hits="$(grep -nE '(^|[^[:alnum:]_-])sed[[:space:]]+(-[[:alpha:]]+[[:space:]]+)*-i([[:space:]]|$)' "$f" || true)"
  if [ -z "$hits" ]; then ok "$name: no bare 'sed -i' (BSD sed incompatible)"
  else bad "$name: bare 'sed -i' (use a temp-file rewrite + mv)" "$hits"; fi
done

echo
echo "portability lint: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
