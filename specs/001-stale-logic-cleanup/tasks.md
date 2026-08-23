# Tasks: Stale-Logic Cleanup (Architecture Archaeology)

**Input**: [spec.md](./spec.md), [plan.md](./plan.md), [research.md](./research.md)
**Flow**: ungated (per Clarifications); suites + parity after every group; dual-repo e2e at the end.

## Phase 0 — Research deliverable (US1)

- [x] T001 Sweep all shipped artifacts and write `docs/decision-inventory.md`:
      every mechanism/claim with origin, rationale, verdict, disposition
      (FR-001); end-state principles embedded from research.md (FR-002);
      dispositions D1–D8 recorded plus every keep with live rationale (FR-004).

## Phase 1 — Cleanup execution (US2; each task = both ports + docs + tests green)

- [x] T002 [D1] Config validation at load: bash + PS entries, unknown-key /
      type / empty-list-parse errors; tests for each failure class; parity
      unaffected on clean configs.
- [x] T003 [D7] Test roster single-sourced: CI iterates `tests/*_test.sh`;
      README/CONTRIBUTING lists replaced with the glob convention.
- [x] T004 [D5] Remove the `concern` facts directive: parser, validator,
      renderer, recover.md, tests, both ports. Declared breaking.
- [x] T005 [D6] Trim auto-detect homes to `.specify/memory/blueprint.md` +
      `docs/blueprint.md`: both oracles, both ports, docs, tests. Declared
      breaking.
- [x] T006 [D2] Fold structure conformance into `check` as SOFT `structure`
      issues; remove the `verify` subcommand; state entry sources partition
      modules for check; rewrite affected tests (slicer/e2e/parity) and all
      doc references. Declared breaking.
- [x] T007 [D3] Lane parity: render accepts `distilled` facts blocks (owner
      parsed from the section marker; jurisdiction widened to the owning
      spec's directory; spec-pointer closer); tests incl. GAP-6 flip
      (distilled edges repairable). Rewrite `distill.md` and `remap.md` onto
      emit-facts → render → restamp; align greenfield guidance in `init.md`.
- [x] T008 [D8] Remove `docs/deterministic-onramp.md` after salvaging the
      still-current essence into README; audit `docs/autonomous-harness.md`
      claims against current behavior (fix or keep).
- [x] T009 [D4 + FR-006] Working-docs zero-contradiction pass: README,
      CONTRIBUTING, all command files, templates, config comments — every
      claim checked against behavior; port-contract keep-rationale recorded in
      the inventory.

## Phase 2 — Prevention (US3)

- [x] T010 CONTRIBUTING: new-mechanism rationale rule (inventory entry
      required in the same change); inventory maintenance note (FR-009).

## Phase 3 — Validation (FR-007/008/010)

- [ ] T011 Full suites + parity green; suite-count deltas recorded in the
      affected inventory entries (FR-008).
- [ ] T012 Dual-repo e2e: full brownfield on-ramp + lifecycle drills on
      pandas AND scikit-learn, gate green at every checkpoint (SC-007);
      inventory outcomes column completed (SC-004); final docs audit
      (SC-003).
