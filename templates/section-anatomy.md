# Section anatomy — the one shape every settled section has

This is the shared contract for the **prose lane**: every settled section of the
blueprint has the same anatomy no matter which command wrote it (`init
--from-code` recovering architecture from a brownfield repo, `remap` refreshing
a stale section, `distill` collapsing a shipped spec) and no matter which
on-ramp seeded the map (code or docs). Structure — headings, markers, section
set — is machine-written and out of scope here; this file governs what a human
or agent writes *inside* a section, so that maps from different provenances
read as one document type and two recovery runs converge on the same content.

## The five parts, in order

1. **Heading + provenance marker** — machine lane. Never edited by hand; the
   scaffold/distill flow owns them, `verify` enforces them.
2. **Ownership banner** (cosmetic, one to three lines): who owns the truth.
   - code-owned: `> **Distilled — owned by code at \`<path>/\`.** (no spec yet) …`
   - spec-owned: `> **Distilled — owned by \`specs/<slug>\`** (implemented at \`<path>/\`). …`
3. **Role sentence** — one or two sentences naming the section's responsibility
   and how it connects to its neighbors. Present tense, what it *is/does*, not
   history or intention.
4. **At-a-glance digest** — 2–6 bullets, each **evidence-anchored** (rules
   below). This is the load-bearing content: a reader should grasp the
   subsystem's shape without opening the owner.
5. **Closer** — an explicit "see the owner, don't restate" line:
   - code-owned: `For exact behavior, read the code under \`<path>/\`. Do not restate it here.`
   - spec-owned: `For every requirement, threshold, and entity shape, see \`specs/<slug>/spec.md\`. Do not restate those details here.`

## Evidence rules (what makes a digest bullet valid)

- **Every bullet cites at least one anchor that exists**: a file or entry point
  under the section's own markers (code-owned), or a spec section reference
  (spec-owned). No anchor → no bullet.
- **Cross-references name sections, not files**: a dependency on another part
  of the system is written as the *section* it lands on (`hands parsed frames
  to **pandas/core**`), keeping the digest at map altitude.
- **Load-bearing only**: entry points, owned data/state, key constants and
  decisions, the contracts neighbors rely on. A fact that wouldn't change any
  reader's next action is below altitude — leave it in the owner.
- **Map what exists; never redesign** and never invent behavior the evidence
  doesn't show. Unknown stays unsaid.

## The recovery procedure (code-owned sections — brownfield on-ramp and remap)

Two independent recovery runs must converge on the same digest content. Wording
may differ; the **anchors** should not, because both runs walk the same
evidence in the same order:

1. **Inventory** — start from the section's markers (the machine-written path
   set). List the files; note the obvious entry points (`__init__.py`,
   `index.*`, `main.*`, `mod.rs`, the file sharing the directory's name).
2. **Boundary before depth** — read the entry points and the section's public
   surface (exports, re-exports) first; then scan which *other sections'* paths
   it imports/includes (its neighbors). Only then open the biggest internal
   files if the role is still unclear.
3. **Write** the role sentence from the surface, one bullet per load-bearing
   facet found, each anchored per the evidence rules.
4. **Self-check** — every anchor resolves to a real path under the markers;
   every cross-reference names an existing section; no `TODO(prose)` remains.

## Worked examples

Code-owned (brownfield recovery):

```markdown
## src/ledger
<!-- blueprint:section state=code -->
> **Distilled — owned by code at `src/ledger/`.** (no spec yet) The implementation
> is the source of truth; this section maps it.
<!-- blueprint:code path=src/ledger sha=… -->

Double-entry bookkeeping core: every balance change is an immutable journal
entry, and account balances are derived, never stored. At a glance:

- **Entry point** — `src/ledger/journal.py: post()` is the only write path;
  everything else is read-model.
- **Owned data** — the `journal_entries` table (append-only); balance snapshots
  are a cache rebuilt by `src/ledger/projector.py`.
- **Neighbors** — consumes account ids from **src/accounts**; emits settlement
  events consumed by **src/payments**.

For exact behavior, read the code under `src/ledger/`. Do not restate it here.
```

Spec-owned (post-distill) — same anatomy, different owner:

```markdown
## 4. Rate Limiting
<!-- blueprint:section state=distilled owner=specs/002-rate-limiting -->
> **Distilled — owned by `specs/002-rate-limiting`** (implemented at `src/ratelimit/`).
> The full detail lives in that spec, which is the source of truth.
<!-- blueprint:code path=src/ratelimit sha=… -->

Per-caller request throttling: a token bucket per API key smooths bursts and
sheds load with a `429` once a caller outruns its budget. At a glance:

- **Algorithm** — token bucket per `api_key`, lazily refilled on read (spec §4.1).
- **Budget** — `capacity = 100`, `refill = 10/sec`; over-budget → `429` + `Retry-After` (§4.2–§4.3).
- **State** — buckets in Redis, keyed `rl:{api_key}` (§4.5).

For every requirement, threshold, and entity shape, see `specs/002-rate-limiting/spec.md`.
Do not restate those details here — this section indexes the spec.
```

The two examples are interchangeable in shape — that is the point. A map seeded
from code and a map seeded from a design doc meet at this anatomy as sections
settle; the only lasting difference is the provenance marker, which is exactly
the difference that must remain.
