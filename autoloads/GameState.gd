extends Node

signal phase_changed(new_phase: int)
signal speed_changed(new_speed: float)
signal economy_changed()

enum Phase { BUILD, DAY, RESULTS }

var phase: int = Phase.BUILD
var speed: float = 1.0

var treasure_total: int = 0
var power_used: int = 0
var power_capacity: int = 10


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


func add_treasure(amount: int) -> void:
	treasure_total = max(0, treasure_total + amount)
	_recalc_power_capacity()
	economy_changed.emit()


func set_power_used(value: int) -> void:
	power_used = max(0, value)
	economy_changed.emit()


func _recalc_power_capacity() -> void:
	# Simple placeholder curve; refined in the economy todo.
	power_capacity = 10 + int(floor(treasure_total / 25.0)) * 2


func reset_all() -> void:
	treasure_total = 0
	power_used = 0
	power_capacity = 10
	set_speed(1.0)
	set_phase(Phase.BUILD)
	economy_changed.emit()
