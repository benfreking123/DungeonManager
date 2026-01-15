extends Control

@onready var treasure_label: Label = $TopBar/HBox/TreasureLabel
@onready var power_label: Label = $TopBar/HBox/PowerLabel
@onready var day_button: Button = $TopBar/HBox/DayButton
@onready var speed_1x: Button = $TopBar/HBox/Speed1x
@onready var speed_2x: Button = $TopBar/HBox/Speed2x
@onready var speed_4x: Button = $TopBar/HBox/Speed4x
@onready var _simulation: Node = get_node("/root/Simulation")
@onready var _game_over: PanelContainer = $GameOverPanel

@onready var _paper_base: ColorRect = $PaperBase
@onready var _paper_grain: TextureRect = $PaperGrain

var _world_frame: Control = null
var _world_canvas: Control = null

var _world_zoom: float = 1.0
var _is_panning: bool = false
var _pan_start_mouse_parent: Vector2 = Vector2.ZERO
var _pan_start_canvas_pos: Vector2 = Vector2.ZERO

const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.5
const ZOOM_STEP := 1.12


func _ready() -> void:
	_resolve_world_nodes()
	_apply_paper_theme()
	day_button.pressed.connect(_on_day_pressed)
	_simulation.day_ended.connect(_on_day_ended)
	if _simulation.has_signal("boss_killed"):
		_simulation.connect("boss_killed", Callable(self, "_on_boss_killed"))
	if _game_over != null:
		_game_over.connect("restart_requested", Callable(self, "_restart_game"))

	var g := ButtonGroup.new()
	speed_1x.button_group = g
	speed_2x.button_group = g
	speed_4x.button_group = g

	speed_1x.pressed.connect(func(): GameState.set_speed(1.0))
	speed_2x.pressed.connect(func(): GameState.set_speed(2.0))
	speed_4x.pressed.connect(func(): GameState.set_speed(4.0))
	_apply_world_transform()


func _apply_paper_theme() -> void:
	# Keep background nodes theme-driven (so changing the Theme updates everything).
	if _paper_base != null and has_theme_color("paper_base", "HUD"):
		_paper_base.color = get_theme_color("paper_base", "HUD")
	if _paper_grain != null:
		# Grain is a subtle ink tint; keep alpha low.
		if has_theme_color("ink_dim", "HUD"):
			var ink_dim := get_theme_color("ink_dim", "HUD")
			_paper_grain.modulate = Color(ink_dim.r, ink_dim.g, ink_dim.b, 0.03)


func _resolve_world_nodes() -> void:
	# Support both HUD layouts (with or without Body container).
	_world_frame = get_node_or_null("Body/DungeonFrame/Dungeon/WorldFrame") as Control
	_world_canvas = get_node_or_null("Body/DungeonFrame/Dungeon/WorldFrame/WorldCanvas") as Control
	if _world_frame == null:
		_world_frame = get_node_or_null("DungeonFrame/Dungeon/WorldFrame") as Control
	if _world_canvas == null:
		_world_canvas = get_node_or_null("DungeonFrame/Dungeon/WorldFrame/WorldCanvas") as Control


func _on_day_pressed() -> void:
	if GameState.phase == GameState.Phase.BUILD:
		_simulation.call("start_day")
		if GameState.phase == GameState.Phase.DAY:
			day_button.text = "Day Running"
			day_button.disabled = true


func _on_day_ended() -> void:
	day_button.text = "Start Day"
	day_button.disabled = false


func set_treasure(value: int) -> void:
	treasure_label.text = "Treasure: %d" % value


func set_power(used: int, cap: int) -> void:
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
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion and _is_panning:
		var parent3 := _world_canvas.get_parent() as CanvasItem
		var parent_inv3: Transform2D = parent3.get_global_transform().affine_inverse()
		var mouse_parent2: Vector2 = parent_inv3 * mouse_global
		_world_canvas.position = _pan_start_canvas_pos + (mouse_parent2 - _pan_start_mouse_parent)
		get_viewport().set_input_as_handled()
		return


func _apply_world_transform() -> void:
	if _world_canvas == null:
		return
	_world_canvas.scale = Vector2(_world_zoom, _world_zoom)


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
