# Contributing

Thanks for your interest. This repo is **Blueprint**, a community
[Spec Kit](https://github.com/github/spec-kit) extension.

## Running the tests

The oracles are plain Bash (with PowerShell ports at byte parity) and depend on
**nothing beyond bash + git** (`python3` is only used to validate JSON in tests).
Each entry script (`blueprint-state.sh`, `blueprint-slice.sh`) only parses
arguments and sequences single-responsibility modules from `scripts/bash/lib/`
(`scripts/powershell/lib/` mirrors them 1:1); every behavior lives in exactly
one lib file, named for its job, with its contract in the header. Two
non-obvious rules the layout depends on:

- **bash**: `source` returns the status of a file's *last command* — every lib
  file therefore ends with an inert `:` so a legitimately-failing final test
  can't kill the entry under `set -e`.
- **PowerShell**: `exit` inside a dot-sourced module does **not** terminate the
  entry (unlike bash) — the entries gate each command-owning module with
  `if ($Command -eq …) { exit $LASTEXITCODE }`.

All suites are deterministic and run anywhere:

```bash
for t in tests/*_test.sh; do bash "$t"; done   # the filesystem is the roster
```

Each suite's header comment states what it covers; adding a suite is one new
`tests/*_test.sh` file — CI picks it up automatically, nothing to register.

CI runs exactly these on every push/PR (`.github/workflows/tests.yml`).

## Local development

```bash
specify extension add /path/to/spec-kit-blueprint --dev
```

## Commit conventions & releases

The extension ships **no Python** — it's bash + git. `pyproject.toml` exists only to pin
the development toolchain, so setup is:

```bash
uv sync --group dev          # installs commitizen into .venv
```

Commits follow [Conventional Commits](https://www.conventionalcommits.org/); CI validates
every PR's commit messages with `cz check`. Write them with the prompt, or by hand:

```bash
uv run cz commit             # guided prompt
uv run cz check --rev-range origin/main..HEAD   # what CI runs on your PR
```

Releases are **generated, never hand-written**:

```bash
uv run cz bump               # infers the version from commit types, updates
                             # pyproject.toml + extension.yml, rewrites
                             # CHANGELOG.md, and creates the vX.Y.Z tag
```

**`CHANGELOG.md` is generated output — never edit it.** cz owns the entire file and
rewrites it from commit subjects on every bump, so hand-written entries are silently
destroyed. That makes your commit subject the changelog entry: write it for a reader of
the release, not for yourself. Anything that needs a narrative — why a change was made,
what it breaks, what to watch for — goes in the **GitHub release notes** instead.

One caveat: the initial commit predates these conventions, so `cz check` is scoped to a
PR's own range rather than the whole history.

## Pre-release ritual

The suites cannot catch what their fixtures never vary. Before cutting a
release, run the full brownfield on-ramp against a **large real repository**
(shallow-clone something like pandas): install with `--dev`, scaffold, author
facts with `#pattern` edges, render, restamp, verify + check, then the drills
— stale/heal, pattern rot (edit a single-hit pattern away), per-block repair,
additive re-onboard, `--strict`. Three shipped bugs were found exactly this
way (size-dependent SIGPIPE inversion, silent duplicate-block last-wins, TOC
drift after re-onboarding) after 120+ asserts were green.

## Guidelines

- Open an issue to discuss anything larger than a fix before sending a PR.
- Keep the oracle **deterministic and dependency-free** (bash + git); agent-authored
  behavior lives in the command markdown, not the script.
- Keep the oracle **portable shell**: POSIX character classes (never GNU regex
  shorthands) and no bare `sed -i` — BSD `sed` on macOS fails *silently* on both.
  CI runs GNU userland and cannot catch these by execution, so
  `tests/portability_lint_test.sh` enforces them statically.
- Add or update a test for any change to `check`/`next`/`status`/`restamp` behavior.
- **Help wanted:** the PowerShell port (`scripts/powershell/blueprint-state.ps1`) is
  execution-verified at output parity with the Bash oracle on **pwsh 7.4 / Linux**, but
  **not on Windows** — path separators and git-for-Windows are the untested surface. A
  Windows maintainer to confirm it there is very welcome.
- Keep the ports at parity — and parity means **byte parity**: `tests/ps_parity_test.sh`
  diffs `slice --json`, `scaffold`, `verify`, and `check --json` between bash and
  PowerShell over the same fixtures, exit codes included. Divergences have caught real
  bugs on both sides (most recently PS 7.5 sorting native-command output culture-aware
  where bash sorts bytewise). CI runs the parity suite on every push.

## License

By contributing you agree your contributions are licensed under the [MIT License](./LICENSE).
