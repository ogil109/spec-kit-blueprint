# Blueprint — Living Architecture Map

A [Spec Kit](https://github.com/github/spec-kit) extension that gives a spec-driven
project **one living architecture map that stays honest as the project evolves** —
and a **deterministic CI gate** that fails the build when the map, the specs, and the
code drift apart.

It doesn't change how you build. It keeps the map true — **no matter where a change
comes from**: a new spec, a ticket in an external tracker, or a raw code edit.

And because that map is **externalized project state** with a **deterministic
next-action**, the same two pieces double as a **harness for autonomous, multi-spec
agent sessions** — see [Autonomous waterfall harness](#autonomous-waterfall-harness-same-map-second-payoff).

## The problem it solves

Teams adopting spec-driven development start from a design doc, slice it into specs,
and then fight drift: the design doc and the specs hold the same detail twice (endless
back-sync), and over time the specs, the docs, and the code diverge until the
"documentation" can't be trusted. The blueprint is a *decreasing-detail* map that
removes the duplication and makes the drift **detectable**.

- A section holds full design **only while design work is pending** (the holding pen).
- Once an **owner** holds the truth, the section collapses to a digest + pointer. The
  owner is a **feature spec** (`specs/<slug>`) or the **code** (`src/...`, brownfield).
- Detail flows out into specs **once, forward — never back-synced**. The map asymptotes
  to a clean architecture index.

## The coherence gate (the core)

The map is only worth trusting if it's provably current. `check` is a **deterministic,
CI-friendly** gate (no LLM) that exits non-zero on either drift signal:

- **Distill drift** — a built spec the map hasn't collapsed yet (e.g. a spec born from
  an external tracker, not the blueprint). → run `distill`.
- **Code staleness** — any section that maps a `src/` area records a git baseline
  (`<!-- blueprint:code path=src/area sha=… -->`). When that code changes **without
  going through a spec** — a refactor, a hotfix — the gate flags it `STALE`. This covers
  both brownfield code-owned sections **and** the code behind already-shipped specs.
  → run `remap`.

```bash
# fails (exit 1) if any spec is un-distilled, or any mapped code moved/vanished
.specify/extensions/blueprint/scripts/bash/blueprint-state.sh check
```

```yaml
# .github/workflows/blueprint.yml
- name: Blueprint coherence
  run: .specify/extensions/blueprint/scripts/bash/blueprint-state.sh check
```

Most commits don't trip it — the map is **map-altitude**, so a bug fix that doesn't
change a section's claims won't flag (a re-`remap` just refreshes the baseline).

## Commands

| Command | What it does |
|---------|--------------|
| `speckit.blueprint.init` | Scaffold the map — from a design doc (greenfield) or `--from-code` to reverse-map existing code (brownfield). |
| `speckit.blueprint.status` | Read-only dashboard: detailed vs settled sections, distill drift, where each spec stands. |
| `speckit.blueprint.distill` | Collapse a finished spec's section to a digest + pointer, and stamp the slice's code baseline. |
| `speckit.blueprint.remap` | Re-derive a section from current code + refresh its git baseline (resync after out-of-band code changes). |

Plus the script-level gate the commands and CI share:
`blueprint-state.sh check` (detect drift) and `blueprint-state.sh restamp` (refresh
baselines).

## Install

```bash
specify extension add blueprint \
  --from https://github.com/ogil109/spec-kit-extensions/releases/download/blueprint-v1.0.0/blueprint.zip
# or, for local development:
specify extension add --dev /path/to/spec-kit-extensions/blueprint
```

## Quickstart

```bash
# Greenfield — seed the map from a design doc
/speckit.blueprint.init docs/master-spec.md
# …build slices with normal spec-kit (/speckit.specify … /implement), then:
/speckit.blueprint.distill 001-some-slice     # collapse it; stamps its code baseline

# Brownfield — reverse-map an existing repo
/speckit.blueprint.init --from-code           # sections start owned-by-code, with baselines
/speckit.blueprint.status                     # see what's mapped / what's drifted

# Keep it honest, everywhere — in CI
blueprint-state.sh check                       # exit 1 on distill drift or code staleness
/speckit.blueprint.remap src/payments          # after a refactor flagged STALE
```

You build however you already build (the normal spec-kit waterfall, or any flow). The
blueprint is the map around it, and `check` is the gate that keeps it true.

## Autonomous waterfall harness (same map, second payoff)

The blueprint is **externalized project state**, and the oracle computes the **single
next action deterministically** from the filesystem (`blueprint-state.sh next`).
Together that's a harness for **long, autonomous, multi-spec agent sessions**: point a
coding agent at the oracle and it can run the spec-kit waterfall — specify → clarify →
plan → tasks → implement, then `distill` — across the whole backlog, re-grounding on the
oracle after **every** step so it **cannot drift** over a multi-hour run. Your memory of
progress is never the source of truth; the filesystem is.

No new command and no interface change — the harness *is* the oracle plus a documented
loop an agent follows:

```bash
# one step of the loop (full contract in docs/autonomous-harness.md)
action=$(blueprint-state.sh next --json)   # deterministic: what's next, read from disk
#   → run exactly that one phase with the matching spec-kit command, then loop again
#   → park a blocked slice with `next --skip <slug>` and keep going; stop on a bound
```

See **[docs/autonomous-harness.md](./docs/autonomous-harness.md)** for the full loop
contract (one phase per step, parking, stop bounds) and a recommended **constitution
principle** that makes an agent follow it.

**Honest scope:** the oracle (the grounding) is deterministic and tested, and
`tests/harness_loop_test.sh` proves that *looping on it* sequences multiple specs
correctly — in order, with parking and stop bounds. What stays a reviewed-not-proven
prompt contract is the agent's *authoring within* each phase and its adherence to the
loop. The harness keeps a long session grounded; it doesn't guarantee the agent's work
inside a step.

## The blueprint document

Prose-first — no rigid tags. An annotated table of contents is the index +
architecture map; each section opens with a `> **Detailed (unspecced)**`,
`> **Distilled — owned by `specs/<slug>`**`, or `> **Distilled — owned by code at
`src/…`**` banner. Sections that map code carry a `<!-- blueprint:code path=… sha=… -->`
baseline marker. It works on organically-grown overview docs, not just generated ones.

## Honest boundaries

- **Detection, not conformance.** The gate flags that mapped code *moved* — "go
  re-verify" — it does **not** verify the code *correctly* implements its spec
  (line-level spec↔code conformance is a different problem, out of scope).
- **Map content is agent-authored.** `init` (mapping a repo) and `distill` (writing a
  digest) are done by the agent and reviewed; the **coherence gate** and the **oracle**
  that grounds the harness are the deterministic parts.
- **The harness is a pattern, not a magic button.** It grounds an autonomous session on
  the filesystem; it does not guarantee the quality of the agent's work inside a phase,
  and there is no coded driver enforcing the loop — an agent follows the documented
  contract (and the optional constitution principle).

## Status of this extension

- Bash oracle + coherence gate: **tested** — `tests/oracle_test.sh` (frontier, distill
  drift) and `tests/check_remap_test.sh` (code staleness for code- and spec-owned
  slices, dangling paths, restamp), against a real git repo.
- Harness loop: **tested** — `tests/harness_loop_test.sh` runs the loop over a
  multi-slice project against the real oracle (sequential specify→…→distill, parking,
  stop bounds).
- PowerShell port (`scripts/powershell/blueprint-state.ps1`): written for parity;
  **needs execution-verification on a Windows/pwsh environment**.
