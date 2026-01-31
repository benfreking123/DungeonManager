## Godot CI smoke checks

This folder contains a tiny "does the project load/run?" validation that works in headless mode.

### What it checks

- **Import pass**: warms the cache and forces resource import (`--import`)
- **Script parse / load**: loads every `.gd` under `autoloads/`, `scripts/`, `ui/`
- **Scene load**: loads every `.tscn` under `scenes/`, `ui/`
- **Run main scene**: starts `res://scenes/Main.tscn` headlessly and exits after one frame
- **Start Day button**: loads the main scene, places a boss room adjacent to Entrance, presses **Start Day**, and asserts the game enters the `DAY` phase

### Run on Windows (PowerShell)

From the project root:

```powershell
$env:GODOT="C:\path\to\Godot_v4.3-stable_win64.exe"
.\tools\run_ci.ps1
```

Or pass it directly:

```powershell
.\tools\run_ci.ps1 -Godot "C:\path\to\Godot_v4.3-stable_win64.exe"
```

If you have Godot on your `PATH` (so `godot` works), you can just run:

```powershell
.\tools\run_ci.ps1
```

To find where Godot is installed:

```powershell
Get-Command godot
where.exe godot
```

### Run on macOS/Linux (bash)

```bash
GODOT=/path/to/godot ./tools/run_ci.sh
```
