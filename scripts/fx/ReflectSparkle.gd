extends Node2D
class_name ReflectSparkle

@export var color: Color = Color(1.0, 0.35, 0.35, 1.0)
@export var duration_s: float = 0.2

var _t := 0.0

func _ready() -> void:
	z_index = 120
	z_as_relative = false
	var tween := create_tween()
	tween.tween_property(self, "_t", 1.0, duration_s).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.finished.connect(queue_free)

func _draw() -> void:
	var rays := 10
	var base_r := 8.0
	for i in range(rays):
		var ang := i * (TAU / float(rays))
		var len := base_r * (1.0 - _t) * 1.5
		var a := clampf(1.0 - _t, 0.0, 1.0)
		var c := Color(color.r, color.g, color.b, a)
		draw_line(Vector2.ZERO, Vector2(cos(ang), sin(ang)) * len, c, 1.5)
