# Decision Inventory

The maintained register of every shipped mechanism: what it is, where it came
from, whether its original rationale is still alive, and what was decided
about it. **Contributors: adding a mechanism requires adding its row here in
the same change** (see CONTRIBUTING). Present tense throughout — this file
describes the current codebase; history lives in version control.

**Verdicts**: `live` (rationale still holds) · `superseded` (a later mechanism
replaced the need) · `lapsed` (the motivating condition no longer exists) ·
`unfounded` (claimed but never implemented) · `unknown` (origin not
reconstructible).
**Dispositions**: `keep` · `rework(D#)` · `remove(D#)` · `defer(#issue)` —
D-numbers reference `specs/001-stale-logic-cleanup/research.md`.

## End-state principles

1. **Validated inputs** — every consumed surface is machine-validated; silent
   acceptance is a defect.
2. **One mechanism per concern.**
3. **No claim without enforcement.**
4. **No feature without demonstrated use.**
5. **Lane parity** — both on-ramps share one authoring/validation model
   (claims are validated in both lanes; `detailed` bodies are
   design-in-waiting, not claims, in both lanes).
6. **Enforced equivalence** — the dual-port contract is machine-enforced.
7. **Present-tense tree** — in-tree docs describe the present.

## Commands (user-facing)

| Mechanism | Origin / rationale | Verdict | Disposition |
|---|---|---|---|
| `init` (greenfield doc-path + brownfield `--from-code` + hybrid) | Core on-ramp; brownfield flow reworked to scaffold+facts during the determinism work | live | keep; greenfield prose authoring aligned to facts flow — rework(D3) |
| `status` | Human dashboard over the frontier | live | keep |
| `distill` | Collapse a shipped spec's section to digest+pointer; predates the facts flow — its hand-authoring guidance is stale | superseded (guidance) | rework(D3): emit facts → render → restamp |
| `remap` | Resync a stale section; guidance predates facts flow | superseded (guidance) | rework(D3); delta-scoping stays defer(#4) |
| `recover` | Stage-2 relations/digest pass; born from the intelligence-layer requirement | live | keep (concern directive within it: remove(D5)) |

## Oracle: `blueprint-state.sh` / `.ps1`

| Mechanism | Origin / rationale | Verdict | Disposition |
|---|---|---|---|
| `next` (waterfall frontier) | The autonomous-harness driver: single next action from filesystem state | live | keep |
| `check` — tiered gate (HARD/SOFT, `--strict`) | The product's core friction bet | live | keep |
| `check` coverage spanning all top-level dirs | Fix for the field-found blind spot (map read clean while whole trees were unmapped) | live | keep |
| `check` coverage silent without a blueprint | Post-fix of advisory flooding on bare repos | live | keep |
| `check` relation validation (endpoints, evidence, `#pattern` rot) | Falsifiable-evidence requirement from design review | live | keep |
| `restamp` | The only deterministic remedy; LLM-free self-heal step | live | keep |
| Structure conformance as a *separate* `verify` subcommand | Built to catch agent transcription drift — superseded when `scaffold` removed agent-written structure | superseded | rework(D2): fold into `check` as SOFT `structure` issues; subcommand removed (breaking) |
| Flags `--root/--blueprint/--json/--human/--skip/--path/--strict` | CLI surface; `--skip` serves harness parking, `--path` scopes restamp | live | keep |
| Output convention (JSON when piped, human on TTY) | git/porcelain convention for machine-first consumers | live | keep |
| US (`\x1f`) record separator | Tab-IFS field-collapse bug with empty targets | live | keep |
| Blueprint resolver warns on configured-but-missing path | Silent-fallback bug class from field findings | live | keep |
| Config-path resolver `|| true` guard | No-`path:`-key crash fix | live | keep |

## Partitioner: `blueprint-slice.sh` / `.ps1`

| Mechanism | Origin / rationale | Verdict | Disposition |
|---|---|---|---|
| `slice` — rules pinned/module/fits/descend+remainder/flat | Reproducible structure requirement; each rule earned by a concrete case | live | keep |
| Holes (subtraction forces ancestor descent) | e2e-found bug: a shrunken parent re-covered owned territory | live | keep |
| Additive re-runs + oversize advisories | Growth must never silently repartition | live | keep |
| `--scope` | The `unmapped` remedy flow | live | keep |
| `--all` | Pure-function view for verification/analysis | live | keep |
| `scaffold` (full skeleton / additive blocks; origin-remote title; empty-redirect edge) | Removed the agent-transcription lane entirely | live | keep |
| `render` — facts parse/validate/write; idempotent; partial per block | Facts-then-render adoption (one validated source for prose+relations) | live | keep |
| Evidence `#pattern` (grep at HEAD, render + gate) | "Validation was buzzwords" review; semantic-rot detection | live | keep |
| Duplicate-block rejection | e2e probe: silent last-wins destroyed a reviewed digest | live | keep |
| Big-file-safe pattern grep (no `-q`) | e2e-found SIGPIPE inversion on >pipe-buffer files | live | keep |
| TOC ownership incl. append of missing entries | e2e-found index drift after additive re-onboard | live | keep |
| Relations-home merge via table round-trip | `why` lives only in the rendered table; merge is the least-bad option given the space-free marker attribute constraint | live (constraint real) | keep, rationale recorded |
| Per-block edge authority (empty neighbor set deletes) | Internalized repair bookkeeping | live | keep |
| `concern` facts directive | Built for directory-less cross-cutters; zero uses in the only full real-repo exercise (all real cross-cutters owned directories) | lapsed | remove(D5) (breaking); `crosscuts` edge kind stays |
| Render for `distilled` sections rejected | Original jurisdiction split predates lane-parity mandate; leaves spec-owned edges unrepairable (GAP-6) | superseded | rework(D3): accept distilled facts blocks, jurisdiction widened to owning spec |
| `blueprint-facts 1` version line | Format evolution safety | live | keep |

## Configuration

| Mechanism | Origin / rationale | Verdict | Disposition |
|---|---|---|---|
| Keys: `blueprint.path`, `distill.require_confirmation`, `slice.{max_files,min_files,boundary_files,context_dirs,pin_dirs}`, `coverage.exclude` | Each added with its feature; all exercised | live | keep |
| Parser accepts unknown keys/typos/misindents silently | Predates every validation surface (config once held two cosmetic keys) | lapsed | rework(D1): validate at load, both ports |
| Config-template claim of layering (`blueprint-config.local.yml`, `SPECKIT_BLUEPRINT_*` env) | Aspirational header comment; no script ever read either source | unfounded (never implemented) | remove: claim deleted from the template (principle 3) |
| Defaults as elicitation devices (400/3, boundary list, docs context) | Zero-friction first cut; the concrete partition is the questionnaire | live | keep (advisory/checkpoint ideas = future feature, out of scope) |

## Marker vocabulary

| Mechanism | Origin / rationale | Verdict | Disposition |
|---|---|---|---|
| `section state=detailed/distilled/code/context` | Core provenance model | live | keep |
| `code path= sha=` (tree/blob baselines; multi-marker sections) | Drift detection; remainder representation | live | keep |
| `context path=` (coverage without baseline) | Widened-coverage need for docs trees | live | keep |
| `relation from= to= kind= evidence=` | Stage-2 intelligence layer | live | keep |
| Space-free attribute constraint | `[^ ]+` parsing across all oracles | live | keep (documented consequence: patterns/`why` cannot contain spaces) |

## Auto-detection & defaults

| Mechanism | Origin / rationale | Verdict | Disposition |
|---|---|---|---|
| Blueprint auto-detect: `.specify/memory/blueprint.md` first | Canonical-home decision | live | keep |
| Candidate `docs/blueprint.md` | Generic alternative home | live | keep |
| Candidate `docs/overview.md` | Relic of the original host project's doc layout | lapsed | remove(D6) (breaking) |
| Coverage default excludes (`.*`, `specs`), blueprint self-exclusion, root-files boundary | Noise control earned during coverage widening | live | keep |

## Infrastructure & meta

| Mechanism | Origin / rationale | Verdict | Disposition |
|---|---|---|---|
| Dual ports at **byte** parity, CI-diffed | Windows claim + parity-as-diff; five real divergences caught | live | keep(D4) — verification is a diff; semantic parity would be judgment (principle 3) |
| Modular lib layout (thin entries; `:` guards; PS `$LASTEXITCODE` gates) | Human-legibility refactor; both shell rules discovered by suites | live | keep |
| Portability lint (GNU idioms, `sed -i`) | BSD-silent-failure class not catchable by GNU CI | live | keep |
| Suite roster listed by hand in CI + README + CONTRIBUTING | Grew a file at a time | lapsed | rework(D7): filesystem is the roster |
| Pre-release big-repo ritual (CONTRIBUTING) | Three e2e-only bug classes (size/malformed-input/time) | live | keep |
| `docs/deterministic-onramp.md` | Design narrative from the on-ramp build | superseded (as in-tree doc) | remove(D8): salvage → README; history in git |
| `docs/autonomous-harness.md` | Harness pattern doc | live (audit in T008) | keep pending audit |
| Commitizen/changelog/release conventions | Release hygiene | live | keep |

## Outcomes

Filled as dispositions execute (T002–T012): each D-row gains
`→ shipped in <commit>` or `→ deferred: <reason>`.
