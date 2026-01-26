extends Control

# Blueprint town strip. For MVP, this is mostly visual + provides spawn positions.

const TOWN_BOX_W := 220.0
const PAD := 12.0
const SHIFT_LEFT := 220.0

const TOWN_ICON: Texture2D = preload("res://assets/icons/town/IconSmallVillage.tres")
const TOWN_ICON_DRAW_SCALE := 2.0
const TOWN_ICON_Y_OFFSET := -5.0
const TOWN_SPAWN_Y_OFFSET_PX := 50.0

var _dungeon_view: Node = null

# Theme keys live in `ui/DungeonManagerTheme.tres` under `TownView/...`.
const THEME_TYPE := "TownView"

# Emitted when the user clicks the town icon itself.
signal town_icon_clicked()

# Back-compat fallback (if dungeon view not set yet)
var entrance_world_pos: Vector2 = Vector2.ZERO
var entrance_cap_world_rect: Rect2 = Rect2()

func _town_icon_rect_local() -> Rect2:
	if TOWN_ICON == null:
		return Rect2()
	var icon_size := TOWN_ICON.get_size()
	if icon_size.x <= 0.0 or icon_size.y <= 0.0:
		return Rect2()

	var max_h := maxf(1.0, size.y - PAD * 2.0)
	var icon_scale := (max_h / maxf(1.0, icon_size.y)) * TOWN_ICON_DRAW_SCALE
	var w := icon_size.x * icon_scale
	var h := icon_size.y * icon_scale

	# Keep within a reasonable width (prevents it from swallowing the whole strip).
	var max_w := TOWN_BOX_W * TOWN_ICON_DRAW_SCALE
	if w > max_w:
		var s2 := max_w / w
		w *= s2
		h *= s2

	var town_pos := Vector2(
		size.x - PAD - SHIFT_LEFT - w,
		PAD + (max_h - h) * 0.5 + TOWN_ICON_Y_OFFSET
	)
	return Rect2(town_pos, Vector2(w, h))


func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	queue_redraw()


func _tcol(key: String, fallback: Color) -> Color:
	return get_theme_color(key, THEME_TYPE) if has_theme_color(key, THEME_TYPE) else fallback


func _tconst(key: String, fallback: int) -> int:
	return get_theme_constant(key, THEME_TYPE) if has_theme_constant(key, THEME_TYPE) else fallback


func set_dungeon_view(dungeon_view: Node) -> void:
	_dungeon_view = dungeon_view
	queue_redraw()


func set_entrance_world_pos(p: Vector2) -> void:
	entrance_world_pos = p
	queue_redraw()


func set_entrance_cap_world_rect(r: Rect2) -> void:
	entrance_cap_world_rect = r
	queue_redraw()


func get_spawn_world_pos() -> Vector2:
	# Spawn at the center of the village icon.
	var local_rect := _town_icon_rect_local()
	if local_rect != Rect2():
		var c_local := local_rect.position + local_rect.size * 0.5
		return (get_global_transform() * c_local) + Vector2(0, TOWN_SPAWN_Y_OFFSET_PX)

	# Fallback: old "ground" spawn near right side.
	var r := get_global_rect()
	return Vector2(r.position.x + r.size.x - PAD - 24.0 - SHIFT_LEFT, r.position.y + r.size.y - PAD - 10.0)


func _draw() -> void:
	var bg := _tcol("bg", BlueprintTheme.BG)
	var line := _tcol("line", BlueprintTheme.LINE)
	var line_dim := _tcol("line_dim", BlueprintTheme.LINE_DIM)
	var outline_w := float(_tconst("outline_w", int(BlueprintTheme.OUTLINE_W)))

	# Background strip
	# Keep transparent so the HUD paper grain shows through.
	draw_rect(Rect2(Vector2.ZERO, size), Color(bg.r, bg.g, bg.b, 0.0), true)
	draw_rect(Rect2(Vector2.ZERO, size), line_dim, false, outline_w)

	# Town icon on the top-right (replaces old square + label mark).
	var town_rect := _town_icon_rect_local()
	if town_rect != Rect2():
		draw_texture_rect(TOWN_ICON, town_rect, true, Color(1, 1, 1, 1))

	# Entrance cap (above ground): 2x1 stamp just before the dungeon.
	var cap_world: Rect2 = entrance_cap_world_rect
	if _dungeon_view != null and is_instance_valid(_dungeon_view):
		cap_world = _dungeon_view.call("entrance_cap_world_rect") as Rect2

	if cap_world != Rect2():
		var inv2: Transform2D = get_global_transform().affine_inverse()
		var tl: Vector2 = inv2 * cap_world.position
		var br: Vector2 = inv2 * (cap_world.position + cap_world.size)
		var local_rect := Rect2(tl, br - tl)
		draw_rect(local_rect, line, false, 2.0)
		# Door mark in the middle
		var mid := local_rect.position + local_rect.size * 0.5
		draw_line(mid + Vector2(0, -10), mid + Vector2(0, 10), line, 2.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var p_local := get_local_mouse_position()
			var r := _town_icon_rect_local()
			if r != Rect2() and r.has_point(p_local):
				town_icon_clicked.emit()
				accept_event()
