# Feature Specification: Stale-Logic Cleanup (Architecture Archaeology)

**Feature Branch**: `001-stale-logic-cleanup`

**Created**: 2026-08-23

**Status**: Draft

**Input**: User description: "I've noticed lots of stale logic while talking through the codebase, which seems the result of carrying forward previous architecture decisions. The config schema without validation is one example of this. This spec looks to clean the codebase and in order to do that will do a full research phase consisting of an analysis of what's there and why it's there, including the desired end state, and then a cleanup of everything that doesn't make sense anymore."

## Problem Statement

The extension grew through rapid, review-driven iteration: each mechanism was
added to answer a specific failure, but earlier mechanisms were rarely
re-examined when later ones changed the ground they stood on. The result is
**stale logic** — behavior whose original rationale has lapsed or been
superseded, kept only by inertia. A confirmed example: every input surface
gained machine validation over time except the configuration file that steers
the entire partition, whose parser still silently ignores unknown keys — a
leftover from when the config held two cosmetic settings. Other suspects are
known (see *Starting Candidates*), and the working assumption is that more
exist undiscovered.

## Clarifications

### Session 2026-08-23

- Q: Is there a human approval gate between the research phase (inventory +
  dispositions) and the cleanup execution? → A: No gate — single flow; research
  and cleanup land together in one reviewable change. Post-cleanup validation
  must include the full end-to-end exercise on two large real codebases
  (pandas plus one of comparable size), not pandas alone. The pending
  script-modularization change was merged before this feature starts.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The Decision Inventory and End State (Priority: P1)

The maintainer can open a single document that lists **every shipped
mechanism** — commands, script behaviors, configuration keys, marker
vocabulary, validation rules, defaults, documented claims — and for each one
see: what it does, why it was originally added, whether that rationale still
holds against a stated **desired end state**, and a disposition
(keep / rework / remove / defer). Nothing shipped is absent from the list.

**Why this priority**: The user's core complaint is not any single stale
mechanism but the *inability to audit* — decisions were carried forward
invisibly. The inventory alone, before any cleanup, restores the ability to
judge the codebase; it is also the prerequisite for every other story.

**Independent Test**: Pick any behavior observable in the shipped extension
(a command, a config key, a marker type, a documented claim) and find its
inventory entry with origin, verdict, and disposition. Repeat for a random
sample of ten; all ten must resolve.

**Acceptance Scenarios**:

1. **Given** the completed inventory, **When** the maintainer looks up any
   shipped mechanism, **Then** an entry exists stating its origin, its
   original rationale, a verdict on whether that rationale is still live, and
   a disposition justified against the end-state principles.
2. **Given** the end-state statement, **When** any disposition is questioned,
   **Then** the justification references a specific end-state principle, not
   taste.
3. **Given** a mechanism whose origin cannot be reconstructed, **When** it is
   inventoried, **Then** it is explicitly marked origin-unknown and receives a
   deliberate disposition rather than a default "keep".

---

### User Story 2 - The Cleanup (Priority: P2)

Every mechanism the inventory marks *remove* or *rework* is acted on: removed
or reworked in both platform implementations, with documentation updated in
the same change, and with the existing acceptance suites demonstrating that
everything retained still behaves as promised. Any disposition that is not
executed is explicitly deferred with a recorded reason — no silent survivals.

**Why this priority**: The cleanup is the feature's payoff, but it is only
safe and reviewable *after* the inventory exists; executing it against
recorded dispositions keeps each change small and traceable.

**Independent Test**: Diff the shipped behavior surface before and after: every
difference maps to a disposition in the inventory, and every *remove/rework*
disposition maps to either a shipped change or a recorded deferral.

**Acceptance Scenarios**:

1. **Given** a mechanism dispositioned *remove*, **When** cleanup completes,
   **Then** the mechanism is absent from both platform implementations, its
   documentation, and its manifest entries — or a deferral with reason is
   recorded in the inventory.
2. **Given** a mechanism dispositioned *keep*, **When** cleanup completes,
   **Then** its behavior is unchanged and the acceptance suites still pass.
3. **Given** a cleanup change that alters released behavior, **When** it
   lands, **Then** it is explicitly declared a breaking change in the change
   record (never discovered by users).
4. **Given** the completed cleanup, **When** the full documentation set is
   audited, **Then** no shipped claim contradicts actual behavior.

---

### User Story 3 - Staleness Does Not Re-Accumulate (Priority: P3)

A contributor adding a new mechanism is required, by the contribution
guidance, to record its rationale in the same change — and the inventory is a
maintained artifact, so the next audit starts from a live document instead of
archaeology.

**Why this priority**: Valuable but meaningless without Stories 1–2; it is the
cheap insurance that this feature does not need to be repeated from scratch.

**Independent Test**: The contribution guidance names the requirement; the
inventory file exists in the repository with a stated maintenance rule.

**Acceptance Scenarios**:

1. **Given** the contribution guidance after this feature, **When** a
   contributor reads the requirements for adding a mechanism, **Then**
   recording its rationale in the inventory is listed among them.

---

### Edge Cases

- A mechanism's origin predates recorded history (no commit trail, no
  session evidence): inventoried as origin-unknown; disposition must still be
  argued from the end-state principles.
- A mechanism is stale but has external consumers (users of released
  versions): removal is a declared breaking change or a deferral — never a
  silent break, never a silent keep.
- Documentation and behavior contradict each other: behavior is presumed the
  intent unless the inventory argues otherwise; either way, exactly one of
  them changes.
- A stale mechanism's tests exist only to pin the stale behavior: the tests
  leave with it, and the recorded before/after suite counts explain the drop.
- Two mechanisms are individually justified but jointly redundant (two ways
  to do one thing): the inventory must treat the *pair* as an entry and pick
  one.
- Cleanup on one platform implementation without the other: not permitted;
  equivalence between the two is itself an end-state principle.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The research phase MUST produce a decision inventory covering
  100% of shipped mechanisms in these categories: user-facing commands,
  script behaviors and their defaults, configuration keys, marker vocabulary,
  validation rules and their gaps, auto-detection behaviors, and documented
  claims. Each entry MUST state: what it is, origin, original rationale,
  a verdict (rationale live / superseded / lapsed / unknown), and a
  disposition (keep / rework / remove / defer) with justification.
- **FR-002**: The research phase MUST produce a desired end-state statement —
  a short set of design principles (for example: every input surface is
  validated; each concern has exactly one mechanism; no documented claim
  without enforcement; no feature without a demonstrated use) — and every
  disposition MUST be justified against it.
- **FR-003**: The cleanup phase MUST execute every *remove* and *rework*
  disposition in both platform implementations and their documentation, or
  record an explicit deferral with reason. Silent deferrals are a defect.
- **FR-004**: Every *keep* disposition MUST cite a live rationale; "it was
  already there" is not a valid justification.
- **FR-005**: Cleanup changes that alter released behavior MUST be declared
  as breaking changes in the project's change record; undeclared behavior
  changes are a defect.
- **FR-006**: After cleanup, the full shipped documentation set MUST contain
  no claim that contradicts actual behavior.
- **FR-007**: The equivalence between the two platform implementations MUST
  be preserved through every cleanup change, verified by the existing
  equivalence checks.
- **FR-008**: All existing acceptance suites MUST pass after each cleanup
  change; suite coverage may shrink only where a removed mechanism takes its
  own tests with it, and such shrinkage MUST be recorded in the inventory
  entry.
- **FR-009**: The contribution guidance MUST require new mechanisms to record
  their rationale in the inventory, and the inventory MUST be kept as a
  maintained repository artifact.
- **FR-010**: Post-cleanup validation MUST include the complete brownfield
  end-to-end exercise (on-ramp through the lifecycle drills) on at least two
  large real codebases: pandas and one additional codebase of comparable size
  (thousands of tracked files, polyglot), both completing with the gate green
  at every checkpoint.

### Key Entities

- **Decision Inventory**: the checked-in register of all shipped mechanisms;
  one entry per mechanism (or per jointly-redundant group) with origin,
  rationale, verdict, disposition, justification, and — after cleanup — the
  outcome (shipped change or deferral).
- **End-State Principles**: the short list of design rules the codebase
  should satisfy; the sole basis for dispositions.
- **Disposition**: keep / rework / remove / defer, always justified against a
  principle; *defer* carries a reason and, where known, a pointer to the
  tracking issue.
- **Breaking-Change Record**: the declared list of released-behavior changes
  produced by the cleanup.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of shipped mechanisms have an inventory entry with an
  explicit verdict and disposition; a random ten-mechanism audit resolves
  ten of ten.
- **SC-002**: Zero mechanisms are retained without a stated live rationale —
  auditable by reading the inventory end to end.
- **SC-003**: Zero documentation claims contradict shipped behavior at
  completion, verified by a full-documentation audit.
- **SC-004**: 100% of remove/rework dispositions are either shipped or
  explicitly deferred with reasons; zero silent survivals.
- **SC-005**: A reader unfamiliar with the project's history can trace any
  shipped mechanism to its rationale in under two minutes using only the
  inventory.
- **SC-006**: All acceptance suites pass at completion, and every change in
  suite counts relative to the start is explained by an inventory entry.
- **SC-007**: The full end-to-end exercise completes green on two large real
  codebases (pandas plus one of comparable size), demonstrating the cleaned
  pipeline end to end on more than one real-world shape.

## Starting Candidates *(scope note, not the boundary)*

Known suspects seeded from prior review; the research phase MUST sweep the
whole codebase and treat this list as a floor, not the scope:

- Configuration accepted without validation (unknown keys silently ignored;
  values untyped) while every other input surface is machine-validated.
- The standalone structure-conformance command, whose original motivation was
  largely superseded when structure became machine-written.
- The cross-cutting "concern" construct, unused in the only full real-repo
  exercise to date.
- The relations-preservation mechanism that exists only because one piece of
  edge data lives in a rendered table rather than in the machine record.
- Legacy document auto-detection locations carried from an earlier host
  project's layout.
- Command guidance written before the current authoring flow (hand-editing
  instructions that predate rendered content).
- The same test-suite roster maintained by hand in three places.

## Assumptions

- The project is pre-1.0 and has prior precedent for declared breaking
  changes; cleanup may therefore change released behavior when declared
  (FR-005), without a compatibility mandate.
- The script-modularization change is already merged; research and cleanup
  run against the modular layout, as a single ungated flow (per
  Clarifications) landing in one reviewable change.
- Recorded session history (review logs, the live end-to-end log, the design
  document) is admissible evidence for mechanism origins.
- Open enhancement work (for example, the delta-scoped recovery issue) is out
  of scope: this feature removes and reworks, it does not add capabilities.
  Additions proposed during research are recorded as candidates for separate
  features, not folded in.
- The inventory lives in the repository as a maintained document; its exact
  location and format are planning-phase decisions.
