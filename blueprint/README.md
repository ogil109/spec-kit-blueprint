# Blueprint — Living Architecture Map

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
  - **unmanaged** — a section `init` hasn't processed yet. → `init`
  - **unstamped** — a mapped area with no baseline yet. → `restamp`

`--strict` promotes SOFT to blocking for teams that want full enforcement. The exit code
is a first-class signal, independent of output format.

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
  --from https://github.com/ogil109/spec-kit-extensions/releases/download/blueprint-v1.0.0/blueprint.zip
# or, for local development:
specify extension add --dev /path/to/spec-kit-extensions/blueprint
```

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
