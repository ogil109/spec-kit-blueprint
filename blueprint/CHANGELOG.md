# Changelog

All notable changes to this extension will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### TODO

- Execution-verify the PowerShell oracle (`scripts/powershell/blueprint-state.ps1`)
  on a Windows/pwsh environment (the Bash oracle is tested; the port is written for parity).

## [1.0.0] - 2026-06-26

A focused **coherence layer** for spec-driven projects: a living, collapsing
architecture map plus a deterministic CI gate that keeps it honest.

### Added

- **The blueprint** — a decreasing-detail architecture map. A section is *Detailed*
  (holding pen, design pending) or *Settled* (a digest + pointer to its owner: a
  feature spec **or** existing code). Detail flows out into specs once, forward —
  never back-synced. Prose-first; works on organically-grown overview docs.
- **Deterministic state oracle** (`scripts/bash/blueprint-state.sh`) — reads `specs/`
  + the blueprint; no LLM in the reliable path. Tests in `tests/oracle_test.sh`.
- **Deterministic section provenance.** Every section the extension processes is stamped
  with `<!-- blueprint:section state=detailed|distilled|code [owner=specs/<slug>] -->`.
  Markers are authoritative — the oracle reads them, not prose banners — so the extension
  always knows what it processed vs. what a human added or edited. A heading with no
  marker is *unmanaged*: reported by `check` and counted as pending backlog, so a raw or
  hand-edited doc can never silently read as "done". `init` is idempotent and safe: it
  stamps unmanaged sections, recognizes and preserves managed ones, and never deletes
  content — which also lets it **formalize an existing master doc** in place.
- **Coherence gate — keep the map honest no matter where a change comes from.**
  Sections that map a `src/` area carry a git baseline (`<!-- blueprint:code path=…
  sha=… -->`).
  - `blueprint-state.sh check` — a **deterministic, CI-friendly** gate that exits
    non-zero on either drift signal: a built spec not yet distilled (e.g. a spec born
    from an external tracker), or **any** mapped `src/` area whose code changed/vanished
    since mapping — covering both brownfield **code-owned** sections and the code behind
    **shipped specs** (`distill` stamps the implementation footprint). Catches
    out-of-band edits (a refactor/hotfix) the spec-anchored oracle alone can't see.
  - `blueprint-state.sh restamp [--path P]` — refresh the git baseline (deterministic).
  - Tested in `tests/check_remap_test.sh` against a real git repo.
- **Dual on-ramp.** `/speckit.blueprint.init` seeds from a design doc (greenfield) or
  **`--from-code`** to reverse-map an existing codebase into a code-owned map
  (brownfield), auto-distilling sections already owned by specs.
- `/speckit.blueprint.status` — read-only dashboard: detailed vs settled sections,
  distill drift, where each spec stands.
- `/speckit.blueprint.distill` — collapse a finished spec's section to an at-a-glance
  digest + pointer, and stamp the slice's code baseline.
- `/speckit.blueprint.remap` — re-derive a section from current code + restamp it, to
  resync after out-of-band code changes.
- **Autonomous waterfall harness (no new command).** The blueprint is externalized
  state and the oracle computes the next action deterministically, so an agent can loop
  on it to run the spec-kit waterfall across a multi-spec backlog without drifting — see
  `docs/autonomous-harness.md` (loop contract + recommended constitution principle).
  `tests/harness_loop_test.sh` proves the loop sequences multiple specs correctly, with
  parking and stop bounds; the agent's authoring within each phase stays reviewed, not
  proven.

### Scope

- **Detection, not conformance:** the gate flags that mapped code *moved* (re-verify),
  not that it *correctly* implements its spec.
- Map content (`init`, `distill`) is agent-authored and reviewed; the gate is the
  deterministic part.

### Requirements

- Spec Kit: >=0.10.0

---

[Unreleased]: https://github.com/ogil109/spec-kit-extensions/tree/main/blueprint
[1.0.0]: https://github.com/ogil109/spec-kit-extensions/releases/tag/blueprint-v1.0.0
