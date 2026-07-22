# Contributing

Thanks for your interest. This repo is **Blueprint**, a community
[Spec Kit](https://github.com/github/spec-kit) extension.

## Running the tests

The oracle/gate is a single Bash script with **no dependencies beyond bash + git**
(`python3` is only used to validate JSON in one test). All suites are deterministic and
run anywhere:

```bash
bash tests/oracle_test.sh          # state frontier, provenance, context
bash tests/check_remap_test.sh     # the tiered gate: hard/soft, --strict, JSON contract, coverage
bash tests/harness_loop_test.sh    # the autonomous-harness loop
```

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

## Guidelines

- Open an issue to discuss anything larger than a fix before sending a PR.
- Keep the oracle **deterministic and dependency-free** (bash + git); agent-authored
  behavior lives in the command markdown, not the script.
- Add or update a test for any change to `check`/`next`/`status`/`restamp` behavior.
- **Help wanted:** the PowerShell port (`scripts/powershell/blueprint-state.ps1`) is
  execution-verified at output parity with the Bash oracle on **pwsh 7.4 / Linux**, but
  **not on Windows** — path separators and git-for-Windows are the untested surface. A
  Windows maintainer to confirm it there is very welcome.
- Keep the two oracles at parity. They are diffed by running both over the same fixture and
  comparing `check --json`; a divergence has already caught a real bug in the Bash side.

## License

By contributing you agree your contributions are licensed under the [MIT License](./LICENSE).
