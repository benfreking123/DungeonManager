# State Model (the “money doc”)

This defines **game states** (not scenes) and allowed transitions. It should be the shared reference for UI, simulation, and debugging.

## State inventory (top-level)

### `Boot`
- **Meaning**: Engine starts; autoloads register; main scene not yet ready.
- **Owner**: Godot runtime + `project.godot`

### `MainSceneLoaded`
- **Meaning**: `Main.tscn` is running; UI and simulation wiring occurs.
- **Owner**: `scripts/Main.gd`

### `InGame(Build)`
- **Meaning**: Player edits dungeon layout and installs/uninstalls items.
- **Owner**: `GameState.phase == BUILD`
- **Key invariants**:
  - Layout mutation is allowed **only** in this state.
  - Power capacity is derived (base + bonuses).

### `InGame(Day)`
- **Meaning**: Day simulation is active; adventurers move, fight, steal, flee/exit.
- **Owner**: `GameState.phase == DAY`
 - **Pause model**: Pausing is implemented as `GameState.speed == 0.0` (time stops; HUD toggles pause/resume).

### `InGame(Shop)`
- **Meaning**: After a successful day clear, the player is offered shop decisions.
- **Owner**: `GameState.phase == SHOP`
 - **Interaction gate**: while the shop is open, most HUD/world interactions are disabled (mouse filter gating); ESC closes the shop.

### `InGame(Results)`
- **Meaning**: Summary/endcap state. Also used as the loss/gameover landing state.
- **Owner**: `GameState.phase == RESULTS`
 - **Loss overlay**: game over panel is shown on boss death; restart resets run state and reloads the main scene.

### `PauseOverlay` (optional / UI-level)
- **Meaning**: A UI overlay that suspends player input and/or simulation.
- **Owner**: UI layer (not currently modeled in `GameState`)
- **Note**: Treat as an overlay state rather than a distinct simulation phase unless the code needs hard guarantees.

### `InspectOverlay` (UI-level)
- **Meaning**: Context panels that let the player inspect current state without changing the simulation state.
- **Examples**:
  - Room inspect popup (shows slot contents/stats)
  - Adventurer inspect popup (identity/goals/traits/ability; works in BUILD preview and DAY)
  - Day event log panel (history)

### `BuildValidityOverlay` (UI-level)
- **Meaning**: Live feedback during BUILD about whether the dungeon can start a day.
- **Owner**: HUD + `DungeonSetupStatusService`
- **Signals/UX**:
  - Setup warning icon appears when there are connectivity/setup issues; hover shows the issue list.
  - Placement hint text shows “why not” during hover/drag placement.

## Day sub-states (useful for debugging “what is happening right now?”)

These are **sub-states inside** `InGame(Day)` and can be derived from runtime flags:

- **`SurfaceTravel`**: adventurers exist on the town surface and are walking to the entrance.
- **`DungeonTravel`**: adventurers are following dungeon paths and triggering room-entry rules.
- **`Combat(room_id)`**: combat record exists for that room in `Simulation_Combat`.

## Allowed transitions (state machine table)

| From | To | Trigger | Guard / reason to block |
|---|---|---|---|
| `Boot` | `MainSceneLoaded` | main scene starts | none |
| `MainSceneLoaded` | `InGame(Build)` | initial `GameState.phase` | none |
| `InGame(Build)` | `InGame(Day)` | `Simulation.start_day()` | `DungeonGrid.validate_required_paths().ok == true` AND boss room exists |
| `InGame(Day)` | `InGame(Shop)` | `Simulation.end_day(\"success\")` | only if not ended as loss |
| `InGame(Day)` | `InGame(Results)` | boss killed → loss | none (loss is immediate) |
| `InGame(Shop)` | `InGame(Results)` | finalize shop | none |
| `InGame(Results)` | `InGame(Build)` | “advance day” | increments `GameState.day_index` and returns to build |

## Ownership map (who drives transitions)

- **`GameState`**: holds authoritative `phase`, `day_index`, and economy (`power_used`, `power_capacity`).
- **`Simulation`**: drives the runtime DAY lifecycle:
  - calls `GameState.set_phase(DAY)` on start
  - calls `GameState.set_phase(SHOP)` on clear
  - calls `GameState.set_phase(RESULTS)` on loss
- **`DungeonGrid`**: enforces the hard rule “only editable during BUILD” and supplies layout validity checks used by `Simulation.start_day()`.

## Input model (player controls worth treating as “stateful”)

- **World navigation**: middle-mouse pan + mouse wheel zoom (cursor-centered).
- **BUILD interactions**: drag/drop rooms and items; right-click remove/uninstall; click room to open inspect popup.
- **DAY interactions**: right-click adventurer to open inspect popup; pause/resume via HUD action button (speed=0).
- **History**: toggle day event log panel via `H` (and via HUD/town UI).

## Tuning sources (where behavior is configured)
- `res://autoloads/ai_tuning.gd` (autoload `ai_tuning`): central knobs for adventurer/party behavior
  - Path mistake rates vs INT, party leash distance, defection thresholds/caps, intent scoring/stability, hazard penalties,
    flee-on-damage mapping, exit-with-loot scaling, loot pickup radius, and soft retarget cooldown.
- `res://autoloads/config_goals.gd` (autoload `config_goals`): goal definitions and dialogue; its scoring/stability delegates to `ai_tuning` when present.
- `res://autoloads/game_config.gd` (autoload `game_config`): general constants (power capacity, treasure IDs, etc.).