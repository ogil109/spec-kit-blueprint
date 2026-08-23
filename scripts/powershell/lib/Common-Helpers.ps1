#!/usr/bin/env pwsh
# lib/Common-Helpers.ps1 — shared string/sort helpers. Dot-sourced by both
# entries before any module that emits ordered output.
# LC_ALL=C parity: native-command output elements are not guaranteed to be
# System.String in PS 7.5+, and both Sort-Object and comparer fallbacks then
# go culture-aware. Force real strings + ordinal everywhere order is emitted.
function Sort-Ordinal([object[]]$a) {
  $s = [string[]]$a; [Array]::Sort($s, [System.StringComparer]::Ordinal); return $s
}
function Sort-OrdinalUnique([object[]]$a) {
  $set = [System.Collections.Generic.HashSet[string]]::new()
  foreach ($x in $a) { [void]$set.Add([string]$x) }
  $s = [string[]]::new($set.Count); $set.CopyTo($s)
  [Array]::Sort($s, [System.StringComparer]::Ordinal); return $s
}
