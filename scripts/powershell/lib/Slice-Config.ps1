#!/usr/bin/env pwsh
# lib/Slice-Config.ps1 — YAML-subset config readers + slice defaults (mirrors
# bash lib/slice-config.sh). Expects: $Cfg. Sets: $MaxFiles..$Excludes.
# ── config (YAML subset: two levels, scalars + string lists) ──────────────────
function Cfg-Val([string]$top, [string]$key) {
  if (-not (Test-Path $Cfg)) { return "" }
  $inTop = $false
  foreach ($line in [System.IO.File]::ReadAllLines($Cfg)) {
    if ($line -match '^[^\s#]') { $inTop = ($line -match "^$top`:\s*$") ; continue }
    if ($inTop -and $line -match "^\s+$key`:\s*(.*)$") {
      $v = $Matches[1] -replace '\s+#.*$', '' -replace '"', ''
      return $v.Trim()
    }
  }
  return ""
}
function Cfg-List([string]$top, [string]$key) {
  $items = @()
  if (-not (Test-Path $Cfg)) { return $items }
  $inTop = $false; $inList = $false
  foreach ($line in [System.IO.File]::ReadAllLines($Cfg)) {
    if ($line -match '^[^\s#]') { $inTop = ($line -match "^$top`:\s*$"); $inList = $false; continue }
    if ($inTop -and $line -match "^\s+$key`:\s*$") { $inList = $true; continue }
    if ($inTop -and $inList) {
      if ($line -match '^\s+-\s+(.*)$') { $items += ($Matches[1] -replace '\s+#.*$', '' -replace '"', '').Trim() }
      elseif ($line -match '^\s*(#|$)') { } else { $inList = $false }
    }
  }
  return $items
}

$MaxFiles = Cfg-Val "slice" "max_files"; if (-not $MaxFiles) { $MaxFiles = 400 } else { $MaxFiles = [int]$MaxFiles }
$MinFiles = Cfg-Val "slice" "min_files"; if (-not $MinFiles) { $MinFiles = 3 } else { $MinFiles = [int]$MinFiles }
$Boundary = @(Cfg-List "slice" "boundary_files")
if ($Boundary.Count -eq 0) {
  $Boundary = @("pyproject.toml", "setup.py", "package.json", "Cargo.toml", "go.mod",
                "pom.xml", "build.gradle", "CMakeLists.txt", "composer.json", "Gemfile")
}
$ContextDirs = @(Cfg-List "slice" "context_dirs")
if ($ContextDirs.Count -eq 0) { $ContextDirs = @("docs", "doc", "documentation") }
$PinDirs = @()
foreach ($pd in @(Cfg-List "slice" "pin_dirs")) { if ($pd) { $PinDirs += ([string]$pd).TrimEnd('/') } }
$Excludes = @(Cfg-List "coverage" "exclude")
if ($Excludes.Count -eq 0) { $Excludes = @(".*", "specs") }

