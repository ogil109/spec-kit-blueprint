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

# 5b. verify: a map generated from the partition is structure-conformant
bash "$SLICER" verify "${A[@]}" --blueprint "$BP" >/dev/null 2>&1
assert "verify passes on a partition-generated map (exit 0)" $? ""

# 5c. verify catches an agent 'merging' sections: move a marker under another
#     heading -> the pair shows as missing from its section AND unexpected in
#     the other, exit 1. Structure conformance is machine-checked, not prompt
#     discipline.
cp "$BP" "$BP.orig"
python3 - "$BP" <<'PYEOF'
import re, sys
p = sys.argv[1]
t = open(p).read()
m = re.search(r'## tests\n<!-- blueprint:section state=code -->\n(<!-- blueprint:code path=tests sha=[^ ]+ -->)\n', t)
t = t.replace(m.group(0), '')
t = t.replace('<!-- blueprint:code path=infra', m.group(1) + '\n<!-- blueprint:code path=infra')
open(p, 'w').write(t)
PYEOF
vj="$(bash "$SLICER" verify "${A[@]}" --blueprint "$BP" --json 2>/dev/null)"; vrc=$?
{ [ "$vrc" = 1 ] && echo "$vj" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['structure_ok'] is False
assert {'section':'tests','kind':'code','marker':'tests'} in d['missing'], d['missing']
assert {'section':'infra','kind':'code','marker':'tests'} in d['unexpected'], d['unexpected']
" >/dev/null 2>&1; }; assert "verify flags a merged section as missing+unexpected (exit 1)" $? "rc=$vrc $vj"
mv "$BP.orig" "$BP"

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

# 11. verify also surfaces structure DRIFT: newtop (added in test 6) is computed
#     but absent from the map -> exit 1 with a missing pair.
vj2="$(bash "$SLICER" verify "${A[@]}" --blueprint "$BP" --json 2>/dev/null)"; vrc2=$?
{ [ "$vrc2" = 1 ] && echo "$vj2" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert {'section':'newtop','kind':'code','marker':'newtop'} in d['missing'], d
assert not d['unexpected'], d['unexpected']
" >/dev/null 2>&1; }; assert "verify surfaces structure drift (new dir missing from map)" $? "rc=$vrc2 $vj2"

# 12. spec-owned markers are outside the slicer's jurisdiction: a distilled
#     section owning newtop makes verify pass again (its paths are subtracted
#     from the recompute and its markers ignored in the diff).
cat >> "$BP" <<'EOF'
## Newtop Feature
<!-- blueprint:section state=distilled owner=specs/001-newtop -->
<!-- blueprint:code path=newtop sha=NONE -->
EOF
bash "$SLICER" verify "${A[@]}" --blueprint "$BP" >/dev/null 2>&1
assert "distilled-owned markers are ignored by verify (exit 0)" $? ""

# 13. scaffold: the map skeleton is machine-written — byte-identical runs, the
#     redirect-creates-empty-file edge included, and verify passes with the
#     TODO(prose) placeholders untouched (prose is provably outside the oracles).
R2="$TMP/scaf"; mkdir -p "$R2/.specify/memory" "$R2/src/a" "$R2/src/b" "$R2/docs"
git -C "$R2" init -q; git -C "$R2" config user.email t@t; git -C "$R2" config user.name t
for i in 1 2 3; do printf 'x\n' > "$R2/src/a/f$i.py"; printf 'x\n' > "$R2/src/b/g$i.py"; done
printf 'x\n' > "$R2/docs/index.md"
git -C "$R2" add -A; git -C "$R2" commit -qm init
B2="$R2/.specify/memory/blueprint.md"
s1="$(bash "$SLICER" scaffold --root "$R2")"        # no blueprint exists yet
s2="$(bash "$SLICER" scaffold --root "$R2")"
bash "$SLICER" scaffold --root "$R2" > "$B2"        # the > pre-creates an empty target
{ [ "$s1" = "$s2" ] && [ "$(cat "$B2")" = "$s1" ]; }
assert "scaffold is byte-identical (empty-redirect edge included)" $? ""
grep -q '^# .* Blueprint$' "$B2" && grep -q '## Table of Contents' "$B2" && grep -q 'TODO(prose)' "$B2"
assert "scaffold emits the full template skeleton (title, TOC, placeholders)" $? "$(head -3 "$B2")"
bash "$ORACLE" restamp --root "$R2" --blueprint "$B2" >/dev/null 2>&1
bash "$SLICER" verify --root "$R2" --blueprint "$B2" >/dev/null 2>&1 \
  && bash "$ORACLE" check --json --root "$R2" --blueprint "$B2" >/dev/null 2>&1
assert "scaffolded map passes verify + gate with placeholders untouched" $? ""

# 14. scaffold is additive against an existing map: only the missing blocks, no header
mkdir -p "$R2/newmod"; for i in 1 2 3; do printf 'x\n' > "$R2/newmod/n$i.py"; done
git -C "$R2" add -A; git -C "$R2" commit -qm newmod
add="$(bash "$SLICER" scaffold --root "$R2" --blueprint "$B2")"
{ echo "$add" | grep -q '^## newmod$' && ! echo "$add" | grep -q 'Table of Contents' \
  && [ "$(echo "$add" | grep -c '^## ')" = 1 ]; }
assert "scaffold against an existing map emits only the missing section" $? "$add"
printf '%s\n' "$add" >> "$B2"
bash "$ORACLE" restamp --root "$R2" --blueprint "$B2" --path newmod >/dev/null 2>&1
bash "$SLICER" verify --root "$R2" --blueprint "$B2" >/dev/null 2>&1
assert "appended scaffold block restores full conformance" $? ""

# 15. hybrid on-ramp coexistence: a markerless DETAILED section (backlog seeded
#     from docs) lives alongside the computed code sections without disturbing
#     verify (no markers -> outside slicer jurisdiction) while the oracle counts
#     it as backlog (next: specify instead of idle).
cat >> "$B2" <<'EOF'
## Planned: streaming ingestion
<!-- blueprint:section state=detailed -->
Design detail from the architecture doc — unbuilt; a future spec formalizes it.
EOF
bash "$SLICER" verify --root "$R2" --blueprint "$B2" >/dev/null 2>&1
assert "detailed (docs-seeded backlog) section is invisible to verify" $? ""
bash "$ORACLE" next --json --root "$R2" --blueprint "$B2" 2>/dev/null | grep -q '"phase": "specify"'
assert "detailed section turns next from idle into specify (backlog works)" $? ""

# 16. render: one validated facts file writes prose AND relation markers —
#     they come from the same source, so they cannot contradict.
cat > "$TMP/facts.txt" <<'FEOF'
blueprint-facts 1
section src
role Application source.
facet Entry | `src/a/f1.py` boots everything. | src/a/f1.py
neighbor uses | newmod | consumes its helpers | src/a/f1.py
section newmod
role A new module.
concern shared-config
role Where configuration lives and who reads it.
neighbor crosscuts | src | config read at import time | src/a/f2.py
FEOF
bash "$SLICER" render --root "$R2" --blueprint "$B2" --facts "$TMP/facts.txt" >/dev/null 2>&1
assert "render accepts validated facts (exit 0)" $? ""
{ grep -q 'Application source. At a glance:' "$B2"   && grep -q '<!-- blueprint:relation from=src to=newmod kind=uses evidence=src/a/f1.py -->' "$B2"   && grep -q '<!-- blueprint:relation from=shared-config to=src kind=crosscuts evidence=src/a/f2.py -->' "$B2"   && grep -q '^## shared-config$' "$B2"   && grep -q -- '- `src` — Application source; \*\*code-owned\*\*' "$B2"; }
assert "render writes prose + relations + concern + TOC from one facts source" $? "$(grep -n 'Application source' "$B2")"
grep -q 'TODO(prose).*`docs`' "$B2"
assert "sections absent from facts keep their placeholder (partial render)" $? ""

# 17. render is idempotent
cp "$B2" "$B2.r1"
bash "$SLICER" render --root "$R2" --blueprint "$B2" --facts "$TMP/facts.txt" >/dev/null 2>&1
diff -q "$B2.r1" "$B2" >/dev/null; assert "re-render with same facts is byte-identical" $? "$(diff "$B2.r1" "$B2" | head -4)"
rm -f "$B2.r1"

# 16b. evidence patterns make claims FALSIFIABLE: path#pattern must be present
#      in the file at HEAD — a right pattern passes, a wrong one is rejected.
printf 'import newmod.helpers\n' > "$R2/src/a/f3.py"
git -C "$R2" add -A; git -C "$R2" commit -qm f3
cat > "$TMP/patfacts.txt" <<'FEOF'
blueprint-facts 1
section src
role Application source.
neighbor uses | newmod | imports its helpers | src/a/f3.py#newmod.helpers
FEOF
bash "$SLICER" render --root "$R2" --blueprint "$B2" --facts "$TMP/patfacts.txt" >/dev/null 2>&1
assert "pattern evidence present in file -> render accepts" $? ""
grep -q 'evidence=src/a/f3.py#newmod.helpers -->' "$B2"
assert "the pattern travels into the relation marker" $? ""
cat > "$TMP/patbad.txt" <<'FEOF'
blueprint-facts 1
section src
role Application source.
neighbor uses | newmod | invented | src/a/f3.py#does_not_appear
FEOF
perr="$(bash "$SLICER" render --root "$R2" --blueprint "$B2" --facts "$TMP/patbad.txt" 2>&1)"; prc=$?
{ [ "$prc" = 1 ] && echo "$perr" | grep -q "evidence pattern not found in src/a/f3.py: 'does_not_appear'"; }
assert "pattern absent from file -> render rejects the claim" $? "rc=$prc $perr"

# 18. render validation: every bad claim rejected, map untouched
cat > "$TMP/badfacts.txt" <<'FEOF'
blueprint-facts 1
section src
role R.
facet X | invented. | src/a/ghost.py
neighbor uses | phantom | nope | src/a/f1.py
neighbor uses | newmod | wrong side | newmod/n1.py
neighbor flows | newmod | bad kind | src/a/f1.py
FEOF
cp "$B2" "$B2.before"
bash "$SLICER" render --root "$R2" --blueprint "$B2" --facts "$TMP/badfacts.txt" >/dev/null 2>&1; brc=$?
{ [ "$brc" = 1 ] && diff -q "$B2.before" "$B2" >/dev/null; }
assert "invalid facts -> exit 1, map untouched" $? "rc=$brc"
n=$(bash "$SLICER" render --root "$R2" --blueprint "$B2" --facts "$TMP/badfacts.txt" 2>&1 | grep -c '^  - ')
[ "$n" = 4 ]; assert "all four invalid claims reported at once" $? "count=$n"
rm -f "$B2.before"

# 19. rendered relations satisfy the gate; concern invisible to verify
bash "$ORACLE" restamp --root "$R2" --blueprint "$B2" >/dev/null 2>&1
bash "$ORACLE" check --json --root "$R2" --blueprint "$B2" >/dev/null 2>&1
assert "rendered relations pass the gate's endpoint+evidence validation" $? ""
bash "$SLICER" verify --root "$R2" --blueprint "$B2" >/dev/null 2>&1
assert "rendered map still verify-conformant (concern/relations invisible)" $? ""

# 20. per-block edge authority is INTERNAL: repairing one section preserves
#     every other section's edges automatically — no caller-side rule.
cat > "$TMP/repair.txt" <<'FEOF'
blueprint-facts 1
section newmod
role A new module, now with a dependency.
neighbor uses | src | calls back into the app core | newmod/n1.py
FEOF
bash "$SLICER" render --root "$R2" --blueprint "$B2" --facts "$TMP/repair.txt" >/dev/null 2>&1
{ grep -q 'from=newmod to=src kind=uses' "$B2" \
  && grep -q 'from=src to=newmod kind=uses evidence=src/a/f3.py#newmod.helpers' "$B2" \
  && grep -q 'from=shared-config to=src kind=crosscuts' "$B2"; }
assert "partial repair adds its edge and preserves every other section's" $? "$(grep 'blueprint:relation' "$B2")"

# 21. a block with ZERO neighbors is authoritative too: it deletes its edges
cat > "$TMP/prune.txt" <<'FEOF'
blueprint-facts 1
section newmod
role A new module; the dependency was removed.
FEOF
bash "$SLICER" render --root "$R2" --blueprint "$B2" --facts "$TMP/prune.txt" >/dev/null 2>&1
{ ! grep -q 'from=newmod ' "$B2" && grep -q 'from=src to=newmod' "$B2"; }
assert "empty neighbor set prunes the block's own edges, nothing else" $? "$(grep 'blueprint:relation' "$B2")"

echo
echo "slicer tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
