#!/usr/bin/env bash
# Behavioral tests for the deterministic oracle (blueprint-state.sh).
# Builds fixture repos in a tmp dir and asserts `next --json` phase/reason.
# No dependencies beyond bash + the oracle itself.
set -uo pipefail

ORACLE="$(cd "$(dirname "$0")/.." && pwd)/blueprint/scripts/bash/blueprint-state.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

# mkroot <name> — create a fixture repo root, echo its path
mkroot() { local d="$TMP/$1"; mkdir -p "$d/specs" "$d/.specify"; echo "$d"; }

# field <json> <key> — extract a string/bool field value
field() { echo "$1" | sed -E "s/.*\"$2\": ?\"?([^\",}]*)\"?.*/\1/"; }

# expect <label> <root> <blueprint> <key> <want>
expect() {
  local label="$1" root="$2" bp="$3" key="$4" want="$5"
  local out got
  out="$(bash "$ORACLE" next --json --root "$root" --blueprint "$bp" 2>&1)"
  got="$(field "$out" "$key")"
  if [ "$got" = "$want" ]; then
    PASS=$((PASS+1)); printf '  ok   %-42s %s=%s\n' "$label" "$key" "$got"
  else
    FAIL=$((FAIL+1)); printf '  FAIL %-42s want %s=%s got "%s"\n      json: %s\n' "$label" "$key" "$want" "$got" "$out"
  fi
}
# expect_reason <label> <root> <blueprint> <substr>
expect_reason() {
  local label="$1" root="$2" bp="$3" sub="$4" out
  out="$(bash "$ORACLE" next --json --root "$root" --blueprint "$bp" 2>&1)"
  if echo "$out" | grep -q "$sub"; then
    PASS=$((PASS+1)); printf '  ok   %-42s reason~%s\n' "$label" "$sub"
  else
    FAIL=$((FAIL+1)); printf '  FAIL %-42s reason missing "%s"\n      json: %s\n' "$label" "$sub" "$out"
  fi
}

# 1. greenfield: a Detailed holding-pen section, no specs -> specify
r="$(mkroot greenfield)"
printf '## 1. Auth\n> **Detailed (unspecced)** — holding pen.\n' > "$r/blueprint.md"
expect "greenfield detailed -> specify" "$r" "$r/blueprint.md" phase specify

# 2. organic overview doc: no banners at all, no specs -> specify (preserved)
r="$(mkroot organic)"
printf '# Overview\nSome prose describing subsystems with no banners.\n' > "$r/blueprint.md"
expect "organic doc (no banners) -> specify" "$r" "$r/blueprint.md" phase specify

# 3. brownfield adopted: only code-owned settled sections, no specs -> done (idle)
r="$(mkroot brownfield)"
printf '## 1. Auth\n> **Distilled — owned by code at `src/auth/`.** (no spec yet)\n' > "$r/blueprint.md"
expect "brownfield all-settled -> done"  "$r" "$r/blueprint.md" phase done
expect_reason "brownfield idle reason"   "$r" "$r/blueprint.md" "owned by a spec or by code"

# 4. spec without plan, referenced in blueprint -> plan
r="$(mkroot needplan)"; mkdir -p "$r/specs/001-foo"
printf 'spec body, no clarification markers\n' > "$r/specs/001-foo/spec.md"
printf '## 1. Foo\n> **Distilled — owned by `specs/001-foo`.**\n' > "$r/blueprint.md"
expect "spec w/o plan -> plan"           "$r" "$r/blueprint.md" phase plan
expect "spec w/o plan -> slug"           "$r" "$r/blueprint.md" slug 001-foo

# 5. clarification markers -> clarify
r="$(mkroot needclarify)"; mkdir -p "$r/specs/001-foo"
printf 'has a [NEEDS CLARIFICATION: scope?] marker\n' > "$r/specs/001-foo/spec.md"
printf '## 1. Foo\n> **Distilled — owned by `specs/001-foo`.**\n' > "$r/blueprint.md"
expect "clarification markers -> clarify" "$r" "$r/blueprint.md" phase clarify

# 6. distill drift: built spec NOT referenced by blueprint -> distill
r="$(mkroot drift)"; mkdir -p "$r/specs/001-foo"
printf 'done\n' > "$r/specs/001-foo/spec.md"
printf 'done\n' > "$r/specs/001-foo/plan.md"
printf -- '- [x] all done\n' > "$r/specs/001-foo/tasks.md"
printf '## 1. Foo\n> **Detailed (unspecced)** — holding pen.\n' > "$r/blueprint.md"
expect "unreferenced built spec -> distill" "$r" "$r/blueprint.md" phase distill

# 7. all built + referenced -> done
r="$(mkroot alldone)"; mkdir -p "$r/specs/001-foo"
printf 'done\n' > "$r/specs/001-foo/spec.md"
printf 'done\n' > "$r/specs/001-foo/plan.md"
printf -- '- [x] all done\n' > "$r/specs/001-foo/tasks.md"
printf '## 1. Foo\n> **Distilled — owned by `specs/001-foo`.**\n' > "$r/blueprint.md"
expect "all built + referenced -> done"  "$r" "$r/blueprint.md" phase done

# 8. in-flight (planned, not built) + unreferenced -> tasks, NOT distill
#    (distill is the slice's LAST step, after implement — not the moment spec.md appears)
r="$(mkroot inflight_unref)"; mkdir -p "$r/specs/001-foo"
printf 'spec\n' > "$r/specs/001-foo/spec.md"
printf 'plan\n' > "$r/specs/001-foo/plan.md"
printf '## 1. Foo\n> **Detailed (unspecced)** — holding pen.\n' > "$r/blueprint.md"
expect "in-flight unreferenced -> tasks (not distill)" "$r" "$r/blueprint.md" phase tasks

# 9. --skip excludes a slug from consideration (e.g. a slice deliberately set aside)
r="$(mkroot skiptest)"; mkdir -p "$r/specs/001-foo"
printf 'spec\n' > "$r/specs/001-foo/spec.md"
printf '## 1. Foo\n> **Detailed (unspecced)** — holding pen. (slug: 001-foo)\n' > "$r/blueprint.md"
g1="$(field "$(bash "$ORACLE" next --json --root "$r" --blueprint "$r/blueprint.md")" phase)"
g2="$(field "$(bash "$ORACLE" next --json --root "$r" --blueprint "$r/blueprint.md" --skip 001-foo)" phase)"
if [ "$g1" = "plan" ] && [ "$g2" = "specify" ]; then
  PASS=$((PASS+1)); printf '  ok   %-42s noskip=plan skip=specify\n' "--skip excludes parked slug"
else
  FAIL=$((FAIL+1)); printf '  FAIL %-42s noskip=%s skip=%s\n' "--skip excludes parked slug" "$g1" "$g2"
fi

echo
echo "oracle tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
