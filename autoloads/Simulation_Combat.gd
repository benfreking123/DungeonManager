extends RefCounted

# Combat subsystem extracted from Simulation.gd.
# Handles:
# - room_id -> combat state
# - join combat on room entry (only if monsters exist)
# - warmup delay before attacks
# - purely-visual formation positioning
# - tick combat + cleanup

const COMBAT_WARMUP_SECONDS := 1.0
const COMBAT_MOVE_SPEED := 220.0

var combats_by_room_id: Dictionary = {}

var _dungeon_view: Control
var _dungeon_grid: Node
var _simulation: Node


func setup(dungeon_view: Control, dungeon_grid: Node, simulation: Node) -> void:
	_dungeon_view = dungeon_view
	_dungeon_grid = dungeon_grid
	_simulation = simulation


func reset() -> void:
	combats_by_room_id.clear()


func is_room_in_combat(room_id: int) -> bool:
	return combats_by_room_id.has(room_id)


func join_room(room: Dictionary, adv: Node2D, room_spawners_by_room_id: Dictionary) -> void:
	var room_id: int = int(room.get("id", 0))
	if room_id == 0:
		return

	# Only enter combat if monsters have spawned in this room.
	var sp: Dictionary = room_spawners_by_room_id.get(room_id, {})
	if sp.is_empty():
		return
	var monsters: Array = sp.get("monsters", [])
	if monsters.is_empty():
		return

	var combat: Dictionary = combats_by_room_id.get(room_id, {})
	if combat.is_empty():
		# Warmup: wait a bit before attacks start, and let units slide into position.
		combat = {
			"room_id": room_id,
			"participants": [],
			"adv_attack_timers": {},
			"warmup_remaining": COMBAT_WARMUP_SECONDS,
			"adv_targets": {},  # adv_instance_id -> world pos
			"mon_targets": {},  # actor_instance_id -> world pos
		}

	var participants: Array = combat.get("participants", [])
	if not participants.has(adv):
		participants.append(adv)
	combat["participants"] = participants

	_assign_combat_positions(room, combat, sp)
	combats_by_room_id[room_id] = combat

	adv.call("enter_combat", room_id)
	DbgLog.log("Adventurer entered combat room_id=%d monsters=%d" % [room_id, monsters.size()], "monsters")


func on_monster_spawned(room_id: int, room_spawners_by_room_id: Dictionary) -> void:
	if not combats_by_room_id.has(room_id):
		return
	if _dungeon_grid == null:
		return
	var sp: Dictionary = room_spawners_by_room_id.get(room_id, {})
	if sp.is_empty():
		return
	var room: Dictionary = _dungeon_grid.call("get_room_by_id", room_id) as Dictionary
	var combat: Dictionary = combats_by_room_id[room_id]
	_assign_combat_positions(room, combat, sp)
	combats_by_room_id[room_id] = combat


func tick(dt: float, room_spawners_by_room_id: Dictionary) -> void:
	var to_remove: Array[int] = []
	for k in combats_by_room_id.keys():
		var room_id: int = int(k)
		var combat: Dictionary = combats_by_room_id[room_id]
		var alive := _tick_one_combat(room_id, combat, dt, room_spawners_by_room_id)
		if not alive:
			to_remove.append(room_id)
		else:
			combats_by_room_id[room_id] = combat
	for rid in to_remove:
		combats_by_room_id.erase(rid)


func _tick_one_combat(room_id: int, combat: Dictionary, dt: float, room_spawners_by_room_id: Dictionary) -> bool:
	if not room_spawners_by_room_id.has(room_id):
		return false
	var sp: Dictionary = room_spawners_by_room_id[room_id]
	var monsters: Array = sp.get("monsters", [])

	var participants: Array = combat.get("participants", [])
	var p2: Array[Node2D] = []
	for p in participants:
		if is_instance_valid(p):
			p2.append(p)
	participants = p2
	combat["participants"] = participants
	if participants.is_empty():
		return false

	if monsters.is_empty():
		for p in participants:
			if is_instance_valid(p):
				p.call("exit_combat")
		return false

	# Visual staging: slide units to formation spots.
	_animate_combat_positions(combat, sp, dt)

	# Delay attacks briefly when combat starts (pure feel/animation).
	var warm: float = float(combat.get("warmup_remaining", 0.0))
	if warm > 0.0:
		warm = max(0.0, warm - dt)
		combat["warmup_remaining"] = warm
		return true

	_tick_adv_attacks(combat, sp, dt)
	_tick_monster_attacks(combat, sp, dt)

	# remove dead monsters
	var m2: Array = []
	for m in sp.get("monsters", []):
		var md := m as Dictionary
		if int(md.get("hp", 0)) > 0:
			m2.append(md)
		else:
			# Boss death triggers game over.
			if String(md.get("id", "")) == "boss":
				if _simulation != null and _simulation.has_signal("boss_killed"):
					_simulation.emit_signal("boss_killed")
			var actor: Variant = md.get("actor", null)
			if actor != null and is_instance_valid(actor):
				(actor as Node).queue_free()
	sp["monsters"] = m2
	room_spawners_by_room_id[room_id] = sp

	if m2.is_empty():
		# Reset monster spawn cooldown when combat ends (prevents immediate respawn as party leaves).
		sp["spawn_timer"] = 0.0
		room_spawners_by_room_id[room_id] = sp
		for p in participants:
			if is_instance_valid(p):
				p.call("exit_combat")
		return false

	return true


func _tick_adv_attacks(combat: Dictionary, sp: Dictionary, dt: float) -> void:
	var participants: Array = combat.get("participants", [])
	var monsters: Array = sp.get("monsters", [])
	if participants.is_empty() or monsters.is_empty():
		return
	var adv_timers: Dictionary = combat.get("adv_attack_timers", {})

	for p in participants:
		if not is_instance_valid(p):
			continue
		var pid: int = int(p.get_instance_id())
		var t: float = float(adv_timers.get(pid, 0.0)) - dt
		if t <= 0.0:
			# Adventurers hit ONE monster per attack.
			var dmg: int = int(p.get("attack_damage"))
			var alive_idxs: Array[int] = []
			for i in range(monsters.size()):
				var m0: Dictionary = monsters[i]
				if int(m0.get("hp", 0)) > 0:
					alive_idxs.append(i)
			if not alive_idxs.is_empty():
				var pick_i: int = alive_idxs[randi() % alive_idxs.size()]
				var m: Dictionary = monsters[pick_i]
				m["hp"] = int(m.get("hp", 0)) - dmg
				_sync_monster_actor(m)
				monsters[pick_i] = m
			t += float(p.get("attack_interval"))
		adv_timers[pid] = t

	combat["adv_attack_timers"] = adv_timers
	sp["monsters"] = monsters


func _tick_monster_attacks(combat: Dictionary, sp: Dictionary, dt: float) -> void:
	var participants: Array = combat.get("participants", [])
	var monsters: Array = sp.get("monsters", [])
	if participants.is_empty() or monsters.is_empty():
		return

	for i in range(monsters.size()):
		var m: Dictionary = monsters[i]
		var t: float = float(m.get("attack_timer", 0.0)) - dt
		if t <= 0.0:
			# Monsters hit ONE adventurer per attack.
			var dmg: int = int(m.get("attack_damage", 1))
			var alive: Array[Node2D] = []
			for p in participants:
				if is_instance_valid(p):
					alive.append(p as Node2D)
			if not alive.is_empty():
				var pick: Node2D = alive[randi() % alive.size()]
				pick.call("apply_damage", dmg)
			t += float(m.get("attack_interval", 1.0))
		m["attack_timer"] = t
		monsters[i] = m

	sp["monsters"] = monsters


func _dungeon_local_to_world(local_pos: Vector2) -> Vector2:
	if _dungeon_view == null:
		return local_pos
	return (_dungeon_view as CanvasItem).get_global_transform() * local_pos


func _assign_combat_positions(room: Dictionary, combat: Dictionary, sp: Dictionary) -> void:
	# Create deterministic-ish positions for participants/monsters inside the room (pure animation).
	if _dungeon_view == null:
		return
	var center_local: Vector2 = _dungeon_view.call("room_center_local", room) as Vector2
	var center_world: Vector2 = _dungeon_local_to_world(center_local)

	var participants: Array = combat.get("participants", [])
	var adv_targets: Dictionary = combat.get("adv_targets", {})
	var mon_targets: Dictionary = combat.get("mon_targets", {})

	# Adventurers line up on the left side of the room center.
	var n_adv := participants.size()
	for i in range(n_adv):
		var p: Node2D = participants[i] as Node2D
		if not is_instance_valid(p):
			continue
		var t_y := (float(i) - float(n_adv - 1) * 0.5) * 14.0
		adv_targets[int(p.get_instance_id())] = center_world + Vector2(-28.0, t_y)

	# Monsters line up on the right side of the room center.
	var monsters: Array = sp.get("monsters", [])
	var mon_actors: Array[Node2D] = []
	for m in monsters:
		var md := m as Dictionary
		var actor: Variant = md.get("actor", null)
		if actor != null and is_instance_valid(actor):
			mon_actors.append(actor as Node2D)

	var n_mon := mon_actors.size()
	for j in range(n_mon):
		var a: Node2D = mon_actors[j]
		var t_y2 := (float(j) - float(n_mon - 1) * 0.5) * 14.0
		mon_targets[int(a.get_instance_id())] = center_world + Vector2(28.0, t_y2)

	combat["adv_targets"] = adv_targets
	combat["mon_targets"] = mon_targets


func _animate_combat_positions(combat: Dictionary, sp: Dictionary, dt: float) -> void:
	var adv_targets: Dictionary = combat.get("adv_targets", {})
	var mon_targets: Dictionary = combat.get("mon_targets", {})

	var participants: Array = combat.get("participants", [])
	for p in participants:
		var adv: Node2D = p as Node2D
		if not is_instance_valid(adv):
			continue
		var key: int = int(adv.get_instance_id())
		if not adv_targets.has(key):
			continue
		var target: Vector2 = adv_targets[key] as Vector2
		adv.global_position = adv.global_position.move_toward(target, COMBAT_MOVE_SPEED * dt)

	var monsters: Array = sp.get("monsters", [])
	for m in monsters:
		var md := m as Dictionary
		var actor: Variant = md.get("actor", null)
		if actor == null or not is_instance_valid(actor):
			continue
		var a: Node2D = actor as Node2D
		var key2: int = int(a.get_instance_id())
		if not mon_targets.has(key2):
			continue
		var target2: Vector2 = mon_targets[key2] as Vector2
		a.global_position = a.global_position.move_toward(target2, COMBAT_MOVE_SPEED * dt)


func _sync_monster_actor(m: Dictionary) -> void:
	var actor: Variant = m.get("actor", null)
	if actor != null and is_instance_valid(actor):
		(actor as Node).call("set_hp", int(m.get("hp", 0)), int(m.get("max_hp", 1)))


