extends Node

signal inventory_changed()

# Room-piece inventory (for build phase).
# Keys are RoomDB type ids: hall, monster, trap, boss, treasure

var counts: Dictionary = {}


func get_count(id: String) -> int:
	return int(counts.get(id, 0))


func can_consume(id: String, amount: int = 1) -> bool:
	return get_count(id) >= amount


func consume(id: String, amount: int = 1) -> bool:
	if not can_consume(id, amount):
		return false
	counts[id] = get_count(id) - amount
	inventory_changed.emit()
	return true


func refund(id: String, amount: int = 1) -> void:
	counts[id] = get_count(id) + amount
	inventory_changed.emit()


func _ready() -> void:
	# Defer rebuild so other autoloads/UI are ready before we emit.
	call_deferred("_rebuild_from_config")


func _rebuild_from_config() -> void:
	var rooms := StartInventoryService.get_merged_rooms()
	counts = StartInventoryService.to_room_counts(rooms)
	if Engine.has_singleton("DbgLog"):
		DbgLog.debug("RoomInventory: built room counts from config ids=%s" % str(counts.keys()), "inventory")
	inventory_changed.emit()


func reset_all() -> void:
	_rebuild_from_config()


