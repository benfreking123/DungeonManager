extends Node2D

# Very small MVP agent:
# - Moves along a surface straight line into entrance
# - Then moves cell-to-cell along a dungeon path

signal died(world_pos: Vector2, class_id: String)
signal damaged(amount: int)
signal right_clicked(adv_id: int, screen_pos: Vector2)

enum Phase { SURFACE, DUNGEON, DONE }

var phase: int = Phase.SURFACE

var _surface_target_local: Vector2 # stored in parent-local space (camera-independent)
var _surface_speed: float = 200.0

var _dungeon_view: Control
var _path: Array[Vector2i] = []
var _path_idx: int = 0
var _dungeon_speed: float = 180.0

var _on_reach_goal: Callable

var _time_accum: float = 0.0
var _wiggle_seed: float = 0.0

signal cell_reached(cell: Vector2i)

var hp_max: int = 10
var hp: int = 10
var attack_damage: int = 2
var attack_interval: float = 1.0
var range: float = 40.0

var in_combat: bool = false
var combat_room_id: int = 0
var party_id: int = 0
var class_id: String = ""
var class_icon: Texture2D
var _dead: bool = false

@onready var _click_area: Area2D = get_node_or_null("ClickArea") as Area2D


func set_surface_target(target_world: Vector2, speed: float) -> void:
	# Legacy API: treat as global space and convert each tick.
	_surface_target_local = _to_parent_local(target_world)
	_surface_speed = speed


func set_surface_target_local(target_local: Vector2, speed: float) -> void:
	# Preferred: parent-local coordinates so UI zoom/pan never affects movement.
	_surface_target_local = target_local
	_surface_speed = speed


func set_dungeon_targets(dungeon_view: Control, path: Array[Vector2i], speed: float) -> void:
	_dungeon_view = dungeon_view
	_path = path
	_path_idx = 0
	_dungeon_speed = speed


func set_path(path: Array[Vector2i]) -> void:
	# Used by AdventurerAI to retarget exploration.
	_path = path
	_path_idx = 0


func apply_class(c: AdventurerClass) -> void:
	if c == null:
		return
	class_id = c.id
	class_icon = c.icon
	hp_max = c.hp_max
	hp = hp_max
	attack_damage = c.attack_damage
	attack_interval = c.attack_interval
	range = c.range
	queue_redraw()


func set_on_reach_goal(cb: Callable) -> void:
	_on_reach_goal = cb


func tick(dt: float) -> void:
	_time_accum += dt
	match phase:
		Phase.SURFACE:
			if in_combat:
				return
			_move_toward_local(_surface_target_local, _surface_speed, dt)
			if position.distance_to(_surface_target_local) <= 2.0:
				phase = Phase.DUNGEON
		Phase.DUNGEON:
			if in_combat:
				return
			if _dungeon_view == null or _path.is_empty():
				_finish()
				return
			if _path_idx >= _path.size():
				_finish()
				return
			var cell: Vector2i = _path[_path_idx]
			var target: Vector2 = _dungeon_view.call("cell_center_world", cell) as Vector2
			var target_local2: Vector2 = _to_parent_local(target)
			_move_toward_local(target_local2, _dungeon_speed, dt)
			if position.distance_to(target_local2) <= 2.0:
				cell_reached.emit(cell)
				_path_idx += 1
		Phase.DONE:
			pass


func _to_parent_local(world_pos: Vector2) -> Vector2:
	var p := get_parent()
	if p == null or not (p is CanvasItem):
		return world_pos
	var inv: Transform2D = (p as CanvasItem).get_global_transform().affine_inverse()
	return inv * world_pos


func _move_toward_local(target: Vector2, speed: float, dt: float) -> void:
	# Add a small perpendicular wiggle so movement feels less robotic.
	var dir0 := target - position
	var dist0 := dir0.length()
	# Important: disable wiggle when close to the goal, otherwise units can orbit the point forever.
	if dist0 > 12.0:
		var dir := dir0 / dist0
		var perp := Vector2(-dir.y, dir.x)
		var amp := 3.0
		var wiggle := sin(_time_accum * 3.0 + _wiggle_seed) * amp
		target += perp * wiggle

	var v := target - position
	var dist := v.length()
	if dist <= 0.001:
		return
	var step: float = minf(dist, speed * dt)
	position += v / dist * step


func _finish() -> void:
	# Mark done, ask Simulation for a new path, then resume if one was assigned.
	phase = Phase.DONE
	if _on_reach_goal.is_valid():
		_on_reach_goal.call()
	if not _path.is_empty():
		phase = Phase.DUNGEON


func apply_damage(amount: int) -> void:
	hp = max(0, hp - amount)
	queue_redraw()
	DbgLog.log("Adventurer dmg=%d hp=%d/%d" % [amount, hp, hp_max], "adventurers")
	damaged.emit(amount)
	if hp <= 0:
		die()


func die() -> void:
	if _dead:
		return
	_dead = true
	# Notify Simulation/loot system (spawn ground loot, etc.)
	died.emit(global_position, class_id)
	phase = Phase.DONE
	queue_free()


func enter_combat(room_id: int) -> void:
	in_combat = true
	combat_room_id = room_id


func exit_combat() -> void:
	in_combat = false
	combat_room_id = 0


func _draw() -> void:
	var line := BlueprintTheme.LINE
	var line_dim := BlueprintTheme.LINE_DIM
	if _dungeon_view != null and is_instance_valid(_dungeon_view):
		# Reuse the dungeon blueprint palette from the active Theme.
		if _dungeon_view.has_theme_color("outline", "DungeonView"):
			line = _dungeon_view.get_theme_color("outline", "DungeonView")
		if _dungeon_view.has_theme_color("outline_dim", "DungeonView"):
			line_dim = _dungeon_view.get_theme_color("outline_dim", "DungeonView")
	var hp_back := ThemePalette.color("Combat", "hp_back", Color(0, 0, 0, 0.35))
	var hp_fill := ThemePalette.color("Combat", "hp_fill", Color(0.9, 0.2, 0.2, 0.95))

	const MARKER_SCALE := 0.65

	# Minimap marker: prefer class icon when present.
	if class_icon != null:
		var s := 22.0 * MARKER_SCALE
		draw_texture_rect(class_icon, Rect2(Vector2(-s * 0.5, -s * 0.5), Vector2(s, s)), true)
	else:
		# Simple dot + ring (blueprint style)
		draw_circle(Vector2.ZERO, 4.5 * MARKER_SCALE, line)
		draw_arc(Vector2.ZERO, 8.0 * MARKER_SCALE, 0, TAU, 24, line_dim, 2.0 * MARKER_SCALE)

	# HP bar above
	var w := 22.0
	var h := 5.0
	var x := -w * 0.5
	var y := -18.0
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), hp_back, true)
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), line_dim, false, 1.0)
	var pct := 0.0 if hp_max <= 0 else float(hp) / float(hp_max)
	draw_rect(Rect2(Vector2(x, y), Vector2(w * pct, h)), hp_fill, true)


func _ready() -> void:
	hp = hp_max
	_wiggle_seed = float(int(get_instance_id()) % 997) * 0.017
	if _click_area != null:
		_click_area.input_event.connect(_on_click_area_input_event)
	queue_redraw()


func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			right_clicked.emit(int(get_instance_id()), get_viewport().get_mouse_position())
