# The autonomous waterfall harness

The blueprint extension ships four commands and a coherence gate. It does **not** ship a
"drive" command — and it doesn't need to. The blueprint is **externalized project state**
and the oracle computes the **single next action deterministically** from the filesystem,
so an autonomous build is just an agent **looping on the oracle**. This document is the
loop contract and a constitution principle that makes an agent follow it.

Why no command: a coded driver would hide the one thing you want visible in an
unattended run — *what the agent decided to do at each step*. The harness keeps the
grounding deterministic (the oracle) and the loop legible (this contract), so a long
session stays on the rails without a black box.

## The loop

Repeat until the oracle reports `done`, you hit a stop bound, or every remaining slice
is parked:

1. **Ask the oracle.** Run
   `bash .specify/extensions/blueprint-index/scripts/bash/blueprint-state.sh next --json`
   (PowerShell: `.../powershell/blueprint-state.ps1 next --json`). Pass `--skip <slug>`
   for every parked slice (repeatable). Parse `{has_next, phase, slug, reason}`.

2. **Check stop conditions.** If `has_next` is false → **stop, report success**. If
   you've reached your step budget, or the next `phase` is one you were told to stop
   before (e.g. "set everything up but don't implement") → **stop and report where you
   are**.

3. **Run exactly one phase** by invoking the matching core spec-kit command for `slug`:

   | phase | command |
   |---|---|
   | `specify` | `/speckit.specify` — pick the next **Detailed (unspecced)** section from the blueprint and specify it, using that section's design as the input. |
   | `clarify` | `/speckit.clarify` for `slug` — resolve the `[NEEDS CLARIFICATION]` markers. |
   | `plan` | `/speckit.plan` for `slug`. |
   | `tasks` | `/speckit.tasks` for `slug`. |
   | `implement` | `/speckit.implement` for `slug`. |
   | `distill` | `/speckit.blueprint-index.distill` `slug` — collapse the finished slice to a digest + pointer (and stamp its code baseline). |

   Do the step properly and completely. The oracle only advances when the phase's
   artifact actually exists on disk, so a half-done phase is simply re-selected next
   iteration — it can't be skipped by accident.

4. **Re-ground and continue.** Go back to step 1. Do **not** assume what comes next —
   re-run the oracle. The remaining work changes as artifacts land.

## Parking (don't get stuck)

If a phase can't be completed autonomously — a `clarify` whose answer needs a human
decision, an `implement` blocked on a missing dependency or credential, a genuinely
ambiguous spec — **do not loop forever and do not guess on something that needs a
human.** Record the blocker (one line: slice, phase, what's needed), add the slug to
your parked set, and pass `--skip <slug>` to the oracle on every subsequent call so it
hands you the next workable slice instead. Surface all parked items in the final report.

A run that parks one slice and keeps building the rest is healthy; one that spins on a
blocked slice is not.

## Bounds (unattended ≠ unbounded)

Always run with a **step budget** (a hard cap on phase-steps) and, when you only want
setup, a **stop-before phase** (e.g. stop before `implement` to produce reviewed-ready
specs without writing code). A dry first pass — print the next action and stop — is a
good way to preview what the loop would do.

## Final report

When the loop ends, report: why it stopped (`done` / budget / stop-before /
all-remaining-parked); what advanced this run, slice by slice (phase → phase); parked
slices and exactly what each needs from a human; and the current
`/speckit.blueprint-index.status` snapshot with how to resume.

## Recommended constitution principle

Add this to your project's `constitution.md` so any agent in the repo follows the
harness (and keeps the map honest) without being told each time:

> **Blueprint-grounded autonomy.** When building autonomously, never trust your own
> memory of progress — re-run the blueprint oracle (`blueprint-state.sh next`) before
> every step and do exactly the one phase it reports, then re-ground. Park (don't guess
> on) anything that needs a human decision or a missing dependency, and keep building
> the rest. When a slice ships, distill its blueprint section. Treat
> `blueprint-state.sh check` as a merge gate: a drifted spec or stale code-owned section
> must be resolved (`distill` / `remap`) before merge.

## What this guarantees — and what it doesn't

- **Guaranteed (deterministic, tested):** the oracle computes a correct next action from
  the filesystem, and looping on it sequences multiple specs in the right order with
  parking and stop bounds (`tests/harness_loop_test.sh`).
- **Not guaranteed:** the quality of the agent's authoring *within* a phase, and the
  agent's adherence to this contract. The harness keeps a long session grounded; it is
  not a substitute for reviewing the specs and code it produces.
