extends Node

signal inventory_changed()

# Counts by item id.
var counts: Dictionary = {}


func get_count(item_id: String) -> int:
	return int(counts.get(item_id, 0))


func can_consume(item_id: String, amount: int = 1) -> bool:
	return get_count(item_id) >= amount


func consume(item_id: String, amount: int = 1) -> bool:
	if amount <= 0:
		return true
	if not can_consume(item_id, amount):
		return false
	counts[item_id] = get_count(item_id) - amount
	inventory_changed.emit()
	return true


func refund(item_id: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	counts[item_id] = get_count(item_id) + amount
	inventory_changed.emit()


func _ready() -> void:
	# Defer rebuild so other autoloads/UI are ready before we emit.
	call_deferred("_rebuild_from_config")


func _rebuild_from_config() -> void:
	# Build the start inventory from merged config via StartInventoryService.
	var items := StartInventoryService.get_merged_items()
	counts = StartInventoryService.to_item_counts(items)
	if Engine.has_singleton("DbgLog"):
		DbgLog.debug("PlayerInventory: built counts from config ids=%s" % str(counts.keys()), "inventory")
	inventory_changed.emit()


func reset_all() -> void:
	StartInventoryService.reload_from_disk()
	_rebuild_from_config()


func list_owned_ids() -> Array:
	var ids: Array = []
	for k in counts.keys():
		var id := String(k)
		if id == "":
			continue
		if int(counts.get(id, 0)) > 0:
			ids.append(id)
	return ids

