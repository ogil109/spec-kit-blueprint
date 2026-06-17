---
description: "Re-derive a code-owned blueprint section from the current code and refresh its git baseline — resync the map after out-of-band code changes that never went through a spec"
---

# Remap a Code-Owned Section

A section the blueprint maps to existing code (`> **Distilled — owned by code at
\`src/<area>/\`.**`) has gone **stale**: the code under it changed without going
through a spec (a refactor, a hotfix, a dependency change). `blueprint.check` flags
this as `STALE`. Remap re-reads the current code, updates the section's at-a-glance
digest to match, and refreshes the git baseline so `check` goes green again.

This is how the blueprint stays relevant against changes that the spec-anchored
oracle cannot see on its own.

## User Input

```text
$ARGUMENTS
```

`$ARGUMENTS` names the area to remap — a `src/...` path or a section heading. If
empty, remap every section that `blueprint.check` reports as `STALE`/`DANGLING`.

## Resolve

1. Repo root = nearest ancestor with `.specify/`.
2. Blueprint path: `blueprint-config.yml` → `blueprint.path`; else auto-detect.
3. Run the oracle's `check` to get the stale/dangling sections:
   `.specify/extensions/blueprint/scripts/bash/blueprint-state.sh check` (or the
   PowerShell port). Target the section(s) whose `path=` matches `$ARGUMENTS`.

## Execution

For each targeted code-owned section:

1. **Re-read the current code** under its `src/<area>/`. Note what changed at *map
   altitude* — new/renamed entry points, changed contracts, a new dependency on
   another subsystem, a split/merged module. Ignore implementation detail below the
   map (a bug fix that doesn't change the section's claims needs no prose change).

2. **Update the digest** to match today's code: fix the role sentence and the
   at-a-glance bullets so the section is true again. **Map what exists; do not
   redesign.** If the change was purely below map altitude, the prose may be
   unchanged — that's fine; you're still refreshing the baseline.

3. **If a `DANGLING` section** points at code that no longer exists, either repoint
   its `path=` marker at the code's new location, or (if the subsystem is gone)
   remove the section and its TOC entry.

4. **Refresh the baseline.** Run the oracle's restamp for the area so the marker
   records the current git hash:
   `.specify/extensions/blueprint/scripts/bash/blueprint-state.sh restamp --path src/<area>`
   (omit `--path` to refresh all). This is the deterministic step — do not hand-edit
   the `sha=`.

## Report Back

- Which section(s) were remapped and what changed at map altitude (or "no prose
  change — baseline refreshed").
- The new `blueprint.check` result (should be in sync).

## Guardrails

- Remap reflects the code *as it is now*; it does not redesign or add a spec.
- A genuine behavior/architecture change that deserves a spec should go through
  `/speckit.specify` (then `distill` when it ships) — remap is for keeping the *map*
  honest against code that changed without a spec, not for designing changes.
- Never hand-write the `sha=` value — always refresh it with `restamp`, so the
  baseline reflects real git state and `check` stays trustworthy.
