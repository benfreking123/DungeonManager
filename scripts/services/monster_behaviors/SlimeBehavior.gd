extends RefCounted

const SPLIT_COUNT := 2
const SPLIT_ID := "slime_small"


func on_death(mi: MonsterInstance, context: Dictionary, simulation: Node) -> bool:
	if mi == null:
		return false
	# Only split standard slime.
	if String(mi.template_id) != "slime":
		return false
	var actor := mi.actor as Node2D
	if actor != null and is_instance_valid(actor):
		_spawn_slime_sparkles(actor)
	if simulation == null:
		return false
	var room_id := int(context.get("room_id", 0))
	if room_id == 0:
		room_id = int(mi.current_room_id)
	var pos := Vector2.ZERO
	if actor != null and is_instance_valid(actor):
		pos = actor.global_position
	if simulation.has_method("spawn_monster_in_room"):
		simulation.call("spawn_monster_in_room", room_id, SPLIT_ID, SPLIT_COUNT, pos)
		return true
	return false


func _spawn_slime_sparkles(actor: Node2D) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	var ring := preload("res://scripts/fx/AbilityRing.gd").new()
	ring.color = Color(0.45, 1.0, 0.45, 1.0)
	ring.duration_s = 0.4
	ring.start_radius = 6.0
	ring.end_radius = 26.0
	ring.thickness_px = 3.0
	actor.add_child(ring)
	ring.position = Vector2.ZERO
