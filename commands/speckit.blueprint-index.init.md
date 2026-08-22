---
description: "Initialize or normalize the blueprint — the project's architecture map — stamping each section's provenance marker; idempotent and safe. Seeds from a design doc (greenfield) or existing code (--from-code, brownfield)."
---

# Initialize Blueprint

Create or **normalize** the project **blueprint**: the authoritative, decreasing-detail
map your spec-driven work builds from and stays coherent against. It is at once the
backlog of unspecced design, the architecture map, and the index of feature specs.

This command is **idempotent and safe**: it never deletes content. It reads each
section, works out its true state, and stamps a machine-readable **provenance marker**
so the extension has a deterministic record of what it has processed. Re-running it is a
no-op on sections that are already marked and accurate.

## User Input

```text
$ARGUMENTS
```

`$ARGUMENTS` selects the **on-ramp** (all idempotent):

- **A doc path** (`docs/overview.md`, `docs/master-spec.md`) — *greenfield / formalize*:
  use it as the blueprint and stamp/normalize every section. Ideal for an existing
  master doc that already half-follows the pattern.
- **`--from-code`** (optionally scoped: `--from-code src/<area>`) — *brownfield*:
  reverse-map the codebase into code-owned sections. **The map's structure is
  machine-written, not chosen**: `blueprint-slice.sh scaffold` emits the skeleton
  (sections, markers, TOC) deterministically from `git ls-files` + checked-in config,
  and you author only the prose placeholders — see *Brownfield on-ramp* below. Scoped
  to a single path, it maps **just that area** (a *partial* init) without touching the
  rest — this is the remedy the `check` gate points at for an `unmapped` (new,
  uncovered) code area.
- **`--from-code` + doc path(s)** (e.g. `--from-code docs/architecture.md`) —
  *hybrid brownfield*: the code decides the settled structure exactly as in
  `--from-code`; the named docs are consumed as **evidence**, not as the blueprint —
  see *Hybrid on-ramp* below. This is the richest seeding for a brownfield repo
  that has real design documentation.
- **Empty** — scaffold an empty blueprint from the template, or normalize the
  already-configured/auto-detected blueprint.

## Resolve

1. Repo root = nearest ancestor with `.specify/`.
2. `BLUEPRINT` = `blueprint-config.yml` → `blueprint.path`, else the doc path in
   `$ARGUMENTS`, else auto-detect (the canonical `.specify/memory/blueprint.md` first,
   then `docs/blueprint.md`, `docs/overview.md`), else create from the template at the
   config path.
   If a doc path was given, that doc **is** the blueprint (normalize it in place); do
   not silently create a second one.
3. Template: `.specify/extensions/blueprint-index/templates/blueprint-template.md`.

## The provenance marker (the deterministic record)

Every managed section carries a marker directly under its `## ` heading:

- `<!-- blueprint:section state=detailed -->` — holding pen, design pending.
- `<!-- blueprint:section state=distilled owner=specs/<slug> -->` — owned by a spec.
- `<!-- blueprint:section state=code -->` — owned by existing code (brownfield).
- `<!-- blueprint:section state=context -->` — framing / docs; not a buildable slice.

Code-owned sections additionally carry one `<!-- blueprint:code path=<p> sha=<sha> -->`
per covered path (a section is a **set** of paths — tree markers for directories, blob
markers for single files). Context sections may carry
`<!-- blueprint:context path=<p> -->` coverage markers: the path is on the map (the
`check` gate won't flag it unmapped) but has **no baseline and no staleness** — it is
not architecture-bearing buildable code.

The marker is authoritative. A heading **with no marker** is *unmanaged* (external /
not yet processed) — this run is what stamps it.

## Execution

Ensure the doc has the template's "how this works" header (add it if missing; don't
disturb existing content). Then, **for each `## ` section** (skip meta headings —
Table of Contents, the header comment):

1. **Already marked?** If it has a `blueprint:section` marker, treat it as processed —
   verify it's still accurate (e.g. `state=distilled owner=specs/X` and `specs/X`
   exists) and leave it. Only correct it if clearly wrong. **Do not re-do or clobber.**

2. **Unmarked but already owned by a spec** (a hand-distilled section like a master
   doc's — a `> **Distilled — owned by \`specs/<slug>\`**` banner or a clear reference
   to `specs/<slug>`, or a `specs/<slug>` that plainly owns this subsystem): recognize
   it, stamp `<!-- blueprint:section state=distilled owner=specs/<slug> -->`. If that
   spec is **built**, also add its implementation-footprint baseline
   `<!-- blueprint:code path=src/<area> sha=NONE -->` so code drift is caught later.

3. **Unmarked, brownfield (`--from-code`)**: follow the *Brownfield on-ramp* procedure
   below — the section set comes from the partitioner, the prose from you.

4. **Unmarked, framing / cross-cutting** (not a buildable slice — e.g. "what this
   system is", scope boundary, key entities/glossary, anti-bias/quality properties,
   definition of done): stamp `<!-- blueprint:section state=context -->`. Context
   sections are managed but are **never** backlog and are never specced — this is what
   keeps a doc full of framing from either looking like endless backlog or blocking
   "done". Be conservative: if a section could plausibly become a spec, mark it
   `detailed`, not `context`.

5. **Unmarked, unspecced design** (a plain holding-pen section that a future spec will
   formalize): stamp `<!-- blueprint:section state=detailed -->`. Keep its full design
   detail in place.

Add the cosmetic prose banner under the marker if it helps human readers; the marker,
not the banner, is what the oracle reads. **Never invent content the source lacks, and
never delete a section's design detail.**

6. **Refresh the Table of Contents** so each section's status matches its marker
   (`context` / `detailed` / `distilled → specs/<slug>` / `owned by code → src/<area>`).

7. **Record code baselines.** Run the oracle's restamp to fill every `sha=NONE`:
   `bash .specify/extensions/blueprint-index/scripts/bash/blueprint-state.sh restamp` (or the
   PowerShell port). Now `blueprint.check` can detect later code drift.

## Brownfield on-ramp (`--from-code`): structure is machine-written, prose is authored

Two independent runs of this on-ramp must produce the **same map structure**. That is
guaranteed by never letting you write structure at all:

1. **Scaffold writes the map, not you** —
   `bash .specify/extensions/blueprint-index/scripts/bash/blueprint-slice.sh scaffold`
   emits the complete, deterministic skeleton: title, how-this-works header,
   status-annotated TOC, and every computed section with its provenance markers,
   banner, and a `TODO(prose)` placeholder. Redirect it to the blueprint path when no
   map exists. Against an existing map it emits **only the missing additive section
   blocks** (append them); add `--scope <dir>` when the init is scoped — this is the
   remedy flow for an `unmapped` gate issue. Same repo state + same config ⇒
   byte-identical output.

2. **Your ONLY edit is replacing the `TODO(prose)` placeholders** (including the TOC
   one-liners), following the **architecture-recovery procedure** in
   `.specify/extensions/blueprint-index/templates/section-anatomy.md` — the shared
   contract every settled section obeys (banner, role sentence, evidence-anchored
   at-a-glance digest, closer; inventory → boundary-before-depth → write →
   self-check). Anchors must resolve to paths under the section's own markers;
   cross-references name *sections*, not files. Touch nothing else — no headings,
   no markers, no banners, no section order. Two runs may word prose differently,
   but they walk the same evidence in the same order, so the anchors converge —
   and no oracle reads prose either way.

3. **Every tracked file is accounted for, nothing silently absent.** Run
   `blueprint-slice.sh slice --json` and echo its `excluded` and `root_files` lists
   and any `advisories` in your report so a human reviews what stayed out — that
   review is the whole point of the on-ramp.

4. **Disagree with the cut? Change the config, not the map.** Granularity and scope are
   owned by `blueprint-config.yml` (`slice.max_files`, `slice.min_files`,
   `slice.boundary_files`, `slice.context_dirs`, `slice.pin_dirs`,
   `coverage.exclude`). Edit it, re-scaffold, re-fill the prose. The override is then
   checked in and **replays identically on every future run** — a freehand deviation
   would be lost non-determinism the next run can't reproduce.

5. **Close the loop — conformance is machine-checked.** Run restamp (step 7
   above), then two oracles must both pass:
   - `blueprint-slice.sh verify` — recomputes the partition and diffs it against
     the (section, kind, marker) structure you actually wrote. A merged,
     dropped, renamed, regrouped, or invented section is a deterministic pair
     diff and exit 1. Rule 2 is not an honor system.
   - `blueprint-state.sh check` — the scoped area must report **no `unmapped`
     issues**.
   Also confirm no `TODO(prose)` placeholder remains (`grep -c 'TODO(prose)'`).
   On failure, fix the structure (or the config, then re-derive) — never
   silence the oracles.

6. **Stage 2 — recover the architecture.** With the sections settled and
   verified, run the architecture-recovery specialist
   (`speckit.blueprint-index.recover`): it derives how the subsystems relate —
   dependency edges, layering, cycles, cross-cutting concerns — as
   evidence-anchored relation markers that the `check` gate validates from
   then on (`relation` / `relation-evidence` issues on decay).

## Hybrid on-ramp (`--from-code` + docs): code decides structure, docs contribute

A brownfield repo with real design docs should consume **both** — this is the
Reflexion-Models division of labor: the source model (code) is authoritative for
what exists; the high-level model (docs) contributes names, intent, and the
backlog. Run the brownfield on-ramp above first (scaffold → prose → verify +
check), then reconcile the docs into it with exactly three moves — each lands in
a lane that keeps the on-ramp reproducible:

1. **Grouping and naming disagreements → config, never freehand.** Where the
   doc's decomposition disagrees with the computed cut (it treats a directory
   pair as one subsystem, or a tree as documentation), express the doc's view in
   `blueprint-config.yml` (`slice.pin_dirs`, `slice.context_dirs`, thresholds)
   and re-scaffold. The doc's influence on structure is thereby checked in and
   replays identically. A conceptual subsystem that **cross-cuts directories**
   cannot be a code section (markers are tree/blob paths); capture it as a
   `context` section citing the doc, or as a `detailed` section if it implies
   future work — never by bending markers.
2. **Doc knowledge about existing code → prose enrichment.** Digests may cite
   the docs as *secondary* anchors (see the section-anatomy evidence rules): the
   primary anchor of a code-owned bullet is always a real path under the
   section's markers, and **where docs and code disagree, code wins** — note the
   disagreement in the prose rather than repeating the doc's claim; it is
   frequently a real finding.
3. **Designed-but-unbuilt content → `detailed` sections (the backlog).** Design
   the docs describe but the code does not contain becomes holding-pen sections
   (`state=detailed`), preserving the doc's detail per the non-destruction
   guardrail. This is the payoff of hybrid seeding: the map comes out with a
   real backlog, so `next` moves from idle to `specify` and the waterfall has
   work to pull. Carry no marker on these sections — they are outside the
   slicer's jurisdiction (verify ignores them) until a spec ships and `distill`
   settles them.

Close the loop as usual: `verify` (unaffected by detailed additions) + `check`
+ no `TODO(prose)` leftovers.

## Report Back

- `BLUEPRINT` path; whether created, seeded, or normalized in place.
- Section tally from the markers: N total — X detailed, Y settled (spec/code), and how
  many were **newly stamped** this run vs already managed.
- Next: `__SPECKIT_COMMAND_BLUEPRINT_STATUS__` for the worklist, and add the
  `check` gate to CI so the map stays honest.

## Guardrails

- **Idempotent + non-destructive:** only add/normalize markers, banners, and the TOC.
  Never delete design detail; never re-process an already-marked, accurate section.
- Never fabricate design detail or code behavior not present in the source.
- Every managed section must end with exactly one `blueprint:section` marker — that is
  the extension's deterministic record of provenance.
- **`--from-code` structure is machine-written, never improvised:** `blueprint-slice.sh
  scaffold` writes the skeleton; your judgment goes into the `TODO(prose)` placeholders
  and, when the cut is wrong, into `blueprint-config.yml` (then re-scaffold) — never
  into freehand structure. `verify` enforces this after the fact.
