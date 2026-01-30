extends RefCounted

# Handles trap room mechanics (on-entry effects) separate from Simulation.gd.

var _item_db: Node
var _simulation: Node

# Per room-slot state.
# key: "%d:%d" % [room_id, slot_idx]
# value: { "cooldown_until_s": float, "charges_left": int, "disarmed": bool }
var _slot_state: Dictionary = {}

# Per-room disarm state (covers rooms not yet initialized).
# room_id -> bool
var _room_disarmed: Dictionary = {}

# Per-room temporary proc buffs (used by rearm).
# room_id -> { "proc_bonus_until_s": float, "proc_bonus_add": float }
var _room_buffs: Dictionary = {}


func setup(item_db: Node, simulation: Node = null) -> void:
	_item_db = item_db
	_simulation = simulation


func reset_for_new_day(dungeon_grid: Node) -> void:
	# Initialize trap state from the current dungeon layout (installed items).
	_slot_state.clear()
	_room_disarmed.clear()
	_room_buffs.clear()
	if _item_db == null or dungeon_grid == null:
		return
	var now_s := _now_s()
	# DungeonGrid stores room instances in a public `rooms` array.
	var rooms: Array = dungeon_grid.get("rooms") as Array
	if rooms.is_empty():
		return
	for r in rooms:
		var room := r as Dictionary
		if room.is_empty():
			continue
		var room_id: int = int(room.get("id", 0))
		if room_id == 0:
			continue
		var slots: Array = room.get("slots", [])
		for i in range(slots.size()):
			var sd := slots[i] as Dictionary
			var item_id := String(sd.get("installed_item_id", ""))
			if item_id == "":
				continue
			# Only track trap items.
			var trap: TrapItem = _item_db.call("get_trap", item_id) as TrapItem
			if trap == null:
				continue
			var cd_until := now_s if bool(trap.start_ready) else (now_s + maxf(0.0, float(trap.cooldown_s)))
			var charges := int(trap.trigger_amount)
			_slot_state[_slot_key(room_id, i)] = {
				"cooldown_until_s": cd_until,
				"charges_left": charges,
				"disarmed": false,
			}


func is_slot_ready(room_id: int, slot_idx: int, item_id: String) -> bool:
	if _item_db == null:
		return false
	if bool(_room_disarmed.get(int(room_id), false)):
		return false
	var trap: TrapItem = _item_db.call("get_trap", String(item_id)) as TrapItem
	if trap == null:
		return false
	var st: Dictionary = _slot_state.get(_slot_key(int(room_id), int(slot_idx)), {}) as Dictionary
	if st.is_empty():
		# If we haven't initialized state (e.g., old save), treat as ready.
		return true
	if bool(st.get("disarmed", false)):
		return false
	var charges_left := int(st.get("charges_left", -1))
	if charges_left == 0:
		return false
	return _now_s() >= float(st.get("cooldown_until_s", 0.0))


func disarm_room(room_id: int) -> void:
	var rid := int(room_id)
	_room_disarmed[rid] = true
	for k in _slot_state.keys():
		var key := String(k)
		if key.begins_with("%d:" % rid):
			var st: Dictionary = _slot_state[key] as Dictionary
			st["disarmed"] = true
			_slot_state[key] = st


func on_room_enter(room: Dictionary, entering_adv: Node2D, adventurers: Array[Node2D], adv_last_room: Dictionary) -> void:
	if _item_db == null:
		return

	var slots: Array = room.get("slots", [])
	if slots.is_empty():
		return

	var room_id: int = int(room.get("id", 0))
	if room_id == 0:
		return
	if bool(_room_disarmed.get(room_id, false)):
		return

	# Determine all adventurers currently in this room (same room_id).
	var targets: Array[Node2D] = []
	for a in adventurers:
		if not is_instance_valid(a):
			continue
		var key: int = int(a.get_instance_id())
		if int(adv_last_room.get(key, 0)) == room_id:
			targets.append(a)
	if targets.is_empty() and is_instance_valid(entering_adv):
		targets.append(entering_adv)
	if targets.is_empty():
		return

	# Process ALL installed trap slots (each can independently proc).
	for slot_idx in range(slots.size()):
		var sd := slots[slot_idx] as Dictionary
		if sd.is_empty():
			continue
		var item_id := String(sd.get("installed_item_id", ""))
		if item_id == "":
			continue

		var trap: TrapItem = _item_db.call("get_trap", item_id) as TrapItem
		if trap == null:
			continue

		var k := _slot_key(room_id, slot_idx)
		var st: Dictionary = _slot_state.get(k, {}) as Dictionary
		if st.is_empty():
			# Lazy init (in case reset_for_new_day wasn't called).
			var cd_until := _now_s() if bool(trap.start_ready) else (_now_s() + maxf(0.0, float(trap.cooldown_s)))
			st = {
				"cooldown_until_s": cd_until,
				"charges_left": int(trap.trigger_amount),
				"disarmed": false,
			}
			_slot_state[k] = st

		if bool(st.get("disarmed", false)):
			continue
		var charges_left := int(st.get("charges_left", -1))
		if charges_left == 0:
			continue
		if _now_s() < float(st.get("cooldown_until_s", 0.0)):
			continue

		# Apply any active per-room proc bonus (rearm).
		var eff_proc := float(trap.proc_chance)
		var rb: Dictionary = _room_buffs.get(room_id, {}) as Dictionary
		if not rb.is_empty() and _now_s() < float(rb.get("proc_bonus_until_s", 0.0)):
			eff_proc += float(rb.get("proc_bonus_add", 0.0))
		eff_proc = clampf(eff_proc, 0.0, 1.0)

		if randf() > eff_proc:
			continue

		# Consume charge (unless unlimited).
		if charges_left > 0:
			st["charges_left"] = charges_left - 1
		# Start cooldown on proc.
		st["cooldown_until_s"] = _now_s() + maxf(0.0, float(trap.cooldown_s))
		_slot_state[k] = st

		# Execute effect (supports optional per-trap delay).
		var d := 0.0
		# Safe access in case of older resources without delay_s (backward-compatible).
		var v_delay: Variant = trap.get("delay_s")
		if typeof(v_delay) == TYPE_FLOAT or typeof(v_delay) == TYPE_INT:
			d = float(v_delay)
		if d > 0.0001:
			var tree := Engine.get_main_loop()
			if tree is SceneTree:
				var timer := (tree as SceneTree).create_timer(d)
				timer.timeout.connect(func():
					_execute_effect(room_id, slot_idx, trap, targets, entering_adv, adventurers, adv_last_room)
				)
			else:
				# Fallback: execute immediately if we cannot obtain a SceneTree.
				_execute_effect(room_id, slot_idx, trap, targets, entering_adv, adventurers, adv_last_room)
		else:
			_execute_effect(room_id, slot_idx, trap, targets, entering_adv, adventurers, adv_last_room)

func _execute_effect(room_id: int, _slot_idx: int, trap: TrapItem, targets: Array[Node2D], _entering_adv: Node2D, _adventurers: Array[Node2D], _adv_last_room: Dictionary) -> void:
	var valid: Array[Node2D] = []
	for t in targets:
		if is_instance_valid(t):
			valid.append(t)
	if valid.is_empty():
		return

	match String(trap.effect):
		"damage_all":
			var dmg := int(trap.value)
			for t2 in valid:
				t2.call("apply_damage", dmg)
		"damage_single":
			var dmg2 := int(trap.value)
			var idx := int(randi() % valid.size())
			valid[idx].call("apply_damage", dmg2)
		"teleport_random_room":
			# Teleport one party member to a random (non-boss) room.
			if _simulation != null and _simulation.has_method("teleport_adv_to_random_room"):
				var idx2 := int(randi() % valid.size())
				var adv_id := int(valid[idx2].get_instance_id())
				_simulation.call("teleport_adv_to_random_room", adv_id, int(room_id))
		"web_pause":
			# Brief movement pause (cast-time style stagger). value = seconds.
			var dur_s := float(int(trap.value))
			if dur_s <= 0.0:
				dur_s = 1.0
			for t3 in valid:
				if t3.has_method("pause_for"):
					t3.call("pause_for", dur_s)
		"rearm_buff":
			# Apply a temporary proc bonus to other traps in the room.
			# value = duration in seconds. Bonus amount is a fixed additive bump.
			var dur2 := float(int(trap.value))
			if dur2 <= 0.0:
				dur2 = 6.0
			_room_buffs[int(room_id)] = {
				"proc_bonus_until_s": _now_s() + dur2,
				"proc_bonus_add": 0.25,
			}
			# Basic single-target damage.
			var idx3 := int(randi() % valid.size())
			valid[idx3].call("apply_damage", 1)
		_:
			# Unknown effect: do nothing.
			pass


func _slot_key(room_id: int, slot_idx: int) -> String:
	return "%d:%d" % [int(room_id), int(slot_idx)]


func _now_s() -> float:
	return float(Time.get_ticks_msec()) / 1000.0