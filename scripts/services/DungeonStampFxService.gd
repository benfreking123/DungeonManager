extends RefCounted

# Simple stamp FX manager for room/slot success feedback.

const STAMP_DUR_S := 0.22

var _room_rect: Rect2 = Rect2()
var _room_t0: float = -999.0
var _room_jitter: Vector2 = Vector2.ZERO

var _slot_rect: Rect2 = Rect2()
var _slot_t0: float = -999.0
var _slot_jitter: Vector2 = Vector2.ZERO


func trigger_room(rect: Rect2) -> void:
	_room_rect = rect
	_room_t0 = _now_s()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_usec())
	_room_jitter = Vector2(rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0))


func trigger_slot(rect: Rect2) -> void:
	_slot_rect = rect
	_slot_t0 = _now_s()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_usec()) ^ 0x9E3779B9
	_slot_jitter = Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))


func has_active(now_s: float) -> bool:
	return (now_s - _room_t0 < STAMP_DUR_S) or (now_s - _slot_t0 < STAMP_DUR_S)


# Draws active stamps and returns whether any were drawn.
func draw(view: Control, now_s: float, col: Color) -> bool:
	var any := false
	if now_s - _room_t0 >= 0.0 and now_s - _room_t0 < STAMP_DUR_S:
		var t := clampf((now_s - _room_t0) / STAMP_DUR_S, 0.0, 1.0)
		_draw_stamp_rect(view, _room_rect, col, t, _room_jitter)
		any = true
	if now_s - _slot_t0 >= 0.0 and now_s - _slot_t0 < STAMP_DUR_S:
		var t2 := clampf((now_s - _slot_t0) / STAMP_DUR_S, 0.0, 1.0)
		_draw_stamp_rect(view, _slot_rect, col, t2, _slot_jitter)
		any = true
	return any


func _now_s() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _draw_stamp_rect(view: Control, rect: Rect2, col: Color, t: float, jitter: Vector2) -> void:
	var grow := lerpf(0.0, 8.0, t)
	var a := lerpf(0.85, 0.0, t)
	var r := rect.grow(grow)
	r.position += jitter
	view.draw_rect(r, Color(col.r, col.g, col.b, col.a * a), false, 2.0)
	view.draw_rect(r.grow(-2.0), Color(col.r, col.g, col.b, col.a * a * 0.08), true)

