extends RefCounted

# Resolves item icons and renders fallback glyphs (cached).

var _glyph_icons: Dictionary = {}


func get_item_icon(item_id: String) -> Texture2D:
	var r: Resource = ItemDB.get_any_item(item_id)
	if r is TrapItem:
		var tex := (r as TrapItem).icon
		return tex if tex != null else get_trap_glyph(item_id)
	if r is MonsterItem:
		return (r as MonsterItem).icon
	if r is TreasureItem:
		return (r as TreasureItem).icon
	if r is BossUpgradeItem:
		return (r as BossUpgradeItem).icon
	return null


func get_trap_glyph(item_id: String) -> Texture2D:
	match String(item_id):
		"spike_trap":
			return _get_glyph_icon("item:spike_trap")
		"floor_pit":
			return _get_glyph_icon("item:floor_pit")
		"teleport_trap":
			return _get_glyph_icon("item:teleport_trap")
		"web_trap":
			return _get_glyph_icon("item:web_trap")
		"rearm_trap":
			return _get_glyph_icon("item:rearm_trap")
		_:
			return _get_glyph_icon("item:trap")


func _get_glyph_icon(key: String) -> Texture2D:
	if _glyph_icons.has(key):
		return _glyph_icons[key] as Texture2D
	var tex := _render_glyph_icon(key, 24)
	_glyph_icons[key] = tex
	return tex


func _render_glyph_icon(key: String, sz: int) -> Texture2D:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var ink := ThemePalette.color("HUD", "ink", Color(0.18, 0.13, 0.08, 0.95))
	var dim := ThemePalette.color("HUD", "ink_dim", Color(0.18, 0.13, 0.08, 0.45))

	var c := Vector2(sz * 0.5, sz * 0.5)
	var s := float(sz) * 0.35
	var w := 2

	match String(key):
		"item:spike_trap":
			_img_draw_line(img, c + Vector2(-s, -s), c + Vector2(s, s), ink, w)
			_img_draw_line(img, c + Vector2(-s, s), c + Vector2(s, -s), ink, w)
			_img_draw_line(img, c + Vector2(0, -s), c + Vector2(0, -s * 0.35), dim, 1)
			_img_draw_line(img, c + Vector2(0, s), c + Vector2(0, s * 0.35), dim, 1)
		"item:floor_pit":
			var r := Rect2(c - Vector2(s * 0.9, s * 0.9), Vector2(s * 1.8, s * 1.8))
			_img_draw_rect_outline(img, r, ink, w)
			_img_draw_disc(img, c, int(round(s * 0.45)), dim)
		"item:teleport_trap":
			_img_draw_line(img, c + Vector2(-s * 0.9, 0), c + Vector2(s * 0.9, 0), ink, w)
			_img_draw_line(img, c + Vector2(s * 0.9, 0), c + Vector2(s * 0.35, -s * 0.45), ink, w)
			_img_draw_line(img, c + Vector2(s * 0.9, 0), c + Vector2(s * 0.35, s * 0.45), ink, w)
		"item:web_trap":
			for i in range(6):
				var ang := TAU * float(i) / 6.0
				var p := Vector2(cos(ang), sin(ang)) * (s * 0.9)
				_img_draw_line(img, c, c + p, ink, 1)
			_img_draw_disc(img, c, 2, ink)
		"item:rearm_trap":
			_img_draw_circle_outline(img, c, s * 0.85, ink, 1, 22)
			_img_draw_line(img, c + Vector2(0, -s * 0.85), c + Vector2(s * 0.35, -s * 0.55), ink, 1)
			_img_draw_line(img, c + Vector2(0, -s * 0.85), c + Vector2(-s * 0.15, -s * 0.35), ink, 1)
		"item:trap":
			_img_draw_line(img, c + Vector2(-s, -s), c + Vector2(s, s), ink, w)
			_img_draw_line(img, c + Vector2(-s, s), c + Vector2(s, -s), ink, w)
		_:
			_img_draw_disc(img, c, 2, ink)

	return ImageTexture.create_from_image(img)


func _img_plot(img: Image, x: int, y: int, col: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	img.set_pixel(x, y, col)


func _img_draw_disc(img: Image, center: Vector2, r: int, col: Color) -> void:
	var cx := int(round(center.x))
	var cy := int(round(center.y))
	var rr := r * r
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if x * x + y * y <= rr:
				_img_plot(img, cx + x, cy + y, col)


func _img_draw_line(img: Image, a: Vector2, b: Vector2, col: Color, width: int) -> void:
	var dx := b.x - a.x
	var dy := b.y - a.y
	var steps := int(max(absf(dx), absf(dy)))
	if steps <= 0:
		_img_draw_disc(img, a, max(1, int(ceil(float(width) * 0.5))), col)
		return
	var r: int = max(1, int(ceil(float(width) * 0.5)))
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var p := a.lerp(b, t)
		_img_draw_disc(img, p, r, col)


func _img_draw_rect_outline(img: Image, rect: Rect2, col: Color, width: int) -> void:
	var tl := rect.position
	var tr_p := rect.position + Vector2(rect.size.x, 0)
	var bl := rect.position + Vector2(0, rect.size.y)
	var br := rect.position + rect.size
	_img_draw_line(img, tl, tr_p, col, width)
	_img_draw_line(img, tr_p, br, col, width)
	_img_draw_line(img, br, bl, col, width)
	_img_draw_line(img, bl, tl, col, width)


func _img_draw_circle_outline(img: Image, center: Vector2, radius: float, col: Color, width: int, segments: int) -> void:
	var r: int = max(1, int(round(radius)))
	var prev := center + Vector2(r, 0)
	for i in range(1, segments + 1):
		var ang := TAU * float(i) / float(segments)
		var p := center + Vector2(cos(ang) * float(r), sin(ang) * float(r))
		_img_draw_line(img, prev, p, col, width)
		prev = p

