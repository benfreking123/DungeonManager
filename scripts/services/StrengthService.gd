extends RefCounted
class_name StrengthService

# Computes player Strength S based on total treasure:
# - Treasure in PlayerInventory
# - Treasure installed in room slots on the grid

func compute_strength_s(player_inventory: Node, dungeon_grid: Node, item_db: Node) -> int:
	if player_inventory == null or dungeon_grid == null or item_db == null:
		return 0

	var s := 0

	# Inventory treasure
	var counts: Dictionary = player_inventory.get("counts") as Dictionary
	for item_id in counts.keys():
		var id := String(item_id)
		var n := int(counts.get(item_id, 0))
		if n <= 0:
			continue
		var kind := ""
		if item_db.has_method("get_item_kind"):
			kind = String(item_db.call("get_item_kind", id))
		if kind == "treasure":
			s += n

	# Installed treasure on grid
	var rooms: Array = dungeon_grid.get("rooms") as Array
	for r0 in rooms:
		var room := r0 as Dictionary
		if room.is_empty():
			continue
		var slots: Array = room.get("slots", [])
		for s0 in slots:
			var sd := s0 as Dictionary
			if sd.is_empty():
				continue
			var installed := String(sd.get("installed_item_id", ""))
			if installed == "":
				continue
			var kind2 := ""
			if item_db.has_method("get_item_kind"):
				kind2 = String(item_db.call("get_item_kind", installed))
			if kind2 == "treasure":
				s += 1

	var w := 1.0
	if Engine.has_singleton("game_config"):
		w = float(game_config.get("STRENGTH_PER_TREASURE"))
	return max(0, int(round(float(s) * w)))

