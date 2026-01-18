extends Node

signal stash_changed()

# Treasure stolen by adventurers that successfully exit the dungeon.
# This is intentionally a simple counter map (recover system can be added later).
var counts: Dictionary = {} # item_id -> int


func add(item_id: String, amount: int = 1) -> void:
	if item_id == "" or amount <= 0:
		return
	counts[item_id] = int(counts.get(item_id, 0)) + int(amount)
	stash_changed.emit()


func get_count(item_id: String) -> int:
	return int(counts.get(item_id, 0))


func reset_all() -> void:
	counts.clear()
	stash_changed.emit()

