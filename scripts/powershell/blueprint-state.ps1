#!/usr/bin/env pwsh
# blueprint-state — deterministic state oracle + coherence gate (PowerShell port).
# Mirrors scripts/bash/blueprint-state.sh at output parity; this entry only
# parses arguments and dot-sources the lib/ modules in order — every piece of
# behavior lives in exactly one file under scripts/powershell/lib/.
#
# Usage:
#   blueprint-state.ps1 status|next|check|restamp
#     [--json|--human] [--strict] [--root <dir>] [--blueprint <path>] [--path <p>]
[CmdletBinding()]
param(
  [Parameter(Position = 0)] [string]$Command = "status",
  [Parameter(ValueFromRemainingArguments = $true)] [string[]]$Rest
)
$ErrorActionPreference = "Stop"

$Json = $false; $Root = ""; $Blueprint = ""; $Skip = @(); $PathFilter = ""; $Strict = $false; $Human = $false; $BpFlag = $false
for ($i = 0; $i -lt $Rest.Count; $i++) {
  switch ($Rest[$i]) {
    "--json"      { $Json = $true }
    "--root"      { $i++; $Root = $Rest[$i] }
    "--blueprint" { $i++; $Blueprint = $Rest[$i]; $BpFlag = $true }
    "--skip"      { $i++; $Skip += $Rest[$i] }   # exclude a slug (e.g. a parked slice); repeatable
    "--path"      { $i++; $PathFilter = $Rest[$i] }  # restamp: limit to one code path
    "--strict"    { $Strict = $true }            # check: make advisory (soft) issues blocking too
    "--human"     { $Human = $true }             # force human-readable output
  }
}
# Output format: explicit flag wins; else JSON when piped, human on a TTY (git/ls convention).
if ($Json) { $Fmt = "json" } elseif ($Human) { $Fmt = "human" }
elseif ([Environment]::UserInteractive -and -not [Console]::IsOutputRedirected) { $Fmt = "human" } else { $Fmt = "json" }


# locate repo root
if (-not $Root) {
  $d = (Get-Location).Path
  while ($d -and (Split-Path $d -Parent)) {
    if (Test-Path (Join-Path $d ".specify")) { $Root = $d; break }
    $d = Split-Path $d -Parent
  }
  if (-not $Root) { $Root = (Get-Location).Path }
}

# An EXPLICIT --blueprint is authoritative: never silently replaced by config
# or auto-detect — a missing explicit path behaves as "no blueprint".
if ($BpFlag -and -not (Test-Path $Blueprint)) {
  [Console]::Error.WriteLine("warning: --blueprint '$Blueprint' not found — treating as absent (no fallback)")
}
# locate blueprint
if (-not $Blueprint) {
  $cfg = Join-Path $Root ".specify/extensions/blueprint-index/blueprint-config.yml"
  if (Test-Path $cfg) {
    $m = Select-String -Path $cfg -Pattern '^\s*path:\s*"?([^"]*)"?\s*$' | Select-Object -First 1
    if ($m) {
      $p = $m.Matches[0].Groups[1].Value
      $Blueprint = Join-Path $Root $p
      # A configured path that doesn't resolve must be loud (parity with the bash oracle):
      # silently falling back to auto-detect means a team's real blueprint is ignored.
      if (-not (Test-Path $Blueprint)) { [Console]::Error.WriteLine("warning: configured blueprint.path '$p' not found — falling back to auto-detect") }
    }
  }
}
if (-not $BpFlag -and (-not $Blueprint -or -not (Test-Path $Blueprint))) {
  # Canonical location first (matches the config default); docs/ candidates are legacy homes.
  foreach ($c in @(".specify/memory/blueprint.md", "docs/blueprint.md")) {
    if (Test-Path (Join-Path $Root $c)) { $Blueprint = Join-Path $Root $c; break }
  }
}


$specsDir = Join-Path $Root "specs"

# NOTE: `exit` inside a dot-sourced module returns HERE (it does not terminate
# the entry, unlike bash `source`); $LASTEXITCODE carries the module's code, so
# each command-owning module is followed by an explicit termination gate.
$Cfg = Join-Path $Root ".specify/extensions/blueprint-index/blueprint-config.yml"
$ConfigInvalid = $false
. "$PSScriptRoot/lib/Common-Config.ps1"   # validates the config
if ($ConfigInvalid) { exit 2 }

. "$PSScriptRoot/lib/Common-Git.ps1"
. "$PSScriptRoot/lib/State-Frontier.ps1"
if ($Command -eq "check" -and $Blueprint -and (Test-Path $Blueprint)) {
  # the gate's structure check recomputes the partition (bash parity: the
  # intersection-domain diff — hand-authored maps are never judged)
  $Struct = $true; $Scope = ""; $All = $false; $Facts = ""
  $Cfg = Join-Path $Root ".specify/extensions/blueprint-index/blueprint-config.yml"
  . "$PSScriptRoot/lib/Common-Helpers.ps1"
  . "$PSScriptRoot/lib/Slice-Config.ps1"
  . "$PSScriptRoot/lib/Slice-Covered.ps1"
  . "$PSScriptRoot/lib/Slice-Partition.ps1"
}
. "$PSScriptRoot/lib/State-Check.ps1"
if ($Command -eq "check") { exit $LASTEXITCODE }
. "$PSScriptRoot/lib/State-Restamp.ps1"
if ($Command -eq "restamp") { exit $LASTEXITCODE }
. "$PSScriptRoot/lib/State-Output.ps1"
