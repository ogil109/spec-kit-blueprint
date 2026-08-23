#!/usr/bin/env bash
# E2E: a slicer-generated map is a TRUE blueprint — consumable by every
# downstream surface. Drives one fixture repo through the extension's whole
# life using only the shipped scripts:
#   0. on-ramp: partition -> map -> restamp -> verify + check green, next idle
#   1. `next` sequences a feature (specify -> plan -> tasks -> implement -> built)
#   2. built spec not in map -> HARD drift blocks; distill lands spec ownership
#   3. out-of-band hotfix -> STALE -> self-heal via the remedy JSON contract
#   4. out-of-band new module -> UNMAPPED -> scoped slice re-onboards it
#   5. final: in_sync, verify conforms, next idle
# The same flow is exercised against a real 2,649-file repo (pandas) in
# docs/deterministic-onramp.md — this is its deterministic CI twin.
set -uo pipefail

EXT="$(cd "$(dirname "$0")/.." && pwd)"
ORACLE="$EXT/scripts/bash/blueprint-state.sh"
SLICER="$EXT/scripts/bash/blueprint-slice.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n        %s\n' "$1" "$2"; }
assert() { [ "$2" = 0 ] && ok "$1" || bad "$1" "$3"; }

# ── fixture ───────────────────────────────────────────────────────────────────
R="$TMP/repo"
mkdir -p "$R/.specify/memory" "$R/.specify/extensions/blueprint-index" \
         "$R/src/core" "$R/src/io" "$R/tests" "$R/docs"
git -C "$R" init -q; git -C "$R" config user.email t@t; git -C "$R" config user.name t
for i in 1 2 3; do printf 'x\n' > "$R/src/core/c$i.py"; printf 'x\n' > "$R/src/io/i$i.py"; printf 'x\n' > "$R/tests/t$i.py"; done
printf 'x\n' > "$R/docs/index.md"; printf 'x\n' > "$R/README.md"
git -C "$R" add -A; git -C "$R" commit -qm init
# thresholds that split src/ into core + io (the feature in phase 1 owns src/io)
printf 'slice:\n  max_files: 5\n  min_files: 3\n' > "$R/.specify/extensions/blueprint-index/blueprint-config.yml"
BP="$R/.specify/memory/blueprint.md"

# ── phase 0: on-ramp (the real shipped path: scaffold writes the structure) ───
bash "$SLICER" scaffold --root "$R" --blueprint "$BP" > "$BP"
bash "$ORACLE" restamp --root "$R" --blueprint "$BP" >/dev/null 2>&1
bash "$ORACLE" check --json --root "$R" --blueprint "$BP" 2>/dev/null | python3 -c "
import json,sys
assert not [i for i in json.load(sys.stdin)['issues'] if i['type']=='structure']
" >/dev/null 2>&1; assert "on-ramp: no structure issues (map == computed)" $? ""
bash "$ORACLE" check --json --root "$R" --blueprint "$BP" >/dev/null 2>&1; assert "on-ramp: gate green" $? ""
bash "$ORACLE" next --json --root "$R" --blueprint "$BP" 2>/dev/null | grep -q '"has_next": false'
assert "on-ramp: next idle (no hallucinated backlog)" $? ""

# ── phase 1: next sequences a feature ─────────────────────────────────────────
mkdir -p "$R/specs/001-io-v2"
printf 'spec\n' > "$R/specs/001-io-v2/spec.md"
bash "$ORACLE" next --json --root "$R" --blueprint "$BP" 2>/dev/null | grep -q '"phase": "plan"'
assert "spec.md -> next=plan" $? ""
printf 'plan\n' > "$R/specs/001-io-v2/plan.md"
printf -- '- [ ] build\n' > "$R/specs/001-io-v2/tasks.md"
bash "$ORACLE" next --json --root "$R" --blueprint "$BP" 2>/dev/null | grep -q '"phase": "implement"'
assert "unchecked tasks -> next=implement" $? ""
bash "$ORACLE" check --json --root "$R" --blueprint "$BP" 2>/dev/null | python3 -c "
import json,sys
assert not [i for i in json.load(sys.stdin)['issues'] if i['type']=='drift']
" >/dev/null 2>&1; assert "in-flight spec does not trip the gate" $? ""
printf -- '- [x] build\n' > "$R/specs/001-io-v2/tasks.md"
bash "$ORACLE" next --json --root "$R" --blueprint "$BP" 2>/dev/null | grep -q '"phase": "distill"'
assert "built spec -> next=distill" $? ""

# ── phase 2: drift blocks; distill lands ownership ────────────────────────────
bash "$ORACLE" check --json --root "$R" --blueprint "$BP" >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ]; assert "built spec not in map -> HARD drift blocks (exit 1)" $? "rc=$rc"
python3 - "$BP" <<'PYEOF'
import sys
p = sys.argv[1]
t = open(p).read()
old = "## src/io\n<!-- blueprint:section state=code -->"
assert old in t, "fixture map lacks the src/io section the distill targets"
t = t.replace(old, "## src/io\n<!-- blueprint:section state=distilled owner=specs/001-io-v2 -->")
open(p, 'w').write(t)
PYEOF
bash "$ORACLE" check --json --root "$R" --blueprint "$BP" >/dev/null 2>&1; assert "distill clears the drift" $? ""
bash "$ORACLE" next --json --root "$R" --blueprint "$BP" 2>/dev/null | grep -q '"has_next": false'
assert "next idle — waterfall complete for the slice" $? ""
bash "$ORACLE" check --json --root "$R" --blueprint "$BP" 2>/dev/null | python3 -c "
import json,sys
assert not [i for i in json.load(sys.stdin)['issues'] if i['type']=='structure']
" >/dev/null 2>&1; assert "structure check: spec-owned src/io outside slicer jurisdiction" $? ""

# ── phase 3: hotfix -> STALE -> self-heal via remedy contract ─────────────────
printf 'y\n' >> "$R/src/core/c1.py"
git -C "$R" add -A; git -C "$R" commit -qm "hotfix, no spec"
bash "$ORACLE" check --root "$R" --blueprint "$BP" --strict >/dev/null 2>&1; src=$?
[ "$src" = 1 ]; assert "hotfix -> STALE (blocks under --strict)" $? "src=$src"
bash "$ORACLE" check --json --root "$R" --blueprint "$BP" 2>/dev/null | python3 -c "
import json,sys
for i in json.load(sys.stdin)['issues']:
    if i['type'] in ('stale','unstamped'): print(i['target'])
" | while IFS= read -r p; do bash "$ORACLE" restamp --root "$R" --blueprint "$BP" --path "$p" >/dev/null 2>&1; done
bash "$ORACLE" check --root "$R" --blueprint "$BP" --strict >/dev/null 2>&1
assert "self-heal loop consumes remedies -> green even under --strict" $? ""

# ── phase 4: new module -> UNMAPPED -> scoped re-onboard ──────────────────────
mkdir -p "$R/newmod"; for i in 1 2 3; do printf 'x\n' > "$R/newmod/n$i.py"; done
git -C "$R" add -A; git -C "$R" commit -qm "new module, no spec"
bash "$ORACLE" check --json --root "$R" --blueprint "$BP" 2>/dev/null | python3 -c "
import json,sys
u=[i for i in json.load(sys.stdin)['issues'] if i['type']=='unmapped']
assert len(u)==1 and u[0]['target']=='newmod' and 'from-code newmod' in u[0]['remedy']['run'], u
" >/dev/null 2>&1; assert "new module -> UNMAPPED with scoped init remedy" $? ""
bash "$SLICER" scaffold --root "$R" --blueprint "$BP" --scope newmod >> "$BP"
bash "$ORACLE" restamp --root "$R" --blueprint "$BP" --path newmod >/dev/null 2>&1
bash "$ORACLE" check --json --root "$R" --blueprint "$BP" >/dev/null 2>&1; assert "re-onboarded module: gate green" $? ""
bash "$ORACLE" check --json --root "$R" --blueprint "$BP" 2>/dev/null | python3 -c "
import json,sys
assert not [i for i in json.load(sys.stdin)['issues'] if i['type']=='structure']
" >/dev/null 2>&1; assert "re-onboarded module: no structure issues (scoped == full recompute)" $? ""

# ── phase 5: end state ────────────────────────────────────────────────────────
bash "$ORACLE" check --json --root "$R" --blueprint "$BP" 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['in_sync'] is True and d['blocking']==0 and d['advisory']==0, d
" >/dev/null 2>&1; assert "final: in_sync, zero blocking, zero advisory" $? ""

echo
echo "e2e lifecycle: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
