param(
  [string]$Path = "."
)

$ErrorActionPreference = "Stop"

$proj = Join-Path (Resolve-Path -LiteralPath $Path).Path "project.godot"
if (-not (Test-Path -LiteralPath $proj)) {
  Write-Error "project.godot not found at: $proj"
}

$text = (cmd /c type "$proj") -join "`n"

function Find-First([string]$pattern) {
  $m = [regex]::Match($text, $pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
  if ($m.Success) { return $m.Groups[1].Value }
  return ""
}

$name = Find-First '^\s*config/name\s*=\s*"(.*)"\s*$'
$mainScene = Find-First '^\s*run/main_scene\s*=\s*"(.*)"\s*$'
$features = Find-First '^\s*config/features\s*=\s*PackedStringArray\((.*)\)\s*$'

Write-Host "Godot Project Summary"
Write-Host "--------------------"
Write-Host ("Path:      " + (Split-Path -Parent $proj))
Write-Host ("Name:      " + $name)
Write-Host ("MainScene: " + $mainScene)
Write-Host ("Features:  " + $features)


