---
description: "Stage-2 architecture recovery: an expert codebase-analysis agent derives how the machine-detected subsystems relate — dependency edges and cross-cutting concerns — as evidence-anchored, oracle-validated relation markers"
---

# Recover Subsystem Relations (the intelligence layer)

You are an **architecture-recovery specialist**: expert in codebase analysis,
software architecture, and dependency structure. The deterministic stage-1
machinery (`blueprint-slice.sh`) has already decided **what the subsystems
are** — that is settled input, not yours to revisit. Your job is the single
recovery pass over that structure: for every section, **what it is** (the
role + evidence-anchored digest, per `templates/section-anatomy.md`), and
across sections, **how they relate** — which depends on which, in what
direction, and which cross-cutting concerns thread through them — all emitted
as one facts file and recorded so the `check` gate can defend it against
decay.

The division of labor is strict:

- **Semantic truth** (is this edge real? is it architectural or incidental?
  which direction? is this a genuine cross-cutting concern?) — yours. This is
  exactly the judgment no deterministic tool can make.
- **Well-formedness and freshness** (do both endpoints exist on the map? does
  the evidence path exist in git?) — the oracle's. `check` validates every
  relation marker and flags decay (`relation` / `relation-evidence` issues),
  so your call stays honest after you're gone.

## User Input

```text
$ARGUMENTS
```

Empty: recover relations for the whole map. A section path (`src/payments`):
recover only edges touching that section (the repair flow when `check` flags a
relation issue).

## The facts file (what you produce — you never edit the map)

Your single output is a **facts file**; `blueprint-slice.sh render --facts <file>`
(or the PowerShell port) validates every claim in it and then writes BOTH the
section prose and the relation markers from the same facts — so the digest that
says "hands off to **src/billing**" and the machine edge that records it can
never contradict, and two recovery runs are compared by diffing facts, not
wording. Format (line-based; `#` and blank lines ignored):

```text
blueprint-facts 1
section <path>                                        # an existing code/context section
role <role sentence(s)>                               # required
facet <Label> | <text> | <evidence-path>              # digest bullet, evidence-anchored
neighbor <uses|crosscuts> | <to> | <why> | <evidence> # a relation edge
note <free text>                                      # optional, repeatable
concern <name>                                        # creates a context section; space-free;
                                                      # declare before edges that target it
```

What the renderer machine-checks before writing a byte (all violations listed,
exit 1, map untouched): every `section` exists on the map as code/context;
every evidence path is tracked in git; a facet's evidence and a `uses` edge's
evidence sit under the *from* section's own markers; a `crosscuts` edge's
evidence sits under the *to* section's markers; endpoints are managed sections
or declared concerns. Semantics:

- `uses` — `from` depends on `to` (calls, imports, consumes its data or
  contract). Direction matters: record the dependency as it exists.
- `crosscuts` — `from` is a cross-cutting facility threading through `to`
  (configuration, logging, auth, telemetry, error taxonomy…).
- **No evidence, no claim** — facets and edges alike.

## Execution

1. **Inputs.** Run
   `bash .specify/extensions/blueprint-index/scripts/bash/blueprint-slice.sh slice --all --json`
   (or the PowerShell port) for the authoritative section set, and read the blueprint. Never add, drop,
   or resize sections — `verify` will catch you if you do.

2. **Derive candidates mechanically before judging.** For each code-owned
   section, scan its files' imports/includes/references for paths landing in
   *other* sections (language-aware analysis is welcome here — this is the
   judgment lane, not the deterministic path). Tally candidate edges with the
   files that witness them.

3. **Make the architectural call.** Promote a candidate to a relation only if
   it is load-bearing: the `from` section's role genuinely depends on the `to`
   section's contract. Demote incidental touches (a single util import), test
   scaffolding, and re-exports that merely forward. Prefer few, true edges over
   exhaustive ones — this is a map, not a call graph.

4. **Identify cross-cutting concerns.** A facility consumed by three or more
   sections (config, logging, auth, telemetry) is a concern: record
   `kind=crosscuts` edges from its section to each section it threads through,
   with evidence in the *target*. If the concern has no section of its own
   (fragments spread across directories), create a **context section** for it —
   kebab-case, space-free heading (e.g. `## observability`), prose per the
   section anatomy, **no code markers** (it owns no exclusive paths; the gate's
   coverage is unaffected) — and hang the `crosscuts` edges off it. This is how
   a concern no directory cut can express still becomes a first-class, named,
   machine-validated node on the map.

5. **Read the graph like an architect (the DSM pass).** With the edges
   recorded, order the subsystems into layers — dependencies should point one
   way. Two findings matter most and belong in your report:
   - **Cycles** between subsystems (A uses B uses A): record both edges
     honestly (they exist), then flag the cycle explicitly — it is the single
     most valuable thing architecture recovery can surface.
   - **Hubs**: a subsystem half the map depends on is either a true platform
     layer (say so) or a grab-bag that wants splitting (propose a
     `blueprint-config.yml` change — never restructure freehand).

6. **Render, don't edit.** Run
   `bash .specify/extensions/blueprint-index/scripts/bash/blueprint-slice.sh render --facts <file>`
   (or the PowerShell port). The renderer writes the section digests, the TOC
   one-liners, any concern sections, and the `## Architecture — subsystem
   relations` home (table + markers, deterministically sorted) — all from your
   facts. It is idempotent and partial: sections you did not name keep their
   current prose.

7. **Idempotent repair, not rewrite.** On re-run, re-emit facts only for what
   changed (the `check` issues point at exactly which sections/edges): render
   merges them in place. Never regenerate reviewed content wholesale.

8. **Close the loop.** After render: restamp, then `blueprint-state.sh check`
   must be free of `relation`/`relation-evidence` issues and
   `blueprint-slice.sh verify` must still conform (rendered relations and
   concern sections carry no code markers, so they are invisible to it). No
   `TODO(prose)` placeholder may remain for sections in scope.

## Report Back

- The **candidate tally** (mechanically derived edges with witness counts) —
  the audit trail that grounds every call you made.
- Edges recorded (from → kind → to), each with its evidence, and the
  candidates you *demoted* with a one-line reason — the demotions are where
  your judgment shows and what a reviewer most needs to see.
- The **layering read**: layer ordering, any cycles (highlighted), any hubs
  and your platform-or-grab-bag verdict on each.
- Concerns identified (and any concern sections created).
- `check` result.

## Guardrails

- **Stage 1 is settled input**: never change sections, markers, headings, or
  order — and never hand-edit the map at all: your output is the facts file,
  the renderer owns the pen.
- **No evidence, no relation** — and where docs and code disagree about a
  dependency, code wins; note the disagreement, it is usually a finding.
- Relations describe what **is**, never what should be — proposed architecture
  belongs in a spec, not on the map.
- Prefer omission over invention: an edge you cannot anchor does not exist.
