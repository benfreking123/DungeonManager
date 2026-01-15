extends Node2D

var hp_max: int = 1
var hp: int = 1
var icon: Texture2D
var is_boss: bool = false


func set_hp(next_hp: int, next_max: int) -> void:
	hp_max = max(1, next_max)
	hp = clamp(next_hp, 0, hp_max)
	queue_redraw()


func set_icon(next_icon: Texture2D) -> void:
	icon = next_icon
	queue_redraw()


func set_is_boss(v: bool) -> void:
	is_boss = v
	queue_redraw()


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	var marker := ThemePalette.color("Combat", "monster_marker", Color(0.9, 0.2, 0.2, 0.95))
	var marker_dim := ThemePalette.color("Combat", "monster_marker_dim", Color(0.9, 0.2, 0.2, 0.35))
	var hp_back := ThemePalette.color("Combat", "hp_back", Color(0, 0, 0, 0.35))
	var hp_outline := ThemePalette.color("Combat", "hp_outline", Color(0.9, 0.2, 0.2, 0.35))
	var hp_fill := ThemePalette.color("Combat", "hp_fill", Color(0.9, 0.2, 0.2, 0.95))

	# Minimap marker: prefer monster icon when present.
	if icon != null:
		var s := 30.0 if is_boss else 22.0
		draw_texture_rect(icon, Rect2(Vector2(-s * 0.5, -s * 0.5), Vector2(s, s)), true)
	else:
		# Same style as adventurer, but red.
		draw_circle(Vector2.ZERO, 6.0, marker)
		draw_arc(Vector2.ZERO, 10.0, 0, TAU, 24, marker_dim, 2.0)

	# HP bar above
	var w := 28.0
	var h := 5.0
	var x := -w * 0.5
	var y := -22.0
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), hp_back, true)
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), hp_outline, false, 1.0)
	var pct := float(hp) / float(hp_max)
	draw_rect(Rect2(Vector2(x, y), Vector2(w * pct, h)), hp_fill, true)


