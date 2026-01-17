extends Node2D


func _ready() -> void:
	var hud := $UI/HUD
	# Support multiple HUD layouts (new VBoxContainer/HBoxContainer, legacy Body, flat).
	var dungeon_view := get_node_or_null("UI/HUD/VBoxContainer/HBoxContainer/DungeonFrame/FrameLayer/Dungeon/WorldFrame/WorldCanvas/Grid/DungeonView")
	if dungeon_view == null:
		dungeon_view = get_node_or_null("UI/HUD/Body/DungeonFrame/Dungeon/WorldFrame/WorldCanvas/Grid/DungeonView")
	if dungeon_view == null:
		dungeon_view = get_node_or_null("UI/HUD/DungeonFrame/Dungeon/WorldFrame/WorldCanvas/Grid/DungeonView")
	var town_view := get_node_or_null("UI/HUD/VBoxContainer/HBoxContainer/DungeonFrame/FrameLayer/Dungeon/WorldFrame/WorldCanvas/Town/TownView")
	if town_view == null:
		town_view = get_node_or_null("UI/HUD/Body/DungeonFrame/Dungeon/WorldFrame/WorldCanvas/Town/TownView")
	if town_view == null:
		town_view = get_node_or_null("UI/HUD/DungeonFrame/Dungeon/WorldFrame/WorldCanvas/Town/TownView")
	var room_inventory_panel := get_node_or_null("UI/HUD/VBoxContainer/HBoxContainer/RoomInventoryPanel")
	if room_inventory_panel == null:
		room_inventory_panel = get_node_or_null("UI/HUD/Body/RoomInventoryPanel")
	if room_inventory_panel == null:
		room_inventory_panel = get_node_or_null("UI/HUD/RoomInventoryPanel")

	var room_db: Node = get_node("/root/RoomDB")
	var dungeon_grid: Node = get_node("/root/DungeonGrid")
	var simulation: Node = get_node("/root/Simulation")

	# Auto-place locked Entrance at cell (3,0) i.e. "4,1" in 1-indexed terms.
	var entrance: Dictionary = dungeon_grid.call("get_first_room_of_kind", "entrance") as Dictionary
	var entrance_def: Dictionary = room_db.call("get_room_type", "entrance") as Dictionary
	var size: Vector2i = entrance_def.get("size", Vector2i(2, 2))
	var desired := Vector2i(3, 0)

	if entrance.is_empty():
		dungeon_grid.call("place_room", "entrance", desired, size, "entrance", true)
	else:
		var cur: Vector2i = entrance.get("pos", Vector2i.ZERO)
		if cur != desired:
			dungeon_grid.call("force_move_room_of_kind", "entrance", desired)

	if dungeon_view != null and room_inventory_panel != null and room_inventory_panel.has_method("set_status"):
		dungeon_view.status_changed.connect(room_inventory_panel.set_status)

	# Town needs to know where the entrance is (surface point above the entrance).
	# Use deferred updates so Control sizes/global rects are valid and stable.
	if town_view != null and dungeon_view != null:
		town_view.call("set_dungeon_view", dungeon_view)
		call_deferred("_update_entrance_ui", town_view, dungeon_view)
		dungeon_grid.layout_changed.connect(func():
			call_deferred("_update_entrance_ui", town_view, dungeon_view)
		)

	# Wire simulation -> views (so Simulation can spawn/move adventurers).
	if town_view != null and dungeon_view != null:
		simulation.call("set_views", town_view, dungeon_view)

	GameState.economy_changed.connect(func():
		hud.set_power(GameState.power_used, GameState.power_capacity)
	)

	# Initial paint
	hud.set_power(GameState.power_used, GameState.power_capacity)


func _update_entrance_ui(town_view: Node, dungeon_view: Node) -> void:
	town_view.call("set_entrance_world_pos", dungeon_view.call("entrance_surface_world_pos"))
	town_view.call("set_entrance_cap_world_rect", dungeon_view.call("entrance_cap_world_rect"))
