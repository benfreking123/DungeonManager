extends PanelContainer

@onready var _title: Label = $VBox/Top/Title
@onready var _filter: OptionButton = $VBox/Top/Filter
@onready var _close: Button = $VBox/Top/Close
@onready var _list: ItemList = $VBox/List
@onready var _count: Label = $VBox/Footer/Count
@onready var _strength_label: Label = $VBox/TownInfo/StrengthRow/StrengthLabel
@onready var _treasure_row: HBoxContainer = $VBox/TownInfo/TreasureRow
@onready var _class_row: HBoxContainer = $VBox/TownInfo/ClassChanceRow

@onready var _history_service: Object = null
var _strength_service: StrengthService = null
const CLASS_ICON_SIZE_PX := 32
const TREASURE_ICON_SIZE_PX := 32
const FILTER_ALL := 0
const FILTER_MAJOR := 1
const FILTER_DIALOGUE := 2
const FILTER_PARTY := 3
const FILTER_HERO := 4
const FILTER_LINEAGE := 5

func _ready() -> void:
	visible = false
	if _close != null:
		_close.pressed.connect(close)
	if _filter != null:
		_filter.clear()
		_filter.add_item("All", FILTER_ALL)
		_filter.add_item("Major", FILTER_MAJOR)
		_filter.add_item("Dialogue", FILTER_DIALOGUE)
		_filter.add_item("Party", FILTER_PARTY)
		_filter.add_item("Hero", FILTER_HERO)
		_filter.add_item("Lineage", FILTER_LINEAGE)
		_filter.selected = FILTER_ALL
		_filter.item_selected.connect(func(_idx: int) -> void:
			_refresh()
		)
	_history_service = preload("res://autoloads/HistoryService.gd").new()
	_strength_service = preload("res://scripts/services/StrengthService.gd").new()
	# Defer initial paint so ItemDB/DungeonGrid are ready.
	call_deferred("_refresh")
	# Update when data sources change
	var item_db := get_node_or_null("/root/ItemDB")
	if item_db != null and item_db.has_signal("db_ready"):
		item_db.db_ready.connect(_refresh)
	var dg := get_node_or_null("/root/DungeonGrid")
	if dg != null and dg.has_signal("layout_changed"):
		dg.layout_changed.connect(_refresh)
	if GameState != null and GameState.has_signal("day_changed"):
		GameState.day_changed.connect(func(_new_day: int) -> void:
			_refresh()
		)


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
	_refresh_town_info()
	var sim := get_node_or_null("/root/Simulation")
	# NOTE: `GameState` is an autoload Object; `"day_index" in GameState` does NOT work reliably.
	var di := int(GameState.day_index) if GameState != null else 1
	var events: Array = []
	var filter := _build_filter()
	events = _apply_filter(sim, filter)
	for e0 in events:
		var e := e0 as Dictionary
		_list.add_item(_format_line(e))
	if _count != null:
		_count.text = "%d entries" % _list.item_count


func _build_filter() -> Dictionary:
	if _filter == null:
		return {}
	match int(_filter.selected):
		FILTER_MAJOR:
			return { "severities": ["major"] }
		FILTER_DIALOGUE:
			return { "types": ["dialogue"] }
		FILTER_PARTY:
			return { "types": ["dialogue"], "tags": ["party_intent"] }
		FILTER_HERO:
			return { "mode": "hero" }
		FILTER_LINEAGE:
			return { "types": ["dialogue"], "tags": ["lineage"] }
		_:
			return {}


func _apply_filter(sim: Node, filter: Dictionary) -> Array:
	var mode := String(filter.get("mode", ""))
	if mode == "hero":
		var out: Array = []
		out.append_array(_get_events(sim, { "types": ["hero_arrived"] }))
		out.append_array(_get_events(sim, { "types": ["dialogue"], "tags": ["hero"] }))
		return out
	return _get_events(sim, filter)


func _get_events(sim: Node, filter: Dictionary) -> Array:
	if sim != null and sim.has_method("get_history_events_filtered"):
		return sim.call("get_history_events_filtered", filter) as Array
	if sim != null and sim.has_method("get_history_events"):
		return sim.call("get_history_events") as Array
	if _history_service != null and _history_service.has_method("get_events"):
		return _history_service.get_events(filter)
	return []


func _refresh_town_info() -> void:
	if _strength_label == null or _treasure_row == null or _class_row == null:
		return
	# Strength breakdown
	var di := 1
	if GameState != null:
		di = maxi(1, int(GameState.day_index))
	var cfg := get_node_or_null("/root/game_config")
	var breakdown := {}
	if _strength_service != null and _strength_service.has_method("compute_strength_breakdown"):
		breakdown = _strength_service.call("compute_strength_breakdown", di, cfg)
	var base_i := int(breakdown.get("base", 0))
	var t_bonus := int(breakdown.get("treasure_bonus", 0))
	_strength_label.text = "Strength: %d(%d)" % [base_i, t_bonus]

	# Treasure chips
	_clear_children(_treasure_row)
	# Static label so the row is visible even if empty
	var treasure_lbl := Label.new()
	treasure_lbl.text = "Treasures:"
	treasure_lbl.add_theme_font_size_override("font_size", 10)
	_treasure_row.add_child(treasure_lbl)
	var treasure_counts := _installed_treasure_counts()
	var item_db := get_node_or_null("/root/ItemDB")
	# Show all treasure types, even if the count is zero.
	var all_ids: Array[String] = []
	if item_db != null:
		var any: Variant = item_db.get("treasures")
		if typeof(any) == TYPE_DICTIONARY:
			for k in (any as Dictionary).keys():
				all_ids.append(String(k))
	for k2 in treasure_counts.keys():
		var id2 := String(k2)
		if not all_ids.has(id2):
			all_ids.append(id2)
	for tid in all_ids:
		var qty := int(treasure_counts.get(tid, 0))
		var chip := HBoxContainer.new()
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var qlbl := Label.new()
		qlbl.text = "%dx" % qty
		qlbl.add_theme_font_size_override("font_size", 10)
		chip.add_child(qlbl)
		if item_db != null and item_db.has_method("get_treasure"):
			var tres := item_db.call("get_treasure", String(tid)) as TreasureItem
			if tres != null and tres.icon != null:
				var tr := TextureRect.new()
				tr.texture = tres.icon
				tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr.custom_minimum_size = Vector2(TREASURE_ICON_SIZE_PX, TREASURE_ICON_SIZE_PX)
				tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				tr.scale = Vector2(0.25, 0.25)
				chip.add_child(tr)
		_treasure_row.add_child(chip)

	# Class chance indicators
	_clear_children(_class_row)
	var class_lbl := Label.new()
	class_lbl.text = "Classes:"
	class_lbl.add_theme_font_size_override("font_size", 10)
	_class_row.add_child(class_lbl)
	var pg := preload("res://scripts/services/PartyGenerator.gd").new() as PartyGenerator
	var weights: Dictionary = {}
	if pg != null and pg.has_method("class_spawn_weights"):
		weights = pg.call("class_spawn_weights", cfg) as Dictionary
	var sum_w := 0.0
	for k in weights.keys():
		sum_w += float(weights.get(k, 0))
	if sum_w <= 0.0001:
		sum_w = 1.0
	var classes := ["warrior", "mage", "priest", "rogue"]
	# Also compute matching treasure counts per class for tooltips
	var counts2 := _installed_treasure_counts()
	for cid in classes:
		var w := float(weights.get(cid, 0))
		var pct_f := (w / sum_w) * 100.0
		var chip2 := HBoxContainer.new()
		chip2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var lbl := Label.new()
		lbl.text = "%.1f%%" % pct_f
		lbl.add_theme_font_size_override("font_size", 10)
		chip2.add_child(lbl)
		if item_db != null and item_db.has_method("get_adv_class"):
			var cls := item_db.call("get_adv_class", String(cid)) as AdventurerClass
			if cls != null and cls.icon != null:
				var tr2 := TextureRect.new()
				tr2.texture = cls.icon
				tr2.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tr2.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr2.custom_minimum_size = Vector2(CLASS_ICON_SIZE_PX, CLASS_ICON_SIZE_PX)
				tr2.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				tr2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				tr2.scale = Vector2(0.25, 0.25)
				chip2.add_child(tr2)
		# Tooltip: how many matching treasures contribute to this class
		var cfg2 := get_node_or_null("/root/game_config")
		var contrib := 0
		if cfg2 != null and cfg2.has_method("treasure_id_for_class"):
			var tid_match := String(cfg2.call("treasure_id_for_class", String(cid)))
			if tid_match != "":
				contrib = int(counts2.get(tid_match, 0))
		chip2.tooltip_text = "%s spawn chance. Matching treasures: %d" % [cid.capitalize(), contrib]
		_class_row.add_child(chip2)


func _clear_children(node: Node) -> void:
	if node == null:
		return
	for c in node.get_children():
		c.queue_free()


func _installed_treasure_counts() -> Dictionary:
	var counts := {}
	var dg := get_node_or_null("/root/DungeonGrid")
	if dg == null:
		return counts
	var rooms: Array = dg.get("rooms") as Array
	for r0 in rooms:
		var r := r0 as Dictionary
		if String(r.get("kind", "")) != "treasure":
			continue
		var slots: Array = r.get("slots", [])
		for s0 in slots:
			var sd := s0 as Dictionary
			var id := String(sd.get("installed_item_id", ""))
			if id == "":
				continue
			counts[id] = int(counts.get(id, 0)) + 1
	return counts
