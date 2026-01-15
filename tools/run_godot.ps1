param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$GodotArgs
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$godotPath = & (Join-Path $scriptDir "godot.ps1")

Write-Host ("Using Godot: " + $godotPath)
Write-Host ("Args: " + ($GodotArgs -join " "))

& $godotPath @GodotArgs
$exit = $LASTEXITCODE
if ($exit -ne 0) {
  exit $exit
}



