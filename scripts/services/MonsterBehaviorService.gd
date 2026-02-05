extends RefCounted
class_name MonsterBehaviorService

var _simulation: Node = null
var _handlers: Dictionary = {}


func setup(simulation: Node) -> void:
	_simulation = simulation
	_handlers.clear()
	# Register per-monster handlers here.
	var slime_handler := preload("res://scripts/services/monster_behaviors/SlimeBehavior.gd").new()
	_handlers["slime"] = slime_handler


func on_monster_died(mi: MonsterInstance, context: Dictionary) -> bool:
	if mi == null:
		return false
	var id := String(mi.template_id)
	if id == "":
		return false
	var handler: Object = _handlers.get(id, null)
	if handler == null:
		return false
	if handler.has_method("on_death"):
		return bool(handler.call("on_death", mi, context, _simulation))
	return false
