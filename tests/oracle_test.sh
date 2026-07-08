#!/usr/bin/env bash
# Behavioral tests for the deterministic oracle (blueprint-state.sh).
# Builds fixture repos in a tmp dir and asserts `next --json` phase/reason.
# Section state is read from machine markers (<!-- blueprint:section state=... -->),
# never from prose banners — a heading with no marker is UNMANAGED (pending backlog).
set -uo pipefail

ORACLE="$(cd "$(dirname "$0")/.." && pwd)/blueprint/scripts/bash/blueprint-state.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

mkroot() { local d="$TMP/$1"; mkdir -p "$d/specs" "$d/.specify"; echo "$d"; }
field() { echo "$1" | sed -E "s/.*\"$2\": ?\"?([^\",}]*)\"?.*/\1/"; }

expect() { # label root blueprint key want
  local label="$1" root="$2" bp="$3" key="$4" want="$5" out got
  out="$(bash "$ORACLE" next --json --root "$root" --blueprint "$bp" 2>&1)"
  got="$(field "$out" "$key")"
  if [ "$got" = "$want" ]; then PASS=$((PASS+1)); printf '  ok   %-46s %s=%s\n' "$label" "$key" "$got"
  else FAIL=$((FAIL+1)); printf '  FAIL %-46s want %s=%s got "%s"\n      %s\n' "$label" "$key" "$want" "$got" "$out"; fi
}
expect_reason() { # label root blueprint substr
  local label="$1" root="$2" bp="$3" sub="$4" out
  out="$(bash "$ORACLE" next --json --root "$root" --blueprint "$bp" 2>&1)"
  if echo "$out" | grep -q "$sub"; then PASS=$((PASS+1)); printf '  ok   %-46s reason~%s\n' "$label" "$sub"
  else FAIL=$((FAIL+1)); printf '  FAIL %-46s reason missing "%s"\n      %s\n' "$label" "$sub" "$out"; fi
}

# 0. raw doc: ## sections but NO markers -> init (never silently "done"; finding #1)
r="$(mkroot raw)"
printf '## 1. Auth\nprose\n## 2. Billing\nprose\n' > "$r/blueprint.md"
expect "raw sections, no markers -> init" "$r" "$r/blueprint.md" phase init

# 1. a managed detailed section, no specs -> specify
r="$(mkroot greenfield)"
printf '## 1. Auth\n<!-- blueprint:section state=detailed -->\n> **Detailed (unspecced)** — holding pen.\n' > "$r/blueprint.md"
expect "managed detailed -> specify" "$r" "$r/blueprint.md" phase specify

# 2. code-owned settled section (brownfield), no specs -> done (idle)
r="$(mkroot brownfield)"
printf '## 1. Auth\n<!-- blueprint:section state=code -->\n> **Distilled — owned by code at `src/auth/`.**\n' > "$r/blueprint.md"
expect "code-owned settled -> done"  "$r" "$r/blueprint.md" phase done
expect_reason "settled idle reason"  "$r" "$r/blueprint.md" "settled (owned by a spec or by code)"

# 3. spec without plan (in-flight) -> plan
r="$(mkroot needplan)"; mkdir -p "$r/specs/001-foo"
printf 'spec body\n' > "$r/specs/001-foo/spec.md"
printf '## 1. Foo\n<!-- blueprint:section state=detailed -->\n' > "$r/blueprint.md"
expect "spec w/o plan -> plan" "$r" "$r/blueprint.md" phase plan
expect "spec w/o plan -> slug" "$r" "$r/blueprint.md" slug 001-foo

# 4. clarification markers -> clarify
r="$(mkroot needclarify)"; mkdir -p "$r/specs/001-foo"
printf 'has a [NEEDS CLARIFICATION: scope?] marker\n' > "$r/specs/001-foo/spec.md"
printf '## 1. Foo\n<!-- blueprint:section state=detailed -->\n' > "$r/blueprint.md"
expect "clarification markers -> clarify" "$r" "$r/blueprint.md" phase clarify

# 5. distill drift: built spec NOT referenced -> distill
r="$(mkroot drift)"; mkdir -p "$r/specs/001-foo"
printf 'x\n' > "$r/specs/001-foo/spec.md"; printf 'x\n' > "$r/specs/001-foo/plan.md"
printf -- '- [x] done\n' > "$r/specs/001-foo/tasks.md"
printf '## 1. Foo\n<!-- blueprint:section state=detailed -->\n' > "$r/blueprint.md"
expect "unreferenced built spec -> distill" "$r" "$r/blueprint.md" phase distill

# 6. all built + referenced (settled marker) -> done
r="$(mkroot alldone)"; mkdir -p "$r/specs/001-foo"
printf 'x\n' > "$r/specs/001-foo/spec.md"; printf 'x\n' > "$r/specs/001-foo/plan.md"
printf -- '- [x] done\n' > "$r/specs/001-foo/tasks.md"
printf '## 1. Foo\n<!-- blueprint:section state=distilled owner=specs/001-foo -->\n' > "$r/blueprint.md"
expect "all built + referenced -> done" "$r" "$r/blueprint.md" phase done

# 7. in-flight (planned, not built) + unreferenced -> tasks, NOT distill
r="$(mkroot inflight_unref)"; mkdir -p "$r/specs/001-foo"
printf 'x\n' > "$r/specs/001-foo/spec.md"; printf 'x\n' > "$r/specs/001-foo/plan.md"
printf '## 1. Foo\n<!-- blueprint:section state=detailed -->\n' > "$r/blueprint.md"
expect "in-flight unreferenced -> tasks (not distill)" "$r" "$r/blueprint.md" phase tasks

# 8. --skip excludes a slug from consideration
r="$(mkroot skiptest)"; mkdir -p "$r/specs/001-foo"
printf 'spec\n' > "$r/specs/001-foo/spec.md"
printf '## 1. Foo\n<!-- blueprint:section state=detailed -->\n' > "$r/blueprint.md"
g1="$(field "$(bash "$ORACLE" next --json --root "$r" --blueprint "$r/blueprint.md")" phase)"
g2="$(field "$(bash "$ORACLE" next --json --root "$r" --blueprint "$r/blueprint.md" --skip 001-foo)" phase)"
if [ "$g1" = "plan" ] && [ "$g2" = "specify" ]; then
  PASS=$((PASS+1)); printf '  ok   %-46s noskip=plan skip=specify\n' "--skip excludes parked slug"
else
  FAIL=$((FAIL+1)); printf '  FAIL %-46s noskip=%s skip=%s\n' "--skip excludes parked slug" "$g1" "$g2"
fi

echo
echo "oracle tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
