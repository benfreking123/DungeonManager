extends RefCounted

# Handles trap room mechanics (on-entry effects) separate from Simulation.gd.

var _item_db: Node


func setup(item_db: Node) -> void:
	_item_db = item_db


func reset() -> void:
	# Reserved for future per-room state (cooldowns, disarms, etc.)
	pass


func on_room_enter(room: Dictionary, entering_adv: Node2D, adventurers: Array[Node2D], adv_last_room: Dictionary) -> void:
	if _item_db == null:
		return

	var slots: Array = room.get("slots", [])
	if slots.is_empty():
		return

	var room_id: int = int(room.get("id", 0))
	if room_id == 0:
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
	for s in slots:
		var sd := s as Dictionary
		if sd.is_empty():
			continue
		var item_id := String(sd.get("installed_item_id", ""))
		if item_id == "":
			continue

		var trap: TrapItem = _item_db.call("get_trap", item_id) as TrapItem
		if trap == null:
			continue

		if randf() > float(trap.proc_chance):
			continue

		if bool(trap.hits_all):
			for t in targets:
				if is_instance_valid(t):
					t.call("apply_damage", int(trap.damage))
		else:
			var valid: Array[Node2D] = []
			for t2 in targets:
				if is_instance_valid(t2):
					valid.append(t2)
			if valid.is_empty():
				continue
			var idx := int(randi() % valid.size())
			valid[idx].call("apply_damage", int(trap.damage))

