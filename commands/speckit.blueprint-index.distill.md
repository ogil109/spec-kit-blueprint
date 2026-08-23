---
description: "Collapse a finalized feature spec's section in the blueprint to an at-a-glance digest + a pointer, leaving unspecced detail untouched"
---

# Distill Blueprint Section

A feature spec now owns a slice the blueprint still describes in full. Replace that
section's duplicated detail with an **at-a-glance digest + a pointer to the spec**,
so the blueprint stays the architecture map and the spec is the single source of
truth. Detail flows out, once, forward — never back-synced.

## User Input

```text
$ARGUMENTS
```

`$ARGUMENTS` names the spec to distill — a feature slug (`002-rate-limiting`),
a spec path, or a subsystem name. If empty, distill the highest-priority drifted
spec the oracle reports (`blueprint-state.sh status` → "Distill drift").

## Resolve

1. Repo root = nearest ancestor with `.specify/`.
2. Blueprint path: `blueprint-config.yml` → `blueprint.path`; else auto-detect
   (the canonical `.specify/memory/blueprint.md`, then `docs/blueprint.md`).
3. Target spec dir under `specs/<slug>/`; confirm `spec.md` exists.
4. Find the blueprint section this spec owns — by heading/scope match, or an
   existing pointer to `specs/<slug>`. If none matches, report it and offer to add
   a distilled section; if several do, ask (interactive) or pick the best and say so.

## Altitude — get this right

The result must follow the shared **section anatomy**
(`.specify/extensions/blueprint-index/templates/section-anatomy.md`) — the same
contract the brownfield on-ramp and `remap` write to, which is what keeps a map
seeded from docs and a map seeded from code reading as one document type.
Distillation is **not** "compress to 2 sentences." At map altitude a reader should
still see the **load-bearing mechanics** without opening the spec. Keep an
**at-a-glance digest** of the decisions that define the slice's shape; drop only
the full requirements, scenarios, and entity detail (those live in the spec).

Worked reference — this is the target quality (a generic rate-limiting slice):

```markdown
## 4. Rate Limiting

> **Distilled — owned by `specs/002-rate-limiting` (§4.1–§4.6).** The full detail
> lives in that feature spec, which is the source of truth. This section is a
> summary + index.

Per-caller request throttling: a token bucket per API key smooths bursts and sheds
load with a `429` once a caller outruns its budget. At a glance:

- **Algorithm** — token bucket, one bucket per `api_key`, lazily refilled on read.
- **Budget** — `capacity = 100` tokens, `refill = 10 tokens/sec`; one token per request.
- **Response** — over-budget → `429` + `Retry-After`; every response carries
  `X-RateLimit-{Limit,Remaining,Reset}`.
- **State** — buckets in Redis, keyed `rl:{api_key}`, TTL `= capacity / refill`.
- **Exemptions** — internal service tokens bypass; unauthenticated callers throttle by IP.

For every threshold, header format, and entity shape, see `specs/002-rate-limiting/spec.md`.
Do not restate those details here — this section indexes the spec.
```

Notice: a one-line ownership banner, a tight prose role sentence, a bulleted digest
of the mechanics with their key constants, and an explicit "see the spec, don't
restate" closer. Match that shape; scale the digest to the slice.

## Execution

Distillation writes its prose through the **same facts → render flow as every
other section** — you author claims with evidence, the renderer validates them
and writes the body, digest, spec-pointer closer, and TOC entry. You never
hand-write the section body.

1. Read `spec.md` (and `plan.md` if present). Extract the digest facts: the
   slice's role in one or two sentences, then the handful of load-bearing
   decisions/constants — each anchored to evidence.
2. **Set the provenance markers by hand** (markers are structure, not prose):
   - Flip the section marker to
     `<!-- blueprint:section state=distilled owner=specs/<slug> -->` (replacing
     the previous `state=detailed`/`state=code` marker). The `owner=` value must
     be the space-free spec directory path — it widens the section's evidence
     jurisdiction to that directory and becomes the TOC's `distilled → owner`
     pointer.
   - Update the ownership banner (`> **Distilled — owned by
     \`specs/<slug>\`.**`) — `> ` callout lines are preserved by the renderer.
   - **Stamp the implementation footprint** if the slice has shipped code: add a
     baseline marker per implemented area directly under the banner —
     `<!-- blueprint:code path=src/<area> sha=NONE -->` (no trailing slash) —
     and note it in the banner as `(implemented at \`src/<area>/\`)`. Skip only
     for a spec-only distill with no code yet.
3. **Author the facts and render.** Write a facts file:

   ```text
   blueprint-facts 1
   section <exact heading>
   role <one-two sentence role>
   facet <Label> | <load-bearing decision/constant> | <evidence>
   neighbor uses | <other-section> | <why> | <evidence>
   ```

   Evidence for a distilled section may anchor into its own code markers **or
   into `specs/<slug>/...`** (e.g. `specs/<slug>/spec.md#SC-001`) — the owning
   spec is inside the section's jurisdiction, and `#pattern` anchors are grepped
   at HEAD so the digest stays falsifiable. Then run
   `bash .specify/extensions/blueprint-index/scripts/bash/blueprint-slice.sh render --facts <file>`
   (or the PowerShell port). The renderer validates every claim and writes the
   role, the at-a-glance bullets, the "see the spec" closer, and the TOC entry
   (`distilled → \`specs/<slug>\``) in one pass; on any invalid claim it writes
   nothing and lists the errors.
4. **Restamp.** `bash .specify/extensions/blueprint-index/scripts/bash/blueprint-state.sh restamp`
   records the git baselines. Now `blueprint.check` flags this slice as STALE if
   its code is later edited out-of-band — the same gate that protects brownfield
   code-owned sections — and its edges are repairable through the same facts flow.
5. **Partial distillation is allowed and normal.** If a spec owns only part of a
   section (e.g. §3.1–§3.9 but not §3.10), distill that part and leave the rest as
   detailed holding-pen, with a short note saying which sub-part is still unspecced
   and which future spec it's earmarked for. Do not force a whole section to one state.
6. **Preserve information with no other home.** Cross-cutting notes the spec doesn't
   capture move to the relevant detailed section or a brief "Cross-cutting" note —
   never dropped.
7. **Idempotent.** Re-running render with the same facts rewrites the same body;
   re-running restamp on an unchanged slice is a no-op. Never expand a pointer
   back into full detail.

## Confirmation

If `blueprint-config.yml` → `distill.require_confirmation` is true (default), show
the before/after of the affected section and ask before writing. In non-interactive
runs with confirmation required, emit the proposed diff and report it as pending.

## Report Back

- Which section was distilled and the spec it now points to.
- Confirmation that no unspecced (detailed) section was touched.
- Any holding-pen sub-parts left in place, and any relocated cross-cutting notes.

## Guardrails

- Touch only the target section (and its index entry). Detailed/unspecced sections
  are the backlog — never modify them.
- Keep the at-a-glance mechanics; only the full requirements/entities leave.
- Never expand a pointer back into detail. No back-sync, ever.
