# Data Contracts (schemas + ownership)

This document defines the “shape” of the game’s core data: **fields, types, invariants, and who owns them**. It is intended to prevent accidental schema drift across UI/simulation/tools.

## Conventions

- **IDs are strings** and must be stable:
  - `RoomType.id` (e.g. `hall`, `boss`, `treasure`)
  - `TrapItem.id`, `MonsterItem.id`, `TreasureItem.id`, `AdventurerClass.id`, `Ability.ability_id`
  - `BossUpgradeItem.upgrade_id` (note: not `id`)
- **Empty string means “none installed/unknown”** for item IDs in slots and optional fields.
- **Build-only mutation**: dungeon layout and slot install/uninstall is allowed only when `GameState.phase == BUILD`.
  - Exception: “inspect” UI is allowed in any phase (read-only).

## What is the “Player” (ownership)

DungeonManager doesn’t have a `Player` object; “player state” is split across autoloads:

- **`GameState`**: phase, day index, speed, economy counters
- **`DungeonGrid`**: the dungeon layout (`rooms[]`) including installed items in slots
- **`RoomInventory`**: counts of placeable room pieces by room type id
- **`PlayerInventory`**: counts of placeable items/upgrades by item id
- **`StolenStash`**: treasure counts successfully stolen by adventurers who exited
- **`HistoryService` (runtime/RefCounted)**: identity profiles + chronological event log (session-scope)

## `GameState` (autoload)

- **Owner**: `autoloads/GameState.gd`
- **Schema**:
  - `phase: int` where `Phase = { BUILD, DAY, SHOP, RESULTS }`
  - `speed: float` clamped to \([0.0, 8.0]\)
  - `day_index: int` \(>= 1\)
  - `power_used: int` \(>= 0\)
  - `power_capacity: int` \(>= 0\) derived as `BASE_POWER_CAPACITY + bonus_from_treasure_room`
- **Signals**: `phase_changed(new_phase:int)`, `speed_changed(new_speed:float)`, `economy_changed()`
- **Invariants**:
  - Phase transitions are authoritative and should be treated as the source of truth for UI gating.
  - Power capacity depends on installed treasure in rooms whose `RoomType.effect_id == TREASURE_ROOM_EFFECT_ID`.

## `DungeonGrid.rooms` (autoload “world model”)

- **Owner**: `autoloads/DungeonGrid.gd`
- **Type**: `Array[Dictionary]`
- **Room instance schema** (per entry):
  - `id: int` unique, \(> 0\)
  - `type_id: String` (RoomType id; lookup via `RoomDB.get_room_type(type_id)`)
  - `pos: Vector2i` top-left cell
  - `size: Vector2i` footprint in cells
  - `kind: String` (room kind; used for slot policy and day logic)
  - `known: bool` (present but fog-of-war is primarily owned by `FogOfWarService`)
  - `locked: bool` (prevents removal; used for Entrance)
  - `slots: Array[Dictionary]` (0..max; see below)
  - `max_monster_size_capacity: int` (monster rooms; default 3)
  - Optional composite placement metadata:
    - `group_id: int`
    - `group_type_id: String`

### Composite room groups (multi-cell “one piece” rooms)

- **Owner**: placement UI (`scripts/DungeonView.gd`) + storage (`autoloads/DungeonGrid.gd`)
- **Placement contract**:
  - Some room types place as a **group of 1x1 rooms** but consume **one** inventory piece (e.g. `hall_plus`, `hall_t_left`).
  - Group placement uses `DungeonGrid.place_room_group(type_id, cells, kind, locked)` and returns a `group_id`.
  - Each stamped 1x1 room includes:
    - `group_id: int` (shared)
    - `group_type_id: String` (the original type id for refunding)
- **Removal contract**:
  - Group removal uses `DungeonGrid.remove_room_group_at(cell)` and refunds a single piece for the group.

### Slot schema (`room.slots[]`)

- **Type**: `Array[Dictionary]` with fixed length `RoomType.max_slots` when `kind in {trap, monster, treasure, boss}`
- **Slot dictionary**:
  - `slot_kind: String` one of:
    - `"trap"`, `"monster"`, `"treasure"`, `"boss_upgrade"`, `"universal"`, or `""`
  - `installed_item_id: String` (empty string means empty)
- **Slot-kind policy**:
  - `boss`: first 2 slots are `"universal"`, last slot is `"boss_upgrade"` (others `"universal"`)
  - `monster`/`trap`/`treasure`: `slot_kind == kind`

### Invariants

- Only editable when `GameState.phase == BUILD`:
  - placing/removing rooms
  - installing/uninstalling items in slots
- `DungeonGrid.validate_required_paths()` guards `Simulation.start_day()`:
  - Requires a path from entrance → boss
  - If treasure exists, requires a path from entrance → treasure

## `RoomType` contract (data resource, exposed as a dict)

- **Owner**: `autoloads/RoomDB.gd` (loads `.tres` under `res://scripts/rooms/`)
- **Public shape**: `RoomDB.get_room_type(id) -> Dictionary`
- **Schema**:
  - `id: String`
  - `label: String`
  - `size: Vector2i`
  - `power_cost: int`
  - `kind: String`
  - `max_slots: int`
  - `effect_id: String` (used for treasure-room economy effects)
  - `monster_capacity: int` (used by monster/boss minion spawners)
  - `monster_cooldown_per_size: float` (spawn interval scaling)
- **Invariants**:
  - `id` must be unique and non-empty (RoomDB warns on missing id).

## Inventories (autoloads)

### `RoomInventory`
- **Owner**: `autoloads/RoomInventory.gd`
- **Schema**: `counts: Dictionary` where keys are `RoomType.id`, values are `int >= 0`

### `PlayerInventory`
- **Owner**: `autoloads/PlayerInventory.gd`
- **Schema**: `counts: Dictionary` where keys are item ids (trap/monster/treasure/boss_upgrade), values are `int >= 0`
- **Invariant**: keys must correspond to ids known by `ItemDB` (or to future content ids being staged).
- **Note**: Treasure item ids double as **currency** for the shop (costs consume from this same `counts` map).

### `StolenStash`
- **Owner**: `autoloads/StolenStash.gd`
- **Schema**: `counts: Dictionary` where keys are treasure item ids, values are `int >= 0`
- **Meaning**: only increments when an adventurer successfully exits while holding stolen treasure.

## `ItemDB` (resource registries)

- **Owner**: `autoloads/ItemDB.gd`
- **Shape**:
  - `traps: Dictionary[String, TrapItem]`
  - `monsters: Dictionary[String, MonsterItem]`
  - `treasures: Dictionary[String, TreasureItem]`
  - `classes: Dictionary[String, AdventurerClass]`
  - `boss_upgrades: Dictionary[String, BossUpgradeItem]` keyed by `upgrade_id`

### Trap (`TrapItem`)
- **Owner**: `scripts/items/Trap.gd`
- **Schema**:
  - `id: String`
  - `display_name: String`
  - `icon: Texture2D`
  - `proc_chance: float` \([0..1] recommended)\)
  - `damage: int` \(>= 0\)
  - `hits_all: bool`
- **Runtime use**: `TrapSystem.on_room_enter(...)` processes each installed trap; rolls proc; applies damage to one target or all targets in the room.

### Monster (`MonsterItem`)
- **Owner**: `scripts/items/Monster.gd`
- **Schema**:
  - `id: String`
  - `display_name: String`
  - `icon: Texture2D`
  - `threat_profile: ThreatProfile`
  - `max_hp: int`
  - `attack_damage: int`
  - `attack_interval: float`
  - `range: float` (px/world distance)
  - `size: float` (room capacity + spawn scaling)

### Treasure (`TreasureItem`)
- **Owner**: `scripts/items/Treasure.gd`
- **Schema**:
  - `id: String`
  - `display_name: String`
  - `icon: Texture2D`
  - `class_id: String` (optional; `""` = generic)

### Boss upgrade (`BossUpgradeItem`)
- **Owner**: `scripts/items/BossUpgradeItem.gd`
- **Schema**:
  - `upgrade_id: String` (primary id)
  - `display_name: String`
  - `icon: Texture2D`
  - `effect_id: String` (dispatch key used by boss upgrade application)
  - `value: float`
  - Optional extra tunables: `chance`, `cooldown_s`, `range_px`, `delay_s`
 - **Runtime effects (current implementation)**:
   - Template-level (applied before spawning the boss): damage, health, attack speed multiplier
   - Instance-level (boss-only): armor (damage block), reflect damage, double strike (chance + delay), glop (damage + cooldown + range)

### Adventurer class (`AdventurerClass`)
- **Owner**: `scripts/classes/AdventurerClass.gd`
- **Schema**:
  - `id: String`
  - `display_name: String`
  - `icon: Texture2D`
  - `threat_profile: ThreatProfile`
  - `hp_max: int`
  - `attack_damage: int`
  - `attack_interval: float`
  - `range: float`
  - Stats: `intelligence:int`, `strength:int`, `agility:int`

### Ability (`Ability`)
- **Owner**: `scripts/resources/Ability.gd` (resources under `res://assets/abilities/*.tres`)
- **Schema**:
  - `ability_id: String`
  - `trigger_name: String` (string enum; e.g. `WhenDamaged`, `LootGathered`, `WhenAttack`, …)
  - `cooldown_s: float` (0 = no wait; -1 = single-use/day regardless of charges)
  - `charges_per_day: int`
  - `s_delta: int` (strength budget contribution)
  - `params: Dictionary` (effect-specific)
  - `cast_time_s: float` (delay before effect fires)
- **Runtime semantics**:
  - Charges are consumed on trigger; cooldown/next-ready includes cast time.
  - Some abilities implement gameplay effects today (heal, AoE damage, stun, etc.) and also spawn FX (rings/pulses/bursts).

## Party/day generation contract

### Party generation result (`PartyGenerator.generate_parties`)
- **Owner**: `scripts/services/PartyGenerator.gd`
- **Schema**:
  - `day_seed: int`
  - `party_defs: Array[Dictionary]` where each party is `{ party_id:int, member_ids:Array[int] }`
  - `member_defs: Dictionary[int, Dictionary]` mapping `member_id -> member_def`

### `member_def` schema (minimum)
- **Owner**: `PartyGenerator` (created), `HistoryService` (enriched), `Simulation` (consumed)
- **Fields**:
  - `member_id: int`
  - `party_id: int`
  - `class_id: String`
  - `morality: int` in \([-5, +5]\)
  - `goal_weights: Dictionary` (goal_id -> int)
  - `goal_params: Dictionary` (goal_id -> Dictionary)
  - `stolen_inv_cap: int`
  - `stat_mods: Dictionary` (currently `hp_bonus:int`, `dmg_bonus:int`)
  - `base_stats: Dictionary` (currently `intelligence:int`, `strength:int`, `agility:int`)
  - `traits: Array[String]`
  - `ability_id: String`
  - `ability_charges: int`
  - `s_contrib: int`
  - Identity fields (injected by `HistoryService.attach_profiles_for_new_members`):
    - `profile_id: int`, `name: String`, `epithet: String`, `origin: String`, `bio: String`

## Runtime entities (DAY)

### Adventurer actor (`Adventurer`)
- **Owner**: scene `res://scenes/Adventurer.tscn` script `scripts/Adventurer.gd`
- **Schema (key runtime fields)**:
  - Identity: `class_id:String`, `party_id:int`
  - Combat: `hp:int`, `hp_max:int`, `attack_damage:int`, `attack_interval:float`, `range:float`, `armor:int`
  - Stats: `intelligence:int`, `strength:int`, `agility:int`
  - Flow: `phase:int` (`SURFACE|DUNGEON|DONE`), `in_combat:bool`, `combat_room_id:int`
- **Signals**: `died(world_pos, class_id)`, `damaged(amount)`, `cell_reached(cell)`, `right_clicked(adv_id, screen_pos)`

### Monster runtime (`MonsterInstance`)
- **Owner**: `scripts/systems/MonsterInstance.gd` (created/owned by `Simulation` + combat system)
- **Schema**:
  - Identity: `instance_id:int`, `template_id:String`
  - Placement: `spawn_room_id:int`, `current_room_id:int`
  - Combat: `hp:int`, `max_hp:int`, `attack_timer:float`
  - Links: `actor:Node2D`, `template:MonsterItem`
  - Boss runtime modifiers (default 0): `dmg_block:int`, `reflect_damage:int`, `double_strike_*`, `glop_*`

## Day event log (History) + filters

### `HistoryService` event record
- **Owner**: `autoloads/HistoryService.gd` (instantiated by `Simulation` and also by UI as a fallback)
- **Event schema**:
  - `day: int`
  - `type: String` (e.g. `day_change`, `spawned`, `exited`, `fled`, `returned`, `died`, `loot_gained`, `dialogue`)
  - `payload: Dictionary` (type-specific; commonly contains `profile_id:int`, plus `text`, `where`, `tags`, etc.)

### Filters contract (`HistoryService.get_events(filter)`)
- **Filter schema** (all optional):
  - `types: Array[String]`
  - `day_min: int`
  - `day_max: int`
  - `profile_id: int`
  - `tags: Array` (must all be present)
  - `text_contains: String` (case-insensitive substring)
- **Invariant**: passing `{}` means “no filter” (return all, capped by history ring buffer).

### UI surface (“Day Event Log”)
- **Owner**: `ui/TownHistoryPanel.gd` (toggled via HUD button / Town icon / `H` key)
- **Data source**:
  - Preferred: `Simulation.get_history_events()`
  - Fallback: `HistoryService.get_events({})`
- **Formatting**: uses `HistoryService.format_event(e)` to get player-facing strings.
 - **Current panel behavior**: UI currently renders the full unfiltered list (`get_events({})`); the filtering contract exists for richer UI.

## Tooltips / inspect panels

### Adventurer tooltip data
- **Owner**: `autoloads/Simulation.gd` (UI reads via `get_adv_tooltip_data(adv_id)`)
- **Returned dictionary (UI-facing)** includes (when available):
  - Combat stats: `class_id`, `party_id`, `party_size`, `hp`, `hp_max`, `attack_damage`
  - Stats: `intelligence`, `strength`, `agility`
  - Identity: `name`, `epithet`, `origin`, `bio`
  - Behavior: `morality_label`, `top_goals`, `traits`, `traits_pretty`
  - Ability (nested): `ability.{id,name,trigger,cooldown_s,cast_time_s,charges_per_day,charges_left,summary}`
- **BUILD preview**: when in BUILD, tooltip identity/goals come from `SurfacePreviewSystem`’s cached generation instead of the live party brain.

### Room/slot inspect (Room popup)
- **Owner**: `ui/room_popup.gd`
- **Data source**:
  - Room instance: `DungeonGrid.get_room_by_id(room_id)` (includes `slots[]`)
  - Room label: `RoomDB.get_room_type(type_id)`
  - Item details: `ItemDB.get_any_item(item_id)` → `{display_name, icon, stats}`
- **Slot stats formatting** (player-facing):
  - Monsters: DMG/APS/RNG/HP/SZ
  - Traps: DMG/PROC%/AOE

### Hover tooltips (Shop slots)
- **Owner**: `ui/ShopItemSlot.gd`
- **Contract**: emits `hover_entered(slot, offer, screen_pos)` / `hover_exited()`; a higher-level Shop UI decides how to render the tooltip.

## Shop (offers, currency, and animations)

### Offer schema (`config_shop`)
- **Owner**: `autoloads/config_shop.gd`
- **Offer dictionary**:
  - `id: String` (unique config id)
  - `kind: "item" | "room"`
  - `target_id: String` (`PlayerInventory` item id or `RoomInventory` room type id)
  - `cost: Dictionary[String,int]` mapping treasure item id → amount
- **Roll contract**: `roll_shop_offers(rng, slot_count)` returns `Array[Dictionary]`

### Shop state + UX
- **Owner**: `ui/Shop.gd`
- **Seed contract**:
  - `Simulation` exposes a deterministic `shop_seed` derived from the day seed.
  - HUD opens shop via `Shop.open_with_seed(shop_seed)`.
- **Purchase contract**:
  - Afford check reads `PlayerInventory.get_count(treasure_id)`.
  - Spending consumes via `PlayerInventory.consume(treasure_id, amount)`.
  - Grant refunds into inventories (`PlayerInventory.refund(...)` or `RoomInventory.refund(...)`).
  - UI fly-to-inventory animation targets `RoomInventoryPanel.get_collect_target_global_pos(tab_id)`.

## Combat targeting (Threat)

### Threat tracking
- **Owner**: `scripts/systems/ThreatSystem.gd`
- **Schema**:
  - `_threat: Dictionary` keyed as `room_id -> monster_key -> adv_id -> threat(float)`
- **Rules**:
  - Threat on damage: `threat += damage * THREAT_PER_DAMAGE`
  - Threat decay: exponential toward 0 using `THREAT_DECAY_PER_SECOND`
  - Target choice: combined score of threat and distance using optional `ThreatProfile` weights

## Build-phase dungeon validity panel (live)

### Connectivity/setup issues
- **Owner**: `scripts/services/DungeonSetupStatusService.gd`
- **API**: `get_setup_issues(dungeon_grid) -> Array[String]`
- **Issues currently reported**:
  - Entrance missing
  - Boss missing
  - Boss not connected to Entrance
  - Treasure not connected to Entrance (only if treasure exists)

### UI presentation
- **Owner**: `ui/HUD.gd` + `ui/SetupWarningPopup.gd`
- **Behavior**:
  - Recomputed on `DungeonGrid.layout_changed` and on phase changes.
  - Hidden during DAY; shown during BUILD when issues exist.
  - Hover opens `SetupWarningPopup` via `set_text(text)` + `open_at(anchor_rect)`.

### Placement “why not” hint (live)
- **Owner**: `scripts/DungeonView.gd` → emits `preview_reason_changed(text, ok)` which HUD displays near the cursor.
- **Reasons**: overlap, out of bounds, not enough power, unique-room already placed.

