#!/usr/bin/env bash
# Tests for the deterministic brownfield partitioner (blueprint-slice.sh).
#
# The contract under test: same repo state + same config => byte-identical
# partition; every tracked file is either sectioned (code/context), excluded by
# a checked-in pattern, or a root-level loose file — nothing silently absent.
# The end-to-end case proves the on-ramp blind spot is closed: a map generated
# from the partition passes `check` clean, and a directory added later is
# flagged unmapped instead of staying invisible.
set -uo pipefail

SLICER="$(cd "$(dirname "$0")/.." && pwd)/scripts/bash/blueprint-slice.sh"
ORACLE="$(cd "$(dirname "$0")/.." && pwd)/scripts/bash/blueprint-state.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n        %s\n' "$1" "$2"; }
assert() { [ "$2" = 0 ] && ok "$1" || bad "$1" "$3"; }

# ── fixture: a small polyglot brownfield repo ─────────────────────────────────
R="$TMP/repo"
mkdir -p "$R/.specify/extensions/blueprint-index" "$R/.github" \
         "$R/src/core" "$R/src/io/parsers" "$R/src/io/formats" "$R/src/tiny" \
         "$R/tests" "$R/infra" "$R/docs" "$R/pkg/mylib" "$R/specs/001-x"
git -C "$R" init -q; git -C "$R" config user.email t@t; git -C "$R" config user.name t
for i in 1 2 3 4 5 6; do printf 'x\n' > "$R/src/core/f$i.py"; done
for i in 1 2 3 4; do printf 'x\n' > "$R/src/io/parsers/p$i.py"; printf 'x\n' > "$R/src/io/formats/g$i.py"; done
printf 'x\n' > "$R/src/io/top.py"; printf 'x\n' > "$R/src/tiny/one.py"; printf 'x\n' > "$R/src/loose.py"
for i in 1 2 3; do printf 'x\n' > "$R/tests/t$i.py"; done
printf 'x\n' > "$R/infra/main.bicep"; printf 'x\n' > "$R/docs/index.md"
printf '{}\n' > "$R/pkg/mylib/package.json"; printf 'x\n' > "$R/pkg/mylib/index.js"
printf 'x\n' > "$R/.github/ci.yml"; printf 'x\n' > "$R/specs/001-x/spec.md"; printf 'x\n' > "$R/README.md"
git -C "$R" add -A; git -C "$R" commit -qm init
A=(--root "$R")

# 1. determinism: two runs are byte-identical
j1="$(bash "$SLICER" slice "${A[@]}" --json)"; j2="$(bash "$SLICER" slice "${A[@]}" --json)"
[ "$j1" = "$j2" ]; assert "two runs are byte-identical" $? "diff"
echo "$j1" | python3 -c "import json,sys; json.load(sys.stdin)" >/dev/null 2>&1
assert "output is valid JSON" $? "$j1"

# 2. the partition itself (defaults: max_files=400 → everything fits)
echo "$j1" | python3 -c "
import json,sys
d=json.load(sys.stdin)
S={s['path']:(s['kind'],s['rule']) for s in d['sections']}
assert S['src']==('code','fits'), S
assert S['tests']==('code','fits') and S['infra']==('code','fits')
assert S['pkg/mylib']==('code','module'), 'boundary file must force the split of pkg/'
assert S['docs']==('context','context-dir')
assert 'pkg' not in S, 'pkg has no content besides the module — no remainder'
assert d['root_files']==['README.md']
ex={e['path'] for e in d['excluded']}
assert ex=={'.github','specs'}, ex
" >/dev/null 2>&1; assert "rules: fits/module/context-dir/exclude/root-files" $? "$j1"

# 3. thresholds descend: max_files=5, min_files=2 → split src, fold tiny+loose
printf 'slice:\n  max_files: 5\n  min_files: 2\n' > "$R/.specify/extensions/blueprint-index/blueprint-config.yml"
j3="$(bash "$SLICER" slice "${A[@]}" --json)"
echo "$j3" | python3 -c "
import json,sys
d=json.load(sys.stdin)
S={(s['path'],s['remainder']):s for s in d['sections']}
assert S[('src/core',False)]['rule']=='flat', 'no subdirs to split: emitted whole'
assert S[('src/io/parsers',False)]['rule']=='fits' and S[('src/io/formats',False)]['rule']=='fits'
io_rem=S[('src/io',True)]; assert io_rem['markers']==['src/io/top.py']
src_rem=S[('src',True)];  assert src_rem['markers']==['src/tiny','src/loose.py'], src_rem['markers']
assert src_rem['files']==2
" >/dev/null 2>&1; assert "descend: flat/fits/remainder markers exact" $? "$j3"

# 4. scope is a subset of the full partition
js="$(bash "$SLICER" slice "${A[@]}" --scope src --json)"
python3 -c "
import json,sys
full=json.loads(sys.argv[1]); scoped=json.loads(sys.argv[2])
fs=[s for s in full['sections'] if s['path']=='src' or s['path'].startswith('src/')]
assert scoped['sections']==fs, 'scoped partition must equal the src subset of the full one'
" "$j3" "$js" >/dev/null 2>&1; assert "--scope src == src subset of full partition" $? "$js"

# 5. end-to-end: generate the map from the partition, restamp, gate is CLEAN
rm -f "$R/.specify/extensions/blueprint-index/blueprint-config.yml"
BP="$R/blueprint.md"
{
  echo "# Blueprint"
  bash "$SLICER" slice "${A[@]}" --json | python3 -c "
import json,sys
d=json.load(sys.stdin)
for s in d['sections']:
    print(f\"## {s['path']}\" + (' (remainder)' if s['remainder'] else ''))
    if s['kind']=='code':
        print('<!-- blueprint:section state=code -->')
        for m in s['markers']: print(f'<!-- blueprint:code path={m} sha=NONE -->')
    else:
        print('<!-- blueprint:section state=context -->')
        for m in s['markers']: print(f'<!-- blueprint:context path={m} -->')
"
} > "$BP"
git -C "$R" add -A; git -C "$R" commit -qm map
bash "$ORACLE" restamp --root "$R" --blueprint "$BP" >/dev/null 2>&1
cj="$(bash "$ORACLE" check --json --root "$R" --blueprint "$BP" 2>/dev/null)"
echo "$cj" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['in_sync'] is True, d['issues']
" >/dev/null 2>&1; assert "partition-generated map passes check clean (full coverage)" $? "$cj"

# 6. the blind spot stays closed: a NEW top-level dir surfaces immediately
mkdir -p "$R/newtop"; printf 'x\n' > "$R/newtop/n.py"
git -C "$R" add -A; git -C "$R" commit -qm newtop
cj2="$(bash "$ORACLE" check --json --root "$R" --blueprint "$BP" 2>/dev/null)"
echo "$cj2" | python3 -c "
import json,sys
u=[i for i in json.load(sys.stdin)['issues'] if i['type']=='unmapped']
assert len(u)==1 and u[0]['target']=='newtop', u
" >/dev/null 2>&1; assert "a later top-level dir is flagged unmapped (blind spot closed)" $? "$cj2"

# 7. respect-existing: covered paths subtracted; only the new dir is proposed
j7="$(bash "$SLICER" slice "${A[@]}" --blueprint "$BP" --json)"
echo "$j7" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['respect_existing'] is True and d['subtracted_files']>0
assert [s['path'] for s in d['sections']]==['newtop'], d['sections']
" >/dev/null 2>&1; assert "respect-existing proposes only the additive section" $? "$j7"

# 8. oversize advisory: an existing section that outgrew max_files is surfaced
printf 'slice:\n  max_files: 2\n' > "$R/.specify/extensions/blueprint-index/blueprint-config.yml"
j8="$(bash "$SLICER" slice "${A[@]}" --blueprint "$BP" --json)"
echo "$j8" | python3 -c "
import json,sys
d=json.load(sys.stdin)
adv={a['path'] for a in d['advisories']}
assert 'src' in adv, d['advisories']
" >/dev/null 2>&1; assert "existing section exceeding max_files raises an oversize advisory" $? "$j8"

# 9. pin_dirs: atomic despite thresholds, and ancestors split down to reach a pin
printf 'slice:\n  max_files: 5\n  min_files: 2\n  pin_dirs:\n    - src\n' > "$R/.specify/extensions/blueprint-index/blueprint-config.yml"
j9="$(bash "$SLICER" slice "${A[@]}" --all --json)"
echo "$j9" | python3 -c "
import json,sys
S={s['path']:s['rule'] for s in json.load(sys.stdin)['sections']}
assert S['src']=='pinned', S
assert not any(p.startswith('src/') for p in S), 'pin must stop descent'
" >/dev/null 2>&1; assert "pinned dir stays one section despite max_files" $? "$j9"
printf 'slice:\n  pin_dirs:\n    - src/io\n' > "$R/.specify/extensions/blueprint-index/blueprint-config.yml"
j10="$(bash "$SLICER" slice "${A[@]}" --all --json)"
echo "$j10" | python3 -c "
import json,sys
S={s['path']:s['rule'] for s in json.load(sys.stdin)['sections']}
assert S['src/io']=='pinned', S
assert 'src' not in S or S.get('src')!='fits', 'ancestor of a pin must split down to it'
assert S.get('src/core')=='fits'
" >/dev/null 2>&1; assert "ancestors split down to reach a nested pin" $? "$j10"
rm -f "$R/.specify/extensions/blueprint-index/blueprint-config.yml"

echo
echo "slicer tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
