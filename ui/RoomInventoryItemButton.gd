extends PanelContainer

@export var room_type_id: String = ""

@onready var _name: Label = $Root/VBox/Name
@onready var _count: Label = $CountBadge

var _display_name: String = ""
var _count_value: int = 0


func set_room(type_id: String, display_name: String, count: int) -> void:
	room_type_id = type_id
	_display_name = display_name
	_count_value = count
	if _name != null:
		_name.text = _display_name
	if _count != null:
		_count.text = "x%d" % _count_value


func _get_drag_data(_at_position: Vector2) -> Variant:
	if room_type_id == "":
		return null
	if GameState.phase != GameState.Phase.BUILD:
		return null
	if RoomInventory.get_count(room_type_id) <= 0:
		return null

	var preview := Label.new()
	preview.text = "%s x%d" % [_display_name, RoomInventory.get_count(room_type_id)]
	set_drag_preview(preview)
	return { "room_type_id": room_type_id }


