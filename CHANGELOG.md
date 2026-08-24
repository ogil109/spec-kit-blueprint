# Changelog

**Generated** by [commitizen](https://commitizen-tools.github.io/commitizen/) from
[Conventional Commit](https://www.conventionalcommits.org/) subjects on every `cz bump` —
do not hand-edit, it is rewritten in full. This project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Each release's narrative — why a change was made, and its caveats — is in the
[GitHub release notes](https://github.com/ogil109/spec-kit-blueprint/releases).

## v0.3.0 (2026-08-24)

### BREAKING CHANGE

- 'blueprint-slice.sh verify' no longer exists; use
'blueprint-state.sh check' — structure divergence appears as SOFT
'structure' issues (--strict promotes).
- a blueprint living at docs/overview.md is no longer
auto-detected — set blueprint.path in blueprint-config.yml.
- the 'concern' facts directive is no longer accepted;
relation endpoints must be managed sections.

### Added

- **render**: accept distilled facts blocks — lane parity (D3, partial)
- **oracle**: fold structure conformance into the check gate; remove the verify subcommand
- **render**: remove the concern directive — cross-cutters are sections with crosscuts edges
- **config**: validate the configuration like every other input surface
- **render**: falsifiable evidence — path#pattern validated at render and re-checked by the gate
- **render**: facts-then-render — one validated source for prose and relations
- **ps**: full PowerShell port of the partitioner at byte parity, CI-enforced
- **recover**: stage-2 architecture recovery — the intelligence layer
- **init**: hybrid on-ramp — brownfield seeding from code AND docs
- **anatomy**: shipped architecture-recovery contract — one section shape for both on-ramps
- **slicer**: scaffold — the map skeleton is machine-written, closing the transcription gap
- **slicer**: downstream-lifecycle e2e; subtraction leaves holes that force descent
- **slicer**: verify — machine-checked structure conformance for the on-ramp
- **slicer**: pin_dirs — atomic sections; guard coverage behind an existing map
- **init**: computed structure for the brownfield on-ramp
- **oracle**: widen the coverage scan to all top-level directories
- **slicer**: deterministic brownfield partitioner (blueprint-slice.sh)

### Changed

- **tests**: the filesystem is the suite roster
- **scripts**: thin entries over single-responsibility lib modules, both ports
- **render**: per-block edge authority — repair bookkeeping becomes internal

### Fixed

- **oracle**: an explicit --blueprint never silently falls back
- **oracle**: trim blueprint auto-detect to canonical + docs/blueprint.md
- **render**: three defects found by a live pandas e2e — SIGPIPE inversion, duplicate blocks, TOC drift

## v0.2.1 (2026-08-22)

### Fixed

- **oracle**: auto-detect prefers the canonical .specify/memory location
- **oracle**: do not crash when the config file has no path key
- **oracle**: make restamp's in-place edit portable to BSD sed
- **oracle**: resolve the configured blueprint path portably and never fall back silently
- **manifest**: declare provides.scripts as name/file mappings (bare paths are rejected by spec-kit >=0.16.5)

## v0.2.0 (2026-07-24)

### BREAKING CHANGE

- commands are now `/speckit.blueprint-index.*` (was
`/speckit.blueprint.*`) and the install path is `.specify/extensions/blueprint-index/`.
The oracle's config-path lookup, every emitted remedy string, both ports, the
docs, and the tests are updated to match. The display name is now "Blueprint
Index — Living Architecture Map" to disambiguate from the existing "Blueprint".

### Changed

- rename extension id blueprint -> blueprint-index

## v0.1.3 (2026-07-22)

### Fixed

- **oracle**: keep issue fields aligned when target is empty (unmanaged)

## v0.1.2 (2026-07-21)

### Fixed

- **docs**: make both README examples match real output
- **docs**: correct --dev syntax and stop pinning the install URL to an old tag

## v0.1.1 (2026-07-21)

### Fixed

- **docs**: correct invocation and machine-first claim to match a real install

## v0.1.0 (2026-07-21)

### Added

- **blueprint**: unmapped-code coverage signal (closes the "new code is invisible" gap)
- **blueprint**: tiered coherence gate + machine-first (JSON) output
- **blueprint**: add section state=context for framing / non-buildable sections
- **blueprint**: deterministic section provenance markers + idempotent init

### Changed

- flatten into a dedicated single-extension repo
