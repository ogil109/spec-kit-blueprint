#!/usr/bin/env pwsh
# lib/Common-Git.ps1 — git + marker plumbing shared by every command (mirrors
# bash lib/common-git.sh). Expects: $Root, $Blueprint.
# code-staleness support (mirrors the bash oracle): a code-owned section carries
#   <!-- blueprint:code path=src/area sha=<git-sha> -->  recording the code baseline.
function Test-Git    { git -C $Root rev-parse --git-dir 2>$null | Out-Null; return $LASTEXITCODE -eq 0 }
function Get-CurSha($p) { $s = git -C $Root rev-parse --verify --quiet "HEAD:$p" 2>$null; if ($LASTEXITCODE -eq 0) { return $s.Trim() } else { return "" } }
function Get-CodeMarkers {
  if (-not ($Blueprint -and (Test-Path $Blueprint))) { return @() }
  Select-String -Path $Blueprint -Pattern '<!-- blueprint:code path=(\S+) sha=(\S+) -->' -AllMatches |
    ForEach-Object { $_.Matches } | ForEach-Object { [pscustomobject]@{ path = $_.Groups[1].Value; sha = $_.Groups[2].Value } }
}
# A context section may declare the paths it covers (docs trees etc.):
#   <!-- blueprint:context path=docs -->
# Context coverage has NO baseline and NO staleness (mirrors the bash oracle).
function Get-ContextMarkers {
  if (-not ($Blueprint -and (Test-Path $Blueprint))) { return @() }
  Select-String -Path $Blueprint -Pattern '<!-- blueprint:context path=(\S+) -->' -AllMatches |
    ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value }
}
# Coverage excludes: config coverage.exclude list, else defaults (hidden
# top-level dirs; specs/, which is gated by distill drift instead). A pattern
# without "/" matches the FIRST path component; with "/" it is a path prefix.
function Get-CoverageExcludes {
  $cfg = Join-Path $Root ".specify/extensions/blueprint-index/blueprint-config.yml"
  $ex = @()
  if (Test-Path $cfg) {
    $inTop = $false; $inList = $false
    foreach ($line in [System.IO.File]::ReadAllLines($cfg)) {
      if ($line -match '^[^\s#]') { $inTop = ($line -match '^coverage:\s*$'); $inList = $false; continue }
      if ($inTop -and $line -match '^\s+exclude:\s*$') { $inList = $true; continue }
      if ($inTop -and $inList) {
        if ($line -match '^\s+-\s+(.*)$') { $ex += ($Matches[1] -replace '\s+#.*$','' -replace '"','') }
        elseif ($line -match '^\s*(#|$)') { } else { $inList = $false }
      }
    }
  }
  if ($ex.Count -gt 0) { return $ex } else { return @(".*", "specs") }
}

