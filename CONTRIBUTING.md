# Contributing

Thanks for your interest. This repo hosts community [Spec Kit](https://github.com/github/spec-kit)
extensions, one per subdirectory (currently [`blueprint/`](./blueprint)).

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
specify extension add --dev /path/to/spec-kit-extensions/blueprint
```

## Guidelines

- Open an issue to discuss anything larger than a fix before sending a PR.
- Keep the oracle **deterministic and dependency-free** (bash + git); agent-authored
  behavior lives in the command markdown, not the script.
- Add or update a test for any change to `check`/`next`/`status`/`restamp` behavior.
- **Help wanted:** the PowerShell port (`blueprint/scripts/powershell/blueprint-state.ps1`)
  is mirrored from the Bash oracle but **not yet execution-verified** — a Windows/pwsh
  maintainer to verify it is very welcome.

## License

By contributing you agree your contributions are licensed under the [MIT License](./LICENSE).
