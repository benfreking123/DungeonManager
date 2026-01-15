extends RefCounted
class_name AdventurerAI

# Lightweight exploration AI:
# - tracks visited cells (room anchor cells)
# - retargets to random unvisited occupied cells

var adv_id: int
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var visited: Dictionary = {} # String(cell) -> true
var current_goal: Vector2i = Vector2i(-1, -1)


func _init(p_adv_id: int) -> void:
	adv_id = p_adv_id
	rng.seed = int(adv_id) * 1337


func mark_visited(cell: Vector2i) -> void:
	visited[_key(cell)] = true


func should_retarget() -> bool:
	# Small chance to change plan occasionally.
	return rng.randf() < 0.25


func pick_goal_cell(dungeon_grid: Node, from_cell: Vector2i) -> Vector2i:
	# Prefer unvisited occupied cells.
	var occ: Array[Vector2i] = _list_occupied_cells(dungeon_grid)
	if occ.is_empty():
		return from_cell

	var unvisited: Array[Vector2i] = []
	for c in occ:
		if not visited.has(_key(c)):
			unvisited.append(c)

	var pool := unvisited if not unvisited.is_empty() else occ
	var idx := rng.randi_range(0, pool.size() - 1)
	current_goal = pool[idx]
	return current_goal


func pick_goal_cell_weighted(dungeon_grid: Node, from_cell: Vector2i) -> Vector2i:
	# Weighted goals (easy to expand to 100s later).
	# boss +2, treasure +1, monster -1, explore 0
	var candidates: Array[Dictionary] = []

	var rooms: Array = dungeon_grid.get("rooms") as Array
	for r in rooms:
		var d := r as Dictionary
		var kind: String = String(d.get("kind", ""))
		var pos: Vector2i = d.get("pos", Vector2i.ZERO)
		var size: Vector2i = d.get("size", Vector2i.ONE)
		var center := Vector2i(pos.x + int(size.x / 2), pos.y + int(size.y / 2))
		if kind == "boss":
			# Prefer center, but include top-left as a reachability fallback (required-path validation uses pos).
			candidates.append({ "cell": center, "w": 2 })
			candidates.append({ "cell": pos, "w": 2 })
		elif kind == "treasure":
			candidates.append({ "cell": center, "w": 1 })
			candidates.append({ "cell": pos, "w": 1 })
		elif kind == "monster":
			candidates.append({ "cell": center, "w": -1 })
			candidates.append({ "cell": pos, "w": -1 })

	# Explore fallback: any occupied cell at weight 0
	var occ: Array[Vector2i] = _list_occupied_cells(dungeon_grid)
	for c in occ:
		candidates.append({ "cell": c, "w": 0 })

	var best_w := -999
	var best_cells: Array[Vector2i] = []
	for c in candidates:
		var cell: Vector2i = c.get("cell", from_cell)
		var w: int = int(c.get("w", 0))
		if cell == from_cell:
			# allow, but de-prioritize if there are others with same weight
			pass
		var path: Array[Vector2i] = dungeon_grid.call("find_path", from_cell, cell) as Array[Vector2i]
		if path.is_empty():
			continue
		if w > best_w:
			best_w = w
			best_cells = [cell]
		elif w == best_w:
			best_cells.append(cell)

	if best_cells.is_empty():
		current_goal = from_cell
		return from_cell

	var idx := rng.randi_range(0, best_cells.size() - 1)
	current_goal = best_cells[idx]
	return current_goal


func _list_occupied_cells(dungeon_grid: Node) -> Array[Vector2i]:
	# Collect one anchor cell per room to keep paths stable.
	# Use room-center cell so parties don't always cluster at the top-left corner.
	var out: Array[Vector2i] = []
	var rooms: Array = dungeon_grid.get("rooms") as Array
	for r in rooms:
		var d := r as Dictionary
		var pos: Vector2i = d.get("pos", Vector2i.ZERO)
		var size: Vector2i = d.get("size", Vector2i.ONE)
		var center := Vector2i(pos.x + int(size.x / 2), pos.y + int(size.y / 2))
		out.append(center)
	return out


func _key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


