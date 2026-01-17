extends RefCounted
class_name DungeonSetupStatusService

# Computes BUILD-time dungeon setup issues to show to the player.
#
# Primary issues:
# - Boss room missing
# - Boss room not connected to Entrance
# - Treasure room not connected to Entrance (only if Treasure exists)
#
# This service intentionally focuses on connectivity/setup only (not placement/power rules).


static func get_setup_issues(dungeon_grid: Node) -> Array[String]:
	var issues: Array[String] = []
	if dungeon_grid == null:
		issues.append("Missing DungeonGrid.")
		return issues

	var entrance: Dictionary = dungeon_grid.call("get_first_room_of_kind", "entrance") as Dictionary
	var boss: Dictionary = dungeon_grid.call("get_first_room_of_kind", "boss") as Dictionary
	var treasure: Dictionary = dungeon_grid.call("get_first_room_of_kind", "treasure") as Dictionary

	if entrance.is_empty():
		issues.append("Entrance room is missing.")

	if boss.is_empty():
		issues.append("Boss room is missing.")

	# Boss connectivity
	if not entrance.is_empty() and not boss.is_empty():
		var e: Vector2i = dungeon_grid.call("get_anchor_cell", entrance) as Vector2i
		var b: Vector2i = dungeon_grid.call("get_anchor_cell", boss) as Vector2i
		var p1: Array[Vector2i] = dungeon_grid.call("find_path", e, b) as Array[Vector2i]
		if p1.is_empty():
			issues.append("Boss room is not connected to the Entrance.")

	# Treasure connectivity (only if treasure exists)
	if not entrance.is_empty() and not treasure.is_empty():
		var e2: Vector2i = dungeon_grid.call("get_anchor_cell", entrance) as Vector2i
		var t: Vector2i = dungeon_grid.call("get_anchor_cell", treasure) as Vector2i
		var p2: Array[Vector2i] = dungeon_grid.call("find_path", e2, t) as Array[Vector2i]
		if p2.is_empty():
			issues.append("Treasure room is not connected to the Entrance.")

	return issues
