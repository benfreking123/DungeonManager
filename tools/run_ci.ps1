param(
  [Parameter(Mandatory=$false)]
  [string]$Godot = $env:GODOT,

  [Parameter(Mandatory=$false)]
  [string]$ProjectPath = "",

  [Parameter(Mandatory=$false)]
  [string]$MainScene = "res://scenes/Main.tscn",

  [Parameter(Mandatory=$false)]
  [switch]$SkipImport
)

$ErrorActionPreference = "Stop"

function Resolve-Godot([string]$Value) {
  # Accept:
  # - Full path to Godot.exe
  # - Directory containing Godot.exe
  # - Command name available on PATH (e.g. "godot")
  if ([string]::IsNullOrWhiteSpace($Value)) {
    $cmd = Get-Command "godot" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    # Try common Windows locations for the official portable zip.
    $candidates = @()
    $roots = @(
      $env:ProgramFiles,
      ${env:ProgramFiles(x86)},
      $env:LOCALAPPDATA,
      $env:USERPROFILE
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    foreach ($r in $roots) {
      foreach ($p in @(
        (Join-Path $r "Godot"),
        (Join-Path $r "Godot*"),
        (Join-Path $r "Programs\Godot*"),
        (Join-Path $r "Downloads\Godot*"),
        (Join-Path $r "Desktop\Godot*")
      )) {
        $candidates += @(Get-ChildItem -LiteralPath $p -Filter "*.exe" -File -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -match '^Godot.*\.exe$' -or $_.Name -match '^godot.*\.exe$' } |
          ForEach-Object { $_.FullName })
      }
    }

    $candidates = $candidates | Select-Object -Unique
    if ($candidates.Count -gt 0) {
      # Prefer 4.x stable if present.
      $preferred = $candidates | Where-Object { $_ -match '4\.' } | Select-Object -First 1
      if ($preferred) { return $preferred }
      return ($candidates | Select-Object -First 1)
    }

    return $null
  }

  # Directory containing exe?
  if (Test-Path -LiteralPath $Value -PathType Container) {
    $candidates = Get-ChildItem -LiteralPath $Value -Filter "*.exe" -File -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -match '^Godot.*\.exe$' -or $_.Name -match '^godot.*\.exe$' } |
      Sort-Object -Property Name
    if ($candidates -and $candidates.Count -gt 0) {
      return $candidates[0].FullName
    }
    return $null
  }

  # Exact file path?
  if (Test-Path -LiteralPath $Value -PathType Leaf) {
    return (Resolve-Path -LiteralPath $Value).Path
  }

  # Command on PATH?
  $cmd2 = Get-Command $Value -ErrorAction SilentlyContinue
  if ($cmd2) { return $cmd2.Source }

  return $null
}

function Run-Step([string]$Title, [string[]]$GodotArgs) {
  Write-Host ""
  Write-Host "=== $Title ==="
  Write-Host "`"$Godot`" $($GodotArgs -join ' ')"

  # Run via Start-Process to avoid PowerShell treating native stderr as terminating errors
  # (especially under $ErrorActionPreference = 'Stop').
  $outFile = [System.IO.Path]::GetTempFileName()
  $errFile = [System.IO.Path]::GetTempFileName()
  try {
    $p = Start-Process -FilePath $Godot -ArgumentList $GodotArgs -NoNewWindow -Wait -PassThru `
      -RedirectStandardOutput $outFile -RedirectStandardError $errFile

    $stdout = Get-Content -LiteralPath $outFile -ErrorAction SilentlyContinue
    $stderr = Get-Content -LiteralPath $errFile -ErrorAction SilentlyContinue

    if ($stdout) { $stdout | ForEach-Object { Write-Host $_ } }
    if ($stderr) { $stderr | ForEach-Object { Write-Host $_ } }

    $exitCode = $p.ExitCode
    $outText = (($stdout + $stderr) -join "`n")
  }
  finally {
    Remove-Item -LiteralPath $outFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
  }

  $hasGodotError = $false
  if ($outText -match '(^|\r?\n)\s*(ERROR:|SCRIPT ERROR:|Parse Error:)') {
    $hasGodotError = $true
  }

  if ($hasGodotError -and $exitCode -eq 0) {
    $exitCode = 1
  }
  if ($exitCode -ne 0) {
    throw "Step failed ($Title) with exit code $exitCode"
  }
}

$Godot = Resolve-Godot $Godot
if ([string]::IsNullOrWhiteSpace($Godot)) {
  throw @"
Godot executable not found.

Fix options:
  1) Set env var:
       `$env:GODOT = "C:\full\path\to\Godot_v4.3-stable_win64.exe"
       .\tools\run_ci.ps1

  2) Pass -Godot:
       .\tools\run_ci.ps1 -Godot "C:\full\path\to\Godot_v4.3-stable_win64.exe"

  3) Put Godot on PATH (so `godot` works), then just run:
       .\tools\run_ci.ps1

To locate Godot from PowerShell:
  - `Get-Command godot`
  - `where.exe godot`

If you downloaded the official zip, it's often under:
  - `$env:USERPROFILE\Downloads\Godot*\Godot*.exe
"@
}

# Compute default project path after params bind (PS 5.1-safe).
if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
  $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
  $ProjectPath = (Resolve-Path (Join-Path $scriptDir "..")).Path
}

if (-not (Test-Path -LiteralPath $ProjectPath)) {
  throw "Project path not found: $ProjectPath"
}

if (-not $SkipImport) {
  # Import/warm cache (catches missing imports/resources).
  Run-Step "Import pass (warm cache)" @("--headless", "--quit", "--path", $ProjectPath, "--import")
}

# Parse/load all scripts + key scenes.
Run-Step "Script + scene load check" @("--headless", "--path", $ProjectPath, "-s", "res://tools/ci/check_resources.gd")

# Run the main scene headlessly for 1 frame (smoke test).
Run-Step "Run main scene (headless smoke test)" @("--headless", "--quit", "--path", $ProjectPath, $MainScene)

Write-Host ""
Write-Host "All CI checks passed."




