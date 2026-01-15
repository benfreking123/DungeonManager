extends PanelContainer

signal room_selected(type_id: String)

@onready var rooms_box: VBoxContainer = $VBox/Rooms
@onready var status_label: Label = $VBox/Status

var selected_type_id: String = "hall"

@onready var _room_db: Node = get_node_or_null("/root/RoomDB")


func _ready() -> void:
	_build_room_buttons()
	_emit_selection()


func _build_room_buttons() -> void:
	for c in rooms_box.get_children():
		c.queue_free()

	if _room_db == null:
		set_status("Missing RoomDB autoload.")
		return

	var types: Array[Dictionary] = _room_db.list_room_types()
	types.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("label", "")) < str(b.get("label", ""))
	)

	for t in types:
		var type_id: String = t.get("id", "")
		if type_id == "entrance":
			continue
		var label: String = t.get("label", type_id)
		var cost: int = t.get("power_cost", 0)
		var size: Vector2i = t.get("size", Vector2i.ONE)

		var b := Button.new()
		b.text = "%s  (%dx%d, cost %d)" % [label, size.x, size.y, cost]
		b.toggle_mode = true
		b.set_meta("type_id", type_id)
		b.button_pressed = (type_id == selected_type_id)
		b.pressed.connect(func():
			_select(type_id)
		)
		rooms_box.add_child(b)


func _select(type_id: String) -> void:
	selected_type_id = type_id
	for c in rooms_box.get_children():
		if c is Button:
			var btn := c as Button
			btn.button_pressed = (String(btn.get_meta("type_id", "")) == type_id)
	_emit_selection()


func _emit_selection() -> void:
	room_selected.emit(selected_type_id)


func set_status(text: String) -> void:
	status_label.text = text


