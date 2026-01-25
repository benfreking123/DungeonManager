extends PanelContainer

@onready var _title: Label = $VBox/Top/Title
@onready var _close: Button = $VBox/Top/Close
@onready var _list: ItemList = $VBox/List
@onready var _count: Label = $VBox/Footer/Count

@onready var _history_service: Object = null

func _ready() -> void:
	visible = false
	if _close != null:
		_close.pressed.connect(close)
	_history_service = preload("res://autoloads/HistoryService.gd").new()
	_refresh()


func open() -> void:
	visible = true
	_refresh()


func close() -> void:
	visible = false


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()


func _format_line(e: Dictionary) -> String:
	if _history_service != null and _history_service.has_method("format_event"):
		var f: Dictionary = _history_service.format_event(e)
		return String(f.get("text", ""))
	return String(e.get("type", ""))


func _refresh() -> void:
	if _list == null:
		return
	_list.clear()
	var sim := get_node_or_null("/root/Simulation")
	var di := 1
	if GameState != null and "day_index" in GameState:
		di = int(GameState.get("day_index"))
	var events: Array = []
	if sim != null and sim.has_method("get_history_events"):
		events = sim.call("get_history_events") as Array
	elif _history_service != null and _history_service.has_method("get_events"):
		events = _history_service.get_events({})
	for e0 in events:
		var e := e0 as Dictionary
		_list.add_item(_format_line(e))
	if _count != null:
		_count.text = "%d entries" % _list.item_count
