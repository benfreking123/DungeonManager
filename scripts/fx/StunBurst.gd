extends Node2D
class_name StunBurst

@export var color: Color = Color(0.4, 0.7, 1.0, 1.0)
@export var duration_s: float = 0.25

var _t := 0.0

func _ready() -> void:
	z_index = 110
	z_as_relative = false
	var tween := create_tween()
	tween.tween_property(self, "_t", 1.0, duration_s).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.finished.connect(queue_free)

func _draw() -> void:
	var r := 10.0 + 8.0 * (1.0 - _t)
	var a := clampf(1.0 - _t, 0.0, 1.0)
	var c := Color(color.r, color.g, color.b, a)
	for i in range(8):
		var ang := i * (TAU / 8.0)
		var p1 := Vector2.ZERO
		var p2 := Vector2(cos(ang), sin(ang)) * r
		draw_line(p1, p2, c, 2.0)
