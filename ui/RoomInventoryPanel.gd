extends PanelContainer

@onready var _room_db: Node = get_node_or_null("/root/RoomDB")

@onready var _room_grid: Container = $VBox/Pages/Room/RoomGrid
@onready var _monster_grid: Container = $VBox/Pages/Monsters/MonsterGrid
@onready var _trap_grid: Container = $VBox/Pages/Traps/TrapGrid
@onready var _boss_grid: Container = $VBox/Pages/Boss/BossGrid
@onready var _treasure_grid: Container = $VBox/Pages/Treasure/TreasureGrid

@onready var _page_room: Control = $VBox/Pages/Room
@onready var _page_monsters: Control = $VBox/Pages/Monsters
@onready var _page_traps: Control = $VBox/Pages/Traps
@onready var _page_boss: Control = $VBox/Pages/Boss
@onready var _page_treasure: Control = $VBox/Pages/Treasure

@onready var _tab_room: Button = $VBox/TabButtons/Row1/RoomTab
@onready var _tab_monsters: Button = $VBox/TabButtons/Row2/MonstersTab
@onready var _tab_traps: Button = $VBox/TabButtons/Row1/TrapsTab
@onready var _tab_boss: Button = $VBox/TabButtons/Row1/BossTab
@onready var _tab_treasure: Button = $VBox/TabButtons/Row2/TreasureTab

var _room_btn_scene: PackedScene = preload("res://ui/RoomInventoryItemButton.tscn")
var _item_btn_scene: PackedScene = preload("res://ui/InventoryItemButton.tscn")

var _glyph_icons: Dictionary = {} # String -> Texture2D

var _tab_lock: String = "" # "" = unlocked, otherwise page id (e.g. "treasure")


func _ready() -> void:
	_refresh()
	RoomInventory.inventory_changed.connect(_refresh)
	PlayerInventory.inventory_changed.connect(_refresh)
	_setup_tabs()


func _setup_tabs() -> void:
	var g := ButtonGroup.new()
	_tab_room.button_group = g
	_tab_monsters.button_group = g
	_tab_traps.button_group = g
	_tab_boss.button_group = g
	_tab_treasure.button_group = g

	_tab_room.pressed.connect(func(): _show_page("room"))
	_tab_monsters.pressed.connect(func(): _show_page("monsters"))
	_tab_traps.pressed.connect(func(): _show_page("traps"))
	_tab_boss.pressed.connect(func(): _show_page("boss"))
	_tab_treasure.pressed.connect(func(): _show_page("treasure"))

	_show_page("room")


func _show_page(which: String) -> void:
	if _tab_lock != "" and which != _tab_lock:
		return
	_page_room.visible = (which == "room")
	_page_monsters.visible = (which == "monsters")
	_page_traps.visible = (which == "traps")
	_page_boss.visible = (which == "boss")
	_page_treasure.visible = (which == "treasure")


func lock_tabs_to(which: String) -> void:
	_tab_lock = which
	_show_page(which)

	# Keep the UI obvious: disable other tabs while locked.
	var lock_room := (which != "room")
	var lock_mon := (which != "monsters")
	var lock_traps := (which != "traps")
	var lock_boss := (which != "boss")
	var lock_treasure := (which != "treasure")
	if _tab_room != null:
		_tab_room.disabled = lock_room
	if _tab_monsters != null:
		_tab_monsters.disabled = lock_mon
	if _tab_traps != null:
		_tab_traps.disabled = lock_traps
	if _tab_boss != null:
		_tab_boss.disabled = lock_boss
	if _tab_treasure != null:
		_tab_treasure.disabled = lock_treasure

	# Ensure the correct button appears selected when locked.
	match which:
		"room":
			if _tab_room != null: _tab_room.button_pressed = true
		"monsters":
			if _tab_monsters != null: _tab_monsters.button_pressed = true
		"traps":
			if _tab_traps != null: _tab_traps.button_pressed = true
		"boss":
			if _tab_boss != null: _tab_boss.button_pressed = true
		"treasure":
			if _tab_treasure != null: _tab_treasure.button_pressed = true


func unlock_tabs() -> void:
	_tab_lock = ""
	if _tab_room != null:
		_tab_room.disabled = false
	if _tab_monsters != null:
		_tab_monsters.disabled = false
	if _tab_traps != null:
		_tab_traps.disabled = false
	if _tab_boss != null:
		_tab_boss.disabled = false
	if _tab_treasure != null:
		_tab_treasure.disabled = false


func select_tab(which: String) -> void:
	# Select a tab/page without locking (player can still change tabs).
	unlock_tabs()
	_show_page(which)
	# Ensure the correct button appears selected.
	match which:
		"room":
			if _tab_room != null: _tab_room.button_pressed = true
		"monsters":
			if _tab_monsters != null: _tab_monsters.button_pressed = true
		"traps":
			if _tab_traps != null: _tab_traps.button_pressed = true
		"boss":
			if _tab_boss != null: _tab_boss.button_pressed = true
		"treasure":
			if _tab_treasure != null: _tab_treasure.button_pressed = true


func get_treasure_collect_target_global_pos() -> Vector2:
	# Used for end-of-day loot collection animation.
	# Aim for the Treasure tab button center (stable even if Treasure page isn't visible).
	if _tab_treasure != null:
		var r := _tab_treasure.get_global_rect()
		return r.position + r.size * 0.5
	return global_position


func get_collect_target_global_pos(tab_id: String) -> Vector2:
	# Used by the shop purchase animation: fly an icon into the relevant inventory tab.
	match String(tab_id):
		"room":
			if _tab_room != null:
				var r := _tab_room.get_global_rect()
				return r.position + r.size * 0.5
		"monsters":
			if _tab_monsters != null:
				var r := _tab_monsters.get_global_rect()
				return r.position + r.size * 0.5
		"traps":
			if _tab_traps != null:
				var r := _tab_traps.get_global_rect()
				return r.position + r.size * 0.5
		"boss":
			if _tab_boss != null:
				var r := _tab_boss.get_global_rect()
				return r.position + r.size * 0.5
		"treasure":
			return get_treasure_collect_target_global_pos()
		_:
			return get_treasure_collect_target_global_pos()
	return get_treasure_collect_target_global_pos()


func _refresh() -> void:
	_clear_children(_room_grid)
	_clear_children(_monster_grid)
	_clear_children(_trap_grid)
	_clear_children(_boss_grid)
	_clear_children(_treasure_grid)

	if _room_db == null:
		return

	_refresh_rooms()
	_refresh_items()


func _clear_children(parent: Node) -> void:
	for c in parent.get_children():
		c.queue_free()


func _refresh_rooms() -> void:
	var types: Array[Dictionary] = _room_db.list_room_types()
	types.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("label", "")) < str(b.get("label", ""))
	)

	for t in types:
		var type_id: String = t.get("id", "")
		if type_id == "entrance":
			continue
		var count: int = RoomInventory.get_count(type_id)
		var label: String = t.get("label", type_id)
		var kind: String = String(t.get("kind", type_id))
		var icon := _get_room_glyph_icon(kind)
		var btn := _room_btn_scene.instantiate()
		_room_grid.add_child(btn)
		btn.call("set_room", type_id, label, count, icon)


func _refresh_items() -> void:
	_refresh_item_group(_monster_grid, ItemDB.monsters)
	_refresh_item_group(_trap_grid, ItemDB.traps)
	_refresh_item_group(_treasure_grid, ItemDB.treasures)
	_refresh_boss()


func _refresh_boss() -> void:
	# Boss is intentionally excluded from Monster tab; show it here instead.
	var item_id := "boss"
	var res: Resource = ItemDB.get_any_item(item_id)
	if res == null:
		return
	var count: int = PlayerInventory.get_count(item_id)
	var display_name := _resource_display_name(res, item_id)
	var icon := _resource_icon(res, item_id)
	var btn := _item_btn_scene.instantiate()
	_boss_grid.add_child(btn)
	btn.call("set_item", item_id, display_name, icon, count)

	# Boss upgrades also live in the Boss tab.
	_refresh_item_group(_boss_grid, ItemDB.boss_upgrades)


func _refresh_item_group(target_grid: Container, dict: Dictionary) -> void:
	var ids: Array = dict.keys()
	ids.sort()

	# Prefer display-name sort when resources are available.
	ids.sort_custom(func(a_id: Variant, b_id: Variant) -> bool:
		var a_res: Resource = ItemDB.get_any_item(str(a_id))
		var b_res: Resource = ItemDB.get_any_item(str(b_id))
		var a_name := _resource_display_name(a_res, str(a_id))
		var b_name := _resource_display_name(b_res, str(b_id))
		return a_name < b_name
	)

	for v_id in ids:
		var item_id := str(v_id)
		if target_grid == _monster_grid and item_id == "boss":
			continue
		var res: Resource = ItemDB.get_any_item(item_id)
		var count: int = PlayerInventory.get_count(item_id)
		var display_name := _resource_display_name(res, item_id)
		var icon := _resource_icon(res, item_id)

		var btn := _item_btn_scene.instantiate()
		target_grid.add_child(btn)
		btn.call("set_item", item_id, display_name, icon, count)


func _resource_display_name(res: Resource, fallback_id: String) -> String:
	if res is TrapItem:
		return (res as TrapItem).display_name
	if res is MonsterItem:
		return (res as MonsterItem).display_name
	if res is TreasureItem:
		return (res as TreasureItem).display_name
	if res is BossUpgradeItem:
		return (res as BossUpgradeItem).display_name
	return fallback_id


func _resource_icon(res: Resource, id: String) -> Texture2D:
	if res is TrapItem:
		var tex := (res as TrapItem).icon
		return tex if tex != null else _get_trap_glyph_icon(id)
	if res is MonsterItem:
		var tex := (res as MonsterItem).icon
		return tex if tex != null else _get_monster_glyph_icon(id)
	if res is TreasureItem:
		return (res as TreasureItem).icon
	if res is BossUpgradeItem:
		return (res as BossUpgradeItem).icon
	return _get_generic_item_glyph_icon(id)


func _get_room_glyph_icon(kind: String) -> Texture2D:
	# Match what the grid draws when the room has no installed item icon.
	return _get_glyph_icon("room:" + kind)


func _get_trap_glyph_icon(item_id: String) -> Texture2D:
	# We don't currently have atlas icons for traps; use blueprint-style glyphs instead.
	# Keep these distinct so SpikeTrap/FloorPit aren't identical.
	match item_id:
		"spike_trap":
			return _get_glyph_icon("item:spike_trap")
		"floor_pit":
			return _get_glyph_icon("item:floor_pit")
		_:
			return _get_glyph_icon("item:trap")


func _get_monster_glyph_icon(_item_id: String) -> Texture2D:
	# Monster items should generally have atlas icons. If missing, fall back to the monster glyph.
	return _get_glyph_icon("room:monster")


func _get_generic_item_glyph_icon(_id: String) -> Texture2D:
	return _get_glyph_icon("item:generic")


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

	match key:
		"room:entrance":
			# Down arrow
			_img_draw_line(img, c + Vector2(0, -s), c + Vector2(0, s), ink, w)
			_img_draw_line(img, c + Vector2(0, s), c + Vector2(-s * 0.6, s * 0.4), ink, w)
			_img_draw_line(img, c + Vector2(0, s), c + Vector2(s * 0.6, s * 0.4), ink, w)
		"room:boss":
			# Crown-ish
			_img_draw_line(img, c + Vector2(-s, s * 0.6), c + Vector2(-s * 0.6, -s * 0.4), ink, w)
			_img_draw_line(img, c + Vector2(-s * 0.6, -s * 0.4), c + Vector2(0, s * 0.2), ink, w)
			_img_draw_line(img, c + Vector2(0, s * 0.2), c + Vector2(s * 0.6, -s * 0.4), ink, w)
			_img_draw_line(img, c + Vector2(s * 0.6, -s * 0.4), c + Vector2(s, s * 0.6), ink, w)
			_img_draw_line(img, c + Vector2(-s, s * 0.6), c + Vector2(s, s * 0.6), ink, w)
		"room:treasure":
			# Chest
			_img_draw_rect_outline(img, Rect2(c - Vector2(s, s * 0.6), Vector2(s * 2.0, s * 1.2)), ink, w)
			_img_draw_line(img, c + Vector2(-s, 0), c + Vector2(s, 0), ink, w)
		"room:monster":
			# Skull-ish: circle + eyes
			_img_draw_circle_outline(img, c, s * 0.8, ink, w, 24)
			_img_draw_disc(img, c + Vector2(-s * 0.3, -s * 0.1), int(round(s * 0.14)), ink)
			_img_draw_disc(img, c + Vector2(s * 0.3, -s * 0.1), int(round(s * 0.14)), ink)
		"room:trap":
			# X mark
			_img_draw_line(img, c + Vector2(-s, -s), c + Vector2(s, s), ink, w)
			_img_draw_line(img, c + Vector2(-s, s), c + Vector2(s, -s), ink, w)
		"room:hall":
			_img_draw_disc(img, c, 2, ink)
		"item:spike_trap":
			# Emphasized X with small "spikes"
			_img_draw_line(img, c + Vector2(-s, -s), c + Vector2(s, s), ink, w)
			_img_draw_line(img, c + Vector2(-s, s), c + Vector2(s, -s), ink, w)
			_img_draw_line(img, c + Vector2(0, -s), c + Vector2(0, -s * 0.35), dim, 1)
			_img_draw_line(img, c + Vector2(0, s), c + Vector2(0, s * 0.35), dim, 1)
		"item:floor_pit":
			# Pit: outlined square with a dark center
			var r := Rect2(c - Vector2(s * 0.9, s * 0.9), Vector2(s * 1.8, s * 1.8))
			_img_draw_rect_outline(img, r, ink, w)
			_img_draw_disc(img, c, int(round(s * 0.45)), dim)
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
