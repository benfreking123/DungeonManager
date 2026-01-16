extends Node

# DAY simulation (scalable MVP):
# - Spawns adventurers in town, walks to entrance, then follows dungeon path
# - On room entry: traps can fire; monster rooms create per-room encounters
# - Encounters handle spawning and lock-room combat; new adventurers join immediately

signal day_started()
signal day_ended()

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

# room_id -> spawner dict (runs from day start, fills to capacity)
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
	_combat = preload("res://autoloads/Simulation_Combat.gd").new()
	_combat.call("setup", _dungeon_view, _dungeon_grid, self)
	# Initialize AI services
	_path_service = preload("res://scripts/nav/PathService.gd").new()
	_path_service.setup(_dungeon_grid)
	_party_ai = preload("res://scripts/ai/PartyAI.gd").new()
	_party_ai.setup(_dungeon_grid, _path_service)


func start_day() -> void:
	if _active:
		return
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
	if _combat != null:
		_combat.call("reset")
	if _dungeon_grid != null:
		_dungeon_grid.call("ensure_room_defaults")
		_init_room_spawners()
		_spawn_boss()
	_begin_party_spawn()


func end_day() -> void:
	_active = false
	_party_spawn_queue.clear()
	_party_spawn_ctx.clear()
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
	GameState.set_phase(GameState.Phase.RESULTS)
	day_ended.emit()


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
	_adventurers.append(adv)
	_adv_was_in_combat[int(adv.get_instance_id())] = false


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
		if kind == "trap":
			_apply_trap_on_enter(room, adv)
		elif kind == "monster" or kind == "boss":
			if _combat != null:
				_combat.call("join_room", room, adv, room_spawners_by_room_id)

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


func _apply_trap_on_enter(room: Dictionary, adv: Node2D) -> void:
	var slots: Array = room.get("slots", [])
	if slots.is_empty():
		return
	var slot: Dictionary = slots[0]
	var item_id := String(slot.get("installed_item_id", ""))
	if item_id == "":
		return

	# Determine all adventurers currently in this room (same room_id).
	var room_id: int = int(room.get("id", 0))
	var targets: Array[Node2D] = []
	for a in _adventurers:
		if not is_instance_valid(a):
			continue
		var key: int = int(a.get_instance_id())
		if int(_adv_last_room.get(key, 0)) == room_id:
			targets.append(a)

	if targets.is_empty():
		targets.append(adv)

	var trap: TrapItem = null
	if _item_db != null:
		trap = _item_db.call("get_trap", item_id) as TrapItem
	if trap == null:
		return

	if randf() > trap.proc_chance:
		return

	if trap.hits_all:
		for t in targets:
			t.call("apply_damage", trap.damage)
	else:
		var idx := randi() % targets.size()
		targets[idx].call("apply_damage", trap.damage)


func _make_spawner(room_id: int, monster_item_id: String, capacity: int) -> Dictionary:
	return {
		"room_id": room_id,
		"monster_item_id": monster_item_id,
		"capacity": capacity,
		"spawn_timer": 0.0,
		"monsters": [], # Array[Dictionary] { hp, max_hp, size, attack_damage, attack_interval, attack_timer, actor }
	}


func _clear_all_monster_actors() -> void:
	for k in room_spawners_by_room_id.keys():
		var sp: Dictionary = room_spawners_by_room_id[int(k)]
		var monsters: Array = sp.get("monsters", [])
		for m in monsters:
			var d := m as Dictionary
			var actor: Variant = d.get("actor", null)
			if actor != null and is_instance_valid(actor):
				(actor as Node).queue_free()


func _init_room_spawners() -> void:
	if _dungeon_grid == null:
		return
	room_spawners_by_room_id.clear()
	for r in _dungeon_grid.get("rooms"):
		var room := r as Dictionary
		if String(room.get("kind", "")) != "monster":
			continue
		var slots: Array = room.get("slots", [])
		if slots.is_empty():
			continue
		var item_id := String((slots[0] as Dictionary).get("installed_item_id", ""))
		if item_id == "":
			continue
		var room_id: int = int(room.get("id", 0))
		var cap: int = int(room.get("max_monster_size_capacity", 3))
		room_spawners_by_room_id[room_id] = _make_spawner(room_id, item_id, cap)
		DbgLog.log("Spawner armed room_id=%d item=%s cap=%d" % [room_id, item_id, cap], "monsters")


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
	if room_spawners_by_room_id.has(room_id):
		return

	var mi: MonsterItem = _item_db.call("get_monster", "boss") as MonsterItem
	if mi == null:
		return

	# Boss spawner: static (no ticking), contains exactly one boss monster.
	var sp := {
		"room_id": room_id,
		"monster_item_id": mi.id,
		"capacity": mi.size,
		"spawn_timer": 0.0,
		"monsters": [],
		"spawn_disabled": true,
	}

	# Spawn boss actor at room center.
	var actor: Node2D = _monster_scene.instantiate() as Node2D
	if _dungeon_view != null:
		_dungeon_view.add_child(actor)
		var base: Vector2 = _dungeon_view.call("room_center_local", boss_room) as Vector2
		actor.position = base + Vector2(0.0, 0.0)
	actor.call("set_hp", mi.max_hp, mi.max_hp)
	actor.call("set_icon", mi.icon)
	actor.set_meta("collision_radius", COLLISION_RADIUS_BOSS)
	actor.call("set_is_boss", true)

	sp["monsters"] = [{
		"id": mi.id,
		"hp": mi.max_hp,
		"max_hp": mi.max_hp,
		"size": mi.size,
		"attack_damage": mi.attack_damage,
		"attack_interval": mi.attack_interval,
		"range": mi.range,
		"attack_timer": 0.0,
		"actor": actor,
	}]

	room_spawners_by_room_id[room_id] = sp
	DbgLog.log("Boss spawned room_id=%d hp=%d" % [room_id, mi.max_hp], "monsters")


func _tick_spawners(dt: float) -> void:
	for k in room_spawners_by_room_id.keys():
		var room_id: int = int(k)
		var sp: Dictionary = room_spawners_by_room_id[room_id]
		if bool(sp.get("spawn_disabled", false)):
			continue
		# Pause spawning while this room is in combat.
		if _combat != null and bool(_combat.call("is_room_in_combat", room_id)):
			continue
		_tick_one_spawner(sp, dt)
		room_spawners_by_room_id[room_id] = sp


func _tick_one_spawner(sp: Dictionary, dt: float) -> void:
	var monster_item_id := String(sp.get("monster_item_id", ""))
	var item := _make_monster_item(monster_item_id)
	if item == null:
		return
	var mi := item as MonsterItem
	var interval: float = float(mi.size) * SPAWN_SECONDS_PER_SIZE
	var capacity: int = int(sp.get("capacity", 3))

	var spawn_timer: float = float(sp.get("spawn_timer", 0.0)) + dt
	var monsters: Array = sp.get("monsters", [])

	while true:
		if spawn_timer < interval:
			break
		var current_size_sum: int = 0
		for m in monsters:
			current_size_sum += int((m as Dictionary).get("size", 1))
		if current_size_sum + mi.size > capacity:
			break
		spawn_timer -= interval
		monsters.append(_spawn_monster_instance(int(sp.get("room_id", 0)), mi, monsters.size()))
		DbgLog.log("Spawned %s in room_id=%d (count=%d)" % [mi.id, int(sp.get("room_id", 0)), monsters.size()], "monsters")
		# If there's an active combat in this room, refresh formation targets for the new monster.
		var rid: int = int(sp.get("room_id", 0))
		if _combat != null:
			_combat.call("on_monster_spawned", rid, room_spawners_by_room_id)

	sp["spawn_timer"] = spawn_timer
	sp["monsters"] = monsters



func _make_monster_item(item_id: String) -> MonsterItem:
	if _item_db == null:
		return null
	return _item_db.call("get_monster", item_id) as MonsterItem


func _spawn_monster_instance(room_id: int, mi: MonsterItem, idx: int) -> Dictionary:
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

	return {
		"id": mi.id,
		"hp": mi.max_hp,
		"max_hp": mi.max_hp,
		"size": mi.size,
		"attack_damage": mi.attack_damage,
		"attack_interval": mi.attack_interval,
		"range": mi.range,
		"attack_timer": 0.0,
		"actor": actor,
	}


func _sync_monster_actor(m: Dictionary) -> void:
	var actor: Variant = m.get("actor", null)
	if actor != null and is_instance_valid(actor):
		(actor as Node).call("set_hp", int(m.get("hp", 0)), int(m.get("max_hp", 1)))


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
	for k in room_spawners_by_room_id.keys():
		var sp: Dictionary = room_spawners_by_room_id[int(k)]
		var monsters: Array = sp.get("monsters", [])
		for m in monsters:
			var d := m as Dictionary
			var actor: Variant = d.get("actor", null)
			if actor != null and is_instance_valid(actor):
				out.append(actor as Node2D)
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
