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
  reverse-map the codebase into code-owned sections. Scoped to a single path, it maps
  **just that area** into one new code-owned section (a *partial* init) without touching
  the rest — this is the remedy the `check` gate points at for an `unmapped` (new,
  uncovered) code area.
- **Empty** — scaffold an empty blueprint from the template, or normalize the
  already-configured/auto-detected blueprint.

## Resolve

1. Repo root = nearest ancestor with `.specify/`.
2. `BLUEPRINT` = `blueprint-config.yml` → `blueprint.path`, else the doc path in
   `$ARGUMENTS`, else auto-detect (`docs/blueprint.md`, `docs/overview.md`,
   `.specify/memory/blueprint.md`), else create from the template at the config path.
   If a doc path was given, that doc **is** the blueprint (normalize it in place); do
   not silently create a second one.
3. Template: `.specify/extensions/blueprint-index/templates/blueprint-template.md`.

## The provenance marker (the deterministic record)

Every managed section carries a marker directly under its `## ` heading:

- `<!-- blueprint:section state=detailed -->` — holding pen, design pending.
- `<!-- blueprint:section state=distilled owner=specs/<slug> -->` — owned by a spec.
- `<!-- blueprint:section state=code -->` — owned by existing code (brownfield).

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

3. **Unmarked, brownfield (`--from-code`)**: map the code as it exists **today** (role
   sentence + at-a-glance digest of mechanics/entry points; do not redesign). Stamp
   `<!-- blueprint:section state=code -->` and `<!-- blueprint:code path=src/<area>
   sha=NONE -->`.

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
