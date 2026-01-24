extends Node2D
class_name HealPulse

@export var color: Color = Color(1.0, 0.95, 0.45, 1.0)
@export var duration_s: float = 0.3

var _t := 0.0

func _ready() -> void:
	z_index = 110
	z_as_relative = false
	var tween := create_tween()
	tween.tween_property(self, "_t", 1.0, duration_s).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.finished.connect(queue_free)

func _draw() -> void:
	var r := 6.0 + 10.0 * _t
	var a := clampf(1.0 - _t, 0.0, 1.0)
	var c := Color(color.r, color.g, color.b, a)
	draw_circle(Vector2.ZERO, r * 0.4, Color(c.r, c.g, c.b, a * 0.5))
	draw_arc(Vector2.ZERO, r, 0, TAU, 28, c, 2.0)
