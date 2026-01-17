extends RefCounted
class_name MonsterInstance

# Runtime monster state (separate from the MonsterItem template resource).

var instance_id: int = 0
var template_id: String = ""
var spawn_room_id: int = 0
var current_room_id: int = 0

var hp: int = 1
var max_hp: int = 1
var attack_timer: float = 0.0

var actor: Node2D
var template: MonsterItem


func setup_from_template(mi: MonsterItem, spawn_room: int, room_now: int, actor_node: Node2D) -> void:
	template = mi
	template_id = mi.id if mi != null else ""
	spawn_room_id = spawn_room
	current_room_id = room_now
	actor = actor_node
	if mi != null:
		max_hp = int(mi.max_hp)
		hp = max_hp
	else:
		max_hp = 1
		hp = 1
	attack_timer = 0.0


func is_alive() -> bool:
	return hp > 0


func is_boss() -> bool:
	return template_id == "boss"


func attack_damage() -> int:
	return int(template.attack_damage) if template != null else 1


func attack_interval() -> float:
	return float(template.attack_interval) if template != null else 1.0


func range_px() -> float:
	var r := float(template.range) if template != null else 0.0
	return r


func size_units() -> int:
	return int(template.size) if template != null else 1

