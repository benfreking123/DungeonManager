extends RefCounted

# Slot interaction logic for DungeonView.
# Computes slot hit tests and handles install/uninstall with inventory.

var _view: Control
var _dungeon_grid: Node

func _init(view: Control, dungeon_grid: Node) -> void:
	_view = view
	_dungeon_grid = dungeon_grid


func slot_rect(room_rect: Rect2, slot_idx: int) -> Rect2:
	# Matches original DungeonView slot placement (top-right, vertical list).
	var s := 14.0
	var pad := 6.0
	var x := room_rect.position.x + room_rect.size.x - pad - s
	var y := room_rect.position.y + pad + float(slot_idx) * (s + 4.0)
	return Rect2(Vector2(x, y), Vector2(s, s))


# Returns { room_id, slot_idx } or {0,-1}, matching original behavior.
func hit_test_slot(local_pos: Vector2) -> Dictionary:
	if _dungeon_grid == null:
		return { "room_id": 0, "slot_idx": -1 }
	var px := int(_view.call("_cell_px"))
	if px <= 0:
		return { "room_id": 0, "slot_idx": -1 }
	var cx := int(floor(local_pos.x / float(px)))
	var cy := int(floor(local_pos.y / float(px)))
	var cell := Vector2i(cx, cy)
	if cell.x < 0 or cell.y < 0 or cell.x >= _view.call("_grid_w") or cell.y >= _view.call("_grid_h"):
		return { "room_id": 0, "slot_idx": -1 }
	var room: Dictionary = _dungeon_grid.call("get_room_at", cell) as Dictionary
	if room.is_empty():
		return { "room_id": 0, "slot_idx": -1 }
	var slots: Array = room.get("slots", [])
	if slots.is_empty():
		return { "room_id": 0, "slot_idx": -1 }
	var pos: Vector2i = room.get("pos", Vector2i.ZERO)
	var size: Vector2i = room.get("size", Vector2i.ONE)
	var room_rect := Rect2(Vector2(pos.x, pos.y) * float(px), Vector2(size.x, size.y) * float(px))
	for i in range(slots.size()):
		var sr := slot_rect(room_rect, i)
		if sr.has_point(local_pos):
			return { "room_id": int(room.get("id", 0)), "slot_idx": i }
	return { "room_id": 0, "slot_idx": -1 }


func can_install(item_id: String, room_id: int, slot_idx: int) -> bool:
	# Only allow between BUILD days.
	if Engine.has_singleton("GameState") and GameState.phase != GameState.Phase.BUILD:
		return false
	if _dungeon_grid == null:
		return false
	if item_id == "":
		return false
	if PlayerInventory.get_count(item_id) <= 0:
		return false
	var room: Dictionary = _dungeon_grid.call("get_room_by_id", room_id) as Dictionary
	if room.is_empty():
		return false
	var slots: Array = room.get("slots", [])
	if slot_idx < 0 or slot_idx >= slots.size():
		return false
	var slot: Dictionary = slots[slot_idx]
	if String(slot.get("installed_item_id", "")) != "":
		return false
	var slot_kind := String(slot.get("slot_kind", ""))
	var item_kind := ""
	if ItemDB != null and ItemDB.has_method("get_item_kind"):
		item_kind = String(ItemDB.call("get_item_kind", item_id))
	if slot_kind == "universal":
		return item_kind in ["trap", "monster", "treasure", "boss_upgrade"]
	elif slot_kind == "boss_upgrade":
		return item_kind == "boss_upgrade"
	else:
		return slot_kind == item_kind


func install(item_id: String, room_id: int, slot_idx: int) -> bool:
	if not can_install(item_id, room_id, slot_idx):
		return false
	if not PlayerInventory.consume(item_id, 1):
		return false
	_dungeon_grid.call("install_item_in_slot", room_id, slot_idx, item_id)
	return true


# Returns refunded item_id or empty string.
func uninstall(room_id: int, slot_idx: int) -> String:
	# Only allow between BUILD days.
	if Engine.has_singleton("GameState") and GameState.phase != GameState.Phase.BUILD:
		return ""
	if _dungeon_grid == null:
		return ""
	var item_id: String = String(_dungeon_grid.call("uninstall_item_from_slot", room_id, slot_idx))
	if item_id != "":
		PlayerInventory.refund(item_id, 1)
	return item_id

