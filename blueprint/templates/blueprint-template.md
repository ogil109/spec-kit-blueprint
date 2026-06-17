# [PROJECT NAME] Blueprint

**Status**: Living document — the authoritative backlog + architecture map for this project.

**Created**: [DATE]

<!--
  HOW THIS DOCUMENT WORKS
  =======================
  The blueprint is a *decreasing-detail* map your spec-driven work builds from and
  stays coherent against. Every section is in ONE of two states:

    - DETAILED (holding pen): design work is pending here — a subsystem with no
      feature spec yet. This is the backlog you pull from when you /speckit.specify
      that slice.

    - SETTLED (index): the detail lives with an authoritative OWNER, and this
      section is just an at-a-glance digest + pointer. The owner is either:
        · a feature SPEC  — `specs/<slug>` (a slice you've designed/built here), or
        · the CODE        — `src/...` (a slice that already exists; brownfield).

  Two on-ramps, same map:
    - GREENFIELD: seed from a design doc (init). Sections start DETAILED and
      collapse to spec-owned as you build. Detail flows out into specs.
    - BROWNFIELD: seed from existing code (init --from-code). Sections start
      SETTLED against code; to change a slice, /speckit.specify it as usual and
      `distill` collapses its section when the spec ships.

  Detail flows ONE WAY — out into specs, once, when a slice is specced. Never
  back. There is nothing to back-sync.

  GROUND TRUTH is the filesystem: `specs/<NNN-slug>/` is authoritative for what's
  been specced/built; `src/...` is authoritative for what already exists; this
  document references both by path, and the `check` gate keeps the references honest.

  SECTION CONVENTION (prose, not tags):
    - DETAILED:        > **Detailed (unspecced)** — holding pen.
    - SETTLED by spec: > **Distilled — owned by `specs/<slug>`.**
    - SETTLED by code: > **Distilled — owned by code at `src/...`.** (no spec yet)
      Each settled banner is followed by a short role sentence, a bulleted
      at-a-glance digest of the load-bearing mechanics, and a "see the owner,
      don't restate" closer.
    Partial distillation is fine: distill the specced sub-part, keep the rest
    detailed with a note naming the future spec it's earmarked for.

  AUTHORITY: feature spec = source of truth for its slice; blueprint = map +
  holding pen that defers to specs; constitution = principles.
-->

## Table of Contents

The index *and* the architecture map. Each entry notes its status so the map and
the sections agree. Keep it current (the /speckit.blueprint.* commands do this).

- §1 [Subsystem A] — [one line]; **detailed** (no spec yet)
- §2 [Subsystem B] — [one line]; **distilled** → `specs/00X-slug`
- … add one entry per section …

---

## 1. [Subsystem A]

> **Detailed (unspecced)** — holding pen. Full design lives here until a feature
> spec takes it over. This is the backlog you specify next.

**Purpose**: [what this subsystem is responsible for].

**Key decisions**: [the real design — entities, contracts, thresholds, gate
mechanics, the things a future spec will formalize].

**Boundaries**: [what it exposes to / expects from neighbors].

**Open questions**: [NEEDS CLARIFICATION: …]

---

## 2. [Subsystem B]

> **Distilled — owned by `specs/00X-slug` ([spec](../../specs/00X-slug/spec.md))**
> (implemented at `src/[area]/`). The full detail lives in that spec, which is the
> source of truth. This is a summary + index.
<!-- blueprint:code path=src/[area] sha=NONE -->

[One or two sentences: the slice's role and how it connects to neighbors.] At a glance:

- **[Facet]** — [the load-bearing decision / constant].
- **[Facet]** — [key mechanic].

For every requirement, threshold, and entity shape, see `specs/00X-slug/spec.md`.
Do not restate those details here — this section indexes the spec.

---

## 3. [Subsystem C]  — brownfield example

> **Distilled — owned by code at `src/[area]/`.** (no spec yet) The implementation
> is the source of truth; this section maps it. To change it, `/speckit.specify` the
> area as usual and `distill` it when the spec ships.
<!-- blueprint:code path=src/[area] sha=NONE -->

<!-- The marker above records the git baseline of the mapped code. `blueprint.check`
     flags this section as STALE when src/[area] changes without going through a
     spec; `blueprint.remap [area]` re-derives it and refreshes the baseline. -->


[One or two sentences: what this existing subsystem does and how it connects.] At a glance:

- **[Facet]** — [the load-bearing behavior as it exists today], entry point `[fn()]`.
- **[Facet]** — [key mechanic / data it owns].

For exact behavior, read the code under `src/[area]/`. Do not restate it here —
this section indexes the implementation.
