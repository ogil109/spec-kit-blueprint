# The deterministic on-ramp — design & validation

Status: **spike** (this branch). Implements the fix for the on-ramp
reproducibility gap found while deploying v0.2.0 on a large enterprise
brownfield repo, validated here against pandas (2,649 tracked files).

## The problem

Two defects were found in the v0.2.0 brownfield on-ramp, one architectural, one
mechanical:

1. **The slicing decision was agent judgment.** `init --from-code` on a fresh
   repo had no deterministic enumeration step: what counted as a subsystem, how
   finely to slice, and *which top-level directories got mapped at all* was
   left to the invoked agent's one-pass judgment. Two runs (or two reviewers)
   could legitimately produce different maps. A map that varies per on-ramp run
   is of no use as shared state.
2. **The coverage backstop could not see what the agent skipped.** The
   `unmapped` scan derived its roots *from the already-mapped paths*, so a
   top-level directory with zero mapped sections was invisible forever. In the
   field, a first-pass map covered 14 subsystems and read `0 blocking` while
   `tests/` (830 files), `infra/` (62 Bicep templates), and four other
   top-level trees were silently absent — with no future warning possible.

## Prior art (and two corrections)

The architecture-recovery literature has drawn the same line for thirty years:
**exhaustive, deterministic enumeration first; subjective interpretation
second.** The interpretation phase is never trusted to decide *what is in
scope* — only how to describe what a deterministic step already enumerated.

- **Software Reflexion Models** (Murphy, Notkin & Sullivan): the human declares
  the high-level map, but a tool computes the complete source-model and the
  convergent/divergent/absent reconciliation. Completeness is the tool's job,
  never the human's.
- **ACDC** (Tzerpos & Holt): pattern-driven clustering aimed at
  *comprehensible* subsystems, with an explicit **orphan adoption** pass — an
  algorithmic guarantee that every file ends up in some cluster. That is
  exactly the invariant defect #2 violated.
- **MoJo / MoJoFM** (Tzerpos & Holt; Wen & Tzerpos): the move/join edit
  distance between two decompositions — the field's instrument for the
  question "how much would two on-ramp runs disagree?"
- **Bunch / MQ** (Mancoridis, Mitchell et al.): search-based clustering
  optimizing a deterministic cohesion/coupling metric. *Correction to the
  finding notes:* the **metric** (MQ) is deterministic, but Bunch's
  hill-climbing/genetic **search is randomized** and is documented to vary
  across runs on the same graph — search-based clustering is a *source* of
  exactly the non-determinism this design must kill, not a cure for it. ACDC's
  essentially-deterministic passes are the better model.
- **Aider's repo map**: tree-sitter symbol extraction, then a ranked selection
  under a token budget — coverage and prioritization as two separate phases.
  *Correction:* its coverage is 100% of files **in languages tree-sitter has a
  grammar for**, not 100% of tracked files. Any parsing-based enumeration is
  language-gated — pandas' `pandas/_libs` (151 Cython files) is precisely the
  kind of tree a Python-parsing pipeline goes blind on.

The corrected lesson: the deterministic phase should be **git-based, not
parser-based**, or it silently reintroduces a coverage gap in every language it
can't parse — and any search/optimization step must be replaced by closed
rules.

## Constraints that shaped the design

- **Language agnosticism is non-negotiable** (the extension's stated
  positioning): the reliable path may consume `git ls-files` and file *names*,
  never file contents.
- **Baselines are git tree/blob SHAs** (`rev-parse HEAD:<path>`): a section's
  covered paths must be actual tree objects, which rules out free-form
  cross-directory clusters without a marker-format redesign (see Open
  questions).
- **Shallow clones must work** (the enterprise mirror case): no git *history*
  may be consumed — no co-change clustering.
- **The gate's friction bet stays**: everything new surfaces as SOFT.

## The design

`P(repo-state, config) → section set`, a pure function, implemented in
`scripts/bash/blueprint-slice.sh` (bash + POSIX awk, ~0.4 s on pandas):

- Evidence consumed: path names, per-subtree tracked-file counts, and the
  **presence** of build-manifest filenames (`slice.boundary_files`). No file is
  ever opened.
- Rules per directory (first match wins): **pinned** (`slice.pin_dirs`, one
  atomic section regardless of size; ancestors split down to it) → **module**
  (boundary file at its root, ≤ `max_files`: whole section even below
  `min_files`) → **fits** (≤ `max_files`, no nested boundary/pin) →
  **descend** (children ≥ `min_files` recurse; smaller children + direct files
  fold into one **remainder** section carrying one marker per path) → **flat**
  (over `max_files` with no subdirectories: emitted whole — nothing to split
  by).
- A section is a **set of paths**: tree markers for directories, blob markers
  for files. The existing oracle already reads markers globally, so multi-marker
  sections needed zero gate changes.
- Every tracked file lands in exactly one bucket: a section (code/context), an
  `excluded` entry (checked-in `coverage.exclude` pattern — reported, never
  silent), or a reported root-level loose file. This is ACDC's orphan-adoption
  invariant, enforced structurally.
- **Additive re-runs**: paths covered by existing markers are subtracted, new
  code proposes new sections, and an existing section that outgrew
  `max_files` raises an *advisory* — an existing map is never silently
  repartitioned (prose survives growth).
- **Overrides are config, not judgment**: disagreeing with the cut means
  editing `blueprint-config.yml` (`slice.*`, `coverage.exclude`) and re-running.
  The override is checked in and replays identically on every future run —
  non-determinism is permitted once, then frozen as state.

`init --from-code` (the command) no longer asks the agent to transcribe the
structure at all: **`blueprint-slice.sh scaffold` writes the map itself** —
title, how-this-works header, status-annotated TOC, and every section with its
markers, banner, and a `TODO(prose)` placeholder — byte-identically for the
same repo state + config (against an existing map it emits only the missing
additive blocks; `--scope` gives the remedy flow for `unmapped`). The agent's
ONLY edit is replacing the placeholders. The guardrail chain, weakest first:

1. *Soft*: the command text constrains the agent (prose placeholders only).
2. *Hard*: the structure never passes through the model — scaffold writes it.
3. *Hard*: `blueprint-slice.sh verify` recomputes the partition and diffs it
   against the (section, kind, marker) structure actually in the doc, so even
   a prose edit that strayed into structure is a deterministic pair diff and
   exit 1. Markers owned by `distilled`/`detailed` sections (a spec's
   implementation footprint) are outside the slicer's jurisdiction and are
   subtracted before the diff.
4. *Hard*: the `check` gate's widened coverage scan catches dropped territory
   and everything that drifts later.

So the agent's remaining degrees of freedom are exactly two: the prose inside
each scaffolded section, and checked-in config changes followed by a
re-scaffold.

**Demonstrated end to end on pandas**: two fresh, independent clones, two
complete on-ramps (scaffold → restamp → prose filled by two deliberately
different writers). The raw scaffolds were **byte-identical including the
stamped SHAs**; after independent prose passes, the structural skeletons
(headings + all markers) were identical, the full-text diff contained *only*
prose lines, and `verify`, `check`, and `next` were green on both. The `check` gate closes the loop: the
coverage scan now spans **all** top-level directories (kills defect #2, plus
the old zero-marker guard and the word-split space edge), with
`blueprint:context path=` markers covering docs-like trees baseline-free.

## Validation on pandas (shallow clone, 2,649 tracked files)

**Reproducibility** — the property under test:

- Two runs in one clone: byte-identical JSON. Two *independent clones*:
  byte-identical partitions. Slice → generate map → re-slice → re-generate:
  byte-identical map structure. MoJo distance between two on-ramp runs is 0 by
  construction; only prose can vary, and the gate never reads prose.

**Quality** — is the computed cut a *good* map, or merely a stable one?
Falsification test against a dependency-derived clustering of the same code:
stdlib-`ast` import graph over pandas' Python surface minus tests (295 files,
2,660 edges, 0 parse errors), versus Clauset-Newman-Moore modularity
communities on that graph. Instruments: TurboMQ (cohesion/coupling), ARI/NMI
and MoJo moves+joins (agreement).

| partition | clusters | TurboMQ | MQ/cluster | ARI vs dep. | NMI vs dep. | MoJo→dep. |
|---|---|---|---|---|---|---|
| slicer, defaults (`max_files=400`) | 11 | 2.66 | **0.242** | 0.18 | 0.37 | 156 |
| slicer, `max_files=100` | 30 | **5.22** | 0.174 | 0.25 | 0.49 | 111 |
| dependency CNM (baseline) | 14 (6 singletons) | 3.24 | 0.231 | — | — | — |

Readings, stated plainly:

- **The directory proxy loses no cohesion quality.** Per-cluster MQ at
  defaults (0.242) matches the dependency baseline (0.231); at finer
  granularity the raw MQ (5.22) far exceeds it. The baseline itself is not a
  gold standard — 6 of its 14 communities are degenerate singletons.
- **Agreement is moderate, and the divergence is legible.** At defaults the
  single biggest source of disagreement was `pandas/core` (173 files spanning
  ~3 dependency communities). Lowering `max_files` — a checked-in config
  lever, not judgment — moved every agreement metric toward the dependency
  structure (ARI 0.18→0.25, NMI 0.37→0.49, MoJo 156→111). The residual
  disagreement is cross-cutting hubs (`compat`, `util`, `api` spread across
  communities), which **no directory partition can express** — see Open
  questions.
- **The language-agnostic bet paid off concretely**: the map covers
  `pandas/_libs` (151 Cython files) as a first-class stamped section; the
  Python-parsing analysis pipeline is blind there (3 `.py` stubs). A
  parser-based enumeration would have re-opened defect #2 in every non-Python
  tree.
- **Full lifecycle exercised on the real repo**: partition → authored map (19
  sections; `pandas/tests` pinned via config after the default cut produced 33
  per-area test sections — that finding is what motivated `pin_dirs`) →
  restamp (22 markers) → `check` in sync → out-of-band hotfix flags `STALE` →
  `restamp --path` heals → out-of-band new module flags `UNMAPPED` (defect #2's
  exact scenario, now caught) → additive re-slice proposes only the new piece.

**Downstream consumption — is the output a *true* blueprint?** Determinism
alone doesn't prove the map is useful, so a 20-assert e2e drives the
template-conformant pandas map (title, how-this-works header, status-annotated
TOC, banners + digests per the shipped template) through every downstream
surface, using only the shipped scripts:

- the **`next` oracle** consumes it correctly: idle on the fresh map (all
  sections settled — nothing hallucinated as backlog), then sequences a real
  feature spec end to end (`plan → tasks → implement → distill → idle`);
- the **gate lifecycle** works against it: a built spec not yet in the map is
  HARD drift (exit 1) with the distill remedy; converting `pandas/io` to
  `state=distilled owner=specs/<slug>` clears it, and `verify` correctly moves
  the section out of slicer jurisdiction;
- the **remedy JSON contract is machine-actionable**: a scripted (no-LLM)
  consumer reads `check --json`, applies each issue's deterministic remedy
  core, and turns the gate green again — including under `--strict`;
- **out-of-band code re-onboards through the remedy**: a new module flags
  `UNMAPPED`, the scoped slice computes exactly the missing section, appending
  it + restamp restores a clean gate, and `verify` proves the scoped result
  equals the full recompute.

The same flow runs in CI against a synthetic fixture
(`tests/e2e_lifecycle_test.sh`). It caught a real design bug on first
execution: **subtraction must leave holes**. Removing covered paths (a
spec-owned slice in `verify`, existing markers in additive re-runs) can shrink
a parent below `max_files`, so the recompute emitted the parent *whole* — a
tree marker spanning territory another owner already covers. Subtracted paths
now force their ancestors to descend (`hnested`, hole-veto on every whole-tree
emit, pins included), so no emitted marker can ever overlap covered ground.

## One document type, two on-ramps (the convergence claim)

Should the docs (greenfield/formalize) on-ramp be dropped in favor of
code-only seeding? **No — the difference worth erasing is anatomical, not
on-ramp-shaped, and the difference worth keeping is semantic.** The `detailed`
(holding-pen) state must exist regardless: it is the backlog that drives the
waterfall, and the docs on-ramp is merely the entry path that populates it
from an existing design doc (it shares all marker/gate machinery, so it is
nearly free to keep). What made the two on-ramps feel like different tools was
that their *prose* had no shared contract.

That contract now ships: `templates/section-anatomy.md` — five parts (heading +
marker are machine lane; banner, role sentence, evidence-anchored digest,
closer are the prose lane), evidence rules (every bullet anchored to a real
path or spec section; cross-references name sections, not files), and the
**architecture-recovery procedure** for code-owned sections (inventory →
boundary-before-depth → write → self-check). `init --from-code`, `remap`, and
`distill` all reference it, and the scaffold's `TODO(prose)` placeholders point
at it, so in spec-kit terms the rendered init agent *is* the shipped
architecture-recovery agent.

Convergence, stated precisely: a code-seeded map and a docs-seeded map meet at
the same steady-state anatomy as sections settle — the lasting difference is
the provenance marker (`code` vs `distilled owner=specs/<slug>`), which encodes
where the truth lives and must remain. A detailed section is temporarily
richer *by design*: its content is the backlog payload, and it collapses to
the shared anatomy when its spec ships. Prose convergence is soft
(anchor-level, not byte-level) and is honestly claimed as such — structure
convergence stays hard (scaffold + verify).

## Open questions (deliberately not resolved in this spike)

1. **Cross-cutting concerns.** A directory partition cannot express `compat`
   spread across dependency communities. The literature's answer is a
   dependency graph; the constraint analysis says that can only ever be an
   **optional, per-language evidence provider** refining the git-only default
   (e.g. proposing `pin_dirs`/threshold values), never the reliable path.
   Whether that plugin seam is worth its complexity is a maintainer call.
2. **Cross-directory clusters** would need content-digest baselines over
   sorted per-file blob SHAs (still git-only, still shallow-safe) — a
   marker-format v2 with a `restamp`/`remap` migration. Cost is real; deferred.
3. **PowerShell port of the slicer.** The gate-side changes (widened coverage,
   context markers) are ported and at parity; `blueprint-slice.ps1` (slice,
   scaffold, verify) is not yet written. Follows on acceptance of the design.
4. **Threshold defaults.** `max_files=400 / min_files=3` are defensible, not
   validated beyond pandas + fixtures. The pandas numbers suggest the default
   should perhaps be lower; more brownfield samples would settle it.
5. **Prose determinism** is out of scope by decision: the gate reads markers,
   never prose, so prose variation cannot move the gate. Pinning prose would
   mean template-constrained authoring — a different feature.

## Verification retained

`tests/slicer_test.sh` (15 asserts: rules, byte-determinism, scope-subset,
end-to-end blind-spot closure, additive re-runs, oversize advisories, pins, and
`verify` — conforming map passes; a merged section, structure drift, and
distilled-ownership subtraction are each exercised) and
`tests/e2e_lifecycle_test.sh` (17 asserts: the full downstream lifecycle above,
CI-runnable on a synthetic fixture)
plus 8 new gate asserts in `tests/check_remap_test.sh` (widened scan, context
coverage, config excludes, no-blueprint silence). The pandas run used the same
shipped scripts unmodified; analysis code (import graph, MQ/ARI/NMI/MoJo) lives
outside the repo on purpose — it is an instrument, not a feature.
