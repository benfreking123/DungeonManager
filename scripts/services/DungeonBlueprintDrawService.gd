extends RefCounted

# Drawing helpers for DungeonView blueprint rendering and previews.

var _view: Control
var _icons: RefCounted

func _init(view: Control, icons: RefCounted) -> void:
	_view = view
	_icons = icons


func draw_grid() -> void:
	var gw := int(_view.call("_grid_w"))
	var gh := int(_view.call("_grid_h"))
	var px := int(_view.call("_cell_px"))
	var w := gw * px
	var h := gh * px

	var grid_w := float(_tconst("grid_w", int(BlueprintTheme.GRID_W)))
	# Paper background
	if _view.PAPER_BG_TEX != null:
		_view.draw_texture_rect(_view.PAPER_BG_TEX, Rect2(Vector2.ZERO, Vector2(w, h)), false, Color(1, 1, 1, 0.92))

	# Grid lines
	for x in range(gw + 1):
		var lx := x * px
		var is_major: bool = (x % _view.MAJOR_EVERY == 0)
		var col := _grid_col(is_major)
		if is_major:
			var w_major := maxf(1.0, grid_w * (0.95 + _hash01(x) * 0.10))
			_draw_noisy_line(Vector2(lx, 0), Vector2(lx, h), col, w_major, x, 0.35, 26.0)
		else:
			var w_minor := maxf(1.0, grid_w * (0.80 + _hash01(x) * 0.60))
			_draw_noisy_line(Vector2(lx, 0), Vector2(lx, h), col, w_minor, x, 1.25, 18.0)

	for y in range(gh + 1):
		var ly := y * px
		var is_major_y: bool = (y % _view.MAJOR_EVERY == 0)
		var coly := _grid_col(is_major_y)
		if is_major_y:
			var w_major_y := maxf(1.0, grid_w * (0.95 + _hash01(y + 777) * 0.10))
			_draw_noisy_line(Vector2(0, ly), Vector2(w, ly), coly, w_major_y, y + 1000, 0.35, 26.0)
		else:
			var w_minor_y := maxf(1.0, grid_w * (0.80 + _hash01(y + 10000) * 0.60))
			_draw_noisy_line(Vector2(0, ly), Vector2(w, ly), coly, w_minor_y, y + 2000, 1.25, 18.0)

	# Outline playable area
	_view.draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), _tcol("outline", BlueprintTheme.LINE), false, float(_tconst("outline_w", int(BlueprintTheme.OUTLINE_W))))


func draw_room(room: Dictionary) -> void:
	var pos: Vector2i = room.get("pos", Vector2i.ZERO)
	var size: Vector2i = room.get("size", Vector2i.ONE)
	var known: bool = room.get("known", true)
	var px := float(_view.call("_cell_px"))
	var rect := Rect2(Vector2(pos.x, pos.y) * px, Vector2(size.x, size.y) * px)

	var outline_col := _tcol("outline", BlueprintTheme.LINE) if known else _tcol("outline_dim", BlueprintTheme.LINE_DIM)
	_view.draw_rect(rect, outline_col, false, float(_tconst("room_outline_w", int(_view.ROOM_OUTLINE_W))))

	var center := rect.position + rect.size * 0.5
	var kind: String = String(room.get("kind", "hall"))
	var show_details := known
	var display_kind := kind if show_details else "hall"
	var center_icon: Texture2D = null
	if show_details and (kind == "trap" or kind == "monster" or kind == "treasure"):
		var slots0: Array = room.get("slots", [])
		if not slots0.is_empty():
			var slot0: Dictionary = slots0[0]
			var installed0 := String(slot0.get("installed_item_id", ""))
			if installed0 != "":
				if kind != "trap" or _view.call("_is_trap_slot_ready", int(room.get("id", 0)), 0, installed0):
					center_icon = _icons.get_item_icon(installed0)
	if center_icon != null:
		_draw_room_center_icon(center, center_icon)
	else:
		_draw_icon_stamp(center, display_kind, known)

	# Slot markers
	var slots: Array = room.get("slots", [])
	if show_details and not slots.is_empty():
		var slot_outline_w := float(_tconst("slot_outline_w", 2))
		var slot_treasure := _tcol("slot_outline_treasure", Color(0.95, 0.78, 0.22, 0.95))
		var slot_trap := _tcol("slot_outline_trap", Color(0.25, 0.58, 1.0, 0.95))
		var slot_monster := _tcol("slot_outline_monster", Color(0.25, 0.9, 0.5, 0.95))
		var slot_universal := _tcol("slot_outline_universal", Color(1.0, 1.0, 1.0, 0.95))
		for i in range(slots.size()):
			var slot: Dictionary = slots[i]
			var slot_rect: Rect2 = _view.call("_slot_rect_local", rect, i) as Rect2
			var installed := String(slot.get("installed_item_id", ""))
			var sk := String(slot.get("slot_kind", ""))
			var base_col := outline_col
			if sk == "treasure":
				base_col = slot_treasure
			elif sk == "trap":
				base_col = slot_trap
			elif sk == "monster":
				base_col = slot_monster
			elif sk == "universal":
				base_col = slot_universal
			var col := base_col if installed != "" else Color(base_col.r, base_col.g, base_col.b, base_col.a * 0.55)
			_view.draw_rect(slot_rect, col, false, float(slot_outline_w))
			if installed != "":
				var show_icon := true
				if sk == "trap":
					show_icon = _view.call("_is_trap_slot_ready", int(room.get("id", 0)), i, installed)
				if show_icon:
					var icon_tex: Texture2D = _icons.get_item_icon(installed)
					if icon_tex != null:
						_view.draw_texture_rect(icon_tex, slot_rect.grow(-1.0), true)
					else:
						_view.draw_rect(slot_rect.grow(-3.0), col, true)

	# Hover slot highlight (optional): relies on view's cached hover state
	if int(room.get("id", 0)) == _view._hover_slot_room_id and _view._hover_slot_idx != -1:
		var slot_rect2: Rect2 = _view.call("_slot_rect_local", rect, _view._hover_slot_idx) as Rect2
		_view.draw_rect(slot_rect2.grow(2.0), _tcol("accent_warn", BlueprintTheme.ACCENT_WARN), false, float(_tconst("slot_outline_w", 2)))


func draw_preview(res: Dictionary, hover_cell: Vector2i) -> void:
	var px := float(_view.call("_cell_px"))
	var accent_ok := _tcol("accent_ok", BlueprintTheme.ACCENT_OK)
	var accent_bad := _tcol("accent_bad", BlueprintTheme.ACCENT_BAD)
	var size: Vector2i = res.get("size", Vector2i.ONE)
	var ok: bool = res.get("ok", false)
	var col := accent_ok if ok else accent_bad
	var cells: Array = res.get("cells", [])
	var rect := Rect2(Vector2(hover_cell.x, hover_cell.y) * px, Vector2(size.x, size.y) * px)
	if cells is Array and not (cells as Array).is_empty():
		for c in (cells as Array):
			var cc := c as Vector2i
			var r := Rect2(Vector2(cc.x, cc.y) * px, Vector2.ONE * px)
			if ok:
				_view.draw_rect(r, col, false, 2.0)
			else:
				_draw_dashed_rect(r, col, 2.0)
				_draw_hatched_rect(r, col)
	else:
		if ok:
			_view.draw_rect(rect, col, false, 2.0)
		else:
			_draw_dashed_rect(rect, col, 2.0)
			_draw_hatched_rect(rect, col)


func _grid_col(is_major: bool) -> Color:
	if is_major:
		return _tcol("grid_major", BlueprintTheme.LINE_DIM)
	return _tcol("grid_minor", BlueprintTheme.LINE_FAINT)


func _tcol(name: String, fallback: Color) -> Color:
	return _view.get_theme_color(name, _view.THEME_TYPE) if _view.has_theme_color(name, _view.THEME_TYPE) else fallback


func _tconst(name: String, fallback: int) -> int:
	return _view.get_theme_constant(name, _view.THEME_TYPE) if _view.has_theme_constant(name, _view.THEME_TYPE) else fallback


func _hash01(i: int) -> float:
	return float(((i * 1103515245) ^ 0x9E3779B9) & 0xFFFF) / 65535.0


func _hash_signed01(i: int) -> float:
	return (_hash01(i) * 2.0) - 1.0


func _hash01_pair(a: int, b: int) -> float:
	return float((((a * 1103515245) ^ (b * 2654435761) ^ 0x9E3779B9) & 0xFFFF)) / 65535.0


func _draw_noisy_line(a: Vector2, b: Vector2, col: Color, base_w: float, seed: int, amp_px: float, seg_px: float) -> void:
	var dir := b - a
	var length := dir.length()
	if length <= 0.001:
		return
	dir /= length
	var perp := Vector2(-dir.y, dir.x)
	var seg_len := maxf(4.0, seg_px)
	var segments := int(ceil(length / seg_len))
	for i in range(segments):
		var t0 := float(i) / float(segments)
		var t1 := float(i + 1) / float(segments)
		var p0 := a + dir * (length * t0)
		var p1 := a + dir * (length * t1)
		var off_amt := _hash_signed01(seed * 131 + i * 17) * amp_px
		var w_mult := 0.85 + _hash01_pair(seed, i) * 0.4
		var w := maxf(1.0, base_w * w_mult)
		var off := perp * off_amt
		_view.draw_line(p0 + off, p1 + off, col, w)


func _clip_code(p: Vector2, xmin: float, xmax: float, ymin: float, ymax: float) -> int:
	var c := 0
	if p.x < xmin:
		c |= 1
	elif p.x > xmax:
		c |= 2
	if p.y < ymin:
		c |= 4
	elif p.y > ymax:
		c |= 8
	return c


func _clip_segment_to_rect(a: Vector2, b: Vector2, rect: Rect2) -> PackedVector2Array:
	var xmin := rect.position.x
	var xmax := rect.position.x + rect.size.x
	var ymin := rect.position.y
	var ymax := rect.position.y + rect.size.y
	var p0 := a
	var p1 := b
	var out0 := _clip_code(p0, xmin, xmax, ymin, ymax)
	var out1 := _clip_code(p1, xmin, xmax, ymin, ymax)
	while true:
		if (out0 | out1) == 0:
			return PackedVector2Array([p0, p1])
		if (out0 & out1) != 0:
			return PackedVector2Array()
		var out := out0 if out0 != 0 else out1
		var x := 0.0
		var y := 0.0
		if (out & 4) != 0:
			x = p0.x + (p1.x - p0.x) * (ymin - p0.y) / (p1.y - p0.y)
			y = ymin
		elif (out & 8) != 0:
			x = p0.x + (p1.x - p0.x) * (ymax - p0.y) / (p1.y - p0.y)
			y = ymax
		elif (out & 2) != 0:
			y = p0.y + (p1.y - p0.y) * (xmax - p0.x) / (p1.x - p0.x)
			x = xmax
		elif (out & 1) != 0:
			y = p0.y + (p1.y - p0.y) * (xmin - p0.x) / (p1.x - p0.x)
			x = xmin
		if out == out0:
			p0 = Vector2(x, y)
			out0 = _clip_code(p0, xmin, xmax, ymin, ymax)
		else:
			p1 = Vector2(x, y)
			out1 = _clip_code(p1, xmin, xmax, ymin, ymax)
	return PackedVector2Array()


func _draw_dashed_line(a: Vector2, b: Vector2, col: Color, width: float, dash_len: float, gap_len: float) -> void:
	var dir := b - a
	var seg_len := dir.length()
	if seg_len <= 0.001:
		return
	dir /= seg_len
	var t := 0.0
	while t < seg_len:
		var seg_a := a + dir * t
		var seg_b := a + dir * minf(t + dash_len, seg_len)
		_view.draw_line(seg_a, seg_b, col, width)
		t += dash_len + gap_len


func _draw_dashed_rect(rect: Rect2, col: Color, width: float) -> void:
	var dash := 8.0
	var gap := 5.0
	var tl := rect.position
	var tr_p := rect.position + Vector2(rect.size.x, 0)
	var bl := rect.position + Vector2(0, rect.size.y)
	var br := rect.position + rect.size
	_draw_dashed_line(tl, tr_p, col, width, dash, gap)
	_draw_dashed_line(tr_p, br, col, width, dash, gap)
	_draw_dashed_line(br, bl, col, width, dash, gap)
	_draw_dashed_line(bl, tl, col, width, dash, gap)


func _draw_hatched_rect(rect: Rect2, col: Color) -> void:
	var hatch_col := Color(col.r, col.g, col.b, col.a * 0.18)
	var spacing := 10.0
	for x in range(int(-rect.size.y), int(rect.size.x) + 1, int(spacing)):
		var p0 := rect.position + Vector2(float(x), rect.size.y)
		var p1 := rect.position + Vector2(float(x) + rect.size.y, 0.0)
		var clipped := _clip_segment_to_rect(p0, p1, rect)
		if clipped.size() == 2:
			_view.draw_line(clipped[0], clipped[1], hatch_col, 1.0)


func _draw_room_center_icon(center: Vector2, tex: Texture2D) -> void:
	var px := float(_view.ICON_BASE_CELL_PX)
	var s := clampf(px * 1.05, 18.0, 36.0)
	_view.draw_texture_rect(tex, Rect2(center - Vector2(s * 0.5, s * 0.5), Vector2(s, s)), true)


func _draw_icon_stamp(center: Vector2, kind: String, known: bool) -> void:
	var col := _tcol("outline", BlueprintTheme.LINE) if known else _tcol("outline_dim", BlueprintTheme.LINE_DIM)
	var s := float(_view.ICON_BASE_CELL_PX) * 0.35
	match kind:
		"entrance":
			_view.draw_line(center + Vector2(0, -s), center + Vector2(0, s), col, float(_tconst("icon_w", int(_view.ICON_W))))
			_view.draw_line(center + Vector2(0, s), center + Vector2(-s * 0.6, s * 0.4), col, float(_tconst("icon_w", int(_view.ICON_W))))
			_view.draw_line(center + Vector2(0, s), center + Vector2(s * 0.6, s * 0.4), col, float(_tconst("icon_w", int(_view.ICON_W))))
		"boss":
			var iw := float(_tconst("icon_w", int(_view.ICON_W)))
			_view.draw_line(center + Vector2(-s, s * 0.6), center + Vector2(-s * 0.6, -s * 0.4), col, iw)
			_view.draw_line(center + Vector2(-s * 0.6, -s * 0.4), center + Vector2(0, s * 0.2), col, iw)
			_view.draw_line(center + Vector2(0, s * 0.2), center + Vector2(s * 0.6, -s * 0.4), col, iw)
			_view.draw_line(center + Vector2(s * 0.6, -s * 0.4), center + Vector2(s, s * 0.6), col, iw)
			_view.draw_line(center + Vector2(-s, s * 0.6), center + Vector2(s, s * 0.6), col, iw)
		"treasure":
			var iw2 := float(_tconst("icon_w", int(_view.ICON_W)))
			_view.draw_rect(Rect2(center - Vector2(s, s * 0.6), Vector2(s * 2.0, s * 1.2)), col, false, iw2)
			_view.draw_line(center + Vector2(-s, 0), center + Vector2(s, 0), col, iw2)
		"monster":
			_view.draw_arc(center, s * 0.8, 0, TAU, 20, col, float(_tconst("icon_w", int(_view.ICON_W))))
			_view.draw_circle(center + Vector2(-s * 0.3, -s * 0.1), s * 0.12, col)
			_view.draw_circle(center + Vector2(s * 0.3, -s * 0.1), s * 0.12, col)
		"trap":
			_view.draw_line(center + Vector2(-s, -s), center + Vector2(s, s), col, float(_tconst("icon_w", int(_view.ICON_W))))
			_view.draw_line(center + Vector2(-s, s), center + Vector2(s, -s), col, float(_tconst("icon_w", int(_view.ICON_W))))
		_:
			_view.draw_circle(center, s * 0.12, col)

