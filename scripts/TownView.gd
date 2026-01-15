extends Control

# Blueprint town strip. For MVP, this is mostly visual + provides spawn positions.

const TOWN_BOX_W := 220.0
const PAD := 12.0
const SHIFT_LEFT := 220.0

var _dungeon_view: Node = null

# Theme keys live in `ui/DungeonManagerTheme.tres` under `TownView/...`.
const THEME_TYPE := "TownView"

# Back-compat fallback (if dungeon view not set yet)
var entrance_world_pos: Vector2 = Vector2.ZERO
var entrance_cap_world_rect: Rect2 = Rect2()

func _ready() -> void:
	queue_redraw()


func _tcol(name: String, fallback: Color) -> Color:
	return get_theme_color(name, THEME_TYPE) if has_theme_color(name, THEME_TYPE) else fallback


func _tconst(name: String, fallback: int) -> int:
	return get_theme_constant(name, THEME_TYPE) if has_theme_constant(name, THEME_TYPE) else fallback


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
	# Spawn on the "ground" in the town strip, near the right side.
	var r := get_global_rect()
	return Vector2(r.position.x + r.size.x - PAD - 24.0 - SHIFT_LEFT, r.position.y + r.size.y - PAD - 10.0)


func _draw() -> void:
	var bg := _tcol("bg", BlueprintTheme.BG)
	var line := _tcol("line", BlueprintTheme.LINE)
	var line_dim := _tcol("line_dim", BlueprintTheme.LINE_DIM)
	var outline_w := float(_tconst("outline_w", int(BlueprintTheme.OUTLINE_W)))

	# Background strip
	draw_rect(Rect2(Vector2.ZERO, size), bg, true)
	draw_rect(Rect2(Vector2.ZERO, size), line_dim, false, outline_w)

	# Town box on the top-right
	var town_rect := Rect2(Vector2(size.x - TOWN_BOX_W - PAD - SHIFT_LEFT, PAD), Vector2(TOWN_BOX_W, size.y - PAD * 2.0))
	draw_rect(town_rect, Color(0, 0, 0, 0), false, 2.0) # intentionally transparent fill
	draw_rect(town_rect, line, false, 2.0)

	# Label-ish mark
	var c := town_rect.position + town_rect.size * 0.5
	draw_line(c + Vector2(-26, 0), c + Vector2(26, 0), line, 2.0)
	draw_line(c + Vector2(0, -10), c + Vector2(0, 10), line, 2.0)

	# Connection to entrance (surface travel line)
	var entrance_world: Vector2 = entrance_world_pos
	if _dungeon_view != null and is_instance_valid(_dungeon_view):
		entrance_world = _dungeon_view.call("entrance_surface_world_pos") as Vector2

	if entrance_world != Vector2.ZERO:
		var inv: Transform2D = get_global_transform().affine_inverse()
		var spawn: Vector2 = inv * get_spawn_world_pos()
		var e: Vector2 = inv * entrance_world
		draw_line(spawn, e, line_dim, 2.0)

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
