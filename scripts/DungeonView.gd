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

#
# Stamps moved to DungeonStampFxService
#

var _preview_last_ok: bool = true
var _preview_last_text: String = ""

@onready var _room_db: Node = get_node_or_null("/root/RoomDB")
@onready var _dungeon_grid: Node = get_node_or_null("/root/DungeonGrid")
@onready var _game_state: Node = get_node_or_null("/root/GameState")

#
# Services (owned by DungeonView)
#
const PlacementServiceScript := preload("res://scripts/services/DungeonPlacementService.gd")
const SlotServiceScript := preload("res://scripts/services/DungeonSlotService.gd")
const DrawServiceScript := preload("res://scripts/services/DungeonBlueprintDrawService.gd")
const StampFxServiceScript := preload("res://scripts/services/DungeonStampFxService.gd")
const ItemIconServiceScript := preload("res://scripts/services/ItemIconService.gd")

var _placement: RefCounted = null
var _slots: RefCounted = null
var _drawsvc: RefCounted = null
var _stamps: RefCounted = null
var _icons: RefCounted = null


func _ready() -> void:
	# Control draws via _draw(). Call queue_redraw when state changes.
	if _dungeon_grid != null and _dungeon_grid.has_signal("layout_changed"):
		_dungeon_grid.layout_changed.connect(queue_redraw)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	# Initialize services
	_icons = ItemIconServiceScript.new()
	_drawsvc = DrawServiceScript.new(self, _icons)
	_placement = PlacementServiceScript.new(self, _dungeon_grid, _room_db, _game_state)
	_slots = SlotServiceScript.new(self, _dungeon_grid)
	_stamps = StampFxServiceScript.new()
	queue_redraw()


func _now_s() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


# (hash/draw helpers moved into DrawService)

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
	if _stamps != null:
		_stamps.trigger_room(rect)
	queue_redraw()


func _trigger_slot_stamp(rect: Rect2) -> void:
	if _stamps != null:
		_stamps.trigger_slot(rect)
	queue_redraw()


#
# (stamp rect draw moved to StampFxService)


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


#
# (dashed/hatch rect helpers moved to DrawService)


#
# (clip + hatch helpers moved to DrawService)


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
	var hit: Dictionary = _slot_at_local_pos(get_local_mouse_position()) if _slots == null else _slots.hit_test_slot(get_local_mouse_position())
	_hover_slot_room_id = int(hit.get("room_id", 0))
	_hover_slot_idx = int(hit.get("slot_idx", -1))
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
	if _slots != null:
		_slots.uninstall(_hover_slot_room_id, _hover_slot_idx)
	queue_redraw()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var d := data as Dictionary
	# Room inventory drag
	if d.has("room_type_id"):
		_drag_room_type_id = String(d.get("room_type_id", ""))
		queue_redraw()
		_update_hover_cell()
		if not _hover_in_bounds():
			return false
		if _placement == null:
			return false
		var res: Dictionary = _placement.can_place(_drag_room_type_id, hover_cell)
		_update_preview_reason(bool(res.get("ok", false)), String(res.get("reason", "")))
		return bool(res.get("ok", false))

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
	var hit: Dictionary = _slot_at_local_pos(get_local_mouse_position()) if _slots == null else _slots.hit_test_slot(get_local_mouse_position())
	var room_id: int = int(hit.get("room_id", 0))
	var slot_idx: int = int(hit.get("slot_idx", -1))
	if room_id == 0 or slot_idx == -1:
		return false
	if _slots == null:
		return false
	return _slots.can_install(item_id, room_id, slot_idx)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	var d := data as Dictionary
	# Room inventory drop
	if d.has("room_type_id"):
		var type_id: String = String(d.get("room_type_id", ""))
		_update_hover_cell()
		var cell := hover_cell
		if _placement != null and _hover_in_bounds():
			var res: Dictionary = _placement.can_place(type_id, cell)
			if bool(res.get("ok", false)) and _placement.drop_room(type_id, cell):
				var size: Vector2i = res.get("size", Vector2i.ONE)
				var px := float(_cell_px())
				_trigger_room_stamp(Rect2(Vector2(cell.x, cell.y) * px, Vector2(size.x, size.y) * px))
				_emit_build_status()
				queue_redraw()
		_drag_room_type_id = ""
		return

	var item_id := String(d.get("item_id", ""))
	if item_id == "":
		return
	var hit: Dictionary = _slot_at_local_pos(get_local_mouse_position()) if _slots == null else _slots.hit_test_slot(get_local_mouse_position())
	var room_id: int = int(hit.get("room_id", 0))
	var slot_idx: int = int(hit.get("slot_idx", -1))
	if room_id == 0 or slot_idx == -1:
		return
	if not _can_drop_data(Vector2.ZERO, data):
		return
	if _slots != null and _slots.install(item_id, room_id, slot_idx):
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

	if _placement == null:
		return false
	return bool(_placement.can_place(type_id, cell).get("ok", false))


func _drop_room(d: Dictionary) -> void:
	if _placement == null:
		return
	if not _can_drop_room(d):
		return
	var type_id: String = String(d.get("room_type_id", ""))
	var cell := hover_cell
	var res: Dictionary = _placement.can_place(type_id, cell)
	if not bool(res.get("ok", false)):
		return
	if _placement.drop_room(type_id, cell):
		var size: Vector2i = res.get("size", Vector2i.ONE)
		var px := float(_cell_px())
		_trigger_room_stamp(Rect2(Vector2(cell.x, cell.y) * px, Vector2(size.x, size.y) * px))
		_emit_build_status()
		queue_redraw()


func _can_place_type_at(type_id: String, cell: Vector2i) -> Dictionary:
	# Returns { ok: bool, reason: String, size: Vector2i, cost: int, kind: String, cells?: Array[Vector2i] }
	if _placement == null:
		return { "ok": false, "reason": "missing_service", "size": Vector2i.ONE, "cost": 0, "kind": "" }
	return _placement.can_place(type_id, cell)


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
	if _placement == null:
		return { "ok": false, "reason": "missing_service", "size": Vector2i.ONE, "cost": 0, "kind": "" }
	return _placement.can_place(selected_type_id, cell)


#
# (click-to-place removed; placement is via drag-and-drop)


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
	var accent_ok := _tcol("accent_ok", BlueprintTheme.ACCENT_OK)
	var accent_bad := _tcol("accent_bad", BlueprintTheme.ACCENT_BAD)
	var accent_warn := _tcol("accent_warn", BlueprintTheme.ACCENT_WARN)

	# Grid and backdrop
	if _drawsvc != null:
		_drawsvc.draw_grid()

	# Render placed rooms (if DungeonGrid autoload exists).
	if _dungeon_grid != null:
		for r in _dungeon_grid.rooms:
			if _drawsvc != null:
				_drawsvc.draw_room(r)

	# Placement preview
	if _hover_in_bounds():
		var use_type: String = selected_type_id
		if _drag_room_type_id != "":
			use_type = _drag_room_type_id
		var res: Dictionary = _can_place_type_at(use_type, hover_cell)
		_update_preview_reason(bool(res.get("ok", false)), String(res.get("reason", "")))
		if _drawsvc != null:
			_drawsvc.draw_preview(res, hover_cell)
	else:
		_update_preview_reason(true, "")

	# Success stamps (room/item).
	var now := _now_s()
	if _stamps != null:
		_stamps.draw(self, now, accent_ok)


func _process(_delta: float) -> void:
	# During DAY, redraw so monster counts/icons update as encounters spawn/despawn.
	if Engine.has_singleton("GameState") and GameState.phase == GameState.Phase.DAY:
		queue_redraw()
		return
	# While stamps are active, keep animating.
	if _stamps != null and _stamps.has_active(_now_s()):
		queue_redraw()


#
# (room drawing moved to DrawService)


func _is_trap_slot_ready(room_id: int, slot_idx: int, item_id: String) -> bool:
	# Trap readiness is owned by Simulation/TrapSystem (cooldowns, charges, disarms).
	if Engine.has_singleton("Simulation") and Simulation != null and Simulation.has_method("is_trap_slot_ready"):
		return bool(Simulation.call("is_trap_slot_ready", int(room_id), int(slot_idx), String(item_id)))
	# If we can't query state, default to showing the icon.
	return true


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


#
# (icon stamp drawing moved to DrawService)
