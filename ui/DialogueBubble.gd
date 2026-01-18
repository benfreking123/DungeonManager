extends Node2D

# World-attached speech bubble drawn via _draw() (avoids Control sizing issues under Node2D).

const MAX_W := 190.0
const PAD_X := 6.0
const PAD_Y := 4.0
const FONT_SIZE := 12
const LIFE_S := 1.35

var _text: String = ""
var _lines: Array[String] = []
var _box_size := Vector2(80, 24)
var _font_cache: Font = null


func show_text(t: String) -> void:
	_text = String(t)
	position = Vector2(0, -26)
	modulate.a = 1.0
	_build_layout()
	queue_redraw()

	var tw := create_tween()
	tw.tween_interval(max(0.1, LIFE_S - 0.35))
	tw.tween_property(self, "modulate:a", 0.0, 0.35)
	tw.finished.connect(func():
		if is_instance_valid(self):
			queue_free()
	)


func _font() -> Font:
	if _font_cache != null:
		return _font_cache
	var f: Font = ThemeDB.fallback_font
	if f == null:
		# Last-resort: system default font.
		f = SystemFont.new()
	_font_cache = f
	return _font_cache


func _build_layout() -> void:
	var font := _font()
	_lines = _wrap_text(font, _text, MAX_W)
	if _lines.is_empty():
		_lines = [_text]

	var max_line_w := 0.0
	for ln in _lines:
		var sz := font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
		max_line_w = maxf(max_line_w, float(sz.x))
	var line_h := float(font.get_height(FONT_SIZE))
	var total_h := line_h * float(_lines.size())
	_box_size = Vector2(
		clampf(max_line_w + PAD_X * 2.0, 60.0, MAX_W + PAD_X * 2.0),
		clampf(total_h + PAD_Y * 2.0, 18.0, 90.0)
	)


func _wrap_text(font: Font, text: String, max_w: float) -> Array[String]:
	# Basic word-wrap for one-sentence bubbles.
	var words := text.split(" ", false)
	if words.is_empty():
		return []
	var out: Array[String] = []
	var cur := ""
	for w in words:
		var next := w if cur == "" else (cur + " " + w)
		var sz := font.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
		if float(sz.x) <= max_w or cur == "":
			cur = next
		else:
			out.append(cur)
			cur = w
	if cur != "":
		out.append(cur)
	return out


func _draw() -> void:
	if _text == "":
		return
	var font := _font()

	var bg := Color(0, 0, 0, 0.65)
	var border := Color(1, 1, 1, 0.55)
	var text_col := Color(1, 1, 1, 0.95)

	var rect := Rect2(Vector2(-_box_size.x * 0.5, -_box_size.y), _box_size)
	draw_rect(rect, bg, true)
	draw_rect(rect, border, false, 1.0)

	var x0 := rect.position.x + PAD_X
	var y0 := rect.position.y + PAD_Y
	var line_h := float(font.get_height(FONT_SIZE))
	for i in range(_lines.size()):
		draw_string(font, Vector2(x0, y0 + line_h * float(i) + line_h), _lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, text_col)

