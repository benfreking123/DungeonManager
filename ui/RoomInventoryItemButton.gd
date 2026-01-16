extends PanelContainer

@export var room_type_id: String = ""

@onready var _icon: TextureRect = $Root/VBox/Icon
@onready var _name: Label = $Root/VBox/Name
@onready var _count: Label = $CountBadge

var _display_name: String = ""
var _icon_tex: Texture2D
var _count_value: int = 0


func set_room(type_id: String, display_name: String, count: int, icon: Texture2D = null) -> void:
	room_type_id = type_id
	_display_name = display_name
	_icon_tex = icon
	_count_value = count
	if _icon != null:
		_icon.texture = _icon_tex
	if _name != null:
		_name.text = _display_name
	if _count != null:
		_count.text = "x%d" % _count_value


func _play_drag_stamp() -> void:
	# Quick "stamp" feedback: tiny scale pop + slight alpha pulse.
	pivot_offset = size * 0.5

	scale = Vector2.ONE * 1.06
	var t_scale := create_tween()
	t_scale.tween_property(self, "scale", Vector2.ONE, 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	var base_a := modulate.a
	var up_a := minf(1.0, base_a + 0.08)
	var t_alpha := create_tween()
	t_alpha.tween_property(self, "modulate:a", up_a, 0.04).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t_alpha.tween_property(self, "modulate:a", base_a, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if room_type_id == "":
		return null
	if GameState.phase != GameState.Phase.BUILD:
		return null
	if RoomInventory.get_count(room_type_id) <= 0:
		return null

	_play_drag_stamp()

	var preview_root := VBoxContainer.new()
	preview_root.alignment = BoxContainer.ALIGNMENT_CENTER
	preview_root.add_theme_constant_override("separation", 4)

	if _icon_tex != null:
		var tex := TextureRect.new()
		tex.texture = _icon_tex
		tex.custom_minimum_size = Vector2(24, 24)
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview_root.add_child(tex)

	var label := Label.new()
	label.text = "%s x%d" % [_display_name, RoomInventory.get_count(room_type_id)]
	preview_root.add_child(label)

	set_drag_preview(preview_root)
	return { "room_type_id": room_type_id }


