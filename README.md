# Blueprint — Living Architecture Map

[![tests](https://github.com/ogil109/spec-kit-blueprint/actions/workflows/tests.yml/badge.svg)](https://github.com/ogil109/spec-kit-blueprint/actions/workflows/tests.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
![Spec Kit](https://img.shields.io/badge/Spec_Kit-%E2%89%A50.10-blue)
![status](https://img.shields.io/badge/status-experimental-orange)

A [Spec Kit](https://github.com/github/spec-kit) extension that keeps a **living
architecture map** of your project honest — and gives you a **deterministic,
low-friction, machine-first CI gate** that catches when the map, the specs, and the
code drift apart, no matter how a change was made.

It doesn't change how you build. It keeps the map true, and it's designed so a CI
step (or a CI agent) can **detect and heal drift automatically**.

> **What this is really about — drift, not retrieval.** Getting an agent to *read* your
> codebase is increasingly handled by your editor/agent. The unsolved half is keeping a
> project's architectural picture *current* as code changes out-of-band: *"code evolves,
> the specification does not… a linter does not flag it, CI does not flag it, the system
> ships with drift baked in."* This extension is a deterministic gate for exactly that.

## Who this is for

**Use it if** you practise spec-driven development (Spec Kit) on a **real, evolving —
often brownfield — codebase**, you feel the specs and the architecture picture going
stale as the code changes, and you want **CI to catch that drift** instead of discovering
it later.

**You probably don't need it if** you're just starting SDD on a small or greenfield
project (Spec Kit's core flow is enough), you want SDD *lighter*, or your pain is the
agent *not knowing your codebase* — that's retrieval, handled by your editor/agent; this
keeps the map *current*, it doesn't read the code for you.

## How to integrate

1. **Install** it into a Spec Kit project (below).
2. **`init` once** — from existing code (`--from-code`) or a design doc — to create the map.
3. **Add `check` to CI** — this is the integration point; it fails the build only when the
   map factually contradicts the specs/code (see the gate below).
4. **Keep building normally.** The map maintains itself as the gate nudges you
   (`distill` a shipped slice, `remap` after a refactor, `init --from-code` a new module).

## The tiered coherence gate (the core)

`check` is a deterministic gate (no LLM) that classifies every issue into two tiers, so
it can run in CI **without crying wolf on every commit**:

- 🔴 **HARD — the map *contradicts* reality → blocks the merge (exit 1).** Precise,
  low-false-positive:
  - **drift** — a built spec the map doesn't index (e.g. a spec born from an external
    tracker). → `distill`
  - **dangling** — a section pointing at code that's been deleted. → `remap`
- 🟡 **SOFT — the map *may* be behind → advisory, does NOT block (exit 0).** Coarse
  signals where the map is usually still true at architecture altitude:
  - **stale** — code changed under a mapped area (a refactor/hotfix, spec or not). → `remap`
  - **unmapped** — new code that no section maps (a module added out-of-band). → `init --from-code <path>`
  - **unmanaged** — a section `init` hasn't processed yet. → `init`
  - **unstamped** — a mapped area with no baseline yet. → `restamp`

`--strict` promotes SOFT to blocking for teams that want full enforcement. The exit code
is a first-class signal, independent of output format.

Running it looks like this (human-readable on a terminal):

```console
$ blueprint-state.sh check --human
HARD — the map contradicts reality (blocks merge):
  DRIFT     007-refunds  built spec not in the map   → /speckit.blueprint.distill 007-refunds

SOFT — the map may be behind (advisory):
  STALE     src/payments  code changed since mapped   → /speckit.blueprint.remap src/payments
  UNMAPPED  src/notifications  tracked code no section maps   → /speckit.blueprint.init --from-code src/notifications

1 blocking, 2 advisory
$ echo $?
1
```

```yaml
# .github/workflows/blueprint.yml — blocks only when the map is factually behind
- run: .specify/extensions/blueprint/scripts/bash/blueprint-state.sh check
```

## Machine-first output — built to be consumed

Following the git/`--porcelain` convention: **JSON when piped/non-interactive (CI, an
agent), human-readable on a terminal**; `--json`/`--human` force either.

```json
{ "blueprint_schema": "1", "command": "check", "in_sync": false,
  "blocking": 1, "advisory": 1,
  "issues": [
    { "severity": "hard", "type": "drift", "target": "007-refunds",
      "detail": "built spec not in the map",
      "remedy": { "run": "/speckit.blueprint.distill 007-refunds", "kind": "authored" } },
    { "severity": "soft", "type": "stale", "target": "src/payments",
      "detail": "code changed since mapped",
      "remedy": { "run": "blueprint-state.sh restamp --path src/payments", "kind": "deterministic" } }
  ] }
```

Each issue carries a **self-describing remedy** and its `kind`, so a CI LLM backend can
**self-heal**:

```
check --json → for each issue, run remedy.run:
  · kind=deterministic → apply + commit (safe, no LLM judgment)
  · kind=authored      → run the agent, land it as a reviewable PR
→ re-run check → exit 0 when the map matches reality
```

## Commands

| Command | What it does |
|---------|--------------|
| `speckit.blueprint.init` | Scaffold the map — from a design doc (greenfield) or `--from-code` to reverse-map existing code (brownfield). Idempotent. |
| `speckit.blueprint.status` | Read-only dashboard: detailed / settled / context / unmanaged sections, drift, where each spec stands. |
| `speckit.blueprint.distill` | Collapse a finished spec's section to a digest + pointer; stamp the slice's code baseline. |
| `speckit.blueprint.remap` | Re-derive a section from current code + refresh its git baseline (resync after out-of-band changes). |

Plus the script-level gate the commands and CI share: `blueprint-state.sh check` (the
tiered gate) and `blueprint-state.sh restamp` (deterministic baseline refresh).

## Install

```bash
specify extension add blueprint \
  --from https://github.com/ogil109/spec-kit-blueprint/releases/download/v1.0.0/blueprint.zip
# or, for local development:
specify extension add --dev /path/to/spec-kit-blueprint
```

**Requirements:** a Spec Kit project (`.specify/`), **Spec Kit ≥ 0.10**, **git** (for the
code-baseline checks), and **bash** (Unix/macOS). A PowerShell port exists but is not yet
execution-verified on Windows.

## Quickstart

```bash
# Brownfield — reverse-map an existing repo into a code-owned map
/speckit.blueprint.init --from-code
/speckit.blueprint.status

# Greenfield — seed the map from a design doc
/speckit.blueprint.init docs/master-spec.md

# Build with your normal spec-kit flow; when a slice ships, collapse it into the map:
/speckit.blueprint.distill 001-some-slice

# Keep it honest in CI (blocks only on hard drift; --strict to block on advisories too)
blueprint-state.sh check
/speckit.blueprint.remap src/payments   # after a change flagged STALE
```

## The blueprint document

An annotated table of contents is the index + architecture map. Each managed section
carries a **provenance marker** under its heading — the extension's deterministic record
of what it has processed:

```markdown
## 3. Payments
<!-- blueprint:section state=distilled owner=specs/007-refunds -->
> **Distilled — owned by `specs/007-refunds`** (implemented at `src/payments/`).
<!-- blueprint:code path=src/payments sha=a1b2c3 -->
```

Section states: `detailed` (holding pen), `distilled owner=specs/<slug>`, `code`
(brownfield), or `context` (framing — not a buildable slice). Code-mapping sections also
carry a git-baseline marker. The prose banners are cosmetic — the **markers** are what
the gate reads, so a hand-written banner can't fool it. `init` is **idempotent and
non-destructive**: it stamps unmanaged sections, preserves managed ones, and never
deletes content — so it also **formalizes an existing master doc** in place.

## Autonomous harness (optional second payoff)

Because the map is externalized state and the oracle computes the single next action
deterministically, the same pieces are a **harness for long, multi-spec agent sessions**
— an agent loops on `blueprint-state.sh next`, re-grounding on the filesystem each step
so it can't drift. It's a documented pattern (no extra command); see
[docs/autonomous-harness.md](./docs/autonomous-harness.md). `tests/harness_loop_test.sh`
proves the loop sequences specs correctly (parking, stop bounds); the agent's authoring
*within* a phase stays reviewed, not proven.

## Honest boundaries

- **Detection, not conformance.** The gate flags that the map is *behind* reality (a
  spec not indexed, code that moved) — it does **not** verify the code *correctly*
  implements its spec, and it doesn't check architectural boundaries. That deeper
  conformance is a heavier, language-specific problem this deliberately doesn't tackle.
- **A structural gate with one known blind spot.** It detects *new* code (the `unmapped`
  signal) and *changed* mapped code, but it does **not** verify whether a distilled
  **digest still faithfully reflects its spec** — it checks the *pointer*, not the prose.
  Treat digests as human-reviewed content, not verified fact.
- **The friction dial is the bet.** Making `stale` advisory (not blocking) is what makes
  the gate usable in real CI; the tradeoff is that out-of-band code changes are *surfaced
  and reconciled*, not hard-blocked (unless `--strict`). Whether this balance is right for
  a given team is exactly what real usage will tell us.
- **Map content is agent-authored.** `init` (mapping a repo) and `distill` (writing a
  digest) are done by the agent and reviewed; only the **gate and the oracle** are
  deterministic. When the map feeds every spec, its authoring quality matters.
- **Prior art:** the "spec↔code drift gate" concept has been articulated in the 2026
  literature (e.g. arXiv 2606.27045). This extension's angle is being **brownfield-first,
  language-agnostic (git baselines, not per-language static analysis), low-friction, and
  shipped as a spec-kit extension** — rather than a greenfield, graph-based framework.

## Status of this extension

- Bash oracle + tiered gate: **tested** — `tests/oracle_test.sh` (state frontier,
  provenance, context) and `tests/check_remap_test.sh` (hard/soft tiers, the friction
  fix, `--strict`, and the JSON contract), against a real git repo. Dogfooded on a real
  2,100-line brownfield project.
- Harness loop: **tested** — `tests/harness_loop_test.sh`.
- PowerShell port (`scripts/powershell/blueprint-state.ps1`): mirrored for parity;
  **needs execution-verification on a Windows/pwsh environment**.

This is an early, honestly-scoped extension: the deterministic gate is tested and
dogfooded; whether its low-friction balance is right for *your* team is exactly what
we'd like to learn.

## Support

Questions, bugs, or "it flagged X and shouldn't have" — please open an issue on the
[repository](https://github.com/ogil109/spec-kit-blueprint). Feedback on the gate's
friction (false positives/negatives on a real repo) is especially welcome.

## Contributing

Contributions welcome — this is a community Spec Kit extension. The oracle/gate is a
single Bash script with **no dependencies beyond bash + git**, so the tests run anywhere:

```bash
bash tests/oracle_test.sh          # state frontier, provenance, context
bash tests/check_remap_test.sh     # the tiered gate: hard/soft, --strict, JSON contract
bash tests/harness_loop_test.sh    # the autonomous-harness loop
```

Iterate locally with `specify extension add --dev /path/to/spec-kit-blueprint`. Please open an
issue to discuss anything larger than a fix before sending a PR. The PowerShell port
(`scripts/powershell/blueprint-state.ps1`) needs a Windows/pwsh maintainer to verify it.

## Authors & acknowledgment

Built by [ogil109](https://github.com/ogil109), with AI assistance (Claude Code) per
Spec Kit's contributing guidelines. The drift-gate concept builds on ideas in the 2026
spec-driven-development literature (see *Honest boundaries*).

## License

[MIT](./LICENSE).
