extends Node2D
class_name WhirlwindCross

@export var color: Color = Color(1.0, 0.35, 0.35, 1.0)
@export var duration_s: float = 0.5
@export var thickness: float = 3.0

var _t := 0.0

func _ready() -> void:
	z_index = 120
	z_as_relative = false
	var tween := create_tween()
	tween.tween_property(self, "_t", 1.0, duration_s).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.finished.connect(queue_free)

func _process(dt: float) -> void:
	rotation += 10.0 * dt # spin
	queue_redraw()

func _draw() -> void:
	var len := 16.0
	var a := clampf(1.0 - _t, 0.0, 1.0)
	var c := Color(color.r, color.g, color.b, a)
	# Thin blades
	draw_line(Vector2(-len, 0), Vector2(len, 0), c, thickness)
	draw_line(Vector2(0, -len), Vector2(0, len), c, thickness)
