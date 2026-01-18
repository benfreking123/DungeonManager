extends Control

signal shop_opened
signal shop_closed

@onready var _panel: Control = $Panel
@onready var _close: Button = $Panel/Close
@onready var _squares_container: Control = get_node_or_null("Squares") as Control
@onready var _items_root: Control = get_node_or_null("Items") as Control

const PANEL_MARGIN := 10.0
const PANEL_W_MIN := 520.0
const PANEL_W_MAX := 900.0
const SLIDE_DURATION := 0.32
const SQUARE_GROUP_SIZE := 2
const SQUARE_GROUP_STAGGER := 0.0275
const SQUARE_SPEED := 0.82 # < 1.0 = faster
const SHOP_SLOT_SCALE := 0.40

var _is_open: bool = false
var _tween: Tween = null
var _squares_tween: Tween = null

var _squares_root: Node = null
var _squares: Array[CanvasItem] = []
var _square_final: Dictionary = {} # NodePath -> {pos, rot, scale, a}

var _slot_scene: PackedScene = preload("res://ui/ShopItemSlot.tscn")
var _popup_scene: PackedScene = preload("res://ui/item_popup.tscn")
var _popup: PanelContainer = null

var _offers: Array[Dictionary] = []
var _offer_by_square_path: Dictionary = {} # NodePath -> Dictionary offer
var _shop_seed: int = 0


func _ready() -> void:
	visible = false
	if _close != null:
		_close.pressed.connect(close)
	resized.connect(_on_resized)
	if _squares_container != null:
		_squares_container.visible = false
	_cache_squares()
	if _items_root != null:
		_items_root.visible = false
	_clear_items()
	_ensure_popup()


func is_open() -> bool:
	return visible and _is_open


func open() -> void:
	_is_open = true
	visible = true
	_layout_panel()
	_stop_squares_anim()
	if _squares_container != null:
		_squares_container.visible = false
	if _items_root != null:
		_items_root.visible = false
	_clear_items()
	_slide(true)
	shop_opened.emit()


func open_with_seed(seed: int) -> void:
	_shop_seed = int(seed)
	_roll_offers()
	open()


func close() -> void:
	_is_open = false
	if not visible:
		return
	_layout_panel()
	if _popup != null:
		_popup.call("close")
	# Close sequence: squares animate out first; then panel slides away.
	if _squares_container != null and _squares_container.visible:
		_play_squares_hide()
	else:
		# Nothing to animate; ensure squares are hidden and slide panel out immediately.
		if _squares_container != null:
			_squares_container.visible = false
		_slide(false)


func _on_resized() -> void:
	if not visible:
		return
	_layout_panel()
	# Keep the panel snapped to its target when window size changes.
	_panel.position.x = _target_x() if _is_open else _offscreen_x()
	_snap_squares_to_panel()


func _layout_panel() -> void:
	if _panel == null:
		return
	var vp := get_viewport_rect().size
	var want_w := clampf(vp.x * 0.62, PANEL_W_MIN, PANEL_W_MAX)
	_panel.size = Vector2(want_w, vp.y)
	_panel.position.y = 0.0


func _slide(to_open: bool) -> void:
	if _panel == null:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()

	var from_x := _panel.position.x
	var to_x := _target_x() if to_open else _offscreen_x()
	_panel.position.x = from_x

	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_panel, "position:x", to_x, SLIDE_DURATION)
	if to_open:
		_tween.tween_callback(_on_panel_fully_opened)
	if not to_open:
		_tween.tween_callback(func():
			visible = false
			shop_closed.emit()
		)


func _target_x() -> float:
	var vp_w := get_viewport_rect().size.x
	return maxf(PANEL_MARGIN, vp_w - _panel.size.x - PANEL_MARGIN)


func _offscreen_x() -> float:
	return -_panel.size.x - PANEL_MARGIN


func _on_panel_fully_opened() -> void:
	# Start the squares sequence only after the panel is done moving.
	# Defer by 1 idle frame so layout/Control sizes are valid, without using `await`.
	call_deferred("_start_squares_reveal_after_open")


func _start_squares_reveal_after_open() -> void:
	_snap_squares_to_panel()
	_play_squares_reveal()


func _snap_squares_to_panel() -> void:
	if _panel == null:
		return
	if _squares_container == null:
		_squares_container = get_node_or_null("Squares") as Control
	if _squares_container == null:
		return
	# Keep squares aligned to the panel's final position, but do not animate with it.
	# IMPORTANT: do NOT resize this container. The square TextureRects are anchored
	# to fill their parent; resizing would stretch them and shift their offsets.
	_squares_container.position = Vector2(_panel.position.x, _squares_container.position.y)
	if _items_root == null:
		_items_root = get_node_or_null("Items") as Control
	if _items_root != null:
		_items_root.position = Vector2(_panel.position.x, _items_root.position.y)


func _cache_squares() -> void:
	# Prefer a root sibling so squares remain transform-independent from the panel.
	_squares_root = get_node_or_null("Squares")
	_squares.clear()
	_square_final.clear()
	if _squares_root == null:
		return

	# Collect BlackSquare..BlackSquare8 in order.
	for c in _squares_root.get_children():
		if c is TextureRect and String(c.name).begins_with("BlackSquare"):
			_squares.append(c)
	_squares.sort_custom(func(a: CanvasItem, b: CanvasItem) -> bool:
		return _square_order(a.name) < _square_order(b.name)
	)

	for s in _squares:
		var ci := s as CanvasItem
		_square_final[ci.get_path()] = {
			"pos": ci.position,
			"rot": ci.rotation,
			"scale": ci.scale,
			"a": ci.modulate.a,
		}


func _square_order(nm: StringName) -> int:
	var s := String(nm)
	if s == "BlackSquare":
		return 1
	var tail := s.replace("BlackSquare", "")
	var v := int(tail) if tail.is_valid_int() else 999
	return v


func _randomized_squares() -> Array[CanvasItem]:
	# Randomize order each time (without disturbing cached final transforms).
	var arr: Array[CanvasItem] = _squares.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# Fisher–Yates shuffle using our RNG.
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
	return arr


func _play_squares_reveal() -> void:
	_cache_squares()
	if _squares.is_empty():
		return

	_stop_squares_anim()
	_clear_items()
	if _items_root != null:
		_items_root.visible = false

	if _squares_container == null and _squares_root is Control:
		_squares_container = _squares_root as Control

	var order := _randomized_squares()

	# Prepare: move each square to an off-board “thrown from left” start pose.
	for i in range(order.size()):
		var sq := order[i] as CanvasItem
		var fin: Dictionary = _square_final.get(sq.get_path(), {}) as Dictionary
		if fin.is_empty():
			continue
		var fin_pos: Vector2 = fin["pos"]
		var fin_rot: float = fin["rot"]
		var fin_scale: Vector2 = fin["scale"]

		# Deterministic per-index spice (no RNG state needed).
		var jitter_x := -120.0 - float(i) * 18.0
		var jitter_y := -40.0 - float((i * 17) % 33)
		var start_pos := fin_pos + Vector2(jitter_x, jitter_y)
		var start_rot := fin_rot + deg_to_rad(18.0) * (1.0 if (i % 2) == 0 else -1.0) + deg_to_rad(float((i * 11) % 9) - 4.0)

		sq.position = start_pos
		sq.rotation = start_rot
		sq.scale = fin_scale * 0.92
		sq.modulate.a = 0.0
		if sq is Control:
			(sq as Control).pivot_offset = (sq as Control).size * 0.5

	# Only show the container after we've zeroed alpha / set start poses (avoids 1-frame flicker).
	if _squares_container != null:
		_squares_container.visible = true
	if _items_root != null:
		_items_root.visible = true

	# Sequence tween: random order, two squares at a time.
	_squares_tween = create_tween()
	for i in range(order.size()):
		var sq := order[i] as CanvasItem
		var fin: Dictionary = _square_final.get(sq.get_path(), {}) as Dictionary
		if fin.is_empty():
			continue

		var fin_pos2: Vector2 = fin["pos"]
		var fin_rot2: float = fin["rot"]
		var fin_scale2: Vector2 = fin["scale"]
		var fin_a2: float = fin["a"]

		var overshoot := fin_pos2 + Vector2(14.0, -10.0)

		var group_idx := int(floor(float(i) / float(SQUARE_GROUP_SIZE)))
		var group_delay := float(group_idx) * SQUARE_GROUP_STAGGER
		var track := _squares_tween.parallel()
		track.tween_interval(group_delay)

		# Phase 1: throw in (fast, visible, rotates toward final)
		var p1 := track.tween_property(sq, "position", overshoot, 0.16 * SQUARE_SPEED)
		p1.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		var r1 := track.parallel().tween_property(sq, "rotation", fin_rot2, 0.16 * SQUARE_SPEED)
		r1.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		var a1 := track.parallel().tween_property(sq, "modulate:a", fin_a2, 0.08 * SQUARE_SPEED)
		a1.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		var s1 := track.parallel().tween_property(sq, "scale", fin_scale2 * 1.06, 0.10 * SQUARE_SPEED)
		s1.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

		# Phase 2: snap + settle (tiny bounce)
		var p2 := track.tween_property(sq, "position", fin_pos2, 0.12 * SQUARE_SPEED)
		p2.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var s2 := track.parallel().tween_property(sq, "scale", fin_scale2, 0.10 * SQUARE_SPEED)
		s2.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		track.tween_callback(func():
			_reveal_item_for_square(sq)
		)

func _play_squares_hide() -> void:
	_cache_squares()
	if _squares.is_empty():
		if _squares_container != null:
			_squares_container.visible = false
		_slide(false)
		return

	_stop_squares_anim()

	if _squares_container == null and _squares_root is Control:
		_squares_container = _squares_root as Control

	var order := _randomized_squares()

	# Sequence tween: random order, two squares at a time, then hide container + slide panel away.
	_squares_tween = create_tween()
	_squares_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	for i in range(order.size()):
		var sq := order[i] as CanvasItem
		var fin: Dictionary = _square_final.get(sq.get_path(), {}) as Dictionary
		if fin.is_empty():
			continue

		var fin_pos: Vector2 = fin["pos"]
		var fin_rot: float = fin["rot"]
		var fin_scale: Vector2 = fin["scale"]

		# Mirror the reveal's deterministic spice, but send them outward.
		var jitter_x := -140.0 - float(i) * 18.0
		var jitter_y := -50.0 - float((i * 19) % 37)
		var out_pos := fin_pos + Vector2(jitter_x, jitter_y)
		var out_rot := fin_rot + deg_to_rad(22.0) * (1.0 if (i % 2) == 0 else -1.0)

		var group_idx := int(floor(float(i) / float(SQUARE_GROUP_SIZE)))
		var group_delay := float(group_idx) * SQUARE_GROUP_STAGGER
		var track := _squares_tween.parallel()
		track.tween_interval(group_delay)

		var p := track.tween_property(sq, "position", out_pos, 0.14 * SQUARE_SPEED)
		p.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		var r := track.parallel().tween_property(sq, "rotation", out_rot, 0.14 * SQUARE_SPEED)
		r.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		var a := track.parallel().tween_property(sq, "modulate:a", 0.0, 0.10 * SQUARE_SPEED)
		a.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		var s := track.parallel().tween_property(sq, "scale", fin_scale * 0.92, 0.12 * SQUARE_SPEED)
		s.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	_squares_tween.tween_callback(func():
		if _squares_container != null:
			_squares_container.visible = false
		if _items_root != null:
			_items_root.visible = false
		_clear_items()
		_restore_squares_final()
		_slide(false)
	)


func _roll_offers() -> void:
	_offers.clear()
	_offer_by_square_path.clear()
	var cfg := get_node_or_null("/root/config_shop")
	if cfg == null or not cfg.has_method("roll_shop_offers"):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_shop_seed)
	_offers = cfg.call("roll_shop_offers", rng, 8) as Array[Dictionary]
	# Assign offers in stable square order (BlackSquare..BlackSquare8).
	_cache_squares()
	for i in range(mini(_squares.size(), _offers.size())):
		var sq := _squares[i]
		_offer_by_square_path[sq.get_path()] = _offers[i]


func _reveal_item_for_square(sq: CanvasItem) -> void:
	if sq == null or not is_instance_valid(sq):
		return
	if _items_root == null:
		_items_root = get_node_or_null("Items") as Control
	if _items_root == null:
		return
	var offer: Dictionary = _offer_by_square_path.get(sq.get_path(), {}) as Dictionary
	if offer.is_empty():
		return

	var slot := _slot_scene.instantiate() as Control
	_items_root.add_child(slot)

	# Place centered on the square's global rect.
	var sq_rect := (sq as Control).get_global_rect() if sq is Control else Rect2(sq.global_position, Vector2(64, 64))
	var center := sq_rect.position + sq_rect.size * 0.5
	var inv: Transform2D = _items_root.get_global_transform().affine_inverse()
	var local_center := inv * center
	# Ensure a stable size so we can center reliably.
	slot.custom_minimum_size = sq_rect.size * SHOP_SLOT_SCALE
	slot.size = slot.custom_minimum_size
	slot.position = local_center - (slot.size * 0.5)

	var icon := _offer_icon(offer)
	var cost_txt := _offer_cost_text(offer)
	slot.call("set_offer", offer, icon, cost_txt)
	slot.connect("hover_entered", Callable(self, "_on_slot_hover_entered"))
	slot.connect("hover_exited", Callable(self, "_on_slot_hover_exited"))
	slot.connect("purchase_pressed", Callable(self, "_on_slot_purchase_pressed"))

	# Animate in quickly (after its square lands).
	slot.modulate.a = 0.0
	slot.scale = Vector2(0.92, 0.92)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(slot, "modulate:a", 1.0, 0.10)
	tw.parallel().tween_property(slot, "scale", Vector2.ONE, 0.12)


func _offer_icon(offer: Dictionary) -> Texture2D:
	var kind := String(offer.get("kind", ""))
	var target_id := String(offer.get("target_id", ""))
	if kind == "item":
		var res: Resource = ItemDB.get_any_item(target_id)
		if res is TrapItem:
			return (res as TrapItem).icon
		if res is MonsterItem:
			return (res as MonsterItem).icon
		if res is TreasureItem:
			return (res as TreasureItem).icon
		if res is BossUpgradeItem:
			return (res as BossUpgradeItem).icon
		return null
	if kind == "room":
		var room_db := get_node_or_null("/root/RoomDB")
		var def: Dictionary = room_db.call("get_room_type", target_id) as Dictionary if room_db != null else {}
		var room_kind := String(def.get("kind", target_id))
		var scene := get_tree().current_scene
		var rip := scene.find_child("RoomInventoryPanel", true, false) if scene != null else null
		if rip != null:
			return rip.call("_get_room_glyph_icon", room_kind) as Texture2D
	return null


func _offer_cost_text(offer: Dictionary) -> String:
	var cost: Dictionary = offer.get("cost", {}) as Dictionary
	if cost.is_empty():
		return ""
	var parts: Array[String] = []
	for k in cost.keys():
		var tid := String(k)
		var amt := int(cost.get(k, 0))
		if tid == "" or amt <= 0:
			continue
		parts.append("%s x%d" % [_short_treasure_name(tid), amt])
	return " • ".join(parts)


func _short_treasure_name(item_id: String) -> String:
	var res: Resource = ItemDB.get_any_item(String(item_id))
	if res is TreasureItem:
		var nm := String((res as TreasureItem).display_name)
		nm = nm.replace(" Treasure", "")
		return nm
	return String(item_id).replace("treasure_", "").capitalize()


func _clear_items() -> void:
	if _items_root == null:
		_items_root = get_node_or_null("Items") as Control
	if _items_root == null:
		return
	for c in _items_root.get_children():
		c.queue_free()


func _ensure_popup() -> void:
	if _popup != null and is_instance_valid(_popup):
		return
	var inst := _popup_scene.instantiate() as PanelContainer
	add_child(inst)
	inst.name = "ItemPopup"
	inst.z_as_relative = false
	inst.z_index = 4096
	_popup = inst


func _on_slot_hover_entered(_slot: Control, offer: Dictionary, screen_pos: Vector2) -> void:
	_ensure_popup()
	if _popup == null:
		return
	var title := _offer_title(offer)
	var body := _offer_body_bbcode(offer)
	_popup.call("open_at", screen_pos, title, body)


func _on_slot_hover_exited() -> void:
	if _popup != null:
		_popup.call("close")


func _on_slot_purchase_pressed(slot: Control, offer: Dictionary, _screen_pos: Vector2) -> void:
	if slot == null or not is_instance_valid(slot):
		return
	if offer.is_empty():
		return
	if not _can_afford(offer):
		DbgLog.debug("Shop purchase blocked (cant afford) offer=%s" % str(offer.get("id", "")), "ui")
		return
	_spend_cost(offer)
	_grant_offer(offer)
	_fly_offer_icon(slot, offer)
	# Remove the purchased slot immediately.
	slot.queue_free()


func _offer_title(offer: Dictionary) -> String:
	var kind := String(offer.get("kind", ""))
	var target_id := String(offer.get("target_id", ""))
	if kind == "item":
		var res: Resource = ItemDB.get_any_item(target_id)
		if res is TrapItem:
			return String((res as TrapItem).display_name)
		if res is MonsterItem:
			return String((res as MonsterItem).display_name)
		if res is TreasureItem:
			return String((res as TreasureItem).display_name)
		if res is BossUpgradeItem:
			return String((res as BossUpgradeItem).display_name)
		return target_id
	if kind == "room":
		var room_db := get_node_or_null("/root/RoomDB")
		var def: Dictionary = room_db.call("get_room_type", target_id) as Dictionary if room_db != null else {}
		return String(def.get("label", target_id))
	return "Shop Item"


func _offer_body_bbcode(offer: Dictionary) -> String:
	var kind := String(offer.get("kind", ""))
	var target_id := String(offer.get("target_id", ""))
	var cost_txt := _offer_cost_text(offer)
	var lines: Array[String] = []
	if cost_txt != "":
		lines.append("[b]Cost[/b] " + cost_txt)
	if kind == "room":
		var room_db := get_node_or_null("/root/RoomDB")
		var def: Dictionary = room_db.call("get_room_type", target_id) as Dictionary if room_db != null else {}
		var k := String(def.get("kind", target_id))
		var sz: Vector2i = def.get("size", Vector2i.ONE)
		lines.append("[b]Kind[/b] %s" % k)
		lines.append("[b]Size[/b] %dx%d" % [int(sz.x), int(sz.y)])
	return "\n".join(lines)


func _can_afford(offer: Dictionary) -> bool:
	var cost: Dictionary = offer.get("cost", {}) as Dictionary
	for k in cost.keys():
		var tid := String(k)
		var amt := int(cost.get(k, 0))
		if tid == "" or amt <= 0:
			continue
		if PlayerInventory.get_count(tid) < amt:
			return false
	return true


func _spend_cost(offer: Dictionary) -> void:
	var cost: Dictionary = offer.get("cost", {}) as Dictionary
	for k in cost.keys():
		var tid := String(k)
		var amt := int(cost.get(k, 0))
		if tid == "" or amt <= 0:
			continue
		PlayerInventory.consume(tid, amt)


func _grant_offer(offer: Dictionary) -> void:
	var kind := String(offer.get("kind", ""))
	var target_id := String(offer.get("target_id", ""))
	if kind == "item":
		PlayerInventory.refund(target_id, 1)
	elif kind == "room":
		RoomInventory.refund(target_id, 1)


func _fly_offer_icon(slot: Control, offer: Dictionary) -> void:
	var icon := _offer_icon(offer)
	if icon == null:
		return
	var from := slot.get_global_rect().position + slot.get_global_rect().size * 0.5
	var to := _inventory_target_global_pos(offer)
	if to == Vector2.ZERO:
		return

	# Reuse the LootDrop visual for the fly animation (matches end-of-day treasure feel).
	var world_canvas := _find_world_canvas()
	if world_canvas == null:
		return
	var node := preload("res://scenes/LootDrop.tscn").instantiate() as Node2D
	world_canvas.add_child(node)
	node.z_index = 999
	node.z_as_relative = false
	node.global_position = from
	node.call("set_icon", icon)

	var t := node.create_tween()
	t.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(node, "global_position", to, 0.55)
	t.parallel().tween_property(node, "scale", Vector2.ONE * 0.05, 0.55)
	t.parallel().tween_property(node, "modulate:a", 0.0, 0.55)
	t.finished.connect(func():
		if is_instance_valid(node):
			node.queue_free()
	)


func _find_world_canvas() -> CanvasItem:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var wc := scene.find_child("WorldCanvas", true, false)
	return wc as CanvasItem


func _inventory_target_global_pos(offer: Dictionary) -> Vector2:
	var scene := get_tree().current_scene
	if scene == null:
		return Vector2.ZERO
	var rip := scene.find_child("RoomInventoryPanel", true, false)
	if rip == null or not rip.has_method("get_collect_target_global_pos"):
		return Vector2.ZERO

	var kind := String(offer.get("kind", ""))
	var target_id := String(offer.get("target_id", ""))
	if kind == "room":
		return rip.call("get_collect_target_global_pos", "room") as Vector2

	# item: choose tab by item kind
	var item_kind := ""
	if ItemDB != null and ItemDB.has_method("get_item_kind"):
		item_kind = String(ItemDB.call("get_item_kind", target_id))
	if item_kind == "monster":
		return rip.call("get_collect_target_global_pos", "monsters") as Vector2
	if item_kind == "trap":
		return rip.call("get_collect_target_global_pos", "traps") as Vector2
	if item_kind == "treasure":
		return rip.call("get_collect_target_global_pos", "treasure") as Vector2
	if item_kind == "boss_upgrade":
		return rip.call("get_collect_target_global_pos", "boss") as Vector2
	return rip.call("get_collect_target_global_pos", "treasure") as Vector2


func _stop_squares_anim() -> void:
	if _squares_tween != null and _squares_tween.is_valid():
		_squares_tween.kill()
	_squares_tween = null


func _restore_squares_final() -> void:
	if _squares_root == null:
		_cache_squares()
	for sq in _squares:
		var ci := sq as CanvasItem
		var fin: Dictionary = _square_final.get(ci.get_path(), {}) as Dictionary
		if fin.is_empty():
			continue
		ci.position = fin["pos"]
		ci.rotation = fin["rot"]
		ci.scale = fin["scale"]
		ci.modulate.a = fin["a"]
