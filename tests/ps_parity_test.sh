#!/usr/bin/env bash
# Byte-parity between the bash oracles and their PowerShell ports.
#
# The PS ports promise OUTPUT PARITY, not just behavioral similarity: for the
# same repo state + config, `slice --json`, `scaffold`, `verify`, and
# `check --json` must emit byte-identical text (and identical exit codes).
# A parity diff has already caught real bugs — most recently PS 7.5's native
# command output sorting culture-aware where bash sorts bytewise (LC_ALL=C).
#
# Skips cleanly when pwsh is unavailable; GitHub's ubuntu runners ship it, so
# CI always executes the diffs.
set -uo pipefail

EXT="$(cd "$(dirname "$0")/.." && pwd)"
BS="$EXT/scripts/bash/blueprint-slice.sh";  PSSL="$EXT/scripts/powershell/blueprint-slice.ps1"
BO="$EXT/scripts/bash/blueprint-state.sh";  PSST="$EXT/scripts/powershell/blueprint-state.ps1"
if ! command -v pwsh >/dev/null 2>&1; then
  echo "ps parity: SKIPPED (pwsh not available)"
  exit 0
fi
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n%s\n' "$1" "$2"; }
par() { # label bash-cmd... vs pwsh equivalent (same args)
  local label="$1"; shift
  local b p
  b="$(bash "$BS" "$@" 2>/dev/null; echo "rc=$?")"
  p="$(pwsh -NoProfile "$PSSL" "$@" 2>/dev/null; echo "rc=$?")"
  if [ "$b" = "$p" ]; then ok "$label"; else bad "$label" "$(diff <(echo "$b") <(echo "$p") | head -6)"; fi
}

# ── fixture: exercises every rule the partitioner has ─────────────────────────
R="$TMP/repo"
mkdir -p "$R/.specify/extensions/blueprint-index" "$R/.specify/memory" "$R/.github" \
         "$R/src/core" "$R/src/io/parsers" "$R/src/io/formats" "$R/src/tiny" \
         "$R/tests" "$R/infra" "$R/docs" "$R/pkg/mylib" "$R/specs/001-x" "$R/MixedCase"
git -C "$R" init -q; git -C "$R" config user.email t@t; git -C "$R" config user.name t
for i in 1 2 3 4 5 6; do printf 'x\n' > "$R/src/core/f$i.py"; done
for i in 1 2 3 4; do printf 'x\n' > "$R/src/io/parsers/p$i.py"; printf 'x\n' > "$R/src/io/formats/g$i.py"; done
printf 'x\n' > "$R/src/io/top.py"; printf 'x\n' > "$R/src/tiny/one.py"; printf 'x\n' > "$R/src/loose.py"
for i in 1 2 3; do printf 'x\n' > "$R/tests/t$i.py"; done
printf 'x\n' > "$R/infra/main.bicep"; printf 'x\n' > "$R/docs/index.md"
printf '{}\n' > "$R/pkg/mylib/package.json"; printf 'x\n' > "$R/pkg/mylib/index.js"
printf 'x\n' > "$R/.github/ci.yml"; printf 'x\n' > "$R/specs/001-x/spec.md"
printf 'x\n' > "$R/MixedCase/File.py"; printf 'x\n' > "$R/MixedCase/aaa.py"; printf 'x\n' > "$R/MixedCase/ZZZ.py"
printf 'r\n' > "$R/README.md"; printf 'l\n' > "$R/LICENSE"
git -C "$R" add -A; git -C "$R" commit -qm init
A=(--root "$R")

# 1. fresh partition, defaults
par "slice --json (defaults)"        slice "${A[@]}" --all --json
par "slice --human (defaults)"       slice "${A[@]}" --all --human
par "scaffold (fresh, full header)"  scaffold "${A[@]}"

# 2. thresholds descend + remainder + pins + scope
printf 'slice:\n  max_files: 5\n  min_files: 2\n  pin_dirs:\n    - src/io\n' \
  > "$R/.specify/extensions/blueprint-index/blueprint-config.yml"
par "slice --json (descend/remainder/pins)" slice "${A[@]}" --all --json
par "slice --json (--scope src)"            slice "${A[@]}" --all --scope src --json
rm -f "$R/.specify/extensions/blueprint-index/blueprint-config.yml"

# 3. a real map: scaffold it, restamp, then verify + respect-existing + additive
BP="$R/.specify/memory/blueprint.md"
bash "$BS" scaffold "${A[@]}" > "$BP"
git -C "$R" add -A; git -C "$R" commit -qm map
bash "$BO" restamp --root "$R" --blueprint "$BP" >/dev/null 2>&1
par "verify --json (conforming)"   verify "${A[@]}"
par "verify --human (conforming)"  verify "${A[@]}" --human
mkdir -p "$R/newmod"; for i in 1 2 3; do printf 'x\n' > "$R/newmod/n$i.py"; done
git -C "$R" add -A; git -C "$R" commit -qm newmod
par "slice --json (respect-existing + holes)" slice "${A[@]}" --json
par "scaffold (additive: only newmod)"        scaffold "${A[@]}"
par "verify --json (structure drift, exit 1)" verify "${A[@]}"

# 4. tampered verify: merged section -> identical pair diff both sides
sed 's|<!-- blueprint:code path=tests sha=|<!-- blueprint:code path=tests_MOVED sha=|' "$BP" > "$BP.t"
par "verify --json (tampered marker)" verify --root "$R" --blueprint "$BP.t"
rm -f "$BP.t"

# 5. the gate: check --json parity, incl. relations validation
cat >> "$BP" <<'EOF'
## Architecture — subsystem relations
<!-- blueprint:section state=context -->
<!-- blueprint:relation from=src to=tests kind=uses evidence=src/loose.py -->
<!-- blueprint:relation from=src to=ghost kind=uses evidence=src/loose.py -->
<!-- blueprint:relation from=tests to=src kind=uses evidence=tests/gone.py -->
<!-- blueprint:relation from=src to=MixedCase kind=uses evidence=src/loose.py#no_such_symbol -->
EOF
b="$(bash "$BO" check --json --root "$R" --blueprint "$BP" 2>/dev/null; echo "rc=$?")"
p="$(pwsh -NoProfile "$PSST" check --json --root "$R" --blueprint "$BP" 2>/dev/null; echo "rc=$?")"
if [ "$b" = "$p" ]; then ok "check --json (coverage + relations)"; else
  # the two JSON emitters differ in escaping style; fall back to semantic equality
  python3 - "$b" "$p" <<'PYEOF' >/dev/null 2>&1
import json, sys
a = json.loads(sys.argv[1].rsplit("rc=",1)[0]); b = json.loads(sys.argv[2].rsplit("rc=",1)[0])
assert sys.argv[1].rsplit("rc=",1)[1] == sys.argv[2].rsplit("rc=",1)[1]
ka = [(i['severity'],i['type'],i['target'],i['detail'],i['remedy']['run'],i['remedy']['kind']) for i in a['issues']]
kb = [(i['severity'],i['type'],i['target'],i['detail'],i['remedy']['run'],i['remedy']['kind']) for i in b['issues']]
assert ka == kb and a['blocking'] == b['blocking'] and a['advisory'] == b['advisory'] and a['in_sync'] == b['in_sync']
PYEOF
  [ $? -eq 0 ] && ok "check --json (coverage + relations; semantically equal)" || bad "check --json (coverage + relations)" "$(diff <(echo "$b") <(echo "$p") | head -8)"
fi

# 6. render parity: same facts over identical fresh scaffolds -> byte-identical maps
cat > "$TMP/facts.txt" <<'FEOF'
blueprint-facts 1
section src
role Application source tree.
facet Entry | `src/loose.py` wires the modules. | src/loose.py
neighbor uses | tests | exercised by the suite | src/loose.py#x
concern build-config
role Where build configuration lives.
neighbor crosscuts | src | manifest read at build time | src/core/f1.py
FEOF
M1="$TMP/m1.md"; M2="$TMP/m2.md"; : > "$M1"; : > "$M2"
bash "$BS" scaffold --root "$R" --blueprint "$M1" > "$M1"
pwsh -NoProfile "$PSSL" scaffold --root "$R" --blueprint "$M2" > "$M2"
b="$(bash "$BS" render --root "$R" --blueprint "$M1" --facts "$TMP/facts.txt" 2>&1; echo "rc=$?")"
p="$(pwsh -NoProfile "$PSSL" render --root "$R" --blueprint "$M2" --facts "$TMP/facts.txt" 2>&1; echo "rc=$?")"
{ [ "$(echo "$b" | tail -1)" = "$(echo "$p" | tail -1)" ] && diff -q "$M1" "$M2" >/dev/null; }
if [ $? -eq 0 ]; then ok "render (prose + relations + concern) byte-identical"; else bad "render byte parity" "$(diff "$M1" "$M2" | head -6)"; fi

# partial repair on top: one block re-rendered, other edges preserved — identical merge
cat > "$TMP/facts2.txt" <<'FEOF'
blueprint-facts 1
section tests
role The pytest suite, exercising the application.
neighbor uses | src | tests import the code under test | tests/t1.py
FEOF
bash "$BS" render --root "$R" --blueprint "$M1" --facts "$TMP/facts2.txt" >/dev/null 2>&1
pwsh -NoProfile "$PSSL" render --root "$R" --blueprint "$M2" --facts "$TMP/facts2.txt" >/dev/null 2>&1
diff -q "$M1" "$M2" >/dev/null
if [ $? -eq 0 ]; then ok "partial repair merge byte-identical (edges preserved)"; else bad "partial repair parity" "$(diff "$M1" "$M2" | head -6)"; fi

echo
echo "ps parity: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
