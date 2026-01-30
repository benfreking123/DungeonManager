extends RefCounted

# Centralized room placement rules and actions for DungeonView.
# Dependencies are injected so this service remains testable.

var _view: Control
var _dungeon_grid: Node
var _room_db: Node
var _game_state: Node

func _init(view: Control, dungeon_grid: Node, room_db: Node, game_state: Node) -> void:
	_view = view
	_dungeon_grid = dungeon_grid
	_room_db = room_db
	_game_state = game_state


# Returns { ok: bool, reason: String, size: Vector2i, cost: int, kind: String, cells?: Array[Vector2i] }
func can_place(type_id: String, cell: Vector2i) -> Dictionary:
	if _room_db == null:
		return { "ok": false, "reason": "missing_roomdb", "size": Vector2i.ONE, "cost": 0, "kind": "" }
	var t: Dictionary = (_room_db.call("get_room_type", type_id) as Dictionary)
	if t.is_empty():
		return { "ok": false, "reason": "unknown_room_type", "size": Vector2i.ONE, "cost": 0, "kind": "" }

	var size: Vector2i = t.get("size", Vector2i.ONE)
	var cost: int = int(t.get("power_cost", 0))
	var kind: String = String(t.get("kind", type_id))

	# Composite footprints use the view-owned definitions.
	var is_composite := false
	if _view != null and _view.has_method("has"):
		# no-op: placeholder to satisfy lints if needed
		pass
	if _view != null and "COMPOSITE_HALL_OFFSETS" in _view:
		is_composite = _view.COMPOSITE_HALL_OFFSETS.has(type_id)

	var cells: Array[Vector2i] = []
	if is_composite:
		size = _view.COMPOSITE_HALL_BBOX_SIZE
		cells = _view.call("_composite_cells_for_type", type_id, cell) as Array
		# Bounds for composite cells
		for c in cells:
			var cc := c as Vector2i
			if cc.x < 0 or cc.y < 0 or cc.x >= _view.call("_grid_w") or cc.y >= _view.call("_grid_h"):
				return { "ok": false, "reason": "out_of_bounds", "size": size, "cost": cost, "kind": kind, "cells": cells }

	# Simple bounds
	if cell.x < 0 or cell.y < 0 or cell.x + size.x > _view.call("_grid_w") or cell.y + size.y > _view.call("_grid_h"):
		return { "ok": false, "reason": "out_of_bounds", "size": size, "cost": cost, "kind": kind, "cells": cells }

	# Unique room kinds
	if _dungeon_grid != null and kind in ["entrance", "boss", "treasure"] and int(_dungeon_grid.call("count_kind", kind)) > 0:
		return { "ok": false, "reason": "unique_room_already_placed", "size": size, "cost": cost, "kind": kind, "cells": cells }

	# Overlap
	if _dungeon_grid == null:
		return { "ok": false, "reason": "overlap", "size": size, "cost": cost, "kind": kind, "cells": cells }
	if is_composite:
		if not bool(_dungeon_grid.call("can_place_cells", cells)):
			return { "ok": false, "reason": "overlap", "size": size, "cost": cost, "kind": kind, "cells": cells }
	else:
		if not bool(_dungeon_grid.call("can_place", type_id, cell, size)):
			return { "ok": false, "reason": "overlap", "size": size, "cost": cost, "kind": kind, "cells": cells }

	# Power
	if _game_state == null:
		return { "ok": false, "reason": "missing_gamestate", "size": size, "cost": cost, "kind": kind, "cells": cells }
	var remaining: int = int(_game_state.get("power_capacity")) - int(_game_state.get("power_used"))
	if cost > remaining:
		return { "ok": false, "reason": "not_enough_power", "size": size, "cost": cost, "kind": kind, "cells": cells }

	return { "ok": true, "reason": "ok", "size": size, "cost": cost, "kind": kind, "cells": cells }


# Places the room(s) if valid. Consumes inventory and updates power. Returns true on success.
func drop_room(type_id: String, cell: Vector2i) -> bool:
	if Engine.has_singleton("GameState") and GameState.phase == GameState.Phase.DAY:
		return false
	if _dungeon_grid == null or _room_db == null or _game_state == null:
		return false
	if type_id == "" or type_id == "entrance":
		return false
	if RoomInventory.get_count(type_id) <= 0:
		return false

	var res := can_place(type_id, cell)
	if not bool(res.get("ok", false)):
		return false
	var size: Vector2i = res.get("size", Vector2i.ONE)
	var cost: int = int(res.get("cost", 0))
	var kind: String = String(res.get("kind", type_id))
	var cells: Array = res.get("cells", [])

	if not RoomInventory.consume(type_id, 1):
		return false

	var placed_ok := false
	if _view.COMPOSITE_HALL_OFFSETS.has(type_id):
		var group_id: int = int(_dungeon_grid.call("place_room_group", type_id, cells, kind, false))
		placed_ok = (group_id != 0)
	else:
		var id: int = int(_dungeon_grid.call("place_room", type_id, cell, size, kind, false))
		placed_ok = (id != 0)

	if not placed_ok:
		RoomInventory.refund(type_id, 1)
		return false

	_game_state.call("set_power_used", int(_game_state.get("power_used")) + cost)
	return true

