extends PanelContainer

@onready var _label: Label = $Label


func set_text(text: String) -> void:
	if _label != null:
		_label.text = text


func open_at(anchor_global_rect: Rect2) -> void:
	visible = true
	# Ensure we draw above regular HUD elements.
	z_as_relative = false
	z_index = 4096

	# Position just below the anchor rect.
	var pad := Vector2(0, 6)
	global_position = anchor_global_rect.position + Vector2(0, anchor_global_rect.size.y) + pad

	# Clamp within viewport bounds.
	var vp := get_viewport().get_visible_rect().size
	var s := get_combined_minimum_size()
	var pos := global_position
	pos.x = clampf(pos.x, 6.0, vp.x - s.x - 6.0)
	pos.y = clampf(pos.y, 6.0, vp.y - s.y - 6.0)
	global_position = pos


func close() -> void:
	visible = false
