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
   (`docs/blueprint.md`, `docs/overview.md`, `.specify/memory/blueprint.md`).
3. Target spec dir under `specs/<slug>/`; confirm `spec.md` exists.
4. Find the blueprint section this spec owns — by heading/scope match, or an
   existing pointer to `specs/<slug>`. If none matches, report it and offer to add
   a distilled section; if several do, ask (interactive) or pick the best and say so.

## Altitude — get this right

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

1. Read `spec.md` (and `plan.md` if present). Extract the digest: the slice's role
   in one or two sentences, then the handful of load-bearing decisions/constants.
2. Rewrite the section in place: **set its provenance marker** to
   `<!-- blueprint:section state=distilled owner=specs/<slug> -->` (replacing the
   previous `state=detailed`/`state=code` marker — this is the extension's deterministic
   record that it processed the section), then the ownership banner (`> **Distilled —
   owned by `specs/<slug>`.**`) + the prose role + the bulleted at-a-glance digest + the
   "see the spec" closer. Compute a correct relative pointer to the spec.
3. **Stamp the implementation footprint (so code drift on this slice is caught).**
   If the slice has shipped code, note where it lives — the directory/directories
   the spec was implemented in (e.g. `src/payments`) — in the banner as
   `(implemented at \`src/<area>/\`)`, and add a baseline marker per area directly
   under the banner: `<!-- blueprint:code path=src/<area> sha=NONE -->` (no trailing
   slash; directory-level is the sane granularity). Then run the oracle's restamp to
   record the git baselines:
   `bash .specify/extensions/blueprint/scripts/bash/blueprint-state.sh restamp` (or the
   PowerShell port). Now `blueprint.check` flags this slice as STALE if its code is
   later edited out-of-band, and `blueprint.remap` / a re-spec resyncs it — the same
   gate that protects brownfield code-owned sections. **Skip this only for a
   spec-only distill with no code yet** (no baseline to record).
4. **Partial distillation is allowed and normal.** If a spec owns only part of a
   section (e.g. §3.1–§3.9 but not §3.10), distill that part and leave the rest as
   detailed holding-pen, with a short note saying which sub-part is still unspecced
   and which future spec it's earmarked for. Do not force a whole section to one state.
5. **Preserve information with no other home.** Cross-cutting notes the spec doesn't
   capture move to the relevant detailed section or a brief "Cross-cutting" note —
   never dropped.
6. Update the blueprint's index/table-of-contents entry for this section to say
   "distilled → spec <slug>" so the map and the sections agree.
7. **Idempotent.** If the section is already a digest+pointer for this spec, leave
   it unless the spec's role/connections changed; never expand a pointer back into
   full detail. Re-running restamp on an unchanged slice is a no-op.

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
