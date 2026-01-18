extends PanelContainer

@onready var _title: Label = $VBox/Title
@onready var _body: RichTextLabel = $VBox/Body

var _ignore_outside_until_ms: int = 0


func _ready() -> void:
	visible = false


func open_at(screen_pos: Vector2, title: String, bbcode: String) -> void:
	_title.text = String(title)
	_body.text = String(bbcode)
	visible = false
	await get_tree().process_frame
	var want := get_combined_minimum_size()
	size = want
	_place_near_screen_pos(screen_pos)
	_ignore_outside_until_ms = int(Time.get_ticks_msec()) + 50
	visible = true


func close() -> void:
	visible = false


func can_close_from_outside_click() -> bool:
	return int(Time.get_ticks_msec()) >= _ignore_outside_until_ms


func _place_near_screen_pos(screen_pos: Vector2) -> void:
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

