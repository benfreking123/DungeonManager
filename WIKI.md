## DungeonManager Wiki (player-facing content + storage)

This file is a quick “what exists” index for everything meaningful to the player, plus **where it’s stored** and **how it’s loaded**.

### How to read this
- **IDs**: Most game content uses a string `id` (or `upgrade_id`) inside a `.tres` resource file.
- **Paths**: Godot uses `res://` paths at runtime; file locations below are written in `res://...` form.
- **Registries / loaders**: Some categories are **directory-scanned** (auto-discovered), others are **registered** in an autoload script.

## Core game loop (Build / Day / Results)
- **Main scene**: `res://scenes/Main.tscn` (script: `res://scripts/Main.gd`)
- **Phase + economy state**: `res://autoloads/GameState.gd`
  - Tracks `phase` (`BUILD`, `DAY`, `RESULTS`), `speed`, and power (`power_used`, `power_capacity`)
  - Recomputes power capacity based on installed Treasure in rooms with `effect_id == game_config.TREASURE_ROOM_EFFECT_ID`
- **Day simulation (“adventure”)**: `res://autoloads/Simulation.gd`
  - Handles party spawn, movement through rooms, room-entry effects, monster spawning, and day end
- **Combat subsystem**: `res://autoloads/Simulation_Combat.gd`
  - Uses threat targeting (`res://scripts/systems/ThreatSystem.gd`) + `ThreatProfile` resources
- **Update rule**: These are code-driven systems; edit the `.gd` files above.

## Inventories (what the player can place/own)
- **Player inventory (placeable items + boss upgrades + treasure counts)**: `res://autoloads/PlayerInventory.gd`
  - Keys are **item IDs** (trap/monster/treasure IDs and boss upgrade `upgrade_id` values)
- **Room-piece inventory (placeable room types during BUILD)**: `res://autoloads/RoomInventory.gd`
  - Keys are **RoomType ids** (e.g. `hall`, `corridor`, `monster`, `trap`, `boss`, `treasure`, `stairs`)
- **Build inventory (alternate/older room count tracking)**: `res://autoloads/BuildInventory.gd`
  - Keys are **RoomType ids**; not all room kinds are tracked by default
- **UI that renders inventories**: `res://ui/RoomInventoryPanel.gd` (tabs: Rooms/Monsters/Traps/Boss/Treasure)
- **Update rule**: Adjust starting counts in the `counts` dictionaries in the autoload `.gd` files.

## Dungeon layout (grid + slots)
- **Dungeon grid state**: `res://autoloads/DungeonGrid.gd`
  - Owns placed room instances (`DungeonGrid.rooms`) and enforces “BUILD-only” editing
  - Slot policy is defined by `DungeonGrid._slot_kind_for_room(...)` (e.g. boss room has `universal` + `boss_upgrade` slots)
- **Dungeon renderer + drag/drop placement**: `res://scripts/DungeonView.gd`
  - Handles DnD placement, slot install/uninstall, and emits `room_clicked(...)` for popups
- **Room selection UI**: `res://ui/BuildPanel.gd`
- **Update rule**: Edit `DungeonGrid.gd` for rules/data model; edit `DungeonView.gd` / `BuildPanel.gd` for UX/input/rendering.

## Game config
- **Source of truth**: `res://autoloads/game_config.gd` (autoload name: `game_config`)
- **Update rule**: Edit constants in `res://autoloads/game_config.gd` (these are hard-coded tunables).
- **Notable player-facing tunables stored here**:
  - `ADV_DEATH_TREASURE_DROP_CHANCE`
  - `BASE_POWER_CAPACITY`
  - `TREASURE_ROOM_EFFECT_ID`
  - `TREASURE_ROOM_POWER_CAPACITY_PER_TREASURE`
  - Treasure IDs and mapping:
    - `TREASURE_ID_WARRIOR` → `treasure_warrior`
    - `TREASURE_ID_MAGE` → `treasure_mage`
    - `TREASURE_ID_PRIEST` → `treasure_priest`
    - `TREASURE_ID_ROGUE` → `treasure_rogue`
    - `TREASURE_ID_BY_CLASS` / `treasure_id_for_class(class_id)`

## Rooms
- **Loader**: `res://autoloads/RoomDB.gd` scans `res://scripts/rooms` for `*.tres` with script `res://scripts/rooms/RoomType.gd` and indexes by `RoomType.id`.
- **RoomType definition**: `res://scripts/rooms/RoomType.gd`
- **Update rule**: Add/update a `RoomType` `.tres` in `res://scripts/rooms/` (auto-discovered by `RoomDB`).
- **Rooms (id → file)**:
  - `boss` → `res://scripts/rooms/BossRoom.tres`
  - `corridor` → `res://scripts/rooms/CorridorRoom.tres`
  - `entrance` → `res://scripts/rooms/EntranceRoom.tres`
  - `hall` → `res://scripts/rooms/HallwayRoom.tres`
  - `monster` → `res://scripts/rooms/MonsterRoom.tres`
  - `stairs` → `res://scripts/rooms/StairsRoom.tres`
  - `trap` → `res://scripts/rooms/TrapRoom.tres`
  - `treasure` → `res://scripts/rooms/TreasureRoom.tres`

## Traps
- **Registry**: `res://autoloads/ItemDB.gd` (`traps` dictionary)
- **Trap resource class**: `res://scripts/items/Trap.gd` (`TrapItem`)
- **Update rule**: Create/update a trap `.tres`, then register it in `ItemDB._ready()` (`traps["your_id"] = load("res://...")`).
- **Traps (id → file)**:
  - `spike_trap` → `res://scripts/items/SpikeTrap.tres`
  - `floor_pit` → `res://scripts/items/FloorPit.tres`

## Monsters
- **Registry**: `res://autoloads/ItemDB.gd` (`monsters` dictionary)
- **Monster resource class**: `res://scripts/items/Monster.gd` (`MonsterItem`)
- **Update rule**: Create/update a monster `.tres`, then register it in `ItemDB._ready()` (`monsters["your_id"] = load("res://...")`).
- **Monsters (id → file)**:
  - `zombie` → `res://scripts/items/Zombie.tres`
  - `boss` → `res://scripts/items/Boss.tres`

## Treasure
- **Registry**: `res://autoloads/ItemDB.gd` (`treasures` dictionary)
- **Treasure resource class**: `res://scripts/items/Treasure.gd` (`TreasureItem`)
- **Update rule**: Create/update a treasure `.tres`, then register it in `ItemDB._ready()` (`treasures["your_id"] = load("res://...")`).
- **Treasures (id → file)**:
  - `treasure_base` → `res://scripts/items/Treasure_Base_Item.tres`
  - `treasure_warrior` → `res://scripts/items/Treasure_Warrior_Item.tres`
  - `treasure_rogue` → `res://scripts/items/Treasure_Rogue_Item.tres`
  - `treasure_mage` → `res://scripts/items/Treasure_Mage_Item.tres`
  - `treasure_priest` → `res://scripts/items/Treasure_Priest_Item.tres`

## Boss upgrades
- **Loader**: `res://autoloads/ItemDB.gd` scans `res://assets/icons/boss_upgrades` for `*.tres` and loads `BossUpgradeItem` by `upgrade_id` (skips `BossUpgradeAtlas.tres`).
- **Boss upgrade resource class**: `res://scripts/items/BossUpgradeItem.gd` (`BossUpgradeItem`)
- **Update rule**: Add/update a `BossUpgradeItem` `.tres` in `res://assets/icons/boss_upgrades/` (auto-discovered by `ItemDB._load_boss_upgrades()`).
- **Boss upgrades (upgrade_id → file)**:
  - `armor` → `res://assets/icons/boss_upgrades/UpgradeArmor.tres`
  - `attack_speed` → `res://assets/icons/boss_upgrades/UpgradeAttackSpeed.tres`
  - `damage` → `res://assets/icons/boss_upgrades/UpgradeDamage.tres`
  - `double_strike` → `res://assets/icons/boss_upgrades/UpgradeDoubleStrike.tres`
  - `glop` → `res://assets/icons/boss_upgrades/UpgradeGlop.tres`
  - `health` → `res://assets/icons/boss_upgrades/UpgradeHealth.tres`
  - `reflect` → `res://assets/icons/boss_upgrades/UpgradeReflect.tres`

## Adventurers / Classes
There isn’t currently a separate “Adventures” data category; the player-facing equivalent is **Adventurers** (runtime actors) and **Classes** (data resources).

- **Adventurer actor (runtime)**
  - Scene: `res://scenes/Adventurer.tscn`
  - Scripts: `res://scripts/Adventurer.gd`, `res://scripts/AdventurerAI.gd`

- **Adventurer classes (data)**
  - **Registry**: `res://autoloads/ItemDB.gd` (`classes` dictionary)
  - **Class resource class**: `res://scripts/classes/AdventurerClass.gd` (`AdventurerClass`)
  - **Update rule**: Create/update a class `.tres`, then register it in `ItemDB._ready()` (`classes["your_id"] = load("res://...")`).
  - **Classes (id → file)**:
    - `warrior` → `res://scripts/classes/Warrior.tres`
    - `rogue` → `res://scripts/classes/Rogue.tres`
    - `mage` → `res://scripts/classes/Mage.tres`
    - `priest` → `res://scripts/classes/Priest.tres`

## Threat profiles
- **ThreatProfile resource class**: `res://scripts/systems/ThreatProfile.gd` (`ThreatProfile`)
- **Update rule**: Add/update a `ThreatProfile` `.tres` in `res://assets/threat/` and reference it from monsters/classes that should use it.
- **Threat profile resources**:
  - `res://assets/threat/ThreatProfile_Default.tres`
  - `res://assets/threat/ThreatProfile_Melee.tres`
  - `res://assets/threat/ThreatProfile_Ranged.tres`

## Config files (non-content)
These aren’t “content” the player unlocks, but they are key configuration/tuning entry points in the repo.

- **Project config**: `res://project.godot`
  - Declares autoloads (`[autoload]`) and the main scene.
  - Declares the UI theme (`[gui] theme/custom`).
- **Autoloads (global singletons)**: `res://autoloads/*`
  - `res://autoloads/game_config.gd` (tuning/constants)
  - `res://autoloads/RoomDB.gd` (room type loader)
  - `res://autoloads/ItemDB.gd` (item registry + boss upgrade loader)
  - Other autoloads are declared in `project.godot` and may affect player-visible behavior (simulation, inventory, etc.).
- **UI theme**: `res://ui/DungeonManagerTheme.tres`
- **Shop UI**: `res://ui/Shop.tscn` (script: `res://ui/Shop.gd`)