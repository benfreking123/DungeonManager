extends Node

signal inventory_changed()

# Room-piece inventory (for build phase).
# Keys are RoomDB type ids: hall, monster, trap, boss, treasure

var counts: Dictionary = {
	"hall": 2,
	"stairs": 2,
	"corridor": 2,
	"hall_plus": 1,
	"hall_t_left": 1,
	"monster": 1,
	"trap": 1,
	"trap_2x1": 1,
	"trap_3x2": 1,
	"boss": 1,
	"treasure": 1,
}


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


func reset_all() -> void:
	counts = {
		"hall": 2,
		"stairs": 2,
		"corridor": 2,
		"hall_plus": 1,
		"hall_t_left": 1,
		"monster": 1,
		"trap": 1,
		"trap_2x1": 1,
		"trap_3x2": 1,
		"boss": 1,
		"treasure": 1,
	}
	inventory_changed.emit()


