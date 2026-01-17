extends Node

signal phase_changed(new_phase: int)
signal speed_changed(new_speed: float)
signal economy_changed()

enum Phase { BUILD, DAY, RESULTS }

var phase: int = Phase.BUILD
var speed: float = 1.0

var power_used: int = 0
var power_capacity: int = 10


func _ready() -> void:
	# Recompute power capacity when rooms/slots change (e.g., treasures installed).
	var dg := get_node_or_null("/root/DungeonGrid")
	if dg != null and dg.has_signal("layout_changed"):
		dg.connect("layout_changed", Callable(self, "_on_layout_changed"))
	_recalc_power_capacity()


func _on_layout_changed() -> void:
	_recalc_power_capacity()
	economy_changed.emit()


func set_phase(next_phase: int) -> void:
	if phase == next_phase:
		return
	phase = next_phase
	phase_changed.emit(phase)


func set_speed(next_speed: float) -> void:
	next_speed = clampf(next_speed, 0.0, 8.0)
	if is_equal_approx(speed, next_speed):
		return
	speed = next_speed
	speed_changed.emit(speed)


func set_power_used(value: int) -> void:
	power_used = max(0, value)
	economy_changed.emit()


func _recalc_power_capacity() -> void:
	# Centralize knobs in game_config; keep sensible fallbacks.
	var cfg := get_node_or_null("/root/game_config")
	var base_cap := 10
	var per_treasure_slot := 1
	var treasure_room_effect := "treasure_room_power_capacity_plus_1"
	if cfg != null:
		base_cap = int(cfg.get("BASE_POWER_CAPACITY"))
		per_treasure_slot = int(cfg.get("TREASURE_ROOM_POWER_CAPACITY_PER_TREASURE"))
		treasure_room_effect = String(cfg.get("TREASURE_ROOM_EFFECT_ID"))

	var bonus_from_treasure_room := _count_installed_treasures_in_effect_rooms(treasure_room_effect) * per_treasure_slot

	power_capacity = base_cap + bonus_from_treasure_room


func _count_installed_treasures_in_effect_rooms(effect_id: String) -> int:
	if effect_id == "":
		return 0
	var dg := get_node_or_null("/root/DungeonGrid")
	var room_db := get_node_or_null("/root/RoomDB")
	var item_db := get_node_or_null("/root/ItemDB")
	if dg == null or room_db == null or item_db == null:
		return 0
	var total := 0
	for r in dg.get("rooms"):
		var room := r as Dictionary
		var type_id := String(room.get("type_id", ""))
		if type_id == "":
			continue
		var rt: Dictionary = room_db.call("get_room_type", type_id) as Dictionary
		if String(rt.get("effect_id", "")) != effect_id:
			continue
		var slots: Array = room.get("slots", [])
		for s in slots:
			var sd := s as Dictionary
			var installed := String(sd.get("installed_item_id", ""))
			if installed == "":
				continue
			var kind := String(item_db.call("get_item_kind", installed))
			if kind == "treasure":
				total += 1
	return total


func reset_all() -> void:
	power_used = 0
	power_capacity = 10
	set_speed(1.0)
	set_phase(Phase.BUILD)
	economy_changed.emit()
