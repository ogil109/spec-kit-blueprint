# Implementation Plan: Stale-Logic Cleanup (Architecture Archaeology)

**Branch**: `001-stale-logic-cleanup` | **Date**: 2026-08-23 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-stale-logic-cleanup/spec.md`

## Summary

Produce a complete decision inventory of every shipped mechanism (origin →
rationale → verdict → disposition) judged against an explicit end-state
statement, then execute every remove/rework disposition in both ports with
docs in the same change — one ungated flow, validated by the full suites, the
parity harness, and the brownfield e2e on two large real codebases (pandas +
scikit-learn).

## Technical Context

**Language/Version**: Bash (POSIX-portable, dependency-free beyond bash+git) + PowerShell 7 ports at machine-enforced equivalence

**Primary Dependencies**: git only (runtime); python3 in tests for JSON validation; commitizen (dev tooling)

**Storage**: N/A — all state lives in the target repo (blueprint doc markers, git SHAs, config file)

**Testing**: 7 deterministic bash suites under `tests/` (156 asserts at start), incl. byte-parity harness (runs when pwsh present; CI always) and the e2e lifecycle suite

**Target Platform**: Linux/macOS (bash), Windows-capable via PS ports; CI on ubuntu-latest

**Project Type**: Spec Kit extension (command markdown + oracle scripts + templates)

**Performance Goals**: no regression — on-ramp machine time stays sub-second-per-step on a 2,600-file repo

**Constraints**: pre-1.0, breaking changes permitted only when declared (FR-005); both ports move together (FR-007); every input surface machine-validated at completion

**Scale/Scope**: ~1,400 lines bash + ~800 lines PS across entries + 13 lib modules, 5 commands, 2 templates, working docs; inventory must cover 100% of it

## Constitution Check

`.specify/memory/constitution.md` is the unratified init template — no
project-specific gates. The spec's mandated principles (lane parity, enforced
equivalence) act as the governing constraints for this feature.

## Project Structure

### Documentation (this feature)

```text
specs/001-stale-logic-cleanup/
├── spec.md         # clarified specification
├── plan.md         # this file
├── research.md     # end-state principles + disposition designs for the major reworks
└── tasks.md        # /speckit-tasks output
```

### Source code (repository root) — surfaces the cleanup touches

```text
docs/decision-inventory.md        # NEW: the maintained inventory (P1 deliverable)
scripts/bash/{blueprint-state.sh,blueprint-slice.sh} + lib/*   # dispositions land here
scripts/powershell/…              # mirrored 1:1
commands/*.md                     # stale guidance reworked (distill, remap, init, recover)
templates/*.md                    # anatomy/template updates per lane parity
.github/workflows/tests.yml       # single-sourced test roster
README.md, CONTRIBUTING.md        # zero-contradiction pass + rationale rule (FR-009)
docs/deterministic-onramp.md      # REMOVED (salvage → working docs; history in git)
```

## Phase 0 — Research (the archaeology)

1. **Mechanism sweep**: enumerate every shipped mechanism from the artifacts
   themselves (entry flags/commands, lib behaviors and defaults, config keys,
   marker vocabulary, facts directives, validation rules, auto-detections,
   documented claims) — not from memory. Sources of origin evidence: git
   history, the design doc (before its removal), session logs, PR trail.
2. **End-state principles**: draft the short statement; must include the two
   mandated principles (lane parity, enforced equivalence).
3. **Inventory**: one entry per mechanism (or jointly-redundant group) with
   origin / rationale / verdict / disposition / justification. Lands as
   `docs/decision-inventory.md` (a working document: present-tense register,
   maintained per FR-009 — not historical narrative).

Output: `research.md` records the principles and the argued *designs* for the
major rework dispositions (below); the inventory itself is the implementation
deliverable.

## Phase 1 — Major rework designs (decided in research.md, executed in tasks)

Known-large dispositions needing design before execution:

- **Config validation** (Starting Candidate #1): both entries validate the
  config at load — unknown keys under known sections rejected with the valid
  key list, numeric fields type-checked, list keys that parse empty flagged.
- **Structure conformance consolidation**: whether `verify` folds into `check`
  as issue types (one coherence oracle) or stays a distinct on-ramp tool —
  argued from the "one mechanism per concern" principle; breaking if folded.
- **Lane parity rework**: `render` accepts facts blocks for spec-owned
  (distilled) sections — prose and edges authored/validated exactly like
  code-owned ones, evidence anchors may include the owning spec's files;
  `distill`/`remap`/greenfield `init` guidance rewritten onto the facts flow.
  This also resolves the known distilled-edges-unrepairable seam (GAP-6).
- **Port-equivalence contract**: argued disposition (byte vs semantic), with
  enforcement retained either way.
- **Concern directive**: remove/keep argued from demonstrated use (none in
  the only real-repo exercise).
- **Auto-detect homes**: legacy candidates carried from the original host
  project's layout — trim, declared-breaking if removed.
- **Test-roster single-sourcing**: CI and docs derive the roster from the
  filesystem (`tests/*_test.sh`), killing the triple bookkeeping.

## Validation strategy (FR-007, FR-008, FR-010)

- Full suites + parity after every disposition group; suite-count deltas
  recorded in the affected inventory entries.
- Final gate: complete brownfield e2e (install → scaffold → facts → render →
  restamp → verify/check → lifecycle drills) on **pandas** and
  **scikit-learn** (comparable size, same Cython-polyglot shape), both green.
- Docs audit pass for FR-006 (zero contradictions in the working set).

## Phases

- Phase 0/1: research.md + inventory (US1)
- Phase 2: `/speckit-tasks` → dependency-ordered execution of dispositions (US2)
- Phase 3: prevention wiring — CONTRIBUTING rationale rule, inventory
  maintenance note (US3)
