# Research: End-State Principles & Major Disposition Designs

**Feature**: [spec.md](./spec.md) | **Date**: 2026-08-23

## End-State Principles (FR-002)

The statement every disposition is judged against:

1. **Validated inputs** — every surface the machinery consumes (facts, markers,
   evidence, endpoints, *and configuration*) is machine-validated; silent
   acceptance of malformed input is a defect.
2. **One mechanism per concern** — jointly-redundant mechanisms collapse; a
   concern with two homes is a defect.
3. **No claim without enforcement** — a documented promise either has a test,
   an oracle, or it is not made.
4. **No feature without demonstrated use** — mechanisms that no real exercise
   has needed are removed until a real need appears.
5. **Lane parity** *(mandated)* — code-seeded and docs-seeded lanes share one
   authoring and validation model. Scope note: parity governs *claims about
   what exists* (digests, edges — validated in both lanes); a `detailed`
   section's body is design-in-waiting, not a claim, and stays free prose in
   both lanes.
6. **Enforced equivalence** *(mandated)* — the dual-port contract, at whatever
   level, is machine-enforced in CI.
7. **Present-tense tree** — in-tree documents describe the present; history
   lives in version control.

## Argued dispositions for the major reworks

### D1 — Configuration validation (rework; principle 1)

Both entries validate at load: within this extension's own config file, an
unknown key under a known section is a hard error naming the valid keys;
`max_files`/`min_files` must be positive integers; a present-but-empty-parsing
list key (the misindent signature) is an error; `require_confirmation` must be
true/false. Validation is silent when the config is clean, so no output
contract changes. Origin of the gap: the parser predates every other
validation surface (config once held two cosmetic keys).

### D2 — Structure conformance folds into the gate (rework; principle 2; breaking)

`verify`'s original rationale — catching agent transcription drift — was
superseded when `scaffold` removed agent-written structure entirely. What
remains is a genuine invariant (doc structure ≡ computed partition) that is
*a coherence concern*, and the coherence oracle is `check`. Disposition: fold
verify's pair-diff into `check` as SOFT `structure` issues (strict promotes),
remedy pointing at scaffold/render/config; remove the standalone subcommand
(declared breaking). The merge/rename case that coverage cannot see (marker
moved, files still covered) is exactly what the new issue type reports. The
modular layout makes this cheap: the state entry sources the partition
modules when running `check`.

### D3 — Lane parity: spec-owned sections join the facts flow (rework; principle 5; resolves GAP-6)

`render` accepts facts blocks for `distilled` sections: role/facets/notes and
edges validated and rendered exactly like code-owned ones, with jurisdiction
widened to the owning spec — evidence anchors may live under the section's
markers *or* under `specs/<owner-slug>/` (the doc parse gains the `owner`
attribute). The closer renders as the spec pointer. Structure stays outside
the partitioner's jurisdiction (verify-subtraction semantics unchanged) —
parity is about authoring and validation, not about the partitioner owning
spec sections. `distill` and `remap` guidance rewrites onto emit-facts →
render → restamp; greenfield `init` keeps its stamping/classification role
but authors settled-section prose through the same flow. Side effect: edges
from distilled sections become repairable/deletable via facts, closing the
recorded GAP-6 seam.

### D4 — Port-equivalence contract (keep byte parity; principles 3 & 6)

Byte parity is retained: it is the only equivalence whose *verification* is a
diff (near-zero cost, zero judgment), it has caught five real divergences to
date, and relaxing to semantic parity would replace a machine check with
per-surface human judgment — precisely the unenforceable-claim shape
principle 3 forbids. The authoring tax is real and accepted with eyes open.

### D5 — Concern directive (remove; principle 4; breaking)

The `concern` facts directive was built for cross-cutting facilities that own
no directory — and the only full real-repo exercise found none: every real
cross-cutter was a directory-owning section using ordinary `crosscuts` edges
(which stay). Removed from the format, parser, renderer, docs, both ports;
declared breaking. Re-addable from history if a real repo ever demands it.

### D6 — Auto-detect homes (trim; principle 4; breaking)

`docs/overview.md` as a blueprint auto-detect candidate is a relic of the
original host project's layout; no shipped rationale survives. Trimmed to the
canonical `.specify/memory/blueprint.md` plus the generic `docs/blueprint.md`
alternative. Declared breaking.

### D7 — Test roster single-sourcing (rework; principle 2)

The suite roster is maintained by hand in three places (CI workflow, README,
CONTRIBUTING). Single source becomes the filesystem: CI iterates
`tests/*_test.sh`; docs say "run everything under `tests/`". Adding a suite
becomes one file, zero bookkeeping.

### D8 — Design-history document (remove from tree; principle 7)

`docs/deterministic-onramp.md` is historical narrative; still-load-bearing
content (the on-ramp model summary, the seeding-comparison essence) already
lives in or is folded into the README before removal. The file's history
remains in version control, and its origin evidence is consumed by the
inventory first.

## Inventory methodology (Phase 0 sweep)

Enumerate from artifacts, not memory: every entry-script flag and command;
every lib module's behaviors and defaults; every config key; every marker and
facts directive; every validation rule; every auto-detection; every claim in
the working docs. Origin evidence: git log, the design doc (pre-removal),
recorded session logs. Output: `docs/decision-inventory.md` — present-tense
register, one row per mechanism (or redundant group): what / origin / rationale
/ verdict / disposition / outcome. Maintained per FR-009.
