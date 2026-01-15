param(
  [int]$Top = 15
)

$ErrorActionPreference = "Stop"

function Show-TopFiles([string]$Root, [int]$N) {
  if (-not (Test-Path -LiteralPath $Root)) {
    Write-Host "Not found: $Root"
    return
  }

  Write-Host ""
  Write-Host ("Top {0} largest files under: {1}" -f $N, $Root)
  Get-ChildItem -Force -Recurse -File -LiteralPath $Root -ErrorAction SilentlyContinue |
    Sort-Object Length -Descending |
    Select-Object -First $N @{
      Name = "SizeMB";
      Expression = { [math]::Round($_.Length / 1MB, 2) }
    }, FullName |
    Format-Table -AutoSize
}

Show-TopFiles -Root (Join-Path $PSScriptRoot "..\\.godot") -N $Top
Show-TopFiles -Root (Join-Path $PSScriptRoot "..") -N $Top

Write-Host ""
Write-Host "Tip: It's safe to delete the .godot folder (shader_cache/imports). Godot will regenerate it."


