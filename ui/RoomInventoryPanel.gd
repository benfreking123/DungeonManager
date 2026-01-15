extends PanelContainer

@onready var _list: VBoxContainer = $VBox/List
@onready var _status: Label = $VBox/Status
@onready var _room_db: Node = get_node_or_null("/root/RoomDB")

var _btn_scene: PackedScene = preload("res://ui/RoomInventoryItemButton.tscn")


func _ready() -> void:
	_refresh()
	RoomInventory.inventory_changed.connect(_refresh)


func set_status(text: String) -> void:
	_status.text = text


func _refresh() -> void:
	for c in _list.get_children():
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
		var count: int = RoomInventory.get_count(type_id)
		if count <= 0:
			continue
		var label: String = t.get("label", type_id)
		var btn := _btn_scene.instantiate()
		_list.add_child(btn)
		btn.call("set_room", type_id, label, count)


