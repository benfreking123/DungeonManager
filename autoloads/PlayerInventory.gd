extends Node

signal inventory_changed()

# Counts by item id.
var counts: Dictionary = {
	"spike_trap": 1,
	"floor_pit": 1,
	"zombie": 1,
	# Boss upgrades
	"armor": 1,
	"attack_speed": 1,
	"damage": 1,
	"double_strike": 1,
	"glop": 1,
	"health": 1,
	"reflect": 1,
	"treasure_base": 0,
	"treasure_mage": 0,
	"treasure_priest": 0,
	"treasure_rogue": 0,
	"treasure_warrior": 0,
}


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


func reset_all() -> void:
	counts = {
		"spike_trap": 1,
		"floor_pit": 1,
		"zombie": 1,
		# Boss upgrades
		"armor": 1,
		"attack_speed": 1,
		"damage": 1,
		"double_strike": 1,
		"glop": 1,
		"health": 1,
		"reflect": 1,
		"treasure_base": 0,
		"treasure_mage": 0,
		"treasure_priest": 0,
		"treasure_rogue": 0,
		"treasure_warrior": 0,
	}
	inventory_changed.emit()


