extends PanelContainer

@onready var _title: Label = $VBox/Top/Title
@onready var _close: Button = $VBox/Top/Close
@onready var _slots_grid: GridContainer = $VBox/SlotsGrid

var _room_id: int = 0
var _ignore_outside_until_ms: int = 0
var _last_open_screen_pos: Vector2 = Vector2.ZERO

@onready var _dg: Node = get_node_or_null("/root/DungeonGrid")
@onready var _room_db: Node = get_node_or_null("/root/RoomDB")
@onready var _item_db: Node = get_node_or_null("/root/ItemDB")

const POPUP_PADDING := Vector2(0, 0)
const SLOT_COL_MIN_W := 80.0
const ICON_MIN_SIZE := Vector2(22, 22)
const MAX_SLOT_COLUMNS := 4
const STATS_FONT_SIZE := 10
const HEADER_FONT_SIZE := 11
const COL_SEPARATION := 2


func _ready() -> void:
	visible = false
	if _close != null:
		_close.pressed.connect(close)


func open_at(room_id: int, screen_pos: Vector2) -> void:
	DbgLog.debug("open_at room_id=%d pos=%s" % [room_id, str(screen_pos)], "ui")
	_last_open_screen_pos = screen_pos
	_room_id = room_id
	visible = false
	_refresh()
	await get_tree().process_frame
	# Size BEFORE showing to avoid visible snapping.
	var want := get_combined_minimum_size()
	size = want + POPUP_PADDING
	_place_near_screen_pos(screen_pos)
	_ignore_outside_until_ms = int(Time.get_ticks_msec()) + 80
	visible = true
	DbgLog.debug("open_at done pos=%s size=%s want=%s" % [str(position), str(size), str(want)], "ui")


func close() -> void:
	_room_id = 0
	visible = false


func can_close_from_outside_click() -> bool:
	return int(Time.get_ticks_msec()) >= _ignore_outside_until_ms


func _refresh() -> void:
	if _slots_grid == null:
		DbgLog.error("RoomPopup missing SlotsGrid node", "ui")
		return
	_clear_children(_slots_grid)
	if _dg == null or _room_db == null:
		DbgLog.error("RoomPopup missing DungeonGrid/RoomDB autoload", "ui")
		_title.text = "Room"
		return
	var room: Dictionary = _dg.call("get_room_by_id", _room_id) as Dictionary
	if room.is_empty():
		DbgLog.warn("RoomPopup unknown room_id=%d" % _room_id, "ui")
		_title.text = "Room"
		return

	var type_id := String(room.get("type_id", ""))
	var kind := String(room.get("kind", ""))
	var def: Dictionary = _room_db.call("get_room_type", type_id) as Dictionary if type_id != "" else {}
	var label := String(def.get("label", "")) if not def.is_empty() else ""
	if label == "":
		label = _pretty_kind(kind)
	_title.text = label

	var slots: Array = room.get("slots", [])
	DbgLog.debug("RoomPopup room_id=%d kind=%s slots=%d" % [_room_id, kind, slots.size()], "ui")
	# Keep the popup small: use as many columns as fit (up to MAX_SLOT_COLUMNS), wrap into rows.
	var vp_w := get_viewport_rect().size.x
	var approx_col_w := SLOT_COL_MIN_W + 10.0
	var fit := int(floor(maxf(1.0, (vp_w - 40.0) / approx_col_w)))
	_slots_grid.columns = clampi(slots.size(), 1, mini(MAX_SLOT_COLUMNS, fit))

	for i in range(slots.size()):
		var s: Dictionary = slots[i] as Dictionary
		var installed := String(s.get("installed_item_id", ""))
		DbgLog.debug("RoomPopup slot=%d installed=%s" % [i, installed], "ui")
		_slots_grid.add_child(_make_slot_column(i + 1, kind, installed))


func _make_slot_column(slot_number: int, room_kind: String, item_id: String) -> Control:
	# room_kind unused for now (kept for future slot-type icons).
	DbgLog.debug("_make_slot_column slot=%d kind=%s item_id=%s" % [slot_number, room_kind, item_id], "ui")
	var col := VBoxContainer.new()
	# Keep compact, but enforce a small floor so it doesn't collapse into a thin strip.
	col.custom_minimum_size = Vector2(SLOT_COL_MIN_W, 0)
	col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	col.add_theme_constant_override("separation", COL_SEPARATION)

	# Header: Slot label
	var slot_lbl := Label.new()
	slot_lbl.text = "Slot %d" % slot_number
	slot_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_lbl.add_theme_font_size_override("font_size", HEADER_FONT_SIZE)
	col.add_child(slot_lbl)

	# Icon
	var icon := TextureRect.new()
	icon.custom_minimum_size = ICON_MIN_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _item_icon(item_id)
	DbgLog.debug("_make_slot_column icon_ok item_id=%s tex=%s" % [item_id, str(icon.texture)], "ui")
	col.add_child(icon)

	# Name
	var name_lbl := Label.new()
	name_lbl.text = _item_name(item_id, room_kind)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Prevent tall growth from wrapping; keep it single-line and compact.
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_lbl.clip_text = true
	name_lbl.add_theme_font_size_override("font_size", HEADER_FONT_SIZE)
	col.add_child(name_lbl)

	# Stats
	var stats := Label.new()
	stats.text = _item_stats(item_id)
	# Keep stats compact: no wrapping, 1–2 lines max from _item_stats().
	stats.autowrap_mode = TextServer.AUTOWRAP_OFF
	stats.clip_text = true
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_theme_font_size_override("font_size", STATS_FONT_SIZE)
	DbgLog.debug("_make_slot_column stats_ok item_id=%s" % item_id, "ui")
	col.add_child(stats)

	return col


func _item_icon(item_id: String) -> Texture2D:
	if item_id == "" or _item_db == null:
		return null
	DbgLog.debug("_item_icon item_id=%s" % item_id, "ui")
	var res: Resource = _item_db.call("get_any_item", item_id) as Resource
	DbgLog.debug("_item_icon res=%s" % str(res), "ui")
	if res is TrapItem:
		return (res as TrapItem).icon
	if res is MonsterItem:
		return (res as MonsterItem).icon
	if res is TreasureItem:
		return (res as TreasureItem).icon
	return null


func _item_name(item_id: String, _room_kind: String) -> String:
	if item_id == "":
		return "(empty)"
	if _item_db == null:
		return item_id
	var res: Resource = _item_db.call("get_any_item", item_id) as Resource
	if res is TrapItem:
		return (res as TrapItem).display_name
	if res is MonsterItem:
		return (res as MonsterItem).display_name
	if res is TreasureItem:
		return (res as TreasureItem).display_name
	return item_id


func _item_stats(item_id: String) -> String:
	if item_id == "" or _item_db == null:
		return ""
	DbgLog.debug("_item_stats item_id=%s" % item_id, "ui")
	var res: Resource = _item_db.call("get_any_item", item_id) as Resource
	DbgLog.debug("_item_stats res=%s" % str(res), "ui")
	if res == null:
		return ""
	if res is MonsterItem:
		var m := res as MonsterItem
		var aps := 0.0
		if float(m.attack_interval) > 0.0001:
			aps = 1.0 / float(m.attack_interval)
		# Compact stats to keep popup short.
		return "DMG %d  APS %.2f\nRNG %.0f  HP %d  SZ %d" % [
			int(m.attack_damage),
			aps,
			float(m.range),
			int(m.max_hp),
			int(m.size),
		]
	if res is TrapItem:
		var t := res as TrapItem
		return "DMG %d  PROC %.0f%%\nAOE %s" % [
			int(t.damage),
			float(t.proc_chance) * 100.0,
			"yes" if bool(t.hits_all) else "no",
		]
	if res is TreasureItem:
		var treasure := res as TreasureItem
		return treasure.display_name
	return ""


func _pretty_kind(kind: String) -> String:
	match kind:
		"monster":
			return "Monster Room"
		"trap":
			return "Trap Room"
		"treasure":
			return "Treasure Room"
		"boss":
			return "Boss Room"
		"entrance":
			return "Entrance"
		_:
			return "Room"


func _clear_children(n: Node) -> void:
	if n == null:
		return
	for c in n.get_children():
		c.queue_free()


func _place_near_screen_pos(screen_pos: Vector2) -> void:
	# Convert screen/global mouse position into the popup's PARENT local space (HUD space),
	# then place the popup near that point.
	var parent_ci := get_parent() as CanvasItem
	var inv: Transform2D = parent_ci.get_global_transform().affine_inverse() if parent_ci != null else Transform2D.IDENTITY
	var local_click := inv * screen_pos
	var offset := Vector2(18, 18)
	var pos := local_click + offset

	var vp := get_viewport_rect().size
	var s := size
	if s.x <= 1.0 or s.y <= 1.0:
		s = get_combined_minimum_size()
	var max_x := maxf(6.0, vp.x - s.x - 6.0)
	var max_y := maxf(6.0, vp.y - s.y - 6.0)
	pos.x = clampf(pos.x, 6.0, max_x)
	pos.y = clampf(pos.y, 6.0, max_y)
	position = pos

