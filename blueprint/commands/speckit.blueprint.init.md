---
description: "Scaffold the blueprint — the project's backlog + architecture map — seeding from a design doc (greenfield) or from the existing codebase (brownfield)"
---

# Initialize Blueprint

Create the project **blueprint**: the authoritative, decreasing-detail map your
spec-driven work builds from and stays coherent against. It is at once the backlog
of unspecced design, the architecture map, and the index of feature specs.

## User Input

```text
$ARGUMENTS
```

`$ARGUMENTS` selects the **on-ramp**:

- **A design doc path** (`docs/master-spec.md`, `docs/overview.md`) — *greenfield*:
  import it as the holding pen. Sections start **detailed** and collapse as you build.
- **`--from-code`** (optionally followed by a path scope, e.g. `--from-code src/`) —
  *brownfield*: reverse-map the existing codebase into a blueprint whose sections are
  already **settled (owned by code)**. This is the "what is this system, how does it
  fit" map for an existing repo.
- **Empty** — scaffold an empty blueprint from the template to fill in by hand.

## Resolve

1. Repo root = nearest ancestor with `.specify/`.
2. Blueprint path: `blueprint-config.yml` → `blueprint.path` (default
   `.specify/memory/blueprint.md`; many teams prefer `docs/blueprint.md`). Call it
   `BLUEPRINT`.
3. Template: `.specify/extensions/blueprint/templates/blueprint-template.md`.

## Prerequisites

- If `BLUEPRINT` exists, **do not overwrite**. Report it and suggest
  `__SPECKIT_COMMAND_BLUEPRINT_STATUS__`, then stop.
- Create `BLUEPRINT`'s parent directory if needed.

## Execution

1. **Start from the template.** Fill `[PROJECT NAME]` and `[DATE]`. Keep the
   "how this works" header and the prose section convention (Detailed vs Distilled
   banners) — the commands and the oracle read prose, not tags.

2. **If a design doc was provided** (greenfield), import it as the holding pen:
   - Split it into subsystem-sized sections; carry over the real design detail at
     design altitude (decisions, thresholds, entities, contracts, open questions).
     Do not invent content the seed lacks.
   - **Cross-check `specs/`.** For each subsystem, if a feature spec already owns it,
     scaffold that section already-**distilled** (digest + pointer) instead of
     copying detail. Where a spec owns only part, distill that part and keep the
     rest detailed (partial distillation). When ownership is ambiguous, leave it
     detailed and note `[NEEDS CLARIFICATION: owning spec?]`.

3. **If `--from-code` was given** (brownfield), reverse-map the codebase:
   - Walk the repo (respecting the optional path scope; skip vendored/build dirs).
     Identify the real subsystems from the directory structure, entry points,
     routes, and module boundaries — not file-by-file.
   - Write each as a **settled "owned by code"** section: the `> **Distilled — owned
     by code at \`src/<area>/\`.**` banner, a one/two-sentence role, an at-a-glance
     digest of how it behaves *today* (key mechanics, entry points, data it owns),
     and a "read the code for exact behavior" closer. **Map what exists; do not
     invent intended behavior or redesign.**
   - **Add a baseline marker** under each code-owned banner so the section can be
     kept honest against future out-of-band code edits:
     `<!-- blueprint:code path=src/<area> sha=NONE -->` (no trailing slash in `path`).
   - **Cross-check `specs/`.** If a spec already owns an area, point the section at
     the spec instead of (or in addition to) the code.
   - After writing the blueprint, **record the baselines** by running the oracle's
     `restamp` (this fills each `sha=NONE` with the code's current git hash):
     `.specify/extensions/blueprint/scripts/bash/blueprint-state.sh restamp` (or the
     PowerShell port). Now `blueprint.check` can detect later code drift.
   - The result is an all-settled map with no pending design — `status` will report
     it idle. To change an area later, run `/speckit.specify` on it as usual; once
     the spec ships, `distill` collapses its section and the `check` gate keeps it
     honest.

4. **If no argument**, leave the example sections as a guide to replace.

5. **Build the Table of Contents** so every section has one entry with its status
   (`detailed` / `distilled → specs/<slug>` / `owned by code → src/<area>`).

6. **Write** `BLUEPRINT`. For a greenfield seed, do not delete the source — recommend
   the author retire it once the blueprint is trusted, to keep a single source of truth.

## Report Back

- Path written; whether seeded and from where.
- TOC summary: N sections — X detailed / Y settled (spec- or code-owned).
- Next: run `__SPECKIT_COMMAND_BLUEPRINT_STATUS__` to see the map's state, and add
  the `check` gate to CI so the map stays in sync as you build.

## Guardrails

- Never overwrite an existing blueprint.
- Never fabricate design detail not in the seed or codebase.
- Keep the prose section convention and the header — downstream commands rely on it.
