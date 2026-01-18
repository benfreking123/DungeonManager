extends SceneTree

# CI smoke test:
# - Load the main scene headlessly
# - Ensure a Boss room exists and is connected to the Entrance
# - "Press" the Start Day button
# - Assert the game enters DAY phase

const MAIN_SCENE_PATH := "res://scenes/Main.tscn"


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	push_error(message)
	print("=== Godot CI: Start Day smoke test FAILED ===")
	quit(1)


func _ok(message: String) -> void:
	print(message)
	print("=== Godot CI: Start Day smoke test OK ===")
	quit(0)


func _wait_frames(n: int) -> void:
	for _i in range(maxi(0, n)):
		await process_frame


func _find_day_button() -> Button:
	var roots: Array[Node] = []
	if current_scene != null:
		roots.append(current_scene)
	if root != null:
		roots.append(root)

	var paths := [
		# New HUD layout (current)
		"UI/HUD/VBoxContainer/HBoxContainer/VBoxContainer/HBoxContainer/PanelContainer/VBoxContainer2/DayButton",
		# New HUD layout (older variant)
		"UI/HUD/VBoxContainer/HBoxContainer/VBoxContainer/HBoxContainer/VBoxContainer/DayButton",
		# Legacy layout (fallback)
		"UI/HUD/TopBar/HBox/DayButton",
		"UI/HUD/VBoxContainer/TopBar/HBox/DayButton",
	]

	for r in roots:
		for p in paths:
			var n := r.get_node_or_null(p)
			if n != null and n is Button:
				return n as Button
	return null


func _ensure_boss_room_connected() -> void:
	if root == null:
		_fail("SceneTree.root is null.")
		return
	var dg := root.get_node_or_null("DungeonGrid")
	var room_db := root.get_node_or_null("RoomDB")
	if dg == null:
		_fail("DungeonGrid autoload missing.")
		return
	if room_db == null:
		_fail("RoomDB autoload missing.")
		return

	var entrance: Dictionary = dg.call("get_first_room_of_kind", "entrance") as Dictionary
	if entrance.is_empty():
		_fail("Entrance room missing (Main scene should auto-place it).")
		return

	var boss: Dictionary = dg.call("get_first_room_of_kind", "boss") as Dictionary
	if boss.is_empty():
		var boss_def: Dictionary = room_db.call("get_room_type", "boss") as Dictionary
		var size: Vector2i = boss_def.get("size", Vector2i(2, 2))
		var epos: Vector2i = entrance.get("pos", Vector2i.ZERO)
		var esize: Vector2i = entrance.get("size", Vector2i(2, 2))

		# Prefer adjacent placement (touching entrance) so an occupied-cell path exists.
		var candidates: Array[Vector2i] = [
			Vector2i(epos.x + esize.x, epos.y), # right
			Vector2i(epos.x - size.x, epos.y), # left
			Vector2i(epos.x, epos.y + esize.y), # down
			Vector2i(epos.x, epos.y - size.y), # up
			Vector2i(epos.x + esize.x, epos.y + esize.y), # down-right
		]

		var placed := false
		for pos in candidates:
			var id := int(dg.call("place_room", "boss", pos, size, "boss", false))
			if id != 0:
				placed = true
				break
		if not placed:
			_fail("Failed to place boss room adjacent to entrance (no valid candidate position).")
			return

	# Connectivity requirement (boss path; treasure path only if treasure exists).
	var req: Dictionary = dg.call("validate_required_paths") as Dictionary
	if not bool(req.get("ok", true)):
		_fail("Dungeon required paths invalid: %s" % String(req.get("reason", "invalid_layout")))
		return

	# Simulation.start_day also requires a boss room dictionary to exist.
	var boss2: Dictionary = dg.call("get_first_room_of_kind", "boss") as Dictionary
	if boss2.is_empty():
		_fail("Boss room still missing after placement attempt.")
		return


func _run() -> void:
	print("=== Godot CI: Start Day smoke test ===")

	var packed := load(MAIN_SCENE_PATH)
	if packed == null or not (packed is PackedScene):
		_fail("Failed to load main scene: %s" % MAIN_SCENE_PATH)
		return

	var err := change_scene_to_packed(packed as PackedScene)
	if err != OK:
		_fail("Failed to change to main scene (%s). Error=%d" % [MAIN_SCENE_PATH, int(err)])
		return

	# Allow _ready() to run (Entrance auto-placement happens in scripts/Main.gd).
	await _wait_frames(3)

	# Ensure Start Day prerequisites are satisfied.
	_ensure_boss_room_connected()

	# Find and press the Start Day button (calls Simulation.start_day via HUD.gd).
	var day_button := _find_day_button()
	if day_button == null:
		_fail("DayButton not found in HUD.")
		return

	day_button.emit_signal("pressed")
	await _wait_frames(2)

	if root == null:
		_fail("SceneTree.root is null (after button press).")
		return

	var gs := root.get_node_or_null("GameState")
	if gs == null:
		_fail("GameState autoload missing.")
		return

	# GameState.Phase is { BUILD=0, DAY=1, RESULTS=2 }
	if int(gs.get("phase")) != 1:
		_fail("Start Day press did not switch GameState to DAY (phase=%d)." % int(gs.get("phase")))
		return

	_ok("Start Day smoke test passed (GameState is DAY).")

