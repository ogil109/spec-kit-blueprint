#!/usr/bin/env bash
# Tests for the tiered coherence gate: `check` (hard/soft severity, JSON contract) +
# `restamp`. HARD = the map contradicts reality (blocks, exit 1). SOFT = the map may be
# behind (advisory, exit 0 unless --strict). Built against a real git repo.
set -uo pipefail

ORACLE="$(cd "$(dirname "$0")/.." && pwd)/scripts/bash/blueprint-state.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n        %s\n' "$1" "$2"; }

# gate <check-args...> : sets OUT (human text) and RC (exit code)
gate() {
  OUT="$(bash "$ORACLE" check --human "$@" 2>/dev/null)"
  bash "$ORACLE" check "$@" >/dev/null 2>&1; RC=$?
}
assert() { # label condition-result detail
  [ "$2" = 0 ] && ok "$1" || bad "$1" "$3"
}

R="$TMP/repo"; mkdir -p "$R/src/payments" "$R/.specify"
git -C "$R" init -q; git -C "$R" config user.email t@t; git -C "$R" config user.name t
printf 'def charge(): pass\n' > "$R/src/payments/pay.py"
git -C "$R" add -A; git -C "$R" commit -qm init
BP="$R/blueprint.md"
cat > "$BP" <<'EOF'
# Blueprint
## 1. Payments
<!-- blueprint:section state=code -->
> **Distilled — owned by code at `src/payments/`.**
<!-- blueprint:code path=src/payments sha=NONE -->
EOF
A=(--root "$R" --blueprint "$BP")

# 1. unstamped -> SOFT: advisory (exit 0) by default; blocks under --strict
gate "${A[@]}"
{ echo "$OUT" | grep -q UNSTAMPED && [ "$RC" = 0 ]; }; assert "unstamped is advisory (exit 0)" $? "rc=$RC $OUT"
gate --strict "${A[@]}"; [ "$RC" = 1 ]; assert "unstamped blocks under --strict (exit 1)" $? "rc=$RC"

# 2. restamp -> in sync (exit 0)
bash "$ORACLE" restamp "${A[@]}" >/dev/null 2>&1
gate "${A[@]}"; { echo "$OUT" | grep -q "in sync" && [ "$RC" = 0 ]; }; assert "restamp -> in sync (exit 0)" $? "$OUT"

# 3. out-of-band code change -> STALE, SOFT: does NOT block (exit 0); --strict blocks
printf 'def charge(): return 1\n' > "$R/src/payments/pay.py"
git -C "$R" add -A; git -C "$R" commit -qm "hotfix, no spec"
gate "${A[@]}"
{ echo "$OUT" | grep -q "STALE.*src/payments" && [ "$RC" = 0 ]; }; assert "specless change is advisory, not blocking (friction fix)" $? "rc=$RC $OUT"
gate --strict "${A[@]}"; [ "$RC" = 1 ]; assert "stale blocks under --strict (exit 1)" $? "rc=$RC"

# 4. restamp re-syncs -> exit 0
bash "$ORACLE" restamp --path src/payments "${A[@]}" >/dev/null 2>&1
gate "${A[@]}"; [ "$RC" = 0 ]; assert "re-stamp clears stale (exit 0)" $? "rc=$RC $OUT"

# 5. mapped code deleted -> DANGLING, HARD: always blocks (exit 1)
git -C "$R" rm -q -r src/payments; git -C "$R" commit -qm "remove payments"
gate "${A[@]}"; { echo "$OUT" | grep -q DANGLING && [ "$RC" = 1 ]; }; assert "deleted mapped code is HARD (blocks)" $? "$OUT"

# 6. distill drift (built spec not in map) -> DRIFT, HARD: blocks (exit 1)
R2="$TMP/repo2"; mkdir -p "$R2/specs/001-foo" "$R2/.specify"
git -C "$R2" init -q; git -C "$R2" config user.email t@t; git -C "$R2" config user.name t
printf 'x\n' > "$R2/specs/001-foo/spec.md"; printf 'x\n' > "$R2/specs/001-foo/plan.md"
printf -- '- [x] d\n' > "$R2/specs/001-foo/tasks.md"
printf '# BP\n## Foo\n<!-- blueprint:section state=detailed -->\n' > "$R2/blueprint.md"
B=(--root "$R2" --blueprint "$R2/blueprint.md")
gate "${B[@]}"; { echo "$OUT" | grep -q DRIFT && [ "$RC" = 1 ]; }; assert "distill drift is HARD (blocks)" $? "rc=$RC $OUT"

# 7. JSON contract: valid, versioned, severity/type/remedy.kind
json="$(bash "$ORACLE" check --json "${B[@]}" 2>/dev/null)"
echo "$json" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['blueprint_schema']=='1' and d['command']=='check' and d['in_sync'] is False
i=d['issues'][0]
assert i['severity']=='hard' and i['type']=='drift'
assert i['remedy']['kind']=='authored' and 'distill' in i['remedy']['run']
" >/dev/null 2>&1; assert "check --json emits versioned contract (severity/type/remedy.kind)" $? "$json"

# 8. unmapped code (coverage): a new src area no section maps -> SOFT, advisory
R4="$TMP/repo4"; mkdir -p "$R4/src/mapped" "$R4/src/newmod/sub" "$R4/.specify"
git -C "$R4" init -q; git -C "$R4" config user.email t@t; git -C "$R4" config user.name t
printf 'x\n' > "$R4/src/mapped/a.py"; printf 'x\n' > "$R4/src/newmod/b.py"; printf 'x\n' > "$R4/src/newmod/sub/c.py"
cat > "$R4/blueprint.md" <<'EOF'
# BP
## Mapped
<!-- blueprint:section state=code -->
<!-- blueprint:code path=src/mapped sha=NONE -->
EOF
git -C "$R4" add -A; git -C "$R4" commit -qm init
C=(--root "$R4" --blueprint "$R4/blueprint.md")
bash "$ORACLE" restamp "${C[@]}" >/dev/null 2>&1   # baseline src/mapped so it's not unstamped noise
gate "${C[@]}"
{ echo "$OUT" | grep -q "UNMAPPED.*src/newmod" && [ "$RC" = 0 ]; }; assert "new unmapped code flagged SOFT (exit 0)" $? "rc=$RC $OUT"
n=$(echo "$OUT" | grep -c UNMAPPED); [ "$n" = 1 ]; assert "unmapped collapses to one area (not per-file)" $? "count=$n"
json2="$(bash "$ORACLE" check --json "${C[@]}" 2>/dev/null)"
echo "$json2" | python3 -c "
import json,sys
u=[i for i in json.load(sys.stdin)['issues'] if i['type']=='unmapped']
assert u and u[0]['target']=='src/newmod' and 'from-code' in u[0]['remedy']['run']
" >/dev/null 2>&1; assert "unmapped JSON remedy = init --from-code src/newmod" $? "$json2"
gate --strict "${C[@]}"; [ "$RC" = 1 ]; assert "unmapped blocks under --strict" $? "rc=$RC"

# 9. unmanaged (unmarked section) — the ONLY issue with an empty target field.
#    Regression guard: records were once \t-joined and read back with tab IFS, which
#    (tab being whitespace) collapsed the empty target and shifted every later field,
#    corrupting target/detail/remedy in BOTH JSON and human output. Every OTHER issue
#    type carries a non-empty target, so this case alone exercises empty-field handling.
R5="$TMP/repo5"; mkdir -p "$R5/.specify"
git -C "$R5" init -q; git -C "$R5" config user.email t@t; git -C "$R5" config user.name t
printf '# BP\n## A section with no marker\nDesign detail.\n' > "$R5/blueprint.md"
git -C "$R5" add -A; git -C "$R5" commit -qm init
D=(--root "$R5" --blueprint "$R5/blueprint.md")
umjson="$(bash "$ORACLE" check --json "${D[@]}" 2>/dev/null)"
echo "$umjson" | python3 -c "
import json,sys
u=[i for i in json.load(sys.stdin)['issues'] if i['type']=='unmanaged']
assert u, 'no unmanaged issue emitted'
i=u[0]
assert i['target']=='', f\"target should be empty, got {i['target']!r}\"
assert 'not processed' in i['detail'], f\"detail wrong: {i['detail']!r}\"
assert i['remedy']['run']=='/speckit.blueprint.init', f\"run shifted: {i['remedy']['run']!r}\"
assert i['remedy']['kind']=='authored', f\"kind shifted: {i['remedy']['kind']!r}\"
" >/dev/null 2>&1; assert "unmanaged (empty target) keeps fields aligned in JSON" $? "$umjson"
umhuman="$(bash "$ORACLE" check --human "${D[@]}" 2>/dev/null)"
echo "$umhuman" | grep -q 'UNMANAGED .* → /speckit.blueprint.init'; assert "unmanaged human remedy is the init command, not a shifted field" $? "$umhuman"

echo
echo "check/gate tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
