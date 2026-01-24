extends Node2D
class_name AbilityRing

@export var color: Color = Color(1.0, 1.0, 0.6, 1.0)
@export var duration_s: float = 0.35
@export var start_radius: float = 10.0
@export var end_radius: float = 36.0
@export var start_alpha: float = 1.0
@export var thickness_px: float = 3.0

var _t: float = 0.0

func _ready() -> void:
	z_index = 100
	z_as_relative = false
	var tween := create_tween()
	tween.tween_property(self, "_t", 1.0, maxf(0.05, duration_s)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.bind_node(self)
	tween.finished.connect(func():
		queue_free()
	)

func _process(_dt: float) -> void:
	queue_redraw()

func _draw() -> void:
	var r := lerpf(start_radius, end_radius, _t)
	var a := clampf(start_alpha * (1.0 - _t), 0.0, 1.0)
	var c := Color(color.r, color.g, color.b, a)
	# Outer ring
	draw_arc(Vector2.ZERO, r, 0, TAU, 36, c, maxf(1.0, thickness_px))
	# Inner soft fill
	draw_circle(Vector2.ZERO, r * 0.3, Color(c.r, c.g, c.b, a * 0.35))
