extends Control

# MVP blueprint renderer: draws the underground grid area.

signal status_changed(text: String)
signal preview_reason_changed(text: String, ok: bool)
signal room_clicked(room_id: int, screen_pos: Vector2)

const DEFAULT_CELL_PX := 36
const ICON_BASE_CELL_PX := 24

const MAJOR_EVERY := 4

const ROOM_OUTLINE_W := 2.0
const ICON_W := 2.0

# Grid background texture (paper).
const PAPER_BG_TEX: Texture2D = preload("res://assets/simple-old-paper-1.jpg")

var selected_type_id: String = "hall"
var hover_cell: Vector2i = Vector2i(-999, -999)

const COMPOSITE_HALL_BBOX_SIZE := Vector2i(3, 3)
const COMPOSITE_HALL_OFFSETS := {
	# 3x3 bbox, anchored at hover cell (top-left).
	# Plus shape:
	#  .#.
	#  ###
	#  .#.
	"hall_plus": [
		Vector2i(1, 0),
		Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1),
		Vector2i(1, 2),
	],
	# Sideways T, stem points LEFT:
	#  ..#
	#  ###
	#  ..#
	"hall_t_left": [
		Vector2i(2, 0),
		Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1),
		Vector2i(2, 2),
	],
}

var _hover_slot_room_id: int = 0
var _hover_slot_idx: int = -1

# Theme keys live in `ui/DungeonManagerTheme.tres` under `DungeonView/...`.
const THEME_TYPE := "DungeonView"

# While dragging a room inventory item, we preview that room size.
var _drag_room_type_id: String = ""

# Lightweight "stamp" FX state for successful drops.
const STAMP_DUR_S := 0.22
var _stamp_room_rect: Rect2 = Rect2()
var _stamp_room_t0: float = -999.0
var _stamp_room_jitter: Vector2 = Vector2.ZERO

var _stamp_slot_rect: Rect2 = Rect2()
var _stamp_slot_t0: float = -999.0
var _stamp_slot_jitter: Vector2 = Vector2.ZERO

var _preview_last_ok: bool = true
var _preview_last_text: String = ""

@onready var _room_db: Node = get_node_or_null("/root/RoomDB")
@onready var _dungeon_grid: Node = get_node_or_null("/root/DungeonGrid")
@onready var _game_state: Node = get_node_or_null("/root/GameState")


func _ready() -> void:
	# Control draws via _draw(). Call queue_redraw when state changes.
	if _dungeon_grid != null and _dungeon_grid.has_signal("layout_changed"):
		_dungeon_grid.layout_changed.connect(queue_redraw)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	queue_redraw()


func _now_s() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _composite_cells_for_type(type_id: String, anchor: Vector2i) -> Array[Vector2i]:
	var off: Array = COMPOSITE_HALL_OFFSETS.get(type_id, []) as Array
	if off.is_empty():
		return []
	var out: Array[Vector2i] = []
	for v in off:
		var o := v as Vector2i
		out.append(Vector2i(anchor.x + o.x, anchor.y + o.y))
	return out


func _trigger_room_stamp(rect: Rect2) -> void:
	_stamp_room_rect = rect
	_stamp_room_t0 = _now_s()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_usec())
	_stamp_room_jitter = Vector2(rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0))
	queue_redraw()


func _trigger_slot_stamp(rect: Rect2) -> void:
	_stamp_slot_rect = rect
	_stamp_slot_t0 = _now_s()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_usec()) ^ 0x9E3779B9
	_stamp_slot_jitter = Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
	queue_redraw()


func _draw_stamp_rect(rect: Rect2, col: Color, t: float, jitter: Vector2) -> void:
	# t: 0..1. Expands and fades.
	var grow := lerpf(0.0, 8.0, t)
	var a := lerpf(0.85, 0.0, t)
	var r := rect.grow(grow)
	r.position += jitter
	draw_rect(r, Color(col.r, col.g, col.b, col.a * a), false, 2.0)
	draw_rect(r.grow(-2.0), Color(col.r, col.g, col.b, col.a * a * 0.08), true)


func _preview_reason_text(reason_key: String) -> String:
	match reason_key:
		"overlap":
			return "Overlaps another room."
		"not_enough_power":
			return "Not enough power."
		"out_of_bounds":
			return "Out of bounds."
		"unique_room_already_placed":
			return "Only one of that room."
		_:
			return ""


func _update_preview_reason(ok: bool, reason_key: String) -> void:
	var text := "" if ok else _preview_reason_text(reason_key)
	if text == _preview_last_text and ok == _preview_last_ok:
		return
	_preview_last_text = text
	_preview_last_ok = ok
	preview_reason_changed.emit(text, ok)


func _draw_dashed_line(a: Vector2, b: Vector2, col: Color, width: float, dash_len: float, gap_len: float) -> void:
	var dir := b - a
	var seg_len := dir.length()
	if seg_len <= 0.001:
		return
	dir /= seg_len
	var t := 0.0
	while t < seg_len:
		var seg_a := a + dir * t
		var seg_b := a + dir * minf(t + dash_len, seg_len)
		draw_line(seg_a, seg_b, col, width)
		t += dash_len + gap_len


func _draw_dashed_rect(rect: Rect2, col: Color, width: float) -> void:
	var dash := 8.0
	var gap := 5.0
	var tl := rect.position
	var tr_p := rect.position + Vector2(rect.size.x, 0)
	var bl := rect.position + Vector2(0, rect.size.y)
	var br := rect.position + rect.size
	_draw_dashed_line(tl, tr_p, col, width, dash, gap)
	_draw_dashed_line(tr_p, br, col, width, dash, gap)
	_draw_dashed_line(br, bl, col, width, dash, gap)
	_draw_dashed_line(bl, tl, col, width, dash, gap)


func _clip_code(p: Vector2, xmin: float, xmax: float, ymin: float, ymax: float) -> int:
	var c := 0
	if p.x < xmin:
		c |= 1
	elif p.x > xmax:
		c |= 2
	if p.y < ymin:
		c |= 4
	elif p.y > ymax:
		c |= 8
	return c


func _clip_segment_to_rect(a: Vector2, b: Vector2, rect: Rect2) -> PackedVector2Array:
	# Cohen–Sutherland clip against axis-aligned rect. Returns 0 or 2 points.
	var xmin := rect.position.x
	var xmax := rect.position.x + rect.size.x
	var ymin := rect.position.y
	var ymax := rect.position.y + rect.size.y

	var p0 := a
	var p1 := b
	var out0 := _clip_code(p0, xmin, xmax, ymin, ymax)
	var out1 := _clip_code(p1, xmin, xmax, ymin, ymax)

	while true:
		if (out0 | out1) == 0:
			return PackedVector2Array([p0, p1])
		if (out0 & out1) != 0:
			return PackedVector2Array()

		var out := out0 if out0 != 0 else out1
		var x := 0.0
		var y := 0.0

		if (out & 4) != 0:
			# Above
			x = p0.x + (p1.x - p0.x) * (ymin - p0.y) / (p1.y - p0.y)
			y = ymin
		elif (out & 8) != 0:
			# Below
			x = p0.x + (p1.x - p0.x) * (ymax - p0.y) / (p1.y - p0.y)
			y = ymax
		elif (out & 2) != 0:
			# Right
			y = p0.y + (p1.y - p0.y) * (xmax - p0.x) / (p1.x - p0.x)
			x = xmax
		elif (out & 1) != 0:
			# Left
			y = p0.y + (p1.y - p0.y) * (xmin - p0.x) / (p1.x - p0.x)
			x = xmin

		if out == out0:
			p0 = Vector2(x, y)
			out0 = _clip_code(p0, xmin, xmax, ymin, ymax)
		else:
			p1 = Vector2(x, y)
			out1 = _clip_code(p1, xmin, xmax, ymin, ymax)

	return PackedVector2Array()


func _draw_hatched_rect(rect: Rect2, col: Color) -> void:
	# Subtle diagonal hatch inside the rect.
	var hatch_col := Color(col.r, col.g, col.b, col.a * 0.18)
	var spacing := 10.0
	# Create \-direction lines and clip to the rect.
	for x in range(int(-rect.size.y), int(rect.size.x) + 1, int(spacing)):
		var p0 := rect.position + Vector2(float(x), rect.size.y)
		var p1 := rect.position + Vector2(float(x) + rect.size.y, 0.0)
		var clipped := _clip_segment_to_rect(p0, p1, rect)
		if clipped.size() == 2:
			draw_line(clipped[0], clipped[1], hatch_col, 1.0)


func _tcol(name: String, fallback: Color) -> Color:
	return get_theme_color(name, THEME_TYPE) if has_theme_color(name, THEME_TYPE) else fallback


func _tconst(name: String, fallback: int) -> int:
	return get_theme_constant(name, THEME_TYPE) if has_theme_constant(name, THEME_TYPE) else fallback


func _grid_col(is_major: bool) -> Color:
	if is_major:
		return _tcol("grid_major", BlueprintTheme.LINE_DIM)
	return _tcol("grid_minor", BlueprintTheme.LINE_FAINT)


func _grid_w() -> int:
	return int(_dungeon_grid.get("GRID_W")) if _dungeon_grid != null else 28


func _grid_h() -> int:
	return int(_dungeon_grid.get("GRID_H")) if _dungeon_grid != null else 22


func _cell_px() -> int:
	# Scale cells to fit this Control's rect.
	var gw := _grid_w()
	var gh := _grid_h()
	if gw <= 0 or gh <= 0:
		return DEFAULT_CELL_PX
	var sx := int(floor(size.x / float(gw)))
	var sy := int(floor(size.y / float(gh)))
	var px := mini(sx, sy)
	return clampi(px, 8, DEFAULT_CELL_PX)


func set_selected_room_type(type_id: String) -> void:
	selected_type_id = type_id
	_emit_build_status()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_hover_cell()
		_update_hover_slot()
		queue_redraw()
		return

	if event is InputEventMouseButton and event.pressed:
		# Ensure hover cell is up-to-date even if the mouse didn't move first.
		_update_hover_cell()
		_update_hover_slot()
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			# If clicking a room, emit selection (works in BUILD and DAY).
			if _dungeon_grid != null and _hover_in_bounds():
				var room: Dictionary = _dungeon_grid.call("get_room_at", hover_cell) as Dictionary
				if not room.is_empty():
					room_clicked.emit(int(room.get("id", 0)), get_viewport().get_mouse_position())
					# Prevent HUD global input from treating this same click as an "outside click"
					# that immediately closes the popup.
					get_viewport().set_input_as_handled()
					return
			# Room placement is drag-and-drop now (handled by DnD), so no-op here.
			return
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			# No build interactions while DAY is running.
			if Engine.has_singleton("GameState") and GameState.phase == GameState.Phase.DAY:
				return
			# If right-clicking a slot, uninstall instead of removing the room.
			if _hover_slot_room_id != 0 and _hover_slot_idx != -1:
				_try_uninstall_hover_slot()
			else:
				_try_remove_at_hover()


func _update_hover_cell() -> void:
	var local := get_local_mouse_position()
	var px := _cell_px()
	var cx := int(floor(local.x / float(px)))
	var cy := int(floor(local.y / float(px)))
	hover_cell = Vector2i(cx, cy)


func _update_hover_slot() -> void:
	_hover_slot_room_id = 0
	_hover_slot_idx = -1
	if _dungeon_grid == null:
		return
	if not _hover_in_bounds():
		return

	var room: Dictionary = _dungeon_grid.call("get_room_at", hover_cell) as Dictionary
	if room.is_empty():
		return
	var slots: Array = room.get("slots", [])
	if slots.is_empty():
		return

	var room_id: int = int(room.get("id", 0))
	var pos: Vector2i = room.get("pos", Vector2i.ZERO)
	var size: Vector2i = room.get("size", Vector2i.ONE)
	var px := float(_cell_px())
	var room_rect := Rect2(Vector2(pos.x, pos.y) * px, Vector2(size.x, size.y) * px)

	for i in range(slots.size()):
		var slot_rect := _slot_rect_local(room_rect, i)
		if slot_rect.has_point(get_local_mouse_position()):
			_hover_slot_room_id = room_id
			_hover_slot_idx = i
			return


func _slot_rect_local(room_rect: Rect2, slot_idx: int) -> Rect2:
	# One slot per room for MVP; render at top-right inside room.
	var s := 14.0
	var pad := 6.0
	var x := room_rect.position.x + room_rect.size.x - pad - s
	var y := room_rect.position.y + pad + float(slot_idx) * (s + 4.0)
	return Rect2(Vector2(x, y), Vector2(s, s))


func _try_uninstall_hover_slot() -> void:
	# Only allow changing installed items between days.
	if Engine.has_singleton("GameState") and GameState.phase != GameState.Phase.BUILD:
		return
	if _dungeon_grid == null:
		return
	var item_id: String = String(_dungeon_grid.call("uninstall_item_from_slot", _hover_slot_room_id, _hover_slot_idx))
	if item_id != "":
		PlayerInventory.refund(item_id, 1)
	queue_redraw()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var d := data as Dictionary
	# Room inventory drag
	if d.has("room_type_id"):
		_drag_room_type_id = String(d.get("room_type_id", ""))
		queue_redraw()
		return _can_drop_room(d)

	# Item slot drag
	# Only allow changing installed items between days.
	if Engine.has_singleton("GameState") and GameState.phase != GameState.Phase.BUILD:
		return false
	_drag_room_type_id = ""
	var item_id := String(d.get("item_id", ""))
	if item_id == "":
		return false
	if _dungeon_grid == null:
		return false
	# While dragging, hover state often doesn't update; compute slot under cursor using at_position.
	var hit := _slot_at_local_pos(get_local_mouse_position())
	var room_id: int = int(hit.get("room_id", 0))
	var slot_idx: int = int(hit.get("slot_idx", -1))
	if room_id == 0 or slot_idx == -1:
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
	# Map item->kind via ItemDB (supports traps/monsters/treasure).
	var item_kind := ""
	if ItemDB != null and ItemDB.has_method("get_item_kind"):
		item_kind = String(ItemDB.call("get_item_kind", item_id))
	var can_install := false
	if slot_kind == "universal":
		# Universal slots can accept any item type that can be installed into a room slot.
		# Boss rooms use these for minion spawners, but they can also hold boss upgrades.
		can_install = item_kind in ["trap", "monster", "treasure", "boss_upgrade"]
	elif slot_kind == "boss_upgrade":
		can_install = item_kind == "boss_upgrade"
	else:
		can_install = (slot_kind == item_kind)
	return can_install and PlayerInventory.get_count(item_id) > 0


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	var d := data as Dictionary
	# Room inventory drop
	if d.has("room_type_id"):
		_drop_room(d)
		_drag_room_type_id = ""
		return

	var item_id := String(d.get("item_id", ""))
	if item_id == "":
		return
	var hit := _slot_at_local_pos(get_local_mouse_position())
	var room_id: int = int(hit.get("room_id", 0))
	var slot_idx: int = int(hit.get("slot_idx", -1))
	if room_id == 0 or slot_idx == -1:
		return
	if not _can_drop_data(Vector2.ZERO, data):
		return
	if not PlayerInventory.consume(item_id, 1):
		return
	_dungeon_grid.call("install_item_in_slot", room_id, slot_idx, item_id)
	# Stamp FX on success path (we already validated empty slot + kind).
	var room: Dictionary = _dungeon_grid.call("get_room_by_id", room_id) as Dictionary
	if not room.is_empty():
		var pos: Vector2i = room.get("pos", Vector2i.ZERO)
		var size: Vector2i = room.get("size", Vector2i.ONE)
		var px := float(_cell_px())
		var room_rect := Rect2(Vector2(pos.x, pos.y) * px, Vector2(size.x, size.y) * px)
		_trigger_slot_stamp(_slot_rect_local(room_rect, slot_idx))
	queue_redraw()


func _can_drop_room(d: Dictionary) -> bool:
	if Engine.has_singleton("GameState") and GameState.phase == GameState.Phase.DAY:
		return false
	if _dungeon_grid == null or _room_db == null or _game_state == null:
		return false
	var type_id: String = String(d.get("room_type_id", ""))
	if type_id == "" or type_id == "entrance":
		return false
	if RoomInventory.get_count(type_id) <= 0:
		return false

	var cell := hover_cell
	if not _hover_in_bounds():
		# compute from mouse
		_update_hover_cell()
		cell = hover_cell
	if not _hover_in_bounds():
		return false

	return bool(_can_place_type_at(type_id, cell).get("ok", false))


func _drop_room(d: Dictionary) -> void:
	if not _can_drop_room(d):
		return
	var type_id: String = String(d.get("room_type_id", ""))
	var cell := hover_cell
	if not _hover_in_bounds():
		_update_hover_cell()
		cell = hover_cell

	var res := _can_place_type_at(type_id, cell)
	var size: Vector2i = res.get("size", Vector2i.ONE)
	var cost: int = int(res.get("cost", 0))
	var kind: String = String(res.get("kind", type_id))
	var cells: Array = res.get("cells", [])

	if not RoomInventory.consume(type_id, 1):
		return
	var placed_ok := false
	if COMPOSITE_HALL_OFFSETS.has(type_id):
		# Composite hallway placement: stamp multiple 1x1 rooms but consume only one piece.
		var group_id: int = int(_dungeon_grid.call("place_room_group", type_id, cells, kind, false))
		placed_ok = (group_id != 0)
	else:
		var id: int = int(_dungeon_grid.call("place_room", type_id, cell, size, kind, false))
		placed_ok = (id != 0)
	if not placed_ok:
		RoomInventory.refund(type_id, 1)
		return
	# Stamp FX on success.
	var px := float(_cell_px())
	_trigger_room_stamp(Rect2(Vector2(cell.x, cell.y) * px, Vector2(size.x, size.y) * px))
	_game_state.call("set_power_used", int(_game_state.get("power_used")) + cost)
	_emit_build_status()
	queue_redraw()


func _can_place_type_at(type_id: String, cell: Vector2i) -> Dictionary:
	# Returns { ok: bool, reason: String, size: Vector2i, cost: int, kind: String, cells?: Array[Vector2i] }
	if _room_db == null:
		return { "ok": false, "reason": "missing_roomdb", "size": Vector2i.ONE, "cost": 0, "kind": "" }
	var t: Dictionary = (_room_db.call("get_room_type", type_id) as Dictionary)
	if t.is_empty():
		return { "ok": false, "reason": "unknown_room_type", "size": Vector2i.ONE, "cost": 0, "kind": "" }

	var size: Vector2i = t.get("size", Vector2i.ONE)
	var cost: int = int(t.get("power_cost", 0))
	var kind: String = String(t.get("kind", type_id))
	var is_composite := COMPOSITE_HALL_OFFSETS.has(type_id)
	var cells: Array[Vector2i] = []
	if is_composite:
		size = COMPOSITE_HALL_BBOX_SIZE
		cells = _composite_cells_for_type(type_id, cell)
		# Bounds check all footprint cells.
		for c in cells:
			if c.x < 0 or c.y < 0 or c.x >= _grid_w() or c.y >= _grid_h():
				return { "ok": false, "reason": "out_of_bounds", "size": size, "cost": cost, "kind": kind, "cells": cells }

	if cell.x < 0 or cell.y < 0 or cell.x + size.x > _grid_w() or cell.y + size.y > _grid_h():
		return { "ok": false, "reason": "out_of_bounds", "size": size, "cost": cost, "kind": kind, "cells": cells }

	if _dungeon_grid != null and kind in ["entrance", "boss", "treasure"] and int(_dungeon_grid.call("count_kind", kind)) > 0:
		return { "ok": false, "reason": "unique_room_already_placed", "size": size, "cost": cost, "kind": kind, "cells": cells }

	if _dungeon_grid == null:
		return { "ok": false, "reason": "overlap", "size": size, "cost": cost, "kind": kind, "cells": cells }
	if is_composite:
		if not bool(_dungeon_grid.call("can_place_cells", cells)):
			return { "ok": false, "reason": "overlap", "size": size, "cost": cost, "kind": kind, "cells": cells }
	else:
		if not bool(_dungeon_grid.call("can_place", type_id, cell, size)):
			return { "ok": false, "reason": "overlap", "size": size, "cost": cost, "kind": kind, "cells": cells }

	if _game_state == null:
		return { "ok": false, "reason": "missing_gamestate", "size": size, "cost": cost, "kind": kind, "cells": cells }

	var remaining: int = int(_game_state.get("power_capacity")) - int(_game_state.get("power_used"))
	if cost > remaining:
		return { "ok": false, "reason": "not_enough_power", "size": size, "cost": cost, "kind": kind, "cells": cells }

	return { "ok": true, "reason": "ok", "size": size, "cost": cost, "kind": kind, "cells": cells }


func _slot_at_local_pos(local_pos: Vector2) -> Dictionary:
	# Returns { room_id, slot_idx } or {0,-1}.
	if _dungeon_grid == null:
		return { "room_id": 0, "slot_idx": -1 }
	var px := _cell_px()
	if px <= 0:
		return { "room_id": 0, "slot_idx": -1 }
	var cx := int(floor(local_pos.x / float(px)))
	var cy := int(floor(local_pos.y / float(px)))
	var cell := Vector2i(cx, cy)
	if cell.x < 0 or cell.y < 0 or cell.x >= _grid_w() or cell.y >= _grid_h():
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
		var slot_rect := _slot_rect_local(room_rect, i)
		if slot_rect.has_point(local_pos):
			return { "room_id": int(room.get("id", 0)), "slot_idx": i }
	return { "room_id": 0, "slot_idx": -1 }

func _hover_in_bounds() -> bool:
	return hover_cell.x >= 0 and hover_cell.y >= 0 and hover_cell.x < _grid_w() and hover_cell.y < _grid_h()


func _get_selected_room_def() -> Dictionary:
	if _room_db == null:
		return {}
	var def: Variant = _room_db.call("get_room_type", selected_type_id)
	return def as Dictionary


func _can_place_selected_at(cell: Vector2i) -> Dictionary:
	# Returns { ok: bool, reason: String, size: Vector2i, cost: int, kind: String }
	var t := _get_selected_room_def()
	if t.is_empty():
		return { "ok": false, "reason": "unknown_room_type", "size": Vector2i.ONE, "cost": 0, "kind": "" }

	var size: Vector2i = t.get("size", Vector2i.ONE)
	var cost: int = t.get("power_cost", 0)
	var kind: String = t.get("kind", selected_type_id)

	if cell.x < 0 or cell.y < 0 or cell.x + size.x > _grid_w() or cell.y + size.y > _grid_h():
		return { "ok": false, "reason": "out_of_bounds", "size": size, "cost": cost, "kind": kind }

	if _dungeon_grid != null and kind in ["entrance", "boss", "treasure"] and int(_dungeon_grid.call("count_kind", kind)) > 0:
		return { "ok": false, "reason": "unique_room_already_placed", "size": size, "cost": cost, "kind": kind }

	if _dungeon_grid == null or not bool(_dungeon_grid.call("can_place", selected_type_id, cell, size)):
		return { "ok": false, "reason": "overlap", "size": size, "cost": cost, "kind": kind }

	if _game_state == null:
		return { "ok": false, "reason": "missing_gamestate", "size": size, "cost": cost, "kind": kind }

	if kind in ["entrance", "boss", "treasure"] and int(_dungeon_grid.call("count_kind", kind)) > 0:
		return { "ok": false, "reason": "unique_room_already_placed", "size": size, "cost": cost, "kind": kind }

	var remaining: int = int(_game_state.get("power_capacity")) - int(_game_state.get("power_used"))
	if cost > remaining:
		return { "ok": false, "reason": "not_enough_power", "size": size, "cost": cost, "kind": kind }

	return { "ok": true, "reason": "ok", "size": size, "cost": cost, "kind": kind }


func _try_place_at_hover() -> void:
	if not _hover_in_bounds():
		return
	var res := _can_place_selected_at(hover_cell)
	if not res["ok"]:
		_emit_build_status()
		return

	var size: Vector2i = res["size"]
	var cost: int = res["cost"]
	var kind: String = res["kind"]

	if _dungeon_grid == null:
		return
	var id: int = int(_dungeon_grid.call("place_room", selected_type_id, hover_cell, size, kind, false))
	if id != 0:
		_game_state.call("set_power_used", int(_game_state.get("power_used")) + cost)
	_emit_build_status()


func _try_remove_at_hover() -> void:
	if not _hover_in_bounds():
		return
	if _dungeon_grid == null:
		return
	var room: Dictionary = (_dungeon_grid.call("get_room_at", hover_cell) as Dictionary)
	if room.is_empty():
		return

	var type_id: String = room.get("type_id", "")
	var group_id: int = int(room.get("group_id", 0))
	var def: Dictionary = (_room_db.call("get_room_type", type_id) as Dictionary) if _room_db != null else {}
	var cost: int = def.get("power_cost", 0)

	# Refund any installed slot items for this room before deletion.
	var slots: Array = room.get("slots", [])
	for s in slots:
		var sd := s as Dictionary
		var installed := String(sd.get("installed_item_id", ""))
		if installed != "":
			PlayerInventory.refund(installed, 1)

	if group_id != 0:
		# Composite removal: remove all cells in group and refund only one piece.
		var result: Dictionary = _dungeon_grid.call("remove_room_group_at", hover_cell) as Dictionary
		if bool(result.get("ok", false)):
			var group_type_id := String(result.get("group_type_id", type_id))
			if group_type_id != "":
				RoomInventory.refund(group_type_id, 1)
			# Cost is charged once per composite.
			var def2: Dictionary = (_room_db.call("get_room_type", group_type_id) as Dictionary) if _room_db != null else {}
			var cost2: int = int(def2.get("power_cost", cost))
			var next_used2: int = max(0, int(_game_state.get("power_used")) - cost2)
			_game_state.call("set_power_used", next_used2)
	else:
		if bool(_dungeon_grid.call("remove_room_at", hover_cell)):
			# Return piece to room inventory (except entrance which is locked anyway).
			if type_id != "":
				RoomInventory.refund(type_id, 1)
			var next_used: int = max(0, int(_game_state.get("power_used")) - cost)
			_game_state.call("set_power_used", next_used)
	_emit_build_status()


func _emit_build_status() -> void:
	if _dungeon_grid == null:
		status_changed.emit("Missing DungeonGrid autoload.")
		return
	var req: Dictionary = (_dungeon_grid.call("validate_required_paths") as Dictionary)
	if req.get("ok", true) and req.get("reason", "") == "missing_required_rooms":
		status_changed.emit("Place Entrance and Boss (Treasure optional). Left-click to place, right-click to remove.")
		return

	if not req.get("ok", true):
		var r: String = req.get("reason", "invalid_layout")
		status_changed.emit("Layout invalid: %s" % r)
		return

	status_changed.emit("Layout OK. Left-click to place, right-click to remove.")


func _draw() -> void:
	var gw := _grid_w()
	var gh := _grid_h()
	var px := _cell_px()
	var w := gw * px
	var h := gh * px

	var grid_w := float(_tconst("grid_w", int(BlueprintTheme.GRID_W)))
	var outline_w := float(_tconst("outline_w", int(BlueprintTheme.OUTLINE_W)))
	var room_outline_w := float(_tconst("room_outline_w", int(ROOM_OUTLINE_W)))
	var icon_w := float(_tconst("icon_w", int(ICON_W)))
	var slot_outline_w := float(_tconst("slot_outline_w", 2))

	var outline_col := _tcol("outline", BlueprintTheme.LINE)
	var outline_dim_col := _tcol("outline_dim", BlueprintTheme.LINE_DIM)
	var accent_ok := _tcol("accent_ok", BlueprintTheme.ACCENT_OK)
	var accent_bad := _tcol("accent_bad", BlueprintTheme.ACCENT_BAD)
	var accent_warn := _tcol("accent_warn", BlueprintTheme.ACCENT_WARN)
	var slot_treasure := _tcol("slot_outline_treasure", Color(0.95, 0.78, 0.22, 0.95))
	var slot_trap := _tcol("slot_outline_trap", Color(0.25, 0.58, 1.0, 0.95))
	var slot_monster := _tcol("slot_outline_monster", Color(0.25, 0.9, 0.5, 0.95))

	# Paper background behind the grid lines (inside the playable area rect).
	if PAPER_BG_TEX != null:
		# Slightly transparent so the blueprint ink stays readable.
		draw_texture_rect(PAPER_BG_TEX, Rect2(Vector2.ZERO, Vector2(w, h)), false, Color(1, 1, 1, 0.92))

	# Draw grid lines
	for x in range(gw + 1):
		var lx := x * px
		var col := _grid_col(x % MAJOR_EVERY == 0)
		draw_line(Vector2(lx, 0), Vector2(lx, h), col, grid_w)

	for y in range(gh + 1):
		var ly := y * px
		var col := _grid_col(y % MAJOR_EVERY == 0)
		draw_line(Vector2(0, ly), Vector2(w, ly), col, grid_w)

	# Outline the playable area
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), outline_col, false, outline_w)

	# Render placed rooms (if DungeonGrid autoload exists).
	if _dungeon_grid != null:
		for r in _dungeon_grid.rooms:
			_draw_room(r)

	# Placement preview
	if _hover_in_bounds():
		var use_type: String = selected_type_id
		if _drag_room_type_id != "":
			use_type = _drag_room_type_id
		var res := _can_place_type_at(use_type, hover_cell)
		var size: Vector2i = res.get("size", Vector2i.ONE)
		var ok: bool = res.get("ok", false)
		var col := accent_ok if ok else accent_bad
		var cells: Array = res.get("cells", [])
		var rect := Rect2(
			Vector2(hover_cell.x, hover_cell.y) * px,
			Vector2(size.x, size.y) * px
		)
		_update_preview_reason(ok, String(res.get("reason", "")))
		if cells is Array and not (cells as Array).is_empty():
			for c in (cells as Array):
				var cc := c as Vector2i
				var r := Rect2(Vector2(cc.x, cc.y) * px, Vector2.ONE * px)
				if ok:
					draw_rect(r, col, false, 2.0)
				else:
					_draw_dashed_rect(r, col, 2.0)
					_draw_hatched_rect(r, col)
		else:
			if ok:
				draw_rect(rect, col, false, 2.0)
			else:
				_draw_dashed_rect(rect, col, 2.0)
				_draw_hatched_rect(rect, col)
	else:
		_update_preview_reason(true, "")

	# Success stamps (room/item).
	var now := _now_s()
	if now - _stamp_room_t0 >= 0.0 and now - _stamp_room_t0 < STAMP_DUR_S:
		var t := clampf((now - _stamp_room_t0) / STAMP_DUR_S, 0.0, 1.0)
		_draw_stamp_rect(_stamp_room_rect, accent_ok, t, _stamp_room_jitter)
	if now - _stamp_slot_t0 >= 0.0 and now - _stamp_slot_t0 < STAMP_DUR_S:
		var t2 := clampf((now - _stamp_slot_t0) / STAMP_DUR_S, 0.0, 1.0)
		_draw_stamp_rect(_stamp_slot_rect, accent_ok, t2, _stamp_slot_jitter)


func _process(_delta: float) -> void:
	# During DAY, redraw so monster counts/icons update as encounters spawn/despawn.
	if Engine.has_singleton("GameState") and GameState.phase == GameState.Phase.DAY:
		queue_redraw()
		return
	# While stamps are active, keep animating.
	var now := _now_s()
	if now - _stamp_room_t0 < STAMP_DUR_S or now - _stamp_slot_t0 < STAMP_DUR_S:
		queue_redraw()


func _draw_room(room: Dictionary) -> void:
	var pos: Vector2i = room["pos"]
	var size: Vector2i = room["size"]
	var known: bool = room.get("known", true)
	var px := float(_cell_px())

	var rect := Rect2(
		Vector2(pos.x, pos.y) * px,
		Vector2(size.x, size.y) * px
	)

	var outline_col := _tcol("outline", BlueprintTheme.LINE) if known else _tcol("outline_dim", BlueprintTheme.LINE_DIM)
	draw_rect(rect, outline_col, false, float(_tconst("room_outline_w", int(ROOM_OUTLINE_W))))

	var center := rect.position + rect.size * 0.5
	# Minimap: prefer installed item icons for rooms with installable slots.
	var kind: String = String(room.get("kind", "hall"))

	# Fog-of-war rendering: unknown rooms should not reveal trap/monster/treasure info.
	# Treat unknown rooms as generic hallway for icon + hide slot markers/icons.
	var show_details := known
	var display_kind := kind if show_details else "hall"
	var center_icon: Texture2D = null
	if show_details and (kind == "trap" or kind == "monster" or kind == "treasure"):
		var slots0: Array = room.get("slots", [])
		if not slots0.is_empty():
			var slot0: Dictionary = slots0[0]
			var installed0 := String(slot0.get("installed_item_id", ""))
			if installed0 != "":
				center_icon = _get_item_icon(installed0)

	if center_icon != null:
		_draw_room_center_icon(center, center_icon)
	else:
		_draw_icon_stamp(center, display_kind, known)

	# Slot markers
	var slots: Array = room.get("slots", [])
	if show_details and not slots.is_empty():
		var slot_outline_w := float(_tconst("slot_outline_w", 2))
		var slot_treasure := _tcol("slot_outline_treasure", Color(0.95, 0.78, 0.22, 0.95))
		var slot_trap := _tcol("slot_outline_trap", Color(0.25, 0.58, 1.0, 0.95))
		var slot_monster := _tcol("slot_outline_monster", Color(0.25, 0.9, 0.5, 0.95))
		var slot_universal := _tcol("slot_outline_universal", Color(1.0, 1.0, 1.0, 0.95))
		for i in range(slots.size()):
			var slot: Dictionary = slots[i]
			var slot_rect := _slot_rect_local(rect, i)
			var installed := String(slot.get("installed_item_id", ""))
			var sk := String(slot.get("slot_kind", ""))
			var base_col := outline_col
			if sk == "treasure":
				base_col = slot_treasure
			elif sk == "trap":
				base_col = slot_trap
			elif sk == "monster":
				base_col = slot_monster
			elif sk == "universal":
				base_col = slot_universal
			# Slightly dim empty slots.
			var col := base_col if installed != "" else Color(base_col.r, base_col.g, base_col.b, base_col.a * 0.55)
			draw_rect(slot_rect, col, false, float(slot_outline_w))
			# Small fill if installed
			if installed != "":
				var icon_tex: Texture2D = _get_item_icon(installed)
				if icon_tex != null:
					# ~50% larger than before (less shrink inside the 14x14 slot)
					draw_texture_rect(icon_tex, slot_rect.grow(-1.0), true)
				else:
					draw_rect(slot_rect.grow(-3.0), col, true)

	# Hover highlight on slot
	if int(room.get("id", 0)) == _hover_slot_room_id and _hover_slot_idx != -1:
		var slot_rect2 := _slot_rect_local(rect, _hover_slot_idx)
		draw_rect(slot_rect2.grow(2.0), _tcol("accent_warn", BlueprintTheme.ACCENT_WARN), false, float(_tconst("slot_outline_w", 2)))

	# Monster spawn icon/count (debug visual)
	# (Removed: monster count dots; MonsterActor nodes are now the primary visual.)


func _get_item_icon(item_id: String) -> Texture2D:
	var r: Resource = ItemDB.get_any_item(item_id)
	if r is TrapItem:
		return (r as TrapItem).icon
	if r is MonsterItem:
		return (r as MonsterItem).icon
	if r is TreasureItem:
		return (r as TreasureItem).icon
	if r is BossUpgradeItem:
		return (r as BossUpgradeItem).icon
	return null


func _draw_room_center_icon(center: Vector2, tex: Texture2D) -> void:
	# Keep these icons a stable pixel size (independent of cell size).
	var px := float(ICON_BASE_CELL_PX)
	# ~50% larger than before
	var s := clampf(px * 1.05, 18.0, 36.0)
	draw_texture_rect(tex, Rect2(center - Vector2(s * 0.5, s * 0.5), Vector2(s, s)), true)


func cell_center_local(cell: Vector2i) -> Vector2:
	var px := float(_cell_px())
	return Vector2(cell.x * px + px * 0.5, cell.y * px + px * 0.5)

func room_center_local(room: Dictionary) -> Vector2:
	var pos: Vector2i = room.get("pos", Vector2i.ZERO)
	var size: Vector2i = room.get("size", Vector2i.ONE)
	var px := float(_cell_px())
	return Vector2((pos.x + size.x * 0.5) * px, (pos.y + size.y * 0.5) * px)


func room_rect_local(room: Dictionary) -> Rect2:
	var pos: Vector2i = room.get("pos", Vector2i.ZERO)
	var size: Vector2i = room.get("size", Vector2i.ONE)
	var px := float(_cell_px())
	return Rect2(Vector2(pos.x, pos.y) * px, Vector2(size.x, size.y) * px)


func room_interior_rect_local(room: Dictionary, pad_px := 6.0) -> Rect2:
	var r := room_rect_local(room)
	# Avoid negative sizes if the room is tiny.
	var pad := clampf(float(pad_px), 0.0, minf(r.size.x, r.size.y) * 0.49)
	return r.grow(-pad)


func cell_center_world(cell: Vector2i) -> Vector2:
	# Control nodes should use CanvasItem global transform.
	return get_global_transform() * cell_center_local(cell)


func entrance_surface_world_pos() -> Vector2:
	var cap := entrance_cap_world_rect()
	if cap == Rect2():
		return Vector2.ZERO
	return cap.position + cap.size * 0.5


func entrance_cap_world_rect() -> Rect2:
	# The above-ground "cap": 2x1 cells, pinned to the Town/Grid boundary (top edge of this control).
	# This is purely visual and used for surface travel; it does not affect dungeon occupancy.
	if _dungeon_grid == null:
		return Rect2()
	var entrance: Dictionary = _dungeon_grid.call("get_first_room_of_kind", "entrance") as Dictionary
	if entrance.is_empty():
		return Rect2()

	var pos: Vector2i = entrance.get("pos", Vector2i.ZERO)
	var size: Vector2i = entrance.get("size", Vector2i(2, 2))
	var px := float(_cell_px())

	# Important: when we zoom/pan the parent UI, this Control is scaled. Use local coords
	# and transform them to world space so the cap stays glued to the Town/Grid boundary.
	var local_tl := Vector2(pos.x * px, -px)
	var local_br := local_tl + Vector2(size.x * px, px)
	var world_tl: Vector2 = get_global_transform() * local_tl
	var world_br: Vector2 = get_global_transform() * local_br
	return Rect2(world_tl, world_br - world_tl)


func _draw_icon_stamp(center: Vector2, kind: String, known: bool) -> void:
	var col := _tcol("outline", BlueprintTheme.LINE) if known else _tcol("outline_dim", BlueprintTheme.LINE_DIM)
	# Keep these icons a stable pixel size (independent of cell size).
	var s := float(ICON_BASE_CELL_PX) * 0.35

	match kind:
		"entrance":
			# Down arrow
			draw_line(center + Vector2(0, -s), center + Vector2(0, s), col, float(_tconst("icon_w", int(ICON_W))))
			draw_line(center + Vector2(0, s), center + Vector2(-s * 0.6, s * 0.4), col, float(_tconst("icon_w", int(ICON_W))))
			draw_line(center + Vector2(0, s), center + Vector2(s * 0.6, s * 0.4), col, float(_tconst("icon_w", int(ICON_W))))
		"boss":
			# Crown-like: three spikes
			var iw := float(_tconst("icon_w", int(ICON_W)))
			draw_line(center + Vector2(-s, s * 0.6), center + Vector2(-s * 0.6, -s * 0.4), col, iw)
			draw_line(center + Vector2(-s * 0.6, -s * 0.4), center + Vector2(0, s * 0.2), col, iw)
			draw_line(center + Vector2(0, s * 0.2), center + Vector2(s * 0.6, -s * 0.4), col, iw)
			draw_line(center + Vector2(s * 0.6, -s * 0.4), center + Vector2(s, s * 0.6), col, iw)
			draw_line(center + Vector2(-s, s * 0.6), center + Vector2(s, s * 0.6), col, iw)
		"treasure":
			# Chest: box + lid line
			var iw := float(_tconst("icon_w", int(ICON_W)))
			draw_rect(Rect2(center - Vector2(s, s * 0.6), Vector2(s * 2.0, s * 1.2)), col, false, iw)
			draw_line(center + Vector2(-s, 0), center + Vector2(s, 0), col, iw)
		"monster":
			# Skull-ish: circle + eyes
			draw_arc(center, s * 0.8, 0, TAU, 20, col, float(_tconst("icon_w", int(ICON_W))))
			draw_circle(center + Vector2(-s * 0.3, -s * 0.1), s * 0.12, col)
			draw_circle(center + Vector2(s * 0.3, -s * 0.1), s * 0.12, col)
		"trap":
			# X mark
			draw_line(center + Vector2(-s, -s), center + Vector2(s, s), col, float(_tconst("icon_w", int(ICON_W))))
			draw_line(center + Vector2(-s, s), center + Vector2(s, -s), col, float(_tconst("icon_w", int(ICON_W))))
		_:
			# Hall / default: small dot
			draw_circle(center, s * 0.12, col)
