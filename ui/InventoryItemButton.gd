extends PanelContainer

@export var item_id: String = ""

@onready var _icon: TextureRect = $Root/VBox/Icon
@onready var _name: Label = $Root/VBox/Name
@onready var _count_badge: Label = $CountBadge

var _item_name: String = ""
var _item_icon: Texture2D
var _count: int = 0


func set_item(next_item_id: String, next_name: String, next_icon: Texture2D, next_count: int) -> void:
	item_id = next_item_id
	_item_name = next_name
	_item_icon = next_icon
	_count = next_count

	if _icon != null:
		_icon.texture = _item_icon
	if _name != null:
		_name.text = _item_name
	if _count_badge != null:
		_count_badge.text = "x%d" % _count


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
	if item_id == "":
		return null
	if PlayerInventory.get_count(item_id) <= 0:
		return null

	_play_drag_stamp()

	var preview_root := VBoxContainer.new()
	preview_root.alignment = BoxContainer.ALIGNMENT_CENTER
	preview_root.add_theme_constant_override("separation", 4)

	if _item_icon != null:
		var tex := TextureRect.new()
		tex.texture = _item_icon
		tex.custom_minimum_size = Vector2(24, 24)
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview_root.add_child(tex)

	var label := Label.new()
	label.text = "%s x%d" % [_item_name, PlayerInventory.get_count(item_id)]
	preview_root.add_child(label)

	set_drag_preview(preview_root)
	return { "item_id": item_id }


