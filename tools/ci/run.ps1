param(
    [string]$GodotPath = "godot"
)

Write-Host "=== Running CI scripts with Godot headless ==="

function Test-Godot {
    try {
        & $GodotPath --version | Out-Null
        return $true
    } catch {
        return $false
    }
}

if (-not (Test-Godot)) {
    Write-Error "Godot not found on PATH. Pass -GodotPath or install Godot 4.x and ensure 'godot' is available."
    exit 1
}

# Run resource validation
& $GodotPath --headless --path . -s res://tools/ci/check_resources.gd
if ($LASTEXITCODE -ne 0) {
    Write-Error "Resource validation failed."
    exit $LASTEXITCODE
}

# Run start-day smoke test
& $GodotPath --headless --path . -s res://tools/ci/smoke_start_day.gd
if ($LASTEXITCODE -ne 0) {
    Write-Error "Smoke test failed."
    exit $LASTEXITCODE
}

Write-Host "=== CI scripts completed successfully ==="
exit 0
