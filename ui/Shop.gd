extends Control

signal shop_opened
signal shop_closed

@onready var _panel: Control = $Panel
@onready var _close: Button = $Panel/Close
@onready var _squares_container: Control = get_node_or_null("Squares") as Control

const PANEL_MARGIN := 10.0
const PANEL_W_MIN := 520.0
const PANEL_W_MAX := 900.0
const SLIDE_DURATION := 0.32
const SQUARE_GROUP_SIZE := 2
const SQUARE_GROUP_STAGGER := 0.055
const SQUARE_SPEED := 0.82 # < 1.0 = faster

var _is_open: bool = false
var _tween: Tween = null
var _squares_tween: Tween = null

var _squares_root: Node = null
var _squares: Array[CanvasItem] = []
var _square_final: Dictionary = {} # NodePath -> {pos, rot, scale, a}


func _ready() -> void:
	visible = false
	if _close != null:
		_close.pressed.connect(close)
	resized.connect(_on_resized)
	if _squares_container != null:
		_squares_container.visible = false
	_cache_squares()


func is_open() -> bool:
	return visible and _is_open


func open() -> void:
	_is_open = true
	visible = true
	_layout_panel()
	_stop_squares_anim()
	if _squares_container != null:
		_squares_container.visible = false
	_slide(true)
	shop_opened.emit()


func close() -> void:
	_is_open = false
	if not visible:
		return
	_layout_panel()
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

		var group_delay := float(i) / float(SQUARE_GROUP_SIZE) * SQUARE_GROUP_STAGGER
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

		var group_delay := float(i) / float(SQUARE_GROUP_SIZE) * SQUARE_GROUP_STAGGER
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
		_restore_squares_final()
		_slide(false)
	)


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
