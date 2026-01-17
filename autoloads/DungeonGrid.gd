extends Node

signal layout_changed()

const CELL_SIZE := 32
const GRID_W := 40
const GRID_H := 20

# Navigation/pathfinding on occupied cells.
var astar: AStarGrid2D

# Room instances:
# { id: int, type_id: String, pos: Vector2i, size: Vector2i, kind: String, known: bool, locked: bool, slots: Array, max_monster_size_capacity: int }
var rooms: Array[Dictionary] = []

var _next_room_id: int = 1
var _occ := {} # Dictionary<Vector2i, int room_id>


func _can_edit_layout() -> bool:
	# Hard rule: dungeon layout/slots can only be edited during BUILD.
	# Pan/zoom are handled by HUD and remain available during DAY.
	return GameState != null and GameState.phase == GameState.Phase.BUILD


func ensure_room_defaults() -> bool:
	# Backfill slots/capacity for rooms created before these fields existed.
	var changed := false
	var room_db := get_node_or_null("/root/RoomDB")
	for i in range(rooms.size()):
		var r: Dictionary = rooms[i]
		var kind := String(r.get("kind", ""))
		var type_id := String(r.get("type_id", ""))
		var max_slots := 0
		if room_db != null and room_db.has_method("get_room_type"):
			var def: Dictionary = room_db.call("get_room_type", type_id) as Dictionary
			max_slots = int(def.get("max_slots", 0))

		# Ensure correct slot count for rooms with installable slots.
		var cur_slots: Array = r.get("slots", [])
		if max_slots <= 0:
			if not cur_slots.is_empty():
				r["slots"] = []
				changed = true
		else:
			var next_slots: Array = []
			var needs_rebuild := (cur_slots.size() != max_slots)
			for si in range(max_slots):
				var installed := ""
				var cur_kind := ""
				if si < cur_slots.size():
					var cur := cur_slots[si] as Dictionary
					installed = String(cur.get("installed_item_id", ""))
					cur_kind = String(cur.get("slot_kind", ""))
				var want_kind := _slot_kind_for_room(kind, si, max_slots)
				if want_kind != cur_kind:
					needs_rebuild = true
				next_slots.append({ "slot_kind": want_kind, "installed_item_id": installed })
			if needs_rebuild:
				r["slots"] = next_slots
				changed = true

		if kind == "monster":
			if int(r.get("max_monster_size_capacity", 0)) <= 0:
				r["max_monster_size_capacity"] = 3
				changed = true
		rooms[i] = r
	if changed:
		layout_changed.emit()
	return changed


func clear() -> void:
	if not _can_edit_layout():
		return
	rooms.clear()
	_occ.clear()
	_next_room_id = 1
	_rebuild_astar()
	layout_changed.emit()


func can_place(_type_id: String, pos: Vector2i, size: Vector2i) -> bool:
	if pos.x < 0 or pos.y < 0:
		return false
	if pos.x + size.x > GRID_W or pos.y + size.y > GRID_H:
		return false
	for x in range(size.x):
		for y in range(size.y):
			var c := Vector2i(pos.x + x, pos.y + y)
			if _occ.has(c):
				return false
	return true


func place_room(type_id: String, pos: Vector2i, size: Vector2i, kind: String, locked: bool = false) -> int:
	if not _can_edit_layout():
		return 0
	if not can_place(type_id, pos, size):
		return 0
	var id := _next_room_id
	_next_room_id += 1
	var slots: Array = []
	var max_monster_size_capacity: int = 0
	var room_db := get_node_or_null("/root/RoomDB")
	var max_slots := 0
	if room_db != null and room_db.has_method("get_room_type"):
		var def: Dictionary = room_db.call("get_room_type", type_id) as Dictionary
		max_slots = int(def.get("max_slots", 0))

	if max_slots > 0 and kind in ["trap", "monster", "treasure", "boss"]:
		for si in range(max_slots):
			slots.append({ "slot_kind": _slot_kind_for_room(kind, si, max_slots), "installed_item_id": "" })
	if kind == "monster":
		max_monster_size_capacity = 3

	var room := {
		"id": id,
		"type_id": type_id,
		"pos": pos,
		"size": size,
		"kind": kind,
		"known": true,
		"locked": locked,
		"slots": slots,
		"max_monster_size_capacity": max_monster_size_capacity,
	}
	rooms.append(room)
	for x in range(size.x):
		for y in range(size.y):
			_occ[Vector2i(pos.x + x, pos.y + y)] = id
	_rebuild_astar()
	layout_changed.emit()
	return id


func _slot_kind_for_room(kind: String, slot_idx: int, max_slots: int) -> String:
	# Slot kind policy by room kind.
	match kind:
		"boss":
			# Boss room: 2 universal slots + 1 boss upgrade slot.
			if slot_idx <= 1:
				return "universal"
			# Keep last slot as boss upgrade even if max_slots changes.
			if slot_idx == max_slots - 1:
				return "boss_upgrade"
			return "universal"
		"monster", "trap", "treasure":
			return kind
		_:
			return ""


func force_move_room_of_kind(kind: String, new_pos: Vector2i) -> bool:
	if not _can_edit_layout():
		return false
	# Used for fixed structures like Entrance. Attempts to relocate without deleting the dungeon.
	var idx := -1
	for i in range(rooms.size()):
		if rooms[i].get("kind", "") == kind:
			idx = i
			break
	if idx == -1:
		return false

	var room := rooms[idx]
	var id: int = room.get("id", 0)
	var size: Vector2i = room.get("size", Vector2i.ONE)

	# Bounds check
	if new_pos.x < 0 or new_pos.y < 0:
		return false
	if new_pos.x + size.x > GRID_W or new_pos.y + size.y > GRID_H:
		return false

	# Temporarily clear occupancy for this room id.
	var cleared: Array[Vector2i] = []
	for x in range(GRID_W):
		for y in range(GRID_H):
			var c := Vector2i(x, y)
			if _occ.get(c, -1) == id:
				_occ.erase(c)
				cleared.append(c)

	# Check target area is empty.
	var ok := true
	for x in range(size.x):
		for y in range(size.y):
			var c := Vector2i(new_pos.x + x, new_pos.y + y)
			if _occ.has(c):
				ok = false
				break
		if not ok:
			break

	if not ok:
		# Restore occupancy
		for c in cleared:
			_occ[c] = id
		return false

	# Move and rebuild occupancy for this room.
	room["pos"] = new_pos
	rooms[idx] = room
	for x in range(size.x):
		for y in range(size.y):
			_occ[Vector2i(new_pos.x + x, new_pos.y + y)] = id

	_rebuild_astar()
	layout_changed.emit()
	return true


func get_room_by_id(room_id: int) -> Dictionary:
	for r in rooms:
		if int(r.get("id", 0)) == room_id:
			return r
	return {}


func set_room_by_id(room_id: int, new_room: Dictionary) -> bool:
	for i in range(rooms.size()):
		if int(rooms[i].get("id", 0)) == room_id:
			rooms[i] = new_room
			layout_changed.emit()
			return true
	return false


func install_item_in_slot(room_id: int, slot_idx: int, item_id: String) -> bool:
	if not _can_edit_layout():
		return false
	var room := get_room_by_id(room_id)
	if room.is_empty():
		return false
	var slots: Array = room.get("slots", [])
	if slot_idx < 0 or slot_idx >= slots.size():
		return false
	var slot: Dictionary = slots[slot_idx]
	if String(slot.get("installed_item_id", "")) != "":
		return false
	slot["installed_item_id"] = item_id
	slots[slot_idx] = slot
	room["slots"] = slots
	return set_room_by_id(room_id, room)


func uninstall_item_from_slot(room_id: int, slot_idx: int) -> String:
	if not _can_edit_layout():
		return ""
	var room := get_room_by_id(room_id)
	if room.is_empty():
		return ""
	var slots: Array = room.get("slots", [])
	if slot_idx < 0 or slot_idx >= slots.size():
		return ""
	var slot: Dictionary = slots[slot_idx]
	var item_id := String(slot.get("installed_item_id", ""))
	if item_id == "":
		return ""
	slot["installed_item_id"] = ""
	slots[slot_idx] = slot
	room["slots"] = slots
	set_room_by_id(room_id, room)
	return item_id


func remove_room_at(cell: Vector2i) -> bool:
	if not _can_edit_layout():
		return false
	if not _occ.has(cell):
		return false
	var id: int = _occ[cell]
	var idx := -1
	for i in range(rooms.size()):
		if rooms[i]["id"] == id:
			idx = i
			break
	if idx == -1:
		return false
	var r := rooms[idx]
	if bool(r.get("locked", false)):
		return false
	rooms.remove_at(idx)
	_rebuild_occ()
	_rebuild_astar()
	layout_changed.emit()
	return true


func _rebuild_occ() -> void:
	_occ.clear()
	for r in rooms:
		var pos: Vector2i = r["pos"]
		var size: Vector2i = r["size"]
		for x in range(size.x):
			for y in range(size.y):
				_occ[Vector2i(pos.x + x, pos.y + y)] = r["id"]

func _ensure_astar() -> void:
	if astar != null:
		return
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, GRID_W, GRID_H)
	astar.cell_size = Vector2(CELL_SIZE, CELL_SIZE)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.update()


func _rebuild_astar() -> void:
	_ensure_astar()
	astar.update()
	for x in range(GRID_W):
		for y in range(GRID_H):
			var cell := Vector2i(x, y)
			# Only cells covered by rooms are walkable.
			astar.set_point_solid(cell, not _occ.has(cell))


func find_path(start_cell: Vector2i, end_cell: Vector2i) -> Array[Vector2i]:
	_ensure_astar()
	if not astar.is_in_boundsv(start_cell) or not astar.is_in_boundsv(end_cell):
		return []
	if astar.is_point_solid(start_cell) or astar.is_point_solid(end_cell):
		return []
	return astar.get_id_path(start_cell, end_cell)


func has_kind(kind: String) -> bool:
	for r in rooms:
		if r.get("kind", "") == kind:
			return true
	return false


func count_kind(kind: String) -> int:
	var c := 0
	for r in rooms:
		if r.get("kind", "") == kind:
			c += 1
	return c


func get_first_room_of_kind(kind: String) -> Dictionary:
	for r in rooms:
		if r.get("kind", "") == kind:
			return r
	return {}


func get_anchor_cell(room: Dictionary) -> Vector2i:
	# For now, top-left is fine (keeps paths stable/deterministic).
	return room.get("pos", Vector2i.ZERO)


func validate_required_paths() -> Dictionary:
	# Returns { ok: bool, reason: String }
	# Only validates once required rooms exist.
	var entrance := get_first_room_of_kind("entrance")
	var boss := get_first_room_of_kind("boss")
	var treasure := get_first_room_of_kind("treasure")

	if entrance.is_empty() or boss.is_empty():
		return { "ok": true, "reason": "missing_required_rooms" }

	var e := get_anchor_cell(entrance)
	var b := get_anchor_cell(boss)
	var p1 := find_path(e, b)
	if p1.is_empty():
		return { "ok": false, "reason": "no_path_entrance_to_boss" }

	if not treasure.is_empty():
		var t := get_anchor_cell(treasure)
		var p2 := find_path(e, t)
		if p2.is_empty():
			return { "ok": false, "reason": "no_path_entrance_to_treasure" }

	return { "ok": true, "reason": "ok" }


func get_room_at(cell: Vector2i) -> Dictionary:
	if not _occ.has(cell):
		return {}
	var id: int = _occ[cell]
	for r in rooms:
		if r["id"] == id:
			return r
	return {}
