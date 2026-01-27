extends RefCounted
class_name FogOfWarService

var _grid: Node = null
var _adj: Dictionary = {} # room_id -> Array[int]
var _known_by_room_id: Dictionary = {} # int -> bool
var _version: int = 0


func setup(dungeon_grid: Node) -> void:
	_grid = dungeon_grid


func reset_for_new_day() -> void:
	_version += 1
	_known_by_room_id.clear()
	_adj.clear()
	if _grid == null:
		return

	var adj_svc := RoomAdjacencyService.new()
	_adj = adj_svc.build_adjacency(_grid)

	# Default: everything unknown, except entrance.
	var entrance: Dictionary = _grid.call("get_first_room_of_kind", "entrance") as Dictionary
	var entrance_id := int(entrance.get("id", 0))
	DbgLog.debug("Fog reset (entrance_room_id=%d adj_rooms=%d)" % [entrance_id, _adj.keys().size()], "fog")

	var rooms: Array = _grid.get("rooms") as Array
	for r0 in rooms:
		var r := r0 as Dictionary
		if r.is_empty():
			continue
		var rid := int(r.get("id", 0))
		if rid == 0:
			continue
		var known := (rid == entrance_id)
		_known_by_room_id[rid] = known
		_set_room_known_flag(rid, known)


func reveal_on_enter(room_id: int) -> Array[int]:
	# Reveals room_id and distance-1 neighbors. Returns the list of room_ids that changed to known.
	var changed: Array[int] = []
	if room_id == 0:
		return changed
	if _grid == null:
		return changed

	var to_reveal: Array[int] = [room_id]
	var neigh: Array = _adj.get(room_id, []) as Array
	for n0 in neigh:
		to_reveal.append(int(n0))

	for rid0 in to_reveal:
		var rid := int(rid0)
		if rid == 0:
			continue
		if bool(_known_by_room_id.get(rid, false)):
			continue
		_known_by_room_id[rid] = true
		_set_room_known_flag(rid, true)
		changed.append(rid)

	if not changed.is_empty():
		_version += 1
		DbgLog.throttle("fog_reveal", 0.35, "Fog reveal enter_room_id=%d revealed=%d" % [int(room_id), changed.size()], "fog", DbgLog.Level.DEBUG)

	return changed


func is_room_known(room_id: int) -> bool:
	return bool(_known_by_room_id.get(int(room_id), false))


func set_room_known(room_id: int, known: bool) -> void:
	# Public override for systems that want to conceal/reveal specific rooms.
	# Keeps both the internal map and DungeonGrid room dict in sync.
	var rid := int(room_id)
	if rid == 0:
		return
	known = bool(known)
	if bool(_known_by_room_id.get(rid, false)) == known:
		return
	_known_by_room_id[rid] = known
	_set_room_known_flag(rid, known)
	_version += 1


func known_room_ids() -> Array[int]:
	var out: Array[int] = []
	for k in _known_by_room_id.keys():
		if bool(_known_by_room_id.get(k, false)):
			out.append(int(k))
	return out


func adjacent_room_ids(room_id: int) -> Array[int]:
	var arr: Array = _adj.get(int(room_id), []) as Array
	var out: Array[int] = []
	for v in arr:
		out.append(int(v))
	return out


func version() -> int:
	return _version


func _set_room_known_flag(room_id: int, known: bool) -> void:
	if _grid == null:
		return
	var room: Dictionary = _grid.call("get_room_by_id", int(room_id)) as Dictionary
	if room.is_empty():
		return
	# SAFE during DAY: use set_room_by_id (not BUILD-only uninstall APIs).
	room["known"] = bool(known)
	_grid.call("set_room_by_id", int(room_id), room)

