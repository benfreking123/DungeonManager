extends Control

signal hover_entered(slot: Control, offer: Dictionary, screen_pos: Vector2)
signal hover_exited()
signal purchase_pressed(slot: Control, offer: Dictionary, screen_pos: Vector2)

@onready var _icon_btn: TextureButton = $VBox/IconButton
@onready var _cost_box: HBoxContainer = $VBox/Cost

var _offer: Dictionary = {}
var _icon: Texture2D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _icon_btn != null:
		_icon_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		_icon_btn.pressed.connect(_on_pressed)
		_icon_btn.mouse_entered.connect(func():
			hover_entered.emit(self, _offer, get_viewport().get_mouse_position())
		)
		_icon_btn.mouse_exited.connect(func():
			hover_exited.emit()
		)
	if _cost_box != null:
		_cost_box.add_theme_constant_override("separation", 2)
	# Fallback hover if button is missing.
	mouse_entered.connect(func():
		hover_entered.emit(self, _offer, get_viewport().get_mouse_position())
	)
	mouse_exited.connect(func():
		hover_exited.emit()
	)


func set_offer(offer: Dictionary, icon: Texture2D, cost_list: Array) -> void:
	_offer = offer.duplicate(true) if offer != null else {}
	_icon = icon
	if _icon_btn != null:
		# Force the texture to render at the button's rect size, not its native size.
		if _icon_btn.has_method("set"):
			# Godot 4: TextureButton supports ignore_texture_size + stretch_mode
			_icon_btn.ignore_texture_size = true
		_icon_btn.stretch_mode = TextureButton.STRETCH_SCALE
		# Shop items at 64x64; room buttons may remain smaller elsewhere
		var px := 64
		_icon_btn.custom_minimum_size = Vector2(px, px)
		_icon_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_icon_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_icon_btn.texture_normal = icon
	_render_cost(cost_list)


func get_icon() -> Texture2D:
	return _icon


func _on_pressed() -> void:
	purchase_pressed.emit(self, _offer, get_viewport().get_mouse_position())


func _render_cost(cost_list: Array) -> void:
	if _cost_box == null:
		return
	# Clear previous children
	for c in _cost_box.get_children():
		c.queue_free()
	if cost_list == null or cost_list.is_empty():
		return
	for entry in cost_list:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var icon: Texture2D = entry.get("icon", null) as Texture2D
		var amount: int = int(entry.get("amount", 0))
		if amount <= 0:
			continue
		# Per-cost cell with overlayed quantity
		var cell := Control.new()
		cell.custom_minimum_size = Vector2(48, 48)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cost_box.add_child(cell)

		var tr := TextureRect.new()
		tr.texture = icon
		tr.custom_minimum_size = Vector2(48, 48)
		# Force cost icons to render at 32x32 regardless of native texture size.
		tr.ignore_texture_size = true
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Fill the cell for proper overlay
		tr.anchor_left = 0.0
		tr.anchor_top = 0.0
		tr.anchor_right = 1.0
		tr.anchor_bottom = 1.0
		tr.offset_left = 0
		tr.offset_top = 0
		tr.offset_right = 0
		tr.offset_bottom = 0
		cell.add_child(tr)

		var qty := Label.new()
		qty.text = "x%d" % amount
		qty.add_theme_font_size_override("font_size", 16)
		qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		qty.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Anchor to bottom-right of the cell
		qty.anchor_left = 0.0
		qty.anchor_top = 0.0
		qty.anchor_right = 1.0
		qty.anchor_bottom = 1.0
		qty.offset_left = 0
		qty.offset_top = 0
		qty.offset_right = 0
		qty.offset_bottom = 0
		cell.add_child(qty)
