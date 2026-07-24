# Changelog

**Generated** by [commitizen](https://commitizen-tools.github.io/commitizen/) from
[Conventional Commit](https://www.conventionalcommits.org/) subjects on every `cz bump` —
do not hand-edit, it is rewritten in full. This project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Each release's narrative — why a change was made, and its caveats — is in the
[GitHub release notes](https://github.com/ogil109/spec-kit-blueprint/releases).

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
