extends Node

# DAY simulation (scalable MVP):
# - Spawns adventurers in town, walks to entrance, then follows dungeon path
# - On room entry: traps can fire; monster rooms create per-room encounters
# - Encounters handle spawning and lock-room combat; new adventurers join immediately

signal day_started()
signal day_ended()
signal combat_started(room_id: int)
signal combat_ended(room_id: int)

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

# New: central AI and path service
var _party_ai: PartyAI
var _path_service: PathService

# adv_instance_id -> last reached cell (for retargeting / resume)
var _adv_last_cell: Dictionary = {}
# adv_instance_id -> was_in_combat last tick
var _adv_was_in_combat: Dictionary = {}

# Party spawn queue (spawn one by one in town)
var _party_spawn_queue: Array[String] = []
var _party_spawn_timer: float = 0.0
var _party_spawn_index: int = 0
var _party_spawn_ctx: Dictionary = {}

var _adv_scene: PackedScene = preload("res://scenes/Adventurer.tscn")

var _loot_system: RefCounted
var _trap_system: RefCounted
var _room_inventory_panel: Node
var _ending_day: bool = false
var _monster_roster: RefCounted


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

	# Loot system (separate file): spawns on-ground treasure drops and collects at day end.
	_loot_system = preload("res://scripts/systems/LootDropSystem.gd").new()
	_loot_system.call("setup", _world_canvas, _item_db, get_node_or_null("/root/game_config"))

	# Trap system: handles trap room entry effects.
	_trap_system = preload("res://scripts/systems/TrapSystem.gd").new()
	_trap_system.call("setup", _item_db)


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
		_init_room_spawners()
		_spawn_boss()
	_begin_party_spawn()
	if _loot_system != null:
		_loot_system.call("reset")
	if _trap_system != null:
		_trap_system.call("reset")


func end_day() -> void:
	if _ending_day:
		return
	_ending_day = true
	_active = false
	_party_spawn_queue.clear()
	_party_spawn_ctx.clear()

	# Collect ground loot (animate to Treasure tab) before final cleanup.
	var target := _loot_collect_target_world_pos()
	if _loot_system != null and bool(_loot_system.call("has_loot")) and target != Vector2.ZERO:
		_loot_system.call("collect_all_to", target, Callable(self, "_finish_end_day_cleanup"))
	else:
		_finish_end_day_cleanup()


func _finish_end_day_cleanup() -> void:
	for a in _adventurers:
		if is_instance_valid(a):
			a.queue_free()
	_adventurers.clear()
	_adv_last_room.clear()
	_adv_last_cell.clear()
	_adv_was_in_combat.clear()
	_clear_all_monster_actors()
	room_spawners_by_room_id.clear()
	if _combat != null:
		_combat.call("reset")
	if _monster_roster != null:
		_monster_roster.call("reset")
	GameState.set_phase(GameState.Phase.RESULTS)
	day_ended.emit()
	_ending_day = false


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

	# Regroup check: keep party cohesive by forcing stragglers to path to the party goal cell.
	_tick_party_regroup()

	_resolve_soft_collisions()

	if _adventurers.is_empty():
		# For MVP, end the day if no adventurers remain (died or finished).
		end_day()


func _begin_party_spawn() -> void:
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
	# Party goal: decided by PartyAI (boss-first, fallback weighted).
	var initial_goal: Vector2i = _party_ai.decide_initial_goal(1, start_cell)

	var path: Array[Vector2i] = _party_ai.compute_initial_path(start_cell, initial_goal)

	var spawn_world := _town_view.call("get_spawn_world_pos") as Vector2
	var entrance_world := _dungeon_view.call("entrance_surface_world_pos") as Vector2

	_party_spawn_ctx = {
		"spawn_world": spawn_world,
		"entrance_world": entrance_world,
		"path": path,
	}

	_party_spawn_queue = ["warrior", "mage", "priest", "rogue"]
	_party_spawn_timer = 0.0
	_party_spawn_index = 0


func _tick_party_spawn(dt: float) -> void:
	if _party_spawn_queue.is_empty():
		return
	_party_spawn_timer -= dt
	while _party_spawn_timer <= 0.0 and not _party_spawn_queue.is_empty():
		var class_id: String = _party_spawn_queue.pop_front()
		_spawn_one_party_member(class_id, _party_spawn_index)
		_party_spawn_index += 1
		_party_spawn_timer += PARTY_SPAWN_INTERVAL


func _spawn_one_party_member(class_id: String, idx: int) -> void:
	if _town_view == null or _dungeon_view == null or _dungeon_grid == null:
		return
	if _party_spawn_ctx.is_empty():
		return

	var spawn_world: Vector2 = _party_spawn_ctx.get("spawn_world", Vector2.ZERO)
	var entrance_world: Vector2 = _party_spawn_ctx.get("entrance_world", Vector2.ZERO)
	var path: Array[Vector2i] = _party_spawn_ctx.get("path", []) as Array[Vector2i]

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
	if _world_canvas != null:
		var inv_wc: Transform2D = _world_canvas.get_global_transform().affine_inverse()
		adv.position = (inv_wc * spawn_world) + scatter[idx % scatter.size()]
	else:
		adv.position = _town_view.get_global_transform().affine_inverse() * (spawn_world + scatter[idx % scatter.size()])
	adv.set("party_id", 1)

	var cls_res: Resource = null
	if _item_db != null:
		cls_res = _item_db.call("get_adv_class", class_id) as Resource
	adv.call("apply_class", cls_res)

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
	if adv.has_signal("died"):
		adv.connect("died", Callable(self, "_on_adventurer_died").bind(int(adv.get_instance_id())))
	_adventurers.append(adv)
	_adv_was_in_combat[int(adv.get_instance_id())] = false


func _on_adventurer_died(world_pos: Vector2, class_id: String, adv_id: int) -> void:
	# Only drop loot if the adventurer has entered the dungeon (has a non-zero last room).
	if int(_adv_last_room.get(adv_id, 0)) == 0:
		return
	if _loot_system != null:
		_loot_system.call("on_adventurer_died", world_pos, class_id)


func _find_room_inventory_panel() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.find_child("RoomInventoryPanel", true, false)


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
	_party_ai.retarget_from_cell(pid, from_cell)
	# Apply paths for party toward new goal
	var cells_by_adv := {}
	for a2 in _adventurers:
		if not is_instance_valid(a2):
			continue
		if int(a2.get("party_id")) != pid:
			continue
		var aid2: int = int(a2.get_instance_id())
		cells_by_adv[aid2] = _adv_last_cell.get(aid2, from_cell)
	var updates: Dictionary = _party_ai.paths_to_current_goal(pid, cells_by_adv)
	for k in updates.keys():
		var aid3: int = int(k)
		var p: Array[Vector2i] = updates[k]
		for a3 in _adventurers:
			if is_instance_valid(a3) and int(a3.get_instance_id()) == aid3 and not bool(a3.get("in_combat")):
				a3.call("set_path", p)


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

	# Exploration AI: after entering a room (and if not in combat), retarget occasionally.
	if bool(adv.get("in_combat")):
		return
	var party_id: int = int(adv.get("party_id"))
	var party_goal: Vector2i = _party_ai.get_current_goal(party_id)
	if party_goal == Vector2i(-1, -1):
		_party_ai.retarget_from_cell(party_id, cell)
		return
	# If the party reached its current goal room, pick a new party goal.
	if cell == party_goal:
		_party_ai.retarget_from_cell(party_id, cell)
		# Apply fresh paths to members toward the new goal.
		var cells_by_adv := {}
		for a2 in _adventurers:
			if not is_instance_valid(a2):
				continue
			if int(a2.get("party_id")) != party_id:
				continue
			var aid2: int = int(a2.get_instance_id())
			cells_by_adv[aid2] = _adv_last_cell.get(aid2, cell)
		var updates: Dictionary = _party_ai.paths_to_current_goal(party_id, cells_by_adv)
		for k in updates.keys():
			var aid3: int = int(k)
			var p: Array[Vector2i] = updates[k]
			for a3 in _adventurers:
				if is_instance_valid(a3) and int(a3.get_instance_id()) == aid3 and not bool(a3.get("in_combat")):
					a3.call("set_path", p)


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
		if String(sd.get("slot_kind", "")) != "boss_upgrade":
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
		var current_size_sum: int = 0
		if _monster_roster != null:
			var minions_only := bool(sp.get("minions_only", false))
			current_size_sum = _size_sum_in_room(room_id, minions_only)
		if current_size_sum + mi.size > capacity:
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


func _size_sum_in_room(room_id: int, minions_only: bool) -> int:
	if _monster_roster == null or room_id == 0:
		return 0
	var monsters: Array = _monster_roster.call("get_monsters_in_room", room_id)
	var sum := 0
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
