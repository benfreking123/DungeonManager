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

var _town_view: Control
var _dungeon_view: Control

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

# Slightly smaller so units can pack without looking like they overlap.
# (Non-boss units ~20% smaller than before.)
# Adventurers a bit smaller still to avoid surface entrance jams.
const COLLISION_RADIUS_ADV := 5.0
const COLLISION_RADIUS_MON := 6.5
const COLLISION_RADIUS_BOSS := 9.0
# Softer collision resolution (less "pushing").
const COLLISION_ITERATIONS := 1

var _ai_by_adv_id: Dictionary = {} # int -> AdventurerAI

# Party-level goal (all members share one goal for now).
var _party_goal_cell_by_party_id: Dictionary = {} # int -> Vector2i
var _party_regroup_target_by_party_id: Dictionary = {} # int -> Vector2i

const PARTY_LEASH_CELLS := 2

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
	_dungeon_grid = get_node_or_null("/root/DungeonGrid")
	_room_db = get_node_or_null("/root/RoomDB")
	_item_db = get_node_or_null("/root/ItemDB")
	_combat = preload("res://autoloads/Simulation_Combat.gd").new()
	_combat.call("setup", _dungeon_view, _dungeon_grid, self)


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
	_ai_by_adv_id.clear()
	_party_goal_cell_by_party_id.clear()
	_party_regroup_target_by_party_id.clear()
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
	_ai_by_adv_id.clear()
	_party_regroup_target_by_party_id.clear()
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

	# Camera is visual-only: if the user pans/zooms the UI, the entrance world position changes.
	# Retarget SURFACE-walking adventurers each frame so they keep walking to the entrance.
	var entrance_world: Vector2 = Vector2.ZERO
	if _dungeon_view != null:
		entrance_world = _dungeon_view.call("entrance_surface_world_pos") as Vector2

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

			if entrance_world != Vector2.ZERO and int(a.get("phase")) == 0 and not bool(a.get("in_combat")):
				a.call("set_surface_target", entrance_world, SURFACE_SPEED)
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
	# Party goal: weighted goals (boss/treasure/etc).
	var initial_goal: Vector2i = start_cell
	if _dungeon_grid != null:
		var ai_tmp: AdventurerAI = AdventurerAI.new(1)
		initial_goal = ai_tmp.pick_goal_cell_weighted(_dungeon_grid, start_cell)
	_party_goal_cell_by_party_id[1] = initial_goal

	var path: Array[Vector2i] = _dungeon_grid.call("find_path", start_cell, initial_goal) as Array[Vector2i]
	if path.is_empty():
		path = [start_cell]

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
	_town_view.add_child(adv)
	# Spawn as a tight cluster on the ground with a tiny scatter (2–4px) so they read as one party.
	var scatter := [
		Vector2(0, 0),
		Vector2(3, -1),
		Vector2(-2, 2),
		Vector2(2, 3),
	]
	adv.global_position = spawn_world + scatter[idx % scatter.size()]
	adv.set("party_id", 1)

	var cls_res: Resource = null
	if _item_db != null:
		cls_res = _item_db.call("get_adv_class", class_id) as Resource
	adv.call("apply_class", cls_res)

	adv.set_meta("collision_radius", COLLISION_RADIUS_ADV)
	adv.call("set_surface_target", entrance_world, SURFACE_SPEED)
	adv.call("set_dungeon_targets", _dungeon_view, path, DUNGEON_SPEED)
	adv.call("set_on_reach_goal", Callable(self, "_on_adventurer_finished").bind(adv))
	adv.connect("cell_reached", Callable(self, "_on_adventurer_cell_reached").bind(adv))
	_adventurers.append(adv)
	_adv_was_in_combat[int(adv.get_instance_id())] = false

	var ai := AdventurerAI.new(int(adv.get_instance_id()))
	_ai_by_adv_id[int(adv.get_instance_id())] = ai


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
	_retarget_party_from_cell(int(adv.get("party_id")), from_cell)


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
	var party_goal: Vector2i = _party_goal_cell_by_party_id.get(party_id, Vector2i(-1, -1))
	if party_goal == Vector2i(-1, -1):
		_party_goal_cell_by_party_id[party_id] = cell
		return
	# If the party reached its current goal room, pick a new party goal.
	if cell == party_goal:
		_retarget_party_from_cell(party_id, cell)


func _retarget_adv(adv: Node2D, from_cell: Vector2i) -> bool:
	if _dungeon_grid == null:
		return false
	if not is_instance_valid(adv):
		return false
	var aid: int = int(adv.get_instance_id())

	var ai: AdventurerAI = _ai_by_adv_id.get(aid, null) as AdventurerAI
	if ai == null:
		ai = AdventurerAI.new(aid)
		_ai_by_adv_id[aid] = ai
	ai.mark_visited(from_cell)

	var goal: Vector2i = ai.pick_goal_cell_weighted(_dungeon_grid, from_cell)
	var new_path: Array[Vector2i] = _dungeon_grid.call("find_path", from_cell, goal) as Array[Vector2i]
	# Only remove the current cell if there's at least one more step; otherwise the adventurer
	# will walk back to the cell center (useful after combat formation animation) then retarget again.
	if new_path.size() > 1 and new_path[0] == from_cell:
		new_path.remove_at(0)
	adv.call("set_path", new_path)
	# If the adventurer was marked DONE, nudge them back into dungeon movement.
	if int(adv.get("phase")) == 2 and not new_path.is_empty():
		adv.set("phase", 1)
	return true


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
	var regroup: Vector2i = _room_center_cell(room, _adv_last_cell.get(adv_id, Vector2i(-1, -1)))
	if regroup == Vector2i(-1, -1):
		return

	_party_regroup_target_by_party_id[party_id] = regroup
	_party_goal_cell_by_party_id[party_id] = regroup
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


func _retarget_party_from_cell(party_id: int, from_cell: Vector2i) -> void:
	if _dungeon_grid == null:
		return
	# Use a stable party AI keyed by party id.
	var ai: AdventurerAI = _ai_by_adv_id.get(party_id, null) as AdventurerAI
	if ai == null:
		ai = AdventurerAI.new(party_id)
		_ai_by_adv_id[party_id] = ai
	ai.mark_visited(from_cell)

	# Boss-first (primary win condition): if the boss room is reachable, always target it.
	var goal: Vector2i = Vector2i(-1, -1)
	var boss_room: Dictionary = _dungeon_grid.call("get_first_room_of_kind", "boss") as Dictionary
	if not boss_room.is_empty():
		var boss_pos: Vector2i = boss_room.get("pos", Vector2i(-1, -1))
		var boss_center: Vector2i = _room_center_cell(boss_room, boss_pos)
		var p_center: Array[Vector2i] = _dungeon_grid.call("find_path", from_cell, boss_center) as Array[Vector2i]
		var p_pos: Array[Vector2i] = _dungeon_grid.call("find_path", from_cell, boss_pos) as Array[Vector2i]
		if not p_center.is_empty():
			goal = boss_center
		elif not p_pos.is_empty():
			goal = boss_pos
		else:
			DbgLog.warn("Boss not reachable from=%s boss_pos=%s boss_center=%s" % [str(from_cell), str(boss_pos), str(boss_center)], "adventurers")

	if goal == Vector2i(-1, -1):
		goal = ai.pick_goal_cell_weighted(_dungeon_grid, from_cell)
	_party_goal_cell_by_party_id[party_id] = goal
	DbgLog.log("Party %d new_goal=%s from=%s" % [party_id, str(goal), str(from_cell)], "adventurers")

	# Assign all party members a new path from their current last cell.
	for a in _adventurers:
		if not is_instance_valid(a):
			continue
		if int(a.get("party_id")) != party_id:
			continue
		if bool(a.get("in_combat")):
			continue
		var aid: int = int(a.get_instance_id())
		var start: Vector2i = _adv_last_cell.get(aid, from_cell)
		var p: Array[Vector2i] = _dungeon_grid.call("find_path", start, goal) as Array[Vector2i]
		if p.size() > 1 and p[0] == start:
			p.remove_at(0)
		a.call("set_path", p)
		DbgLog.log("Party %d path adv=%d start=%s goal=%s len=%d" % [party_id, aid, str(start), str(goal), p.size()], "adventurers")


func _tick_party_regroup() -> void:
	# Very simple leash: if party members are spread out by > PARTY_LEASH_CELLS (Manhattan),
	# force the farthest ones to path toward the current party goal anchor.
	if _dungeon_grid == null:
		return
	# Only one party for now, but keep it generic.
	for party_id in _party_goal_cell_by_party_id.keys():
		var pid: int = int(party_id)
		var goal: Vector2i = _party_goal_cell_by_party_id.get(pid, Vector2i(-1, -1))
		if goal == Vector2i(-1, -1):
			continue

		var regroup_target: Vector2i = _party_regroup_target_by_party_id.get(pid, Vector2i(-1, -1))
		var members: Array[Node2D] = []
		var cells: Array[Vector2i] = []
		for a in _adventurers:
			if not is_instance_valid(a):
				continue
			if int(a.get("party_id")) != pid:
				continue
			members.append(a)
			var aid: int = int(a.get_instance_id())
			cells.append(_adv_last_cell.get(aid, Vector2i(-1, -1)))
		if members.size() <= 1:
			continue

		# If we're regrouping (post-combat), pull everyone toward the regroup_target and
		# once they're close enough, pick the next party goal.
		if regroup_target != Vector2i(-1, -1):
			var all_close := true
			for c in cells:
				if c == Vector2i(-1, -1):
					all_close = false
					break
				var d: int = abs(c.x - regroup_target.x) + abs(c.y - regroup_target.y)
				if d > PARTY_LEASH_CELLS:
					all_close = false
					break
			if all_close:
				_party_regroup_target_by_party_id.erase(pid)
				_retarget_party_from_cell(pid, regroup_target)
				continue

			# Not all close: force paths toward regroup target.
			for i in range(members.size()):
				var a2 := members[i]
				if bool(a2.get("in_combat")):
					continue
				var c2: Vector2i = cells[i]
				if c2 == Vector2i(-1, -1):
					continue
				var p_to: Array[Vector2i] = _dungeon_grid.call("find_path", c2, regroup_target) as Array[Vector2i]
				if p_to.size() > 1 and p_to[0] == c2:
					p_to.remove_at(0)
				a2.call("set_path", p_to)
			continue

		# Compute a leader cell as the median-ish: use first valid.
		var leader_cell := Vector2i(-1, -1)
		for c in cells:
			if c != Vector2i(-1, -1):
				leader_cell = c
				break
		if leader_cell == Vector2i(-1, -1):
			continue

		for i in range(members.size()):
			var a2 := members[i]
			if bool(a2.get("in_combat")):
				continue
			var c2: Vector2i = cells[i]
			if c2 == Vector2i(-1, -1):
				continue
			var dist: int = abs(c2.x - leader_cell.x) + abs(c2.y - leader_cell.y)
			if dist <= PARTY_LEASH_CELLS:
				continue
			# Straggler: path toward leader_cell first (regroup).
			var p: Array[Vector2i] = _dungeon_grid.call("find_path", c2, leader_cell) as Array[Vector2i]
			if p.size() > 1 and p[0] == c2:
				p.remove_at(0)
			a2.call("set_path", p)


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
	if _dungeon_view != null:
		_dungeon_view.add_child(actor)
		var base: Vector2 = Vector2.ZERO
		if not room.is_empty():
			base = _dungeon_view.call("room_center_local", room) as Vector2
		actor.position = base + Vector2(-12.0 + float(idx) * 12.0, 10.0)
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

	# If the UI is zoomed, CanvasItem global distances scale by zoom, but our radii are in unzoomed units.
	# Compensate so zoom has ZERO effect on collision behavior.
	var zoom_scale: float = 1.0
	if _dungeon_view != null:
		zoom_scale = float((_dungeon_view as CanvasItem).get_global_transform().get_scale().x)
	zoom_scale = max(0.0001, zoom_scale)

	for _it in range(COLLISION_ITERATIONS):
		for i in range(bodies.size()):
			var a := bodies[i]
			if not is_instance_valid(a):
				continue
			var ra: float = float(a.get_meta("collision_radius", 10.0)) * zoom_scale
			for j in range(i + 1, bodies.size()):
				var b := bodies[j]
				if not is_instance_valid(b):
					continue
				var rb: float = float(b.get_meta("collision_radius", 10.0)) * zoom_scale

				var delta := b.global_position - a.global_position
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
				a.global_position -= dir * push
				b.global_position += dir * push
