#!/usr/bin/env bash
# Tests for the CI coherence gate: `check` (distill drift + code staleness) and
# `restamp`. Builds a real git repo, moves code under a mapped section, and asserts
# the gate catches changes that never went through a spec.
set -uo pipefail

ORACLE="$(cd "$(dirname "$0")/.." && pwd)/blueprint/scripts/bash/blueprint-state.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n        %s\n' "$1" "$2"; }

R="$TMP/repo"; mkdir -p "$R/src/payments" "$R/.specify"
git -C "$R" init -q
git -C "$R" config user.email t@t; git -C "$R" config user.name t
printf 'def charge(): pass\n' > "$R/src/payments/pay.py"
git -C "$R" add -A; git -C "$R" commit -qm init
BP="$R/blueprint.md"

# blueprint with a code-owned section + an unstamped marker
cat > "$BP" <<'EOF'
# Blueprint
## 1. Payments
> **Distilled — owned by code at `src/payments/`.** (no spec yet)
<!-- blueprint:code path=src/payments sha=NONE -->
Charges via Stripe.
EOF

run() { bash "$ORACLE" "$@" --root "$R" --blueprint "$BP" 2>&1; }

# 1. unstamped marker -> check fails, asks for remap
out="$(run check)"; rc=$?
{ [ "$rc" -ne 0 ] && echo "$out" | grep -q UNSTAMPED; } && ok "unstamped marker fails check" \
  || bad "unstamped marker fails check" "$out"

# 2. restamp records the baseline -> check passes
run restamp >/dev/null
out="$(run check)"; rc=$?
{ [ "$rc" -eq 0 ] && echo "$out" | grep -q "in sync"; } && ok "restamp makes check pass" \
  || bad "restamp makes check pass" "rc=$rc $out"

# 3. out-of-band code change (no spec!) -> check flags STALE, exits nonzero
printf 'def charge(): return 1\n' > "$R/src/payments/pay.py"
git -C "$R" add -A; git -C "$R" commit -qm "hotfix, no spec"
out="$(run check)"; rc=$?
{ [ "$rc" -ne 0 ] && echo "$out" | grep -q "STALE.*src/payments"; } && ok "specless code change flagged STALE" \
  || bad "specless code change flagged STALE" "rc=$rc $out"

# 4. remap (here: restamp the path) re-syncs -> check passes again
run restamp --path src/payments >/dev/null
out="$(run check)"; rc=$?
{ [ "$rc" -eq 0 ]; } && ok "remap re-syncs the section" || bad "remap re-syncs the section" "rc=$rc $out"

# 5. mapped code deleted -> DANGLING
git -C "$R" rm -q -r src/payments; git -C "$R" commit -qm "remove payments"
out="$(run check)"; rc=$?
{ [ "$rc" -ne 0 ] && echo "$out" | grep -q DANGLING; } && ok "deleted mapped code flagged DANGLING" \
  || bad "deleted mapped code flagged DANGLING" "rc=$rc $out"

# 6. distill drift (built spec not referenced) also fails check
R2="$TMP/repo2"; mkdir -p "$R2/specs/001-foo" "$R2/.specify"
git -C "$R2" init -q; git -C "$R2" config user.email t@t; git -C "$R2" config user.name t
printf 'spec\n' > "$R2/specs/001-foo/spec.md"; printf 'plan\n' > "$R2/specs/001-foo/plan.md"
printf -- '- [x] done\n' > "$R2/specs/001-foo/tasks.md"
printf '# BP\n## Foo\n> **Detailed (unspecced)** — holding pen.\n' > "$R2/blueprint.md"
out="$(bash "$ORACLE" check --root "$R2" --blueprint "$R2/blueprint.md" 2>&1)"; rc=$?
{ [ "$rc" -ne 0 ] && echo "$out" | grep -q DRIFT; } && ok "distill drift fails check" \
  || bad "distill drift fails check" "rc=$rc $out"

# 7. SPEC-OWNED slice carrying an implementation-footprint marker: code edited
#    out-of-band (no spec change) is flagged STALE — the gap this closes. The spec
#    is built + referenced (no distill drift), so the ONLY signal is code staleness.
R3="$TMP/repo3"; mkdir -p "$R3/src/orders" "$R3/specs/007-orders" "$R3/.specify"
git -C "$R3" init -q; git -C "$R3" config user.email t@t; git -C "$R3" config user.name t
printf 'def place(): pass\n' > "$R3/src/orders/o.py"
printf 'spec\n' > "$R3/specs/007-orders/spec.md"; printf 'plan\n' > "$R3/specs/007-orders/plan.md"
printf -- '- [x] done\n' > "$R3/specs/007-orders/tasks.md"
cat > "$R3/blueprint.md" <<'EOF'
# BP
## Orders
> **Distilled — owned by `specs/007-orders`** (implemented at `src/orders/`).
<!-- blueprint:code path=src/orders sha=NONE -->
Places orders.
EOF
git -C "$R3" add -A; git -C "$R3" commit -qm init
run3() { bash "$ORACLE" "$@" --root "$R3" --blueprint "$R3/blueprint.md" 2>&1; }
run3 restamp >/dev/null
out="$(run3 check)"; rc=$?
{ [ "$rc" -eq 0 ]; } && ok "spec-owned + stamped -> in sync" || bad "spec-owned + stamped -> in sync" "rc=$rc $out"
printf 'def place(): return 1\n' > "$R3/src/orders/o.py"
git -C "$R3" add -A; git -C "$R3" commit -qm "edit orders code, no spec change"
out="$(run3 check)"; rc=$?
{ [ "$rc" -ne 0 ] && echo "$out" | grep -q "STALE.*src/orders"; } && ok "spec-owned code edit flagged STALE" \
  || bad "spec-owned code edit flagged STALE" "rc=$rc $out"

echo
echo "check/remap tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
