extends Node

const ROOM_TYPES_DIR := "res://scripts/rooms"

const ROOM_TYPE_SCRIPT := preload("res://scripts/rooms/RoomType.gd")

var _room_types: Dictionary = {} # String -> Resource (RoomType)


func _ready() -> void:
	_load_room_types()


func _load_room_types() -> void:
	_room_types.clear()
	var dir := DirAccess.open(ROOM_TYPES_DIR)
	if dir == null:
		push_error("RoomDB: missing dir %s" % ROOM_TYPES_DIR)
		return
	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name == "":
			break
		if dir.current_is_dir():
			continue
		if not file_name.ends_with(".tres"):
			continue
		var res_path := "%s/%s" % [ROOM_TYPES_DIR, file_name]
		var res: Resource = load(res_path)
		if res != null and res.get_script() == ROOM_TYPE_SCRIPT:
			var id := String(res.get("id"))
			if id == "":
				push_warning("RoomDB: RoomType missing id: %s" % res_path)
				continue
			_room_types[id] = res
	dir.list_dir_end()


func get_room_type(id: String) -> Dictionary:
	var rt: Resource = _room_types.get(id, null) as Resource
	return _to_dict(rt)


func list_room_types() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k in _room_types.keys():
		out.append(_to_dict(_room_types[k] as Resource))
	return out


func _to_dict(rt: Resource) -> Dictionary:
	if rt == null:
		return {}
	var v_size: Variant = rt.get("size")
	var v_power: Variant = rt.get("power_cost")
	var v_max: Variant = rt.get("max_slots")
	var v_eff: Variant = rt.get("effect_id")
	var v_mon_cap: Variant = rt.get("monster_capacity")
	var v_mon_cd: Variant = rt.get("monster_cooldown_per_size")
	var v_rarity: Variant = rt.get("rarity")
	return {
		"id": String(rt.get("id")),
		"label": String(rt.get("label")),
		"size": (v_size as Vector2i) if v_size != null else Vector2i.ONE,
		"power_cost": int(v_power) if v_power != null else 0,
		"kind": String(rt.get("kind")),
		"max_slots": int(v_max) if v_max != null else 0,
		"effect_id": String(v_eff) if v_eff != null else "",
		"monster_capacity": int(v_mon_cap) if v_mon_cap != null else 3,
		"monster_cooldown_per_size": float(v_mon_cd) if v_mon_cd != null else 5.0,
		"rarity": String(v_rarity) if v_rarity != null else "common",
	}



