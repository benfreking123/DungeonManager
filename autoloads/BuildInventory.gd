extends Node

signal inventory_changed()

# Room counts by room type id.
var counts: Dictionary = {
	"hall": 3,
	"monster": 1,
	"boss": 1,
	"treasure": 1,
	# trap not included by default in this spec
}


func get_count(type_id: String) -> int:
	return int(counts.get(type_id, 0))


func is_tracked(type_id: String) -> bool:
	return counts.has(type_id)


func can_consume(type_id: String, amount: int = 1) -> bool:
	if not is_tracked(type_id):
		return true
	return get_count(type_id) >= amount


func consume(type_id: String, amount: int = 1) -> bool:
	if amount <= 0:
		return true
	if not is_tracked(type_id):
		return true
	if not can_consume(type_id, amount):
		return false
	counts[type_id] = get_count(type_id) - amount
	inventory_changed.emit()
	return true


func refund(type_id: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	if not is_tracked(type_id):
		return
	counts[type_id] = get_count(type_id) + amount
	inventory_changed.emit()


