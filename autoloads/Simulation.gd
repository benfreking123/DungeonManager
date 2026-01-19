extends Node

# DAY simulation (scalable MVP):
# - Spawns adventurers in town, walks to entrance, then follows dungeon path
# - On room entry: traps can fire; monster rooms create per-room encounters
# - Encounters handle spawning and lock-room combat; new adventurers join immediately

signal day_started()
signal day_ended()
signal combat_started(room_id: int)
signal combat_ended(room_id: int)
signal adventurer_right_clicked(adv_id: int, screen_pos: Vector2)

const SURFACE_SPEED := 64.0
const DUNGEON_SPEED := 52.0
const SPAWN_SECONDS_PER_SIZE := 5.0
const PARTY_SPAWN_INTERVAL := 0.1

# Render above the grid paper/lines (which live under WorldCanvas/Grid with z_index=1).
const ACTOR_Z_INDEX := 5

var _town_view: Control
var _dungeon_view: Control
var _world_canvas: CanvasItem

var _active: bool = false
var _adventurers: Array[Node2D] = []
var _tracked_adv: Dictionary = {} # adv_id -> true
var _alive_adv_count: int = 0

var _dungeon_grid: Node
var _room_db: Node
var _item_db: Node

# adv_instance_id -> last room id (0 if none)
var _adv_last_room: Dictionary = {}

# room_id -> spawner record dict (runs from day start, fills to capacity)
# Record shape:
# {
#   room_id: int,
#   capacity: int,
#   spawners: Array[Dictionary] (each { monster_item_id: String, spawn_timer: float }),
#   spawn_disabled?: bool
# }
var room_spawners_by_room_id: Dictionary = {}

var _combat: RefCounted

signal boss_killed()

var _monster_scene: PackedScene = preload("res://scenes/MonsterActor.tscn")

const COLLISION_RADIUS_ADV := 2.5
const COLLISION_RADIUS_MON := 3.25
const COLLISION_RADIUS_BOSS := 4.5
const COLLISION_ITERATIONS := 1

# AI/path + party/adventure systems
var _party_ai: PartyAI
var _path_service: PathService

var _strength_service: StrengthService
var _party_gen: PartyGenerator
var _fog: FogOfWarService
var _steal: TreasureStealService
var _party_adv: PartyAdventureSystem
var _bubble_service: DialogueBubbleService

# adv_instance_id -> last reached cell (for retargeting / resume)
var _adv_last_cell: Dictionary = {}
# adv_instance_id -> was_in_combat last tick
var _adv_was_in_combat: Dictionary = {}

# Spawn queue (spawn members one by one in town)
# Each entry: { member_id:int, party_id:int, class_id:String, idx_in_party:int }
var _spawn_queue: Array[Dictionary] = []
var _party_spawn_timer: float = 0.0
var _party_spawn_index: int = 0
var _party_spawn_ctx: Dictionary = {}

var _adv_scene: PackedScene = preload("res://scenes/Adventurer.tscn")

var _loot_system: RefCounted
var _trap_system: RefCounted
var _room_inventory_panel: Node
var _ending_day: bool = false
var _monster_roster: RefCounted

var _last_day_seed: int = 0
var _shop_seed: int = 0
var _end_day_reason: String = "success" # "success" or "loss"


func set_views(town_view: Control, dungeon_view: Control) -> void:
	_town_view = town_view
	_dungeon_view = dungeon_view
	# Use the shared WorldCanvas (parent of Town and Grid) as the simulation space.
	# This keeps pan/zoom purely aesthetic: zoom scales WorldCanvas, but local positions remain stable.
	var wc: Node = null
	if _town_view != null and _town_view.get_parent() != null:
		wc = _town_view.get_parent().get_parent()
	if wc == null and _dungeon_view != null and _dungeon_view.get_parent() != null:
		wc = _dungeon_view.get_parent().get_parent()
	_world_canvas = wc as CanvasItem
	_dungeon_grid = get_node_or_null("/root/DungeonGrid")
	_room_db = get_node_or_null("/root/RoomDB")
	_item_db = get_node_or_null("/root/ItemDB")
	_room_inventory_panel = _find_room_inventory_panel()

	# Runtime monsters live in a roster (separate from spawners/templates).
	# Must be created BEFORE combat setup so combat can query current monsters.
	_monster_roster = preload("res://scripts/systems/MonsterRoster.gd").new()

	_combat = preload("res://autoloads/Simulation_Combat.gd").new()
	_combat.call("setup", _dungeon_view, _dungeon_grid, self, _monster_roster)
	# Initialize AI services
	_path_service = preload("res://scripts/nav/PathService.gd").new()
	_path_service.setup(_dungeon_grid)
	_party_ai = preload("res://scripts/ai/PartyAI.gd").new()
	_party_ai.setup(_dungeon_grid, _path_service)

	_strength_service = preload("res://scripts/services/StrengthService.gd").new()
	_party_gen = preload("res://scripts/services/PartyGenerator.gd").new()
	_fog = preload("res://scripts/services/FogOfWarService.gd").new()
	_fog.setup(_dungeon_grid)
	_steal = preload("res://scripts/services/TreasureStealService.gd").new()
	_party_adv = preload("res://scripts/services/PartyAdventureSystem.gd").new()
	_bubble_service = preload("res://scripts/services/DialogueBubbleService.gd").new()

	# Loot system (separate file): spawns on-ground treasure drops and collects at day end.
	_loot_system = preload("res://scripts/systems/LootDropSystem.gd").new()
	_loot_system.call("setup", _world_canvas, _item_db, get_node_or_null("/root/game_config"))

	# Trap system: handles trap room entry effects.
	_trap_system = preload("res://scripts/systems/TrapSystem.gd").new()
	_trap_system.call("setup", _item_db)

	# Wire boss killed event into party logic once.
	var cb := Callable(self, "_on_boss_killed")
	if not boss_killed.is_connected(cb):
		boss_killed.connect(cb)


func start_day() -> void:
	if _active:
		return
	_ending_day = false
	# Require a valid layout (entrance->boss path).
	if _dungeon_grid != null:
		var req: Dictionary = _dungeon_grid.call("validate_required_paths") as Dictionary
		if not bool(req.get("ok", true)):
			DbgLog.log("Start day blocked: %s" % String(req.get("reason", "invalid_layout")), "game_state")
			return
		# Require a boss room to exist.
		var boss_room: Dictionary = _dungeon_grid.call("get_first_room_of_kind", "boss") as Dictionary
		if boss_room.is_empty():
			DbgLog.log("Start day blocked: missing boss room", "game_state")
			return
	_active = true
	GameState.set_phase(GameState.Phase.DAY)
	day_started.emit()
	_adv_last_room.clear()
	_adv_last_cell.clear()
	_adv_was_in_combat.clear()
	room_spawners_by_room_id.clear()
	if _monster_roster != null:
		_monster_roster.call("reset")
	if _combat != null:
		_combat.call("reset")
	if _dungeon_grid != null:
		_dungeon_grid.call("ensure_room_defaults")
		if _fog != null:
			_fog.reset_for_new_day()
		_init_room_spawners()
		_spawn_boss()
	# Generate parties/members for the day (Strength-scaled).
	var cfg := get_node_or_null("/root/game_config")
	var goals_cfg := get_node_or_null("/root/config_goals")
	if goals_cfg == null:
		goals_cfg = preload("res://autoloads/config_goals.gd").new()
	var strength_s := 0
	if _strength_service != null:
		var day_idx := 1
		if GameState != null and "day_index" in GameState:
			day_idx = int(GameState.get("day_index"))
		if _strength_service.has_method("compute_strength_s_for_day"):
			strength_s = int(_strength_service.call("compute_strength_s_for_day", day_idx, cfg))
	var day_seed := int(Time.get_ticks_usec()) ^ (strength_s * 1103515245)
	var gen := {}
	if _party_gen != null:
		# Determine A (adventurers to spawn today). Default from S if not provided elsewhere.
		var A_default := clampi(int(round(float(strength_s) / 3.0)), 4, 50)
		gen = _party_gen.generate_parties(strength_s, cfg, goals_cfg, day_seed, A_default)
		_log_party_generation(strength_s, gen, A_default, day_seed)
	_last_day_seed = int(gen.get("day_seed", day_seed))
	if _party_adv != null:
		_party_adv.setup(_dungeon_grid, _item_db, cfg, goals_cfg, _fog, _steal, _last_day_seed)
		_party_adv.init_from_generated(gen)
	var di := 1
	if GameState != null and "day_index" in GameState:
		di = int(GameState.get("day_index"))
	DbgLog.info("Day start: Day=%d StrengthS=%d seed=%d" % [di, strength_s, _last_day_seed], "game_state")
	_begin_party_spawn(gen)
	if _loot_system != null:
		_loot_system.call("reset")
	if _trap_system != null:
		_trap_system.call("reset")


func end_day(reason: String = "success") -> void:
	if _ending_day:
		return
	_ending_day = true
	_end_day_reason = String(reason)
	_active = false
	_spawn_queue.clear()
	_party_spawn_ctx.clear()

	# Derive a deterministic shop seed from the day seed.
	# (Only used if this day ends in success and transitions into SHOP.)
	_shop_seed = int(_last_day_seed) ^ 0x9E3779B9

	# Collect ground loot (animate to Treasure tab) before final cleanup.
	var target := _loot_collect_target_world_pos()
	var has_loot := (_loot_system != null and bool(_loot_system.call("has_loot")))
	var waiting_for_loot := (_end_day_reason != "loss" and has_loot and target != Vector2.ZERO)
	DbgLog.info(
		"Day end requested reason=%s has_loot=%s target_ok=%s waiting_for_loot=%s" % [
			_end_day_reason,
			str(has_loot),
			str(target != Vector2.ZERO),
			str(waiting_for_loot),
		],
		"game_state"
	)
	if waiting_for_loot:
		_loot_system.call("collect_all_to", target, Callable(self, "_finish_end_day_cleanup"))
		# Failsafe: if loot callback never arrives, don't remain stuck in DAY.
		var timer := get_tree().create_timer(3.0)
		timer.timeout.connect(func():
			if _ending_day and GameState != null and int(GameState.phase) == int(GameState.Phase.DAY):
				DbgLog.warn("End-day failsafe triggered: forcing cleanup", "game_state")
				_finish_end_day_cleanup()
		)
	else:
		_finish_end_day_cleanup()


func _finish_end_day_cleanup() -> void:
	# Guard against duplicate callbacks (e.g. failsafe timeout + late loot callback).
	if not _ending_day:
		return
	for a in _adventurers:
		if is_instance_valid(a):
			a.queue_free()
	_adventurers.clear()
	_tracked_adv.clear()
	_alive_adv_count = 0
	_adv_last_room.clear()
	_adv_last_cell.clear()
	_adv_was_in_combat.clear()
	_clear_all_monster_actors()
	room_spawners_by_room_id.clear()
	if _combat != null:
		_combat.call("reset")
	if _monster_roster != null:
		_monster_roster.call("reset")
	if _end_day_reason == "loss":
		DbgLog.info("Day ended: LOSS (boss dead)", "game_state")
		GameState.set_phase(GameState.Phase.RESULTS)
	else:
		DbgLog.info("Day ended: CLEAR -> SHOP", "game_state")
		GameState.set_phase(GameState.Phase.SHOP)
	day_ended.emit()
	_ending_day = false


func get_shop_seed() -> int:
	return int(_shop_seed)


func _process(delta: float) -> void:
	if not _active:
		return
	var dt: float = delta * GameState.speed

	_tick_party_spawn(dt)
	_tick_spawners(dt)
	if _combat != null:
		_combat.call("tick", dt, room_spawners_by_room_id)

	var alive: Array[Node2D] = []
	for a in _adventurers:
		if is_instance_valid(a):
			var aid: int = int(a.get_instance_id())
			var now_in_combat: bool = bool(a.get("in_combat"))
			var was_in_combat: bool = bool(_adv_was_in_combat.get(aid, false))
			_adv_was_in_combat[aid] = now_in_combat

			# Failsafe: if an adventurer still thinks it's in combat, but the combat record is gone,
			# force-exit combat so they can resume pathing.
			if now_in_combat and _combat != null:
				var rid: int = int(a.get("combat_room_id"))
				if rid != 0 and not bool(_combat.call("is_room_in_combat", rid)):
					DbgLog.log("Forcing exit_combat (stale) adv=%d room_id=%d" % [aid, rid], "adventurers")
					a.call("exit_combat")
					now_in_combat = false
					_adv_was_in_combat[aid] = false

			# If combat just ended, immediately retarget so parties keep exploring.
			if was_in_combat and not now_in_combat:
				_on_party_combat_ended(aid)

			a.call("tick", dt)
			alive.append(a)
	_adventurers = alive

	# Diagnostics: if we're close to ending but not ending, show what's left.
	if _active and not _ending_day and _alive_adv_count > 0 and _alive_adv_count <= 3:
		var parts: Array[String] = []
		for a2 in _adventurers:
			if a2 == null or not is_instance_valid(a2):
				continue
			var aid2 := int(a2.get_instance_id())
			parts.append("adv=%d hp=%d/%d in_combat=%s room=%d phase=%s" % [
				aid2,
				int(a2.get("hp")),
				int(a2.get("hp_max")),
				str(bool(a2.get("in_combat"))),
				int(a2.get("combat_room_id")),
				str(int(a2.get("phase"))),
			])
		DbgLog.throttle(
			"adv_low_count",
			1.0,
			"Adv remaining (%d): %s" % [_alive_adv_count, " | ".join(parts)],
			"adventurers",
			DbgLog.Level.DEBUG
		)

	# Authoritative day-end trigger: all adventurers gone.
	if _alive_adv_count <= 0 and not _ending_day:
		end_day()
		return

	# Regroup check: keep party cohesive by forcing stragglers to path to the party goal cell.
	_tick_party_regroup()

	_resolve_soft_collisions()

	# (Removed) redundant empty-array day-end; `_alive_adv_count` owns this now.


func _begin_party_spawn(gen: Dictionary) -> void:
	if _town_view == null or _dungeon_view == null:
		end_day()
		return
	if _dungeon_grid == null:
		end_day()
		return

	var entrance: Dictionary = _dungeon_grid.call("get_first_room_of_kind", "entrance") as Dictionary
	if entrance.is_empty():
		end_day()
		return

	var start_cell: Vector2i = entrance.get("pos", Vector2i.ZERO)

	var spawn_world := _town_view.call("get_spawn_world_pos") as Vector2
	var entrance_world := _dungeon_view.call("entrance_surface_world_pos") as Vector2

	_party_spawn_ctx = {
		"spawn_world": spawn_world,
		"entrance_world": entrance_world,
		"start_cell": start_cell,
		"paths_by_party_id": {},
	}

	_spawn_queue.clear()

	var member_defs: Dictionary = gen.get("member_defs", {}) as Dictionary
	var party_defs: Array = gen.get("party_defs", []) as Array
	var paths_by_party_id: Dictionary = {}

	for p0 in party_defs:
		var pd := p0 as Dictionary
		var pid := int(pd.get("party_id", 0))
		if pid == 0:
			continue
		var goal: Vector2i = start_cell
		if _party_adv != null:
			goal = _party_adv.party_goal_cell(pid, start_cell)
		if _party_ai != null:
			_party_ai.set_goal(pid, goal)
		var path: Array[Vector2i] = []
		if _path_service != null:
			path = _path_service.path(start_cell, goal, true)
		paths_by_party_id[pid] = path

		var mids: Array = pd.get("member_ids", []) as Array
		for i in range(mids.size()):
			var mid := int(mids[i])
			var md: Dictionary = member_defs.get(mid, {}) as Dictionary
			if md.is_empty():
				continue
			_spawn_queue.append({
				"member_id": mid,
				"party_id": pid,
				"class_id": String(md.get("class_id", "")),
				"idx_in_party": i,
			})

	_party_spawn_ctx["paths_by_party_id"] = paths_by_party_id
	_party_spawn_timer = 0.0
	_party_spawn_index = 0


func _tick_party_spawn(dt: float) -> void:
	if _spawn_queue.is_empty():
		return
	_party_spawn_timer -= dt
	while _party_spawn_timer <= 0.0 and not _spawn_queue.is_empty():
		var entry: Dictionary = _spawn_queue.pop_front()
		_spawn_one_party_member(entry, _party_spawn_index)
		_party_spawn_index += 1
		_party_spawn_timer += PARTY_SPAWN_INTERVAL


func _spawn_one_party_member(entry: Dictionary, idx: int) -> void:
	if _town_view == null or _dungeon_view == null or _dungeon_grid == null:
		return
	if _party_spawn_ctx.is_empty():
		return

	var member_id: int = int(entry.get("member_id", 0))
	var party_id: int = int(entry.get("party_id", 0))
	var class_id: String = String(entry.get("class_id", ""))
	var idx_in_party: int = int(entry.get("idx_in_party", idx))

	var spawn_world: Vector2 = _party_spawn_ctx.get("spawn_world", Vector2.ZERO)
	var entrance_world: Vector2 = _party_spawn_ctx.get("entrance_world", Vector2.ZERO)
	var paths_by_party_id: Dictionary = _party_spawn_ctx.get("paths_by_party_id", {}) as Dictionary
	var path: Array[Vector2i] = paths_by_party_id.get(party_id, []) as Array[Vector2i]

	var adv := _adv_scene.instantiate() as Node2D
	if _world_canvas != null:
		_world_canvas.add_child(adv)
	else:
		_town_view.add_child(adv)
	adv.z_index = ACTOR_Z_INDEX
	adv.z_as_relative = false
	# Spawn as a tight cluster on the ground with a tiny scatter (2–4px) so they read as one party.
	var scatter := [
		Vector2(0, 0),
		Vector2(3, -1),
		Vector2(-2, 2),
		Vector2(2, 3),
	]
	var party_offset := Vector2(float((party_id - 1) * 18), float(((party_id - 1) % 3) * 12))
	if _world_canvas != null:
		var inv_wc: Transform2D = _world_canvas.get_global_transform().affine_inverse()
		adv.position = (inv_wc * spawn_world) + party_offset + scatter[idx_in_party % scatter.size()]
	else:
		adv.position = _town_view.get_global_transform().affine_inverse() * (spawn_world + party_offset + scatter[idx_in_party % scatter.size()])

	var cls_res: Resource = null
	if _item_db != null:
		cls_res = _item_db.call("get_adv_class", class_id) as Resource
	adv.call("apply_class", cls_res)

	# Register with party/adventure system (assigns party_id and applies stat mods).
	if _party_adv != null:
		_party_adv.register_adventurer(adv, member_id)
		_drain_party_bubble_events()

	adv.set_meta("collision_radius", COLLISION_RADIUS_ADV)
	# Store the surface target in WorldCanvas-local space so camera transforms don't affect movement.
	if _world_canvas != null:
		var inv_wc2: Transform2D = _world_canvas.get_global_transform().affine_inverse()
		adv.call("set_surface_target_local", inv_wc2 * entrance_world, SURFACE_SPEED)
	else:
		adv.call("set_surface_target", entrance_world, SURFACE_SPEED)
	adv.call("set_dungeon_targets", _dungeon_view, path, DUNGEON_SPEED)
	adv.call("set_on_reach_goal", Callable(self, "_on_adventurer_finished").bind(adv))
	adv.connect("cell_reached", Callable(self, "_on_adventurer_cell_reached").bind(adv))
	if adv.has_signal("damaged"):
		adv.connect("damaged", Callable(self, "_on_adventurer_damaged").bind(int(adv.get_instance_id())))
	if adv.has_signal("died"):
		adv.connect("died", Callable(self, "_on_adventurer_died").bind(int(adv.get_instance_id())))
	if adv.has_signal("right_clicked"):
		adv.connect("right_clicked", Callable(self, "_on_adventurer_right_clicked"))
	_adventurers.append(adv)
	_track_adv(adv)
	_adv_was_in_combat[int(adv.get_instance_id())] = false


func _on_adventurer_right_clicked(adv_id: int, screen_pos: Vector2) -> void:
	# Adventurers only exist during DAY, but keep this safe.
	if GameState != null and GameState.phase != GameState.Phase.DAY:
		return
	adventurer_right_clicked.emit(int(adv_id), screen_pos)


func get_adv_tooltip_data(adv_id: int) -> Dictionary:
	# Convenience for UI: merge actor runtime stats with PartyAdventureSystem tooltip fields.
	var out: Dictionary = {}
	var adv := _find_adv_by_id(int(adv_id))
	if adv == null:
		return {}
	out["class_id"] = String(adv.get("class_id"))
	out["party_id"] = int(adv.get("party_id"))
	out["hp"] = int(adv.get("hp"))
	out["hp_max"] = int(adv.get("hp_max"))
	out["attack_damage"] = int(adv.get("attack_damage"))
	if _party_adv != null and _party_adv.has_method("get_adv_tooltip"):
		var t: Dictionary = _party_adv.call("get_adv_tooltip", int(adv_id)) as Dictionary
		for k in t.keys():
			out[k] = t.get(k)
	return out


func find_adventurer_at_screen_pos(screen_pos: Vector2, radius_px: float = 16.0) -> int:
	# Robust hit-test for UI-driven clicks (avoids Control mouse capture blocking Area2D input).
	# `screen_pos` is viewport mouse position (same space as CanvasItem global_position).
	var best_id := 0
	var best_d2 := 0.0
	var r := maxf(0.0, float(radius_px))
	var r2 := r * r
	for a in _adventurers:
		if a == null or not is_instance_valid(a):
			continue
		var d2 := a.global_position.distance_squared_to(screen_pos)
		if d2 <= r2 and (best_id == 0 or d2 < best_d2):
			best_id = int(a.get_instance_id())
			best_d2 = d2
	return best_id


func _on_adventurer_died(world_pos: Vector2, class_id: String, adv_id: int) -> void:
	var entered_dungeon := int(_adv_last_room.get(adv_id, 0)) != 0
	# Only drop loot if the adventurer has entered the dungeon (has a non-zero last room).
	if entered_dungeon and _loot_system != null:
		_loot_system.call("on_adventurer_died", world_pos, class_id)
	# Always clear party system state; only spawn forced drops if they died in-dungeon.
	if _party_adv != null:
		var stolen: Array[String] = _party_adv.on_adv_died(int(adv_id))
		if entered_dungeon and _loot_system != null:
			for tid in stolen:
				_loot_system.call("spawn_treasure_drop", world_pos, String(tid))
	_remove_adv_from_tracking(int(adv_id))


func _find_room_inventory_panel() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.find_child("RoomInventoryPanel", true, false)


func _track_adv(adv: Node2D) -> void:
	if adv == null or not is_instance_valid(adv):
		return
	var aid := int(adv.get_instance_id())
	if aid == 0:
		return
	if bool(_tracked_adv.get(aid, false)):
		return
	_tracked_adv[aid] = true
	_alive_adv_count += 1
	# Safety net: if freed without explicit death/exit path, decrement.
	if not adv.tree_exited.is_connected(Callable(self, "_on_adv_tree_exited").bind(aid)):
		adv.tree_exited.connect(Callable(self, "_on_adv_tree_exited").bind(aid))


func _on_adv_tree_exited(aid: int) -> void:
	_remove_adv_from_tracking(int(aid))


func _remove_adv_from_tracking(adv_id: int) -> void:
	var aid := int(adv_id)
	if aid == 0:
		return
	if not bool(_tracked_adv.get(aid, false)):
		return
	_tracked_adv.erase(aid)
	_alive_adv_count = maxi(0, _alive_adv_count - 1)
	_adv_last_room.erase(aid)
	_adv_last_cell.erase(aid)
	_adv_was_in_combat.erase(aid)
	# Remove from list immediately so `find_adventurer_at_screen_pos` doesn't hit dead refs.
	var next: Array[Node2D] = []
	for a in _adventurers:
		if is_instance_valid(a) and int(a.get_instance_id()) != aid:
			next.append(a)
	_adventurers = next


func _loot_collect_target_world_pos() -> Vector2:
	if _room_inventory_panel == null:
		_room_inventory_panel = _find_room_inventory_panel()
	if _room_inventory_panel != null and _room_inventory_panel.has_method("get_treasure_collect_target_global_pos"):
		var v: Variant = _room_inventory_panel.call("get_treasure_collect_target_global_pos")
		if v is Vector2:
			return v
	return Vector2.ZERO


func _on_adventurer_finished(adv: Node2D) -> void:
	# End-of-path: pick a new goal and continue exploring.
	# (Day ends when all adventurers are gone.)
	# We rely on last reached cell for retargeting.
	if not _active or _dungeon_grid == null:
		return
	if not is_instance_valid(adv):
		return
	var aid: int = int(adv.get_instance_id())
	var from_cell: Vector2i = _adv_last_cell.get(aid, Vector2i(-1, -1))
	if from_cell == Vector2i(-1, -1):
		return
	var pid := int(adv.get("party_id"))
	_retarget_party(pid, from_cell)


func _on_adventurer_damaged(_amount: int, adv_id: int) -> void:
	# Route damage events into the party/adventure system (flee rules, morale, etc.)
	if _party_adv != null:
		var adv := _find_adv_by_id(int(adv_id))
		if adv != null:
			_party_adv.on_adv_damaged(int(adv_id), int(adv.get("hp")), int(adv.get("hp_max")))
		else:
			_party_adv.on_adv_damaged(int(adv_id))
		_drain_party_bubble_events()


func _on_boss_killed() -> void:
	if _party_adv != null:
		_party_adv.on_boss_killed()
	DbgLog.info("Boss killed", "game_state")
	# Loss condition: boss died. End the day as a loss (no shop).
	if _active and not _ending_day:
		end_day("loss")


func _on_monster_room_cleared(_room_id: int, adv_ids: Array[int], killed: int) -> void:
	if _party_adv != null:
		_party_adv.on_monster_room_cleared(adv_ids, int(killed))


func _retarget_party(party_id: int, from_cell: Vector2i) -> void:
	if not _active or _dungeon_grid == null:
		return
	if _party_adv == null or _path_service == null or _party_ai == null:
		return

	# Sync party ids onto actors (micro-party splits update brains first).
	for a0 in _adventurers:
		if not is_instance_valid(a0):
			continue
		var aid0 := int(a0.get_instance_id())
		var pid0 := _party_adv.party_id_for_adv(aid0)
		if pid0 != 0:
			a0.set("party_id", pid0)

	# Retarget the requested party, and any newly created parties that don't yet have a goal.
	var parties_to_retarget: Dictionary = {}
	for a1 in _adventurers:
		if not is_instance_valid(a1):
			continue
		if bool(a1.get("in_combat")):
			continue
		var pid1 := int(a1.get("party_id"))
		if pid1 == 0:
			continue
		if not parties_to_retarget.has(pid1):
			var aid1 := int(a1.get_instance_id())
			parties_to_retarget[pid1] = _adv_last_cell.get(aid1, from_cell)

	for pid_key in parties_to_retarget.keys():
		var pid := int(pid_key)
		var existing_goal: Vector2i = _party_ai.get_current_goal(pid)
		if pid != int(party_id) and existing_goal != Vector2i(-1, -1):
			continue

		var base_cell: Vector2i = parties_to_retarget[pid_key]
		if base_cell == Vector2i(-1, -1):
			base_cell = from_cell

		var party_intent := _party_adv.party_intent(pid)
		var party_goal: Vector2i = _party_adv.party_goal_cell(pid, base_cell)
		_party_ai.set_goal(pid, party_goal)

		for a in _adventurers:
			if not is_instance_valid(a):
				continue
			if bool(a.get("in_combat")):
				continue
			if int(a.get("party_id")) != pid:
				continue
			var aid := int(a.get_instance_id())
			var cur_cell: Vector2i = _adv_last_cell.get(aid, base_cell)
			if cur_cell == Vector2i(-1, -1):
				cur_cell = base_cell
			var eff_intent := _party_adv.effective_intent_for_adv(aid, party_intent)
			var goal := party_goal if eff_intent == party_intent else _party_adv.goal_cell_for_intent(eff_intent, cur_cell)
			var p: Array[Vector2i] = _path_service.path(cur_cell, goal, true)
			a.call("set_path", p)
		_drain_party_bubble_events()


func _drain_party_bubble_events() -> void:
	if _party_adv == null or _bubble_service == null:
		return
	var events: Array = _party_adv.consume_bubble_events()
	if events.is_empty():
		return
	DbgLog.throttle(
		"bubble_events",
		0.75,
		"Bubble events consumed: %d" % events.size(),
		"ui",
		DbgLog.Level.DEBUG
	)
	for e0 in events:
		var e := e0 as Dictionary
		if e.is_empty():
			continue
		var t := String(e.get("type", ""))
		var text := String(e.get("text", ""))
		if text == "":
			continue
		if t == "party_intent":
			var leader := int(e.get("leader_adv_id", 0))
			var adv := _find_adv_by_id(leader)
			if adv != null:
				_bubble_service.show_for_actor(adv, text, "party_intent:%d" % int(e.get("party_id", 0)))
			else:
				DbgLog.throttle(
					"bubble_missing_leader:%d" % leader,
					1.0,
					"Bubble skipped: missing leader adv_id=%d party_id=%d" % [leader, int(e.get("party_id", 0))],
					"ui",
					DbgLog.Level.DEBUG
				)
		elif t == "defect":
			var adv2 := _find_adv_by_id(int(e.get("adv_id", 0)))
			if adv2 != null:
				_bubble_service.show_for_actor(adv2, text, "defect")
			else:
				DbgLog.throttle(
					"bubble_missing_defect:%d" % int(e.get("adv_id", 0)),
					1.0,
					"Bubble skipped: missing defector adv_id=%d" % int(e.get("adv_id", 0)),
					"ui",
					DbgLog.Level.DEBUG
				)
		elif t == "flee":
			var adv3 := _find_adv_by_id(int(e.get("adv_id", 0)))
			if adv3 != null:
				_bubble_service.show_for_actor(adv3, text, "flee")
			else:
				DbgLog.throttle(
					"bubble_missing_flee:%d" % int(e.get("adv_id", 0)),
					1.0,
					"Bubble skipped: missing flee adv_id=%d" % int(e.get("adv_id", 0)),
					"ui",
					DbgLog.Level.DEBUG
				)


func _log_party_generation(strength_s: int, gen: Dictionary, adventurers_used: int, day_seed: int) -> void:
	# Emit a summary and details for adventure/party generation.
	if not DbgLog.is_enabled("party_gen"):
		return
	var party_defs: Array = gen.get("party_defs", []) as Array
	var member_defs: Dictionary = gen.get("member_defs", {}) as Dictionary
	DbgLog.info(
		"PartyGen: S=%d A=%d parties=%d seed=%d" % [int(strength_s), int(adventurers_used), party_defs.size(), int(day_seed)],
		"party_gen"
	)
	for p0 in party_defs:
		var pd := p0 as Dictionary
		if pd.is_empty():
			continue
		var pid := int(pd.get("party_id", 0))
		var mids: Array = pd.get("member_ids", []) as Array
		var classes: Array[String] = []
		for m0 in mids:
			var mid := int(m0)
			var md: Dictionary = member_defs.get(mid, {}) as Dictionary
			var cls := String(md.get("class_id", ""))
			if cls != "":
				classes.append(cls)
		var classes_label := str(classes)
		DbgLog.debug("Party pid=%d size=%d classes=%s" % [pid, mids.size(), classes_label], "party_gen")


func _find_adv_by_id(adv_id: int) -> Node2D:
	if adv_id == 0:
		return null
	for a in _adventurers:
		if is_instance_valid(a) and int(a.get_instance_id()) == adv_id:
			return a
	return null


func _on_adventurer_cell_reached(cell: Vector2i, adv: Node2D) -> void:
	if not _active:
		return
	if _dungeon_grid == null:
		return
	if not is_instance_valid(adv):
		return

	var room: Dictionary = _dungeon_grid.call("get_room_at", cell) as Dictionary
	var room_id: int = int(room.get("id", 0))

	var adv_key: int = int(adv.get_instance_id())
	_adv_last_cell[adv_key] = cell
	var last_room_id: int = int(_adv_last_room.get(adv_key, 0))
	if room_id == 0:
		return
	var entered_new_room: bool = (room_id != last_room_id)
	if entered_new_room:
		_adv_last_room[adv_key] = room_id

	var kind: String = String(room.get("kind", ""))
	# Only fire room-entry effects when we actually enter a new room.
	if entered_new_room:
		if kind == "trap" or kind == "boss":
			if _trap_system != null:
				_trap_system.call("on_room_enter", room, adv, _adventurers, _adv_last_room)
		if kind == "monster" or kind == "boss":
			if _combat != null:
				_combat.call("join_room", room, adv)

	# Fog of war + stealing are room-entry events.
	var party_id: int = int(adv.get("party_id"))
	if entered_new_room:
		if _fog != null:
			_fog.reveal_on_enter(room_id)
		if _party_adv != null:
			var steal_evt: Dictionary = _party_adv.on_party_enter_room(party_id, room)
			if not steal_evt.is_empty() and DbgLog.is_enabled("theft"):
				var stolen: Array = steal_evt.get("stolen", [])
				if not stolen.is_empty():
					DbgLog.info("Theft room_id=%d party=%d stolen=%d" % [room_id, party_id, stolen.size()], "theft")

	# Exit handling: if an adventurer reaches entrance while intending to exit, remove them.
	if kind == "entrance" and _party_adv != null:
		var aid_exit := int(adv.get_instance_id())
		var intent := _party_adv.effective_intent_for_adv(aid_exit, _party_adv.party_intent(party_id))
		if intent == PartyAdventureSystem.INTENT_EXIT:
			_party_adv.on_adv_exited(aid_exit)
			_remove_adv_from_tracking(aid_exit)
			adv.queue_free()
			return

	# If in combat, don't retarget paths now.
	if bool(adv.get("in_combat")):
		return

	# Retarget when reaching the current party goal (or if none exists yet).
	var party_goal: Vector2i = _party_ai.get_current_goal(party_id)
	if party_goal == Vector2i(-1, -1) or cell == party_goal:
		_retarget_party(party_id, cell)


#


func _on_party_combat_ended(adv_id: int) -> void:
	# After combat ends, force a regroup step to the room anchor cell so units don't
	# get stuck at "formation" offsets or doorways. Once the party reaches the anchor,
	# normal goal logic will retarget to the next destination.
	if _dungeon_grid == null:
		return
	var adv: Node2D = null
	for a in _adventurers:
		if is_instance_valid(a) and int(a.get_instance_id()) == adv_id:
			adv = a
			break
	if adv == null:
		return
	var party_id: int = int(adv.get("party_id"))

	# Determine the room the party was in last, and a regroup target cell (room center).
	var room_id: int = int(_adv_last_room.get(adv_id, 0))
	var room: Dictionary = _dungeon_grid.call("get_room_by_id", room_id) as Dictionary
	var regroup: Vector2i = _party_ai.on_combat_ended(party_id, room, _adv_last_cell.get(adv_id, Vector2i(-1, -1)))
	if regroup == Vector2i(-1, -1):
		return

	DbgLog.log("Combat ended: party=%d regroup_to=%s" % [party_id, str(regroup)], "adventurers")

	for a2 in _adventurers:
		if not is_instance_valid(a2):
			continue
		if int(a2.get("party_id")) != party_id:
			continue
		if bool(a2.get("in_combat")):
			continue
		# Force a one-step path to the anchor; this will emit cell_reached when they arrive,
		# allowing the normal party-goal retarget to kick in reliably.
		var one_step: Array[Vector2i] = [regroup]
		a2.call("set_path", one_step)

func _tick_party_regroup() -> void:
	# Ask PartyAI for any path updates (regroup/leash) and apply them.
	# Only one party for now (id=1), but keep generic by discovering parties from members.
	var parties := {}
	for a in _adventurers:
		if not is_instance_valid(a):
			continue
		if bool(a.get("in_combat")):
			continue
		var pid := int(a.get("party_id"))
		var aid := int(a.get_instance_id())
		if not parties.has(pid):
			parties[pid] = {}
		parties[pid][aid] = _adv_last_cell.get(aid, Vector2i(-1, -1))
	for pid2 in parties.keys():
		var updates: Dictionary = _party_ai.tick_regroup_and_paths(int(pid2), parties[pid2])
		for k in updates.keys():
			var aid4: int = int(k)
			var p4: Array[Vector2i] = updates[k]
			for a4 in _adventurers:
				if is_instance_valid(a4) and int(a4.get_instance_id()) == aid4 and not bool(a4.get("in_combat")):
					a4.call("set_path", p4)


func _room_center_cell(room: Dictionary, fallback: Vector2i) -> Vector2i:
	if room.is_empty():
		return fallback
	var pos: Vector2i = room.get("pos", fallback)
	var size: Vector2i = room.get("size", Vector2i.ONE)
	return Vector2i(pos.x + int(size.x / 2), pos.y + int(size.y / 2))


func _make_spawner(room_id: int, monster_item_id: String, capacity: int, cooldown_per_size: float, minions_only: bool = false) -> Dictionary:
	return {
		"room_id": room_id,
		"monster_item_id": monster_item_id,
		"capacity": capacity,
		"spawn_timer": 0.0,
		"cooldown_per_size": cooldown_per_size,
		"minions_only": minions_only,
	}


func _make_room_spawner_record(room_id: int, capacity: int, spawners: Array) -> Dictionary:
	return {
		"room_id": room_id,
		"capacity": capacity,
		"spawners": spawners,
	}


func _room_spawn_config(room: Dictionary) -> Dictionary:
	# Returns { capacity: int, cooldown_per_size: float } with sane fallbacks.
	var cap := 3
	var cd := float(SPAWN_SECONDS_PER_SIZE)
	if _room_db != null and _room_db.has_method("get_room_type"):
		var type_id := String(room.get("type_id", ""))
		if type_id != "":
			var def: Dictionary = _room_db.call("get_room_type", type_id) as Dictionary
			cap = int(def.get("monster_capacity", cap))
			cd = float(def.get("monster_cooldown_per_size", cd))
	return { "capacity": cap, "cooldown_per_size": cd }


func _clear_all_monster_actors() -> void:
	if _monster_roster != null:
		_monster_roster.call("clear_all_actors")


func _init_room_spawners() -> void:
	if _dungeon_grid == null:
		return
	room_spawners_by_room_id.clear()
	for r in _dungeon_grid.get("rooms"):
		var room := r as Dictionary
		var kind := String(room.get("kind", ""))
		if kind != "monster" and kind != "boss":
			continue
		var slots: Array = room.get("slots", [])
		if slots.is_empty():
			continue
		var room_id: int = int(room.get("id", 0))
		var cfg := _room_spawn_config(room)
		var cap: int = int(cfg.get("capacity", 3))
		var cd: float = float(cfg.get("cooldown_per_size", float(SPAWN_SECONDS_PER_SIZE)))
		var spawners: Array = []
		for s in slots:
			var sd := s as Dictionary
			if sd.is_empty():
				continue
			var item_id := String(sd.get("installed_item_id", ""))
			if item_id == "":
				continue
			var slot_kind := String(sd.get("slot_kind", ""))
			# Monster rooms: only monster slots spawn.
			if kind == "monster":
				if slot_kind != "monster":
					continue
				spawners.append(_make_spawner(room_id, item_id, cap, cd, false))
				continue
			# Boss rooms: only universal slots can spawn minions, and only if the installed item is a monster.
			if kind == "boss":
				if slot_kind != "universal":
					continue
				var item_kind := ""
				if _item_db != null and _item_db.has_method("get_item_kind"):
					item_kind = String(_item_db.call("get_item_kind", item_id))
				if item_kind != "monster":
					continue
				# Boss room capacity is for MINIONS only (boss size does not consume it).
				spawners.append(_make_spawner(room_id, item_id, cap, cd, true))
		if spawners.is_empty():
			continue
		room_spawners_by_room_id[room_id] = _make_room_spawner_record(room_id, cap, spawners)
		DbgLog.log("Spawner armed room_id=%d slots=%d cap=%d" % [room_id, spawners.size(), cap], "monsters")


func _spawn_boss() -> void:
	if _dungeon_grid == null or _item_db == null:
		return
	var boss_room: Dictionary = _dungeon_grid.call("get_first_room_of_kind", "boss") as Dictionary
	if boss_room.is_empty():
		return
	var room_id: int = int(boss_room.get("id", 0))
	if room_id == 0:
		return
	# Prevent duplicates if start_day is called twice.
	if _boss_exists_in_room(room_id):
		return

	var mi: MonsterItem = _item_db.call("get_monster", "boss") as MonsterItem
	if mi == null:
		return

	# Collect boss upgrades installed in the boss room.
	var upgrades := _boss_upgrades_in_room(boss_room)

	# Apply boss upgrades to the boss template (stats).
	var boss_template: MonsterItem = mi.duplicate(true) as MonsterItem
	if boss_template == null:
		boss_template = mi
	for up in upgrades:
		_apply_boss_upgrade_to_template(boss_template, up)

	# Spawn boss actor at room center.
	var actor: Node2D = _monster_scene.instantiate() as Node2D
	if _dungeon_view != null:
		_dungeon_view.add_child(actor)
		var base: Vector2 = _dungeon_view.call("room_center_local", boss_room) as Vector2
		actor.position = base + Vector2(0.0, 0.0)
	actor.call("set_hp", boss_template.max_hp, boss_template.max_hp)
	actor.call("set_icon", boss_template.icon)
	actor.set_meta("collision_radius", COLLISION_RADIUS_BOSS)
	actor.call("set_is_boss", true)
	if _monster_roster != null:
		var mon := preload("res://scripts/systems/MonsterInstance.gd").new()
		mon.call("setup_from_template", boss_template, room_id, room_id, actor)
		for up in upgrades:
			_apply_boss_upgrade_to_instance(mon, up)
		_monster_roster.call("add", mon)
	DbgLog.log("Boss spawned room_id=%d hp=%d" % [room_id, int(boss_template.max_hp)], "monsters")


func _boss_exists_in_room(room_id: int) -> bool:
	if room_id == 0 or _monster_roster == null:
		return false
	var monsters: Array = _monster_roster.call("get_monsters_in_room", room_id)
	for m in monsters:
		var mi := m as MonsterInstance
		if mi != null and mi.is_boss() and mi.is_alive():
			return true
	return false


func _boss_upgrades_in_room(boss_room: Dictionary) -> Array[BossUpgradeItem]:
	var out: Array[BossUpgradeItem] = []
	if boss_room.is_empty() or _item_db == null:
		return out
	var slots: Array = boss_room.get("slots", [])
	for s in slots:
		var sd := s as Dictionary
		if sd.is_empty():
			continue
		var item_id := String(sd.get("installed_item_id", ""))
		if item_id == "":
			continue
		var up: BossUpgradeItem = null
		if _item_db.has_method("get_boss_upgrade"):
			up = _item_db.call("get_boss_upgrade", item_id) as BossUpgradeItem
		if up != null:
			out.append(up)
	return out


func _apply_boss_upgrade_to_template(boss_template: MonsterItem, up: BossUpgradeItem) -> void:
	if boss_template == null or up == null:
		return
	match String(up.effect_id):
		"boss_upgrade_damage":
			boss_template.attack_damage = int(boss_template.attack_damage) + int(round(up.value))
		"boss_upgrade_health":
			boss_template.max_hp = int(boss_template.max_hp) + int(round(up.value))
		"boss_upgrade_attack_speed":
			# value is an attack-speed multiplier (e.g. 1.15 = 15% faster).
			var mult := float(up.value)
			if mult > 0.0001:
				boss_template.attack_interval = float(boss_template.attack_interval) / mult
		_:
			pass


func _apply_boss_upgrade_to_instance(mon: MonsterInstance, up: BossUpgradeItem) -> void:
	if mon == null or up == null:
		return
	match String(up.effect_id):
		"boss_upgrade_armor":
			mon.dmg_block += int(round(up.value))
		"boss_upgrade_reflect":
			mon.reflect_damage += int(round(up.value))
		"boss_upgrade_double_strike":
			var ch := float(up.value)
			if ch > 1.0:
				ch = ch / 100.0
			mon.double_strike_chance = clampf(ch, 0.0, 1.0)
			var d := float(up.delay_s)
			if d <= 0.0001:
				d = 0.1
			mon.double_strike_delay_s = d
		"boss_upgrade_glop":
			mon.glop_damage = int(round(up.value))
			mon.glop_cooldown_s = float(up.cooldown_s) if float(up.cooldown_s) > 0.0001 else 3.0
			mon.glop_range_px = float(up.range_px) if float(up.range_px) > 0.0001 else 160.0
		_:
			pass


func _tick_spawners(dt: float) -> void:
	for k in room_spawners_by_room_id.keys():
		var room_id: int = int(k)
		var rec: Dictionary = room_spawners_by_room_id[room_id]
		if bool(rec.get("spawn_disabled", false)):
			continue
		# Pause spawning while this room is in combat.
		if _combat != null and bool(_combat.call("is_room_in_combat", room_id)):
			continue
		var cap: int = int(rec.get("capacity", 3))
		var spawners: Array = rec.get("spawners", [])
		var next_spawners: Array = []
		for s0 in spawners:
			var sd := s0 as Dictionary
			if sd.is_empty():
				continue
			next_spawners.append(_tick_one_spawner(sd, room_id, cap, dt))
		rec["spawners"] = next_spawners
		room_spawners_by_room_id[room_id] = rec


func _tick_one_spawner(sp: Dictionary, room_id: int, capacity: int, dt: float) -> Dictionary:
	var monster_item_id := String(sp.get("monster_item_id", ""))
	var item := _make_monster_item(monster_item_id)
	if item == null:
		return sp
	var mi := item as MonsterItem
	var cooldown_per_size: float = float(sp.get("cooldown_per_size", float(SPAWN_SECONDS_PER_SIZE)))
	var interval: float = float(mi.size) * cooldown_per_size
	var spawn_timer: float = float(sp.get("spawn_timer", 0.0)) + dt

	while true:
		if spawn_timer < interval:
			break
		var current_size_sum := 0.0
		if _monster_roster != null:
			var minions_only := bool(sp.get("minions_only", false))
			current_size_sum = _size_sum_in_room(room_id, minions_only)
		if current_size_sum + float(mi.size) > float(capacity):
			break
		spawn_timer -= interval
		var idx := 0
		if _monster_roster != null:
			idx = int(_monster_roster.call("count_in_room", room_id))
		var inst: Variant = _spawn_monster_instance(room_id, mi, idx)
		if _monster_roster != null and inst != null:
			_monster_roster.call("add", inst)
		var count_now := idx + 1
		if _monster_roster != null:
			count_now = int(_monster_roster.call("count_in_room", room_id))
		DbgLog.log("Spawned %s in room_id=%d (count=%d)" % [mi.id, room_id, count_now], "monsters")
		# If adventurers are already in this room, start/join combat now (otherwise they could
		# walk through before the first spawn and never re-enter combat).
		_join_combat_for_adventurers_in_room(room_id)
		# If there's an active combat in this room, refresh formation targets for the new monster.
		if _combat != null:
			_combat.call("on_monster_spawned", room_id)

	sp["spawn_timer"] = spawn_timer
	return sp


func _size_sum_in_room(room_id: int, minions_only: bool) -> float:
	if _monster_roster == null or room_id == 0:
		return 0
	var monsters: Array = _monster_roster.call("get_monsters_in_room", room_id)
	var sum := 0.0
	for m in monsters:
		var inst := m as MonsterInstance
		if inst == null or not inst.is_alive():
			continue
		if minions_only and inst.is_boss():
			continue
		sum += inst.size_units()
	return sum


func _join_combat_for_adventurers_in_room(room_id: int) -> void:
	if room_id == 0 or _combat == null or _dungeon_grid == null:
		return
	if _adventurers.is_empty():
		return
	var room: Dictionary = _dungeon_grid.call("get_room_by_id", room_id) as Dictionary
	if room.is_empty():
		return
	for a in _adventurers:
		if not is_instance_valid(a):
			continue
		var aid: int = int((a as Node2D).get_instance_id())
		if int(_adv_last_room.get(aid, 0)) != room_id:
			continue
		_combat.call("join_room", room, a)



func _make_monster_item(item_id: String) -> MonsterItem:
	if _item_db == null:
		return null
	return _item_db.call("get_monster", item_id) as MonsterItem


func _spawn_monster_instance(room_id: int, mi: MonsterItem, idx: int) -> RefCounted:
	var room: Dictionary = _dungeon_grid.call("get_room_by_id", room_id) as Dictionary if _dungeon_grid != null else {}

	var actor: Node2D = _monster_scene.instantiate() as Node2D
	if _world_canvas != null and _dungeon_view != null:
		_world_canvas.add_child(actor)
		var inv_wc3: Transform2D = _world_canvas.get_global_transform().affine_inverse()
		var base_local: Vector2 = Vector2.ZERO
		if not room.is_empty():
			var room_center_local: Vector2 = _dungeon_view.call("room_center_local", room) as Vector2
			var room_center_world: Vector2 = (_dungeon_view as CanvasItem).get_global_transform() * room_center_local
			base_local = inv_wc3 * room_center_world
		actor.position = base_local + Vector2(-12.0 + float(idx) * 12.0, 10.0)
	elif _dungeon_view != null:
		_dungeon_view.add_child(actor)
		var base: Vector2 = Vector2.ZERO
		if not room.is_empty():
			base = _dungeon_view.call("room_center_local", room) as Vector2
		actor.position = base + Vector2(-12.0 + float(idx) * 12.0, 10.0)
	actor.z_index = ACTOR_Z_INDEX
	actor.z_as_relative = false
	actor.call("set_hp", mi.max_hp, mi.max_hp)
	actor.call("set_icon", mi.icon)
	actor.set_meta("collision_radius", COLLISION_RADIUS_MON)
	actor.call("set_is_boss", false)

	var mon := preload("res://scripts/systems/MonsterInstance.gd").new()
	mon.call("setup_from_template", mi, room_id, room_id, actor)
	return mon


func _collect_collision_bodies() -> Array[Node2D]:
	var out: Array[Node2D] = []
	# Adventurers
	for a in _adventurers:
		if is_instance_valid(a):
			# Don't soft-collide on the surface; it causes entrance jams as parties converge
			# on a single target point.
			if int(a.get("phase")) == 0:
				continue
			out.append(a)
	# Monsters (actors)
	if _monster_roster != null:
		var bodies: Variant = _monster_roster.call("collect_actor_bodies")
		if bodies is Array:
			for b in bodies:
				var n := b as Node2D
				if n != null and is_instance_valid(n):
					out.append(n)
	return out


func _resolve_soft_collisions() -> void:
	# Simple pairwise separation so units don't overlap.
	var bodies := _collect_collision_bodies()
	if bodies.size() <= 1:
		return

	for _it in range(COLLISION_ITERATIONS):
		for i in range(bodies.size()):
			var a := bodies[i]
			if not is_instance_valid(a):
				continue
			var ra: float = float(a.get_meta("collision_radius", 10.0))
			for j in range(i + 1, bodies.size()):
				var b := bodies[j]
				if not is_instance_valid(b):
					continue
				var rb: float = float(b.get_meta("collision_radius", 10.0))

				# Use local positions so UI zoom/pan can't affect simulation.
				# (All sim actors are parented to WorldCanvas when available.)
				var delta := b.position - a.position
				var dist := delta.length()
				var min_dist := ra + rb
				if dist >= min_dist:
					continue

				# If perfectly overlapping, pick a deterministic-ish direction.
				var dir := Vector2.RIGHT
				if dist > 0.0001:
					dir = delta / dist
				else:
					var rng_seed := float(int(a.get_instance_id()) % 97) * 0.123
					dir = Vector2(cos(rng_seed), sin(rng_seed)).normalized()

				var push := (min_dist - dist) * 0.5
				a.position -= dir * push
				b.position += dir * push
