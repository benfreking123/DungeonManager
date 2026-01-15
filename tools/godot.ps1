param(
  [string]$HintPath = ""
)

$ErrorActionPreference = "Stop"

function Resolve-GodotCandidate([string]$p) {
  if ([string]::IsNullOrWhiteSpace($p)) { return $null }
  try {
    $expanded = [Environment]::ExpandEnvironmentVariables($p)
    if (Test-Path -LiteralPath $expanded) {
      return (Resolve-Path -LiteralPath $expanded).Path
    }
  } catch { }
  return $null
}

function Find-GodotInCommonLocations {
  $candidates = @()

  # 1) Explicit hint / env var
  $candidates += (Resolve-GodotCandidate $HintPath)
  $candidates += (Resolve-GodotCandidate $env:GODOT)
  $candidates += (Resolve-GodotCandidate $env:GODOT4)

  # 2) On PATH (godot / godot4 / Godot_*)
  foreach ($cmd in @("godot4", "godot")) {
    try {
      $found = (Get-Command $cmd -ErrorAction Stop).Source
      $candidates += (Resolve-GodotCandidate $found)
    } catch { }
  }

  # 3) Typical install folders
  $roots = @(
    "C:\Program Files\Godot",
    "C:\Program Files (x86)\Godot"
  )

  foreach ($root in $roots) {
    if (Test-Path -LiteralPath $root) {
      $candidates += (Get-ChildItem -LiteralPath $root -Filter "*.exe" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "Godot" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 5 |
        ForEach-Object { $_.FullName })
    }
  }

  # 4) Local Apps folder (common if installed per-user)
  if ($env:LOCALAPPDATA) {
    $localRoot = Join-Path $env:LOCALAPPDATA "Programs"
    if (Test-Path -LiteralPath $localRoot) {
      $candidates += (Get-ChildItem -LiteralPath $localRoot -Depth 3 -Filter "*.exe" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "Godot" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 5 |
        ForEach-Object { $_.FullName })
    }
  }

  # De-dupe + validate
  $seen = @{}
  $valid = @()
  foreach ($c in $candidates) {
    $p = Resolve-GodotCandidate $c
    if ($null -ne $p -and -not $seen.ContainsKey($p)) {
      $seen[$p] = $true
      $valid += $p
    }
  }
  return $valid
}

$paths = Find-GodotInCommonLocations

if ($paths.Count -eq 0) {
  Write-Error "Could not find Godot. Install Godot 4.x, or set env var GODOT/GODOT4 to your Godot executable path (e.g. C:\Program Files\Godot\Godot_v4.3-stable_win64.exe)."
}

# Pick the most recently modified candidate.
$best = $paths |
  ForEach-Object { Get-Item -LiteralPath $_ } |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

Write-Output $best.FullName



