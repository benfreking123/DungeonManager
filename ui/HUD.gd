extends Control

var treasure_label: Label = null
var power_label: Label = null
var day_button: Button = null
var speed_1x: Button = null
var speed_2x: Button = null
var speed_4x: Button = null
@onready var _simulation: Node = get_node("/root/Simulation")
@onready var _game_over: PanelContainer = $GameOverPanel

# Optional paper FX nodes (some HUD layouts don't include these).
@onready var _paper_base: ColorRect = get_node_or_null("PaperBase") as ColorRect
@onready var _paper_grain: TextureRect = get_node_or_null("PaperGrain") as TextureRect
@onready var _paper_grain2: TextureRect = get_node_or_null("PaperGrain2") as TextureRect
@onready var _vignette: ColorRect = get_node_or_null("Vignette") as ColorRect
@onready var _placement_hint: Label = get_node_or_null("PlacementHint") as Label

var _world_frame: Control = null
var _world_canvas: Control = null
var _dungeon_view: Node = null
var _frame_paper_base: TextureRect = null

var _world_zoom: float = 1.0
var _is_panning: bool = false
var _pan_start_mouse_parent: Vector2 = Vector2.ZERO
var _pan_start_canvas_pos: Vector2 = Vector2.ZERO

const ZOOM_MIN := 1.0
const ZOOM_MAX := 2.5
const ZOOM_STEP := 1.12


func _ready() -> void:
	_resolve_topbar_nodes()
	_resolve_world_nodes()
	_apply_paper_theme()
	_layout_paper_fx()
	resized.connect(_layout_paper_fx)
	resized.connect(_apply_world_transform)
	_resolve_dungeon_view()
	_connect_placement_hint()
	set_process(true)
	if _game_over != null:
		# Ensure the overlay always renders above everything.
		_game_over.z_index = 4096
		_game_over.z_as_relative = false
	if day_button != null:
		day_button.pressed.connect(_on_day_pressed)
	_simulation.day_ended.connect(_on_day_ended)
	if _simulation.has_signal("boss_killed"):
		_simulation.connect("boss_killed", Callable(self, "_on_boss_killed"))
	if _game_over != null:
		_game_over.connect("restart_requested", Callable(self, "_restart_game"))

	var g := ButtonGroup.new()
	if speed_1x != null:
		speed_1x.button_group = g
	if speed_2x != null:
		speed_2x.button_group = g
	if speed_4x != null:
		speed_4x.button_group = g

	if speed_1x != null:
		speed_1x.pressed.connect(func(): GameState.set_speed(1.0))
	if speed_2x != null:
		speed_2x.pressed.connect(func(): GameState.set_speed(2.0))
	if speed_4x != null:
		speed_4x.pressed.connect(func(): GameState.set_speed(4.0))
	_apply_world_transform()


func _resolve_topbar_nodes() -> void:
	# Support old and new layouts:
	# - TopBar/HBox/...
	# - VBoxContainer/TopBar/HBox/...
	var bases := [
		"TopBar/HBox",
		"VBoxContainer/TopBar/HBox"
	]
	for base in bases:
		var tl := get_node_or_null("%s/TreasureLabel" % base) as Label
		var pl := get_node_or_null("%s/PowerLabel" % base) as Label
		var db := get_node_or_null("%s/DayButton" % base) as Button
		var s1 := get_node_or_null("%s/Speed1x" % base) as Button
		var s2 := get_node_or_null("%s/Speed2x" % base) as Button
		var s4 := get_node_or_null("%s/Speed4x" % base) as Button
		if tl != null and pl != null and db != null and s1 != null and s2 != null and s4 != null:
			treasure_label = tl
			power_label = pl
			day_button = db
			speed_1x = s1
			speed_2x = s2
			speed_4x = s4
			return
	# Fallback to whatever was found, even if partial
	if treasure_label == null:
		treasure_label = get_node_or_null("TopBar/HBox/TreasureLabel") as Label
	if power_label == null:
		power_label = get_node_or_null("TopBar/HBox/PowerLabel") as Label
	if day_button == null:
		day_button = get_node_or_null("TopBar/HBox/DayButton") as Button
	if speed_1x == null:
		speed_1x = get_node_or_null("TopBar/HBox/Speed1x") as Button
	if speed_2x == null:
		speed_2x = get_node_or_null("TopBar/HBox/Speed2x") as Button
	if speed_4x == null:
		speed_4x = get_node_or_null("TopBar/HBox/Speed4x") as Button

func _apply_paper_theme() -> void:
	# Keep background nodes theme-driven (so changing the Theme updates everything).
	if _paper_base != null and has_theme_color("paper_base", "HUD"):
		_paper_base.color = get_theme_color("paper_base", "HUD")
	if _paper_grain != null:
		# Grain is a subtle ink tint; keep alpha low.
		if has_theme_color("ink_dim", "HUD"):
			var ink_dim := get_theme_color("ink_dim", "HUD")
			_paper_grain.modulate = Color(ink_dim.r, ink_dim.g, ink_dim.b, 0.03)
			if _paper_grain2 != null:
				_paper_grain2.modulate = Color(ink_dim.r, ink_dim.g, ink_dim.b, 0.018)
			if _vignette != null:
				# Vignette shader uses its own color uniform; keep node visible.
				_vignette.color = Color(1, 1, 1, 1)


func _layout_paper_fx() -> void:
	# Keep rotated grain centered and oversized across window resizes.
	if _paper_grain2 != null:
		_paper_grain2.pivot_offset = _paper_grain2.size * 0.5


func _resolve_dungeon_view() -> void:
	# Support multiple HUD layouts (matches _resolve_world_nodes philosophy).
	var paths := [
		"VBoxContainer/HBoxContainer/DungeonFrame/FrameLayer/Dungeon/WorldFrame/WorldCanvas/Grid/DungeonView",
		"Body/DungeonFrame/Dungeon/WorldFrame/WorldCanvas/Grid/DungeonView",
		"DungeonFrame/Dungeon/WorldFrame/WorldCanvas/Grid/DungeonView",
	]
	for p in paths:
		var n := get_node_or_null(p)
		if n != null:
			_dungeon_view = n
			return


func _connect_placement_hint() -> void:
	if _placement_hint == null or _dungeon_view == null:
		return
	if _dungeon_view.has_signal("preview_reason_changed"):
		_dungeon_view.connect("preview_reason_changed", Callable(self, "_on_preview_reason_changed"))


func _on_preview_reason_changed(text: String, ok: bool) -> void:
	if _placement_hint == null:
		return
	_placement_hint.text = text
	_placement_hint.visible = (not ok) and text != ""


func _process(_delta: float) -> void:
	if _placement_hint == null or not _placement_hint.visible:
		return
	var mouse := get_viewport().get_mouse_position()
	var offset := Vector2(14, 18)
	var pos := mouse + offset
	var vp := get_viewport_rect().size
	var hint_size := _placement_hint.get_combined_minimum_size()
	pos.x = clampf(pos.x, 6.0, vp.x - hint_size.x - 6.0)
	pos.y = clampf(pos.y, 6.0, vp.y - hint_size.y - 6.0)
	_placement_hint.position = pos


func _resolve_world_nodes() -> void:
	# Support multiple HUD layouts.
	# 1) New layout with VBoxContainer/HBoxContainer prefix
	_world_frame = get_node_or_null("VBoxContainer/HBoxContainer/DungeonFrame/FrameLayer/Dungeon/WorldFrame") as Control
	_world_canvas = get_node_or_null("VBoxContainer/HBoxContainer/DungeonFrame/FrameLayer/Dungeon/WorldFrame/WorldCanvas") as Control
	# 2) Legacy layout with Body container
	if _world_frame == null:
		_world_frame = get_node_or_null("Body/DungeonFrame/Dungeon/WorldFrame") as Control
	if _world_canvas == null:
		_world_canvas = get_node_or_null("Body/DungeonFrame/Dungeon/WorldFrame/WorldCanvas") as Control
	# 3) Flat layout without Body/VBoxContainer
	if _world_frame == null:
		_world_frame = get_node_or_null("DungeonFrame/Dungeon/WorldFrame") as Control
	if _world_canvas == null:
		_world_canvas = get_node_or_null("DungeonFrame/Dungeon/WorldFrame/WorldCanvas") as Control

	# Background paper texture that should pan/zoom with the world contents.
	_frame_paper_base = null
	if _world_frame != null:
		_frame_paper_base = _world_frame.get_node_or_null("FramePaperBase") as TextureRect


func _on_day_pressed() -> void:
	if GameState.phase == GameState.Phase.BUILD:
		_simulation.call("start_day")
		if GameState.phase == GameState.Phase.DAY:
			if day_button != null:
				day_button.text = "Day Running"
				day_button.disabled = true


func _on_day_ended() -> void:
	if day_button != null:
		day_button.text = "Start Day"
		day_button.disabled = false


func set_treasure(value: int) -> void:
	if treasure_label != null:
		treasure_label.text = "Treasure: %d" % value


func set_power(used: int, cap: int) -> void:
	if power_label != null:
		power_label.text = "Power: %d/%d" % [used, cap]


func _input(event: InputEvent) -> void:
	if _world_frame == null or _world_canvas == null:
		return

	var mouse_global: Vector2 = get_viewport().get_mouse_position()
	var over_world: bool = _world_frame.get_global_rect().has_point(mouse_global)

	# Middle mouse pan
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				if not over_world:
					return
				_is_panning = true
				var parent := _world_canvas.get_parent() as CanvasItem
				var parent_inv: Transform2D = parent.get_global_transform().affine_inverse()
				_pan_start_mouse_parent = parent_inv * mouse_global
				_pan_start_canvas_pos = _world_canvas.position
				get_viewport().set_input_as_handled()
				return
			else:
				_is_panning = false
				get_viewport().set_input_as_handled()
				return

		# Wheel zoom (cursor-centered)
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if not over_world:
				return
			var old_zoom := _world_zoom
			var factor := ZOOM_STEP if mb.button_index == MOUSE_BUTTON_WHEEL_UP else (1.0 / ZOOM_STEP)
			_world_zoom = clampf(_world_zoom * factor, ZOOM_MIN, ZOOM_MAX)
			if absf(_world_zoom - old_zoom) < 0.0001:
				return

			var parent2 := _world_canvas.get_parent() as CanvasItem
			var parent_inv2: Transform2D = parent2.get_global_transform().affine_inverse()
			var mouse_parent: Vector2 = parent_inv2 * mouse_global

			# Keep the world point under cursor stable.
			var local_before: Vector2 = (mouse_parent - _world_canvas.position) / old_zoom
			_world_canvas.position = mouse_parent - local_before * _world_zoom
			_apply_world_transform()
			_clamp_world_canvas_position()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion and _is_panning:
		var parent3 := _world_canvas.get_parent() as CanvasItem
		var parent_inv3: Transform2D = parent3.get_global_transform().affine_inverse()
		var mouse_parent2: Vector2 = parent_inv3 * mouse_global
		_world_canvas.position = _pan_start_canvas_pos + (mouse_parent2 - _pan_start_mouse_parent)
		_clamp_world_canvas_position()
		get_viewport().set_input_as_handled()
		return


func _clamp_world_canvas_position() -> void:
	# Clamp panning so the world stays within the visible WorldFrame.
	# If the world is smaller than the frame (at current zoom), keep it centered.
	if _world_frame == null or _world_canvas == null:
		return

	var frame_size := _world_frame.size
	if frame_size.x <= 0.0 or frame_size.y <= 0.0:
		return

	var scaled_size := _world_canvas.size * _world_zoom
	if scaled_size.x <= 0.0 or scaled_size.y <= 0.0:
		return

	var min_x: float
	var max_x: float
	if scaled_size.x <= frame_size.x:
		min_x = (frame_size.x - scaled_size.x) * 0.5
		max_x = min_x
	else:
		min_x = frame_size.x - scaled_size.x
		max_x = 0.0

	var min_y: float
	var max_y: float
	if scaled_size.y <= frame_size.y:
		min_y = (frame_size.y - scaled_size.y) * 0.5
		max_y = min_y
	else:
		min_y = frame_size.y - scaled_size.y
		max_y = 0.0

	_world_canvas.position = Vector2(
		clampf(_world_canvas.position.x, min_x, max_x),
		clampf(_world_canvas.position.y, min_y, max_y)
	)


func _apply_world_transform() -> void:
	if _world_canvas == null:
		return
	_world_canvas.scale = Vector2(_world_zoom, _world_zoom)
	_clamp_world_canvas_position()

	# We now draw paper inside `DungeonView` itself. Disable the separate
	# `FramePaperBase` background to avoid layout/z-order surprises.
	if _frame_paper_base != null:
		_frame_paper_base.visible = false


func _on_boss_killed() -> void:
	# Stop simulation and show game over overlay.
	GameState.set_speed(0.0)
	_simulation.call_deferred("end_day")
	if _game_over != null:
		_game_over.visible = true


func _restart_game() -> void:
	# Full reset of run state.
	var sim := get_node_or_null("/root/Simulation")
	if sim != null:
		sim.call("end_day")
	var dg := get_node_or_null("/root/DungeonGrid")
	if dg != null:
		dg.call("clear")
	GameState.reset_all()
	PlayerInventory.reset_all()
	RoomInventory.reset_all()
	# Reload main scene so entrance auto-placement runs again.
	get_tree().reload_current_scene()
