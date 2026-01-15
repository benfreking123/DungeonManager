extends PanelContainer

@onready var spike_btn: PanelContainer = $HBox/SpikeTrap
@onready var zombie_btn: PanelContainer = $HBox/Zombie
@onready var pit_btn: PanelContainer = $HBox/FloorPit


func _ready() -> void:
	_refresh()
	PlayerInventory.inventory_changed.connect(_refresh)


func _refresh() -> void:
	_set_btn(spike_btn, "spike_trap")
	_set_btn(zombie_btn, "zombie")
	_set_btn(pit_btn, "floor_pit")


func _set_btn(btn: Node, item_id: String) -> void:
	var count: int = PlayerInventory.get_count(item_id)
	var res: Resource = ItemDB.get_any_item(item_id)

	var name: String = item_id
	var icon: Texture2D = null

	if res is TrapItem:
		var t := res as TrapItem
		name = t.display_name
		icon = t.icon
	elif res is MonsterItem:
		var m := res as MonsterItem
		name = m.display_name
		icon = m.icon

	btn.call("set_item", item_id, name, icon, count)
