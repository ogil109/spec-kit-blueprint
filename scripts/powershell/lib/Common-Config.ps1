#!/usr/bin/env pwsh
# lib/Common-Config.ps1 — configuration validation (mirrors bash
# lib/common-config.sh at byte parity on the error output). Silent when clean;
# exits 2 on any violation, listing all of them. Expects: $Cfg.
if (Test-Path $Cfg) {
  $valid = @{ blueprint = @("path"); distill = @("require_confirmation")
              slice = @("max_files", "min_files", "boundary_files", "context_dirs", "pin_dirs")
              coverage = @("exclude") }
  $listKeys = @("boundary_files", "context_dirs", "pin_dirs", "exclude")
  $numKeys  = @("max_files", "min_files")
  $boolKeys = @("require_confirmation")
  $errs = [System.Collections.Generic.List[string]]::new()
  $top = ""; $lastList = ""; $items = @{}; $nr = 0
  function Flush-List {
    if ($script:lastList -ne "" -and $script:items[$script:lastList] -eq 0) {
      $script:errs.Add("list key '$($script:lastList)' has no parseable items (check indentation)")
    }
    $script:lastList = ""
  }
  foreach ($line in [System.IO.File]::ReadAllLines($Cfg)) {
    $nr++
    if ($line -match '^\s*(#|$)') { continue }
    if ($line -match '^[^\s]') {
      Flush-List
      if ($line -notmatch ':') { $errs.Add("unrecognized top-level line ${nr}: $line"); $top = ""; continue }
      $t = ($line -replace ':.*$', '') -replace '\s+$', ''
      if (-not $valid.ContainsKey($t)) { $errs.Add("unknown section '$t' (valid: blueprint, distill, slice, coverage)"); $top = ""; continue }
      $top = $t; continue
    }
    if ($top -eq "") { continue }
    if ($line -match '^\s+-\s+') {
      if ($lastList -ne "") { $items[$lastList]++ }
      else { $errs.Add("list item outside any list key (line $nr)") }
      continue
    }
    if ($line -match '^\s+[A-Za-z_]+:') {
      Flush-List
      $k = ($line -replace '^\s+', '') -replace ':.*$', ''
      if ($valid[$top] -notcontains $k) {
        $errs.Add("unknown key '$k' under '$top' (valid: $($valid[$top] -join ' ') )"); continue
      }
      $v = ($line -replace '^\s+[A-Za-z_]+:\s*', '') -replace '\s+#.*$', '' -replace '"', ''
      if ($listKeys -contains $k) {
        if ($v -eq "")        { $lastList = $k; $items[$k] = 0 }
        elseif ($v -eq "[]")  { }
        else { $errs.Add("key '$k' expects a block list (- items) or [], got: $v") }
        continue
      }
      if ($numKeys -contains $k)  { if ($v -notmatch '^[1-9][0-9]*$') { $errs.Add("key '$k' must be a positive integer, got: '$v'") }; continue }
      if ($boolKeys -contains $k) { if ($v -ne "true" -and $v -ne "false") { $errs.Add("key '$k' must be true or false, got: '$v'") }; continue }
      if ($k -eq "path" -and $v -eq "") { $errs.Add("key 'path' is empty") }
      continue
    }
    $errs.Add("unrecognized line ${nr}: $line")
  }
  Flush-List
  if ($errs.Count -gt 0) {
    [Console]::Error.WriteLine("invalid blueprint-config.yml — nothing run:")
    foreach ($e in $errs) { [Console]::Error.WriteLine("  - $e") }
    # `exit` in a dot-sourced module does not terminate the entry; the entry
    # gates on this flag (same pattern as the command modules).
    $ConfigInvalid = $true
  }
}
