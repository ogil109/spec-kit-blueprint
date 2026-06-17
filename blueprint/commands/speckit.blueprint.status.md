---
description: "Show the blueprint's coherence state: detailed vs settled sections, distill drift, and where each spec stands (deterministic, read-only)"
---

# Blueprint Status

Human-readable dashboard of the map's state — which sections are detailed (design
pending) vs settled (owned by a spec or by code), what's drifted, and where each
spec stands. Read-only.

## Execution

Run the state script and present its output:

- **Bash**: `.specify/extensions/blueprint/scripts/bash/blueprint-state.sh status`
- **PowerShell**: `.specify/extensions/blueprint/scripts/powershell/blueprint-state.ps1 status`

If it adds value, point the user at the fix for any drift it reports — distill drift
→ `__SPECKIT_COMMAND_BLUEPRINT_DISTILL__`, and remind them the deterministic
`check` gate (`blueprint-state.sh check`) catches both distill drift and code
staleness in CI.

## Guardrails

- Read-only: never edit specs, the blueprint, or any state. Only report what the
  script computes.
