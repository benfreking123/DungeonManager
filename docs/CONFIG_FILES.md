## Configuration and Data Reference (complete list)

This document lists all configuration and data files that tune gameplay, AI/party behavior, content catalogs, and project wiring. Paths use `res://` (Godot) style.

### Project-level
- `res://project.godot`
  - Declares autoload singletons (e.g. `GameState`, `ai_tuning`, `config_goals`, `game_config`, etc.) and the main scene and theme.

### Core tuning autoloads
- `res://autoloads/ai_tuning.gd` (autoload: `ai_tuning`)
  - Central knobs for AI/party/pathing: path mistake rates vs INT, party leash distance, retarget cooldown, defection thresholds/caps, intent scoring and stability, hazard penalties, flee-on-damage mapping, exit-with-loot scaling, and ground-loot pickup radius.
- `res://autoloads/config_goals.gd` (autoload: `config_goals`)
  - Goal definitions (`GOAL_DEFS`), spawn-roll rules, per-goal params, and dialogue pools. Its `get_intent_score()` and `get_intent_stability()` delegate to `ai_tuning` when present.
- `res://autoloads/game_config.gd` (autoload: `game_config`)
  - General game constants (treasure IDs, power capacity, base drop chances, strength scaling). Non-AI tunables live here.
- `res://autoloads/traits_config.gd`
  - Trait definitions and stat modifiers (flat and percent), with optional strength (S) impact used by party generation.
- `res://autoloads/config_shop.gd`
  - Shop-related configuration.

### Start inventory configuration
- `res://config/start_inventory/base.json`
- `res://config/start_inventory/test.json`
- `res://config/start_inventory/profile.json` (selects which profile to use)
  - Loaded/merged by `res://autoloads/StartInventoryService.gd`. Controls initial room pieces and items for BUILD.

### Dialogue and identity data
- `res://data/dialogue_rules.json`
  - Rules pool for one-liner bubble text (intent/defect/flee/etc.). Loaded by `Simulation`.
- `res://data/bio_templates.json`
- `res://data/epithets.json`
- `res://data/names/common.json`
  - Used to generate adventurer identities (names, bios, epithets).

### Content catalogs (resources)
- Threat profiles:
  - `res://assets/threat/ThreatProfile_Default.tres`
  - `res://assets/threat/ThreatProfile_Melee.tres`
  - `res://assets/threat/ThreatProfile_Ranged.tres`
- Boss upgrades:
  - `res://assets/icons/boss_upgrades/UpgradeArmor.tres`
  - `res://assets/icons/boss_upgrades/UpgradeAttackSpeed.tres`
  - `res://assets/icons/boss_upgrades/UpgradeDamage.tres`
  - `res://assets/icons/boss_upgrades/UpgradeDoubleStrike.tres`
  - `res://assets/icons/boss_upgrades/UpgradeGlop.tres`
  - `res://assets/icons/boss_upgrades/UpgradeHealth.tres`
  - `res://assets/icons/boss_upgrades/UpgradeReflect.tres`
  - (Atlas resource: `BossUpgradeAtlas.tres`, not a single upgrade)
- Adventurer classes:
  - `res://scripts/classes/Warrior.tres`
  - `res://scripts/classes/Rogue.tres`
  - `res://scripts/classes/Mage.tres`
  - `res://scripts/classes/Priest.tres`
- Items (traps, treasures, boss):
  - Traps: `res://scripts/items/SpikeTrap.tres`, `FloorPit.tres`, `WebTrap.tres`, `RearmTrap.tres`, `TeleportTrap.tres`
  - Treasures: `res://scripts/items/Treasure_Base_Item.tres`, `Treasure_Warrior_Item.tres`, `Treasure_Rogue_Item.tres`, `Treasure_Mage_Item.tres`, `Treasure_Priest_Item.tres`
  - Boss: `res://scripts/items/Boss.tres`
- Room types:
  - `res://scripts/rooms/EntranceRoom.tres`, `BossRoom.tres`, `TreasureRoom.tres`, `MonsterRoom.tres`, `TrapRoom.tres`, `TrapRoom_2x1.tres`, `TrapRoom_3x2.tres`, `HallwayRoom.tres`, `HallwayPlus.tres`, `HallwayTLeft.tres`, `CorridorRoom.tres`, `StairsRoom.tres`

### Autoload/service configs (code-driven, but affect behavior)
- `res://autoloads/ItemDB.gd` (registers items, classes, boss upgrades; scans directories)
- `res://autoloads/RoomDB.gd` (scans room-type resources and builds the catalog)
- `res://autoloads/StartInventoryService.gd` (merges start-inventory profiles)
- `res://autoloads/Simulation.gd` (day runtime; reads dialogue rules; wires AI and systems)

### Editing guidance
- Change AI/party/pathing behavior in `ai_tuning.gd` (preferred). `config_goals.gd` is for goal definitions and dialogue; scoring/stability read from `ai_tuning`.
- Change general constants (power, treasure IDs, scaling) in `game_config.gd`.
- Add or tune traits in `traits_config.gd`.
- Adjust start inventories in `config/start_inventory/*.json`.
- Change dialogue pools in `data/dialogue_rules.json`; change identity pools in `data/*.json`.
- Add/modify content by editing/adding `.tres` resources in the listed directories; `ItemDB`/`RoomDB` will discover/register them.

