extends PanelContainer

@onready var _title: Label = $VBox/Top/Title
@onready var _close: Button = $VBox/Top/Close
@onready var _line1: Label = $VBox/Body/Line1
@onready var _line2: Label = $VBox/Body/Line2
@onready var _line3: Label = $VBox/Body/Line3
@onready var _party: Label = $VBox/Body/VBoxContainer/HBoxContainer/Party
@onready var _morality: Label = $VBox/Body/VBoxContainer/HBoxContainer/Morality
@onready var _traits: RichTextLabel = $VBox/Body/VBoxContainer/HBoxContainer2/Traits
@onready var _abilities: RichTextLabel = $VBox/Body/VBoxContainer/HBoxContainer2/Abilities
@onready var _goals: RichTextLabel = $VBox/Body/Goals

var _adv_id: int = 0
var _ignore_outside_until_ms: int = 0
var _last_open_screen_pos: Vector2 = Vector2.ZERO

@onready var _simulation: Node = get_node_or_null("/root/Simulation")

const POPUP_PADDING := Vector2(0, 0)


func _ready() -> void:
	visible = false
	if _close != null:
		_close.pressed.connect(close)


func open_at(adv_id: int, screen_pos: Vector2) -> void:
	_last_open_screen_pos = screen_pos
	_adv_id = int(adv_id)
	visible = false
	_refresh()
	await get_tree().process_frame
	# Size BEFORE showing to avoid visible snapping.
	var want := get_combined_minimum_size()
	size = want + POPUP_PADDING
	_place_near_screen_pos(screen_pos)
	_ignore_outside_until_ms = int(Time.get_ticks_msec()) + 80
	visible = true


func close() -> void:
	_adv_id = 0
	visible = false


func can_close_from_outside_click() -> bool:
	return int(Time.get_ticks_msec()) >= _ignore_outside_until_ms


func _refresh() -> void:
	_title.text = "Adventurer"
	_line1.text = ""
	_line2.text = ""
	_line3.text = ""
	if _party != null:
		_party.text = ""
	if _morality != null:
		_morality.text = ""
	if _traits != null:
		_traits.text = ""
	if _abilities != null:
		_abilities.text = ""
	_goals.text = ""

	if _simulation == null or not _simulation.has_method("get_adv_tooltip_data"):
		_line1.text = "(missing tooltip data)"
		return

	var data: Dictionary = _simulation.call("get_adv_tooltip_data", _adv_id) as Dictionary
	if data.is_empty():
		_line1.text = "(unknown adventurer)"
		return

	# Player-friendly lines.
	var class_id := String(data.get("class_id", ""))
	var party_id := int(data.get("party_id", 0))
	var party_size := int(data.get("party_size", 0))
	var hp := int(data.get("hp", 0))
	var hp_max := int(data.get("hp_max", 0))
	var dmg := int(data.get("attack_damage", 0))
	var moral_lbl := String(data.get("morality_label", ""))
	var name := String(data.get("name", ""))
	var epithet := String(data.get("epithet", ""))
	var origin := String(data.get("origin", ""))
	var bio := String(data.get("bio", ""))

	# Title prefers identity if present, else class.
	if name != "":
		_title.text = name + ((" " + epithet) if epithet != "" else "")
	else:
		_title.text = "%s" % (class_id if class_id != "" else "Adventurer")
	# Line 1: class and origin, or party fallback.
	if class_id != "" and origin != "":
		_line1.text = "%s from %s" % [class_id, origin]
	elif party_id != 0:
		_line1.text = "Party %d" % party_id
	_line2.text = "HP %d/%d   DMG %d" % [hp, hp_max, dmg]
	# Line 3: show bio/background if present; else fall back to morality.
	if bio != "":
		_line3.text = bio
	elif moral_lbl != "":
		_line3.text = "Morality: %s" % moral_lbl

	# Expanded fields (Party/Morality/Traits/Ability)
	if _party != null and party_id != 0:
		_party.text = ("Party %d (%d)" % [party_id, party_size]) if party_size > 0 else ("Party %d" % party_id)
	if _morality != null and moral_lbl != "":
		_morality.text = "Morality: %s" % moral_lbl

	if _traits != null:
		var tpretty: Array = data.get("traits_pretty", []) as Array
		var tids: Array = data.get("traits", []) as Array
		var lines_t: Array[String] = []
		if not tpretty.is_empty():
			for x in tpretty:
				var s := String(x)
				if s != "":
					lines_t.append("• %s" % s)
		elif not tids.is_empty():
			for x2 in tids:
				var s2 := String(x2)
				if s2 != "":
					lines_t.append("• %s" % s2)
		_traits.text = "[b]Traits[/b]\n" + ("\n".join(lines_t) if not lines_t.is_empty() else "—")

	if _abilities != null:
		var ab: Dictionary = data.get("ability", {}) as Dictionary
		if ab.is_empty():
			_abilities.text = "[b]Ability[/b]\n—"
		else:
			var ab_name := String(ab.get("name", String(ab.get("id", ""))))
			var trigger := String(ab.get("trigger", ""))
			var cd := float(ab.get("cooldown_s", 0.0))
			var cast := float(ab.get("cast_time_s", 0.0))
			var per_day := int(ab.get("charges_per_day", 0))
			var left := int(ab.get("charges_left", -1))
			var summary := String(ab.get("summary", ""))
			var lines_a: Array[String] = []
			if ab_name != "":
				lines_a.append("• %s" % ab_name)
			if trigger != "":
				lines_a.append("• Trigger: %s" % trigger)
			if cd != 0.0:
				lines_a.append("• Cooldown: %s" % str(cd))
			if cast > 0.0:
				lines_a.append("• Cast: %s" % str(cast))
			if per_day > 0:
				lines_a.append("• Charges: %d/day" % per_day)
			if left >= 0:
				lines_a.append("• Remaining: %d" % left)
			if summary != "":
				lines_a.append("• %s" % summary)
			_abilities.text = "[b]Ability[/b]\n" + ("\n".join(lines_a) if not lines_a.is_empty() else "—")

	var goals: Array = data.get("top_goals", []) as Array
	var lines: Array[String] = []
	for g in goals:
		var s := String(g)
		if s != "":
			lines.append("• %s" % s)
	_goals.text = "[b]Goals[/b]\n" + ("\n".join(lines) if not lines.is_empty() else "—")


func _place_near_screen_pos(screen_pos: Vector2) -> void:
	# Convert screen/global mouse position into the popup's PARENT local space (HUD space),
	# then place the popup near that point.
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

