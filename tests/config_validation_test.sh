#!/usr/bin/env bash
# Config validation: the config steers the entire partition, so it is
# validated like every other input surface (decision inventory, D1). A typo'd
# key must be a hard error naming the valid keys — never a silent fallback to
# defaults; all violations report at once; clean configs stay silent.
set -uo pipefail

EXT="$(cd "$(dirname "$0")/.." && pwd)"
SL="$EXT/scripts/bash/blueprint-slice.sh"
ST="$EXT/scripts/bash/blueprint-state.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n        %s\n' "$1" "$2"; }
assert() { [ "$2" = 0 ] && ok "$1" || bad "$1" "$3"; }

R="$TMP/repo"; mkdir -p "$R/.specify/extensions/blueprint-index" "$R/src"
git -C "$R" init -q; git -C "$R" config user.email t@t; git -C "$R" config user.name t
printf 'x\n' > "$R/src/a.py"; git -C "$R" add -A; git -C "$R" commit -qm init
C="$R/.specify/extensions/blueprint-index/blueprint-config.yml"

# 1. the field typo class: pin_dir instead of pin_dirs -> hard error, valid keys named
printf 'slice:\n  pin_dir:\n    - src/tests\n' > "$C"
out="$(bash "$SL" slice --root "$R" --json 2>&1)"; rc=$?
{ [ "$rc" = 2 ] && echo "$out" | grep -q "unknown key 'pin_dir' under 'slice'" \
  && echo "$out" | grep -q "pin_dirs"; }
assert "typo'd key is a hard error naming the valid keys (exit 2)" $? "rc=$rc $out"

# 2. all violations reported at once; nothing runs
printf 'slice:\n  pin_dir:\n    - x\n  max_files: lots\nweird:\n  a: 1\ndistill:\n  require_confirmation: maybe\n' > "$C"
out="$(bash "$SL" slice --root "$R" --json 2>&1)"; rc=$?
n=$(echo "$out" | grep -c '^  - ')
{ [ "$rc" = 2 ] && [ "$n" -ge 4 ]; }
assert "multiple violations reported together (typo, type, section, bool)" $? "rc=$rc n=$n $out"

# 3. misindented list (the silent-empty signature) is an error
printf 'slice:\n  boundary_files:\nnope\n' > "$C"
out="$(bash "$SL" slice --root "$R" --json 2>&1)"; rc=$?
{ [ "$rc" = 2 ] && echo "$out" | grep -q "has no parseable items"; }
assert "list key that parses empty -> misindent error" $? "rc=$rc $out"

# 4. both entries validate: the state oracle rejects the same config
out="$(bash "$ST" check --json --root "$R" 2>&1)"; rc=$?
[ "$rc" = 2 ]; assert "the gate entry validates too (exit 2)" $? "rc=$rc $out"

# 5. clean configs are silent: explicit [] and block lists both valid
printf 'blueprint:\n  path: ".specify/memory/blueprint.md"\nslice:\n  max_files: 100\n  pin_dirs: []\ncoverage:\n  exclude:\n    - ".*"\n' > "$C"
out="$(bash "$SL" slice --root "$R" --json 2>/dev/null)"; rc=$?
{ [ "$rc" = 0 ] && ! bash "$SL" slice --root "$R" --json 2>&1 >/dev/null | grep -q .; }
assert "clean config: exit 0, zero validation output" $? "rc=$rc"

# 6. no config file at all is fine (defaults)
rm -f "$C"
bash "$SL" slice --root "$R" --json >/dev/null 2>&1
assert "absent config: defaults, no error" $? ""

echo
echo "config validation: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
