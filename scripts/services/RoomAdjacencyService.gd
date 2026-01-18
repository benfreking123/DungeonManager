extends RefCounted
class_name RoomAdjacencyService

# Builds a room-graph adjacency map for Fog of War reveals.
# Rooms are adjacent if any occupied cell has an orthogonal neighbor in a different room.

func build_adjacency(dungeon_grid: Node) -> Dictionary:
	# Returns: room_id -> Array[int neighbor_room_id]
	var out: Dictionary = {}
	if dungeon_grid == null:
		return out

	var gw := int(dungeon_grid.get("GRID_W"))
	var gh := int(dungeon_grid.get("GRID_H"))

	# Ensure keys for all rooms exist.
	var rooms: Array = dungeon_grid.get("rooms") as Array
	for r0 in rooms:
		var r := r0 as Dictionary
		if r.is_empty():
			continue
		var rid := int(r.get("id", 0))
		if rid != 0 and not out.has(rid):
			out[rid] = []

	for x in range(gw):
		for y in range(gh):
			var cell := Vector2i(x, y)
			var room_a: Dictionary = dungeon_grid.call("get_room_at", cell) as Dictionary
			var a := int(room_a.get("id", 0))
			if a == 0:
				continue
			if not out.has(a):
				out[a] = []
			# Check 4-neighbors.
			var neigh := [Vector2i(x + 1, y), Vector2i(x - 1, y), Vector2i(x, y + 1), Vector2i(x, y - 1)]
			for c2 in neigh:
				if c2.x < 0 or c2.y < 0 or c2.x >= gw or c2.y >= gh:
					continue
				var room_b: Dictionary = dungeon_grid.call("get_room_at", c2) as Dictionary
				var b := int(room_b.get("id", 0))
				if b == 0 or b == a:
					continue
				if not out.has(b):
					out[b] = []
				var arr_a: Array = out[a] as Array
				if not arr_a.has(b):
					arr_a.append(b)
					out[a] = arr_a
				var arr_b: Array = out[b] as Array
				if not arr_b.has(a):
					arr_b.append(a)
					out[b] = arr_b

	return out

