extends RefCounted

# Owns all runtime MonsterInstance objects and indexes them by room.

var _next_id: int = 1

# instance_id -> MonsterInstance
var _by_id: Dictionary = {}

# room_id -> Array[int] (instance ids)
var _ids_by_room: Dictionary = {}

# spawn_room_id -> Array[int] (instance ids)
var _ids_by_spawn_room: Dictionary = {}


func reset() -> void:
	_next_id = 1
	_by_id.clear()
	_ids_by_room.clear()
	_ids_by_spawn_room.clear()


func add(mon: MonsterInstance) -> MonsterInstance:
	if mon == null:
		return null
	if mon.instance_id == 0:
		mon.instance_id = _next_id
		_next_id += 1
	_by_id[mon.instance_id] = mon
	_index(mon.instance_id, mon.current_room_id, mon.spawn_room_id)
	return mon


func remove(instance_id: int) -> void:
	var mon: MonsterInstance = _by_id.get(instance_id, null) as MonsterInstance
	if mon == null:
		return
	_unindex(instance_id, mon.current_room_id, mon.spawn_room_id)
	_by_id.erase(instance_id)


func move_to_room(instance_id: int, new_room_id: int) -> void:
	var mon: MonsterInstance = _by_id.get(instance_id, null) as MonsterInstance
	if mon == null:
		return
	if mon.current_room_id == new_room_id:
		return
	_unindex(instance_id, mon.current_room_id, mon.spawn_room_id)
	mon.current_room_id = new_room_id
	_index(instance_id, mon.current_room_id, mon.spawn_room_id)


func get_monsters_in_room(room_id: int) -> Array[MonsterInstance]:
	var out: Array[MonsterInstance] = []
	var ids: Array = _ids_by_room.get(room_id, [])
	for iid in ids:
		var mon: MonsterInstance = _by_id.get(int(iid), null) as MonsterInstance
		if mon != null:
			out.append(mon)
	return out


func get_all_monsters() -> Array[MonsterInstance]:
	var out: Array[MonsterInstance] = []
	for k in _by_id.keys():
		var mon: MonsterInstance = _by_id.get(int(k), null) as MonsterInstance
		if mon != null:
			out.append(mon)
	return out


func size_sum_in_room(room_id: int) -> int:
	var sum := 0
	for mon in get_monsters_in_room(room_id):
		if mon != null and mon.is_alive():
			sum += mon.size_units()
	return sum


func count_in_room(room_id: int) -> int:
	return int((_ids_by_room.get(room_id, []) as Array).size())


func collect_actor_bodies() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for mon in get_all_monsters():
		if mon == null:
			continue
		var a: Node2D = mon.actor
		if a != null and is_instance_valid(a):
			out.append(a)
	return out


func clear_all_actors() -> void:
	for mon in get_all_monsters():
		if mon == null:
			continue
		var a: Node2D = mon.actor
		if a != null and is_instance_valid(a):
			a.queue_free()


func _index(instance_id: int, room_id: int, spawn_room_id: int) -> void:
	if room_id != 0:
		var a: Array = _ids_by_room.get(room_id, [])
		a.append(instance_id)
		_ids_by_room[room_id] = a
	if spawn_room_id != 0:
		var b: Array = _ids_by_spawn_room.get(spawn_room_id, [])
		b.append(instance_id)
		_ids_by_spawn_room[spawn_room_id] = b


func _unindex(instance_id: int, room_id: int, spawn_room_id: int) -> void:
	if room_id != 0 and _ids_by_room.has(room_id):
		var a: Array = _ids_by_room[room_id]
		a.erase(instance_id)
		if a.is_empty():
			_ids_by_room.erase(room_id)
		else:
			_ids_by_room[room_id] = a
	if spawn_room_id != 0 and _ids_by_spawn_room.has(spawn_room_id):
		var b: Array = _ids_by_spawn_room[spawn_room_id]
		b.erase(instance_id)
		if b.is_empty():
			_ids_by_spawn_room.erase(spawn_room_id)
		else:
			_ids_by_spawn_room[spawn_room_id] = b

