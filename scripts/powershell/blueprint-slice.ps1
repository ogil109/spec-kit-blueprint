#!/usr/bin/env pwsh
# blueprint-slice — deterministic brownfield partitioner (PowerShell port).
# Mirrors scripts/bash/blueprint-slice.sh at OUTPUT PARITY: for the same repo
# state + config, slice --json, scaffold, and render emit byte-identical
# text to the bash oracle (tests/ps_parity_test.sh diffs them in CI).
#
# Usage:
#   blueprint-slice.ps1 [slice] [--json|--human]
#     [--root <dir>] [--blueprint <path>] [--scope <dir>] [--all]
#   blueprint-slice.ps1 scaffold [--root <dir>] [--blueprint <path>] [--scope <dir>]
#   blueprint-slice.ps1 render   --facts <file> [--root <dir>] [--blueprint <path>]
#
# This entry only parses arguments and dot-sources the lib/ modules in order;
# every piece of behavior lives in exactly one file under scripts/powershell/lib/.
[CmdletBinding()]
param(
  [Parameter(Position = 0)] [string]$Command = "slice",
  [Parameter(ValueFromRemainingArguments = $true)] [string[]]$Rest
)
$ErrorActionPreference = "Stop"

$Json = $false; $Human = $false; $Root = ""; $Blueprint = ""; $Scope = ""; $All = $false; $Facts = ""; $BpFlag = $false
for ($i = 0; $i -lt $Rest.Count; $i++) {
  switch ($Rest[$i]) {
    "--json"      { $Json = $true }
    "--human"     { $Human = $true }
    "--root"      { $i++; $Root = $Rest[$i] }
    "--blueprint" { $i++; $Blueprint = $Rest[$i]; $BpFlag = $true }
    "--scope"     { $i++; $Scope = $Rest[$i].TrimEnd('/') }
    "--facts"     { $i++; $Facts = $Rest[$i] }
    "--all"       { $All = $true }
  }
}
if ($Json) { $Fmt = "json" } elseif ($Human) { $Fmt = "human" }
elseif ([Environment]::UserInteractive -and -not [Console]::IsOutputRedirected) { $Fmt = "human" } else { $Fmt = "json" }
if (@("slice", "scaffold", "render") -notcontains $Command) {
  [Console]::Error.WriteLine("unknown command: $Command (only: slice, scaffold, render)"); exit 2
}
$Out = [System.Text.StringBuilder]::new()
function W([string]$s)  { [void]$Out.Append($s) }
function WL([string]$s) { [void]$Out.Append($s + "`n") }
function Flush { [Console]::Out.Write($Out.ToString()) }
# ── locate repo root (same rule as the bash port) ─────────────────────────────
if (-not $Root) {
  $d = (Get-Location).Path
  while ($d -and (Split-Path $d -Parent)) {
    if (Test-Path (Join-Path $d ".specify")) { $Root = $d; break }
    $d = Split-Path $d -Parent
  }
  if (-not $Root) { $Root = (Get-Location).Path }
}
git -C $Root rev-parse --git-dir 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { [Console]::Error.WriteLine("not a git repository: $Root"); exit 1 }

$Cfg = Join-Path $Root ".specify/extensions/blueprint-index/blueprint-config.yml"
$ConfigInvalid = $false
. "$PSScriptRoot/lib/Common-Config.ps1"   # validates the config
if ($ConfigInvalid) { exit 2 }

# ── locate the blueprint doc ──────────────────────────────────────────────────
if (-not $Blueprint -and (Test-Path $Cfg)) {
  $m = Select-String -Path $Cfg -Pattern '^\s*path:\s*"?([^"]*)"?\s*$' | Select-Object -First 1
  if ($m) {
    $p = $m.Matches[0].Groups[1].Value
    if ($p -and (Test-Path (Join-Path $Root $p))) { $Blueprint = Join-Path $Root $p }
  }
}
# An EXPLICIT --blueprint is authoritative and never silently replaced: a
# missing explicit target means a FRESH map there (scaffold) / no subtraction.
if (-not $BpFlag -and (-not $Blueprint -or -not (Test-Path $Blueprint))) {
  foreach ($c in @(".specify/memory/blueprint.md", "docs/blueprint.md")) {
    if (Test-Path (Join-Path $Root $c)) { $Blueprint = Join-Path $Root $c; break }
  }
}


# NOTE: `exit` inside a dot-sourced module returns HERE (it does not terminate
# the entry, unlike bash `source`); $LASTEXITCODE carries the module's code, so
# each command-owning module is followed by an explicit termination gate.
. "$PSScriptRoot/lib/Common-Helpers.ps1"
. "$PSScriptRoot/lib/Slice-Config.ps1"
. "$PSScriptRoot/lib/Slice-Render.ps1"
if ($Command -eq "render") { exit $LASTEXITCODE }
. "$PSScriptRoot/lib/Slice-Covered.ps1"
. "$PSScriptRoot/lib/Slice-Partition.ps1"
. "$PSScriptRoot/lib/Slice-Scaffold.ps1"
if ($Command -eq "scaffold") { exit $LASTEXITCODE }
. "$PSScriptRoot/lib/Slice-Output.ps1"
exit $LASTEXITCODE
