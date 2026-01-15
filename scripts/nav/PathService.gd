extends RefCounted
class_name PathService

var _grid: Node = null


func setup(grid: Node) -> void:
	_grid = grid


func path(start_cell: Vector2i, goal_cell: Vector2i, drop_first_if_same: bool = true) -> Array[Vector2i]:
	if _grid == null:
		return []
	var p: Array[Vector2i] = _grid.call("find_path", start_cell, goal_cell) as Array[Vector2i]
	if drop_first_if_same and p.size() > 1 and p[0] == start_cell:
		p.remove_at(0)
	return p


func is_reachable(start_cell: Vector2i, goal_cell: Vector2i) -> bool:
	if _grid == null:
		return false
	var p: Array[Vector2i] = _grid.call("find_path", start_cell, goal_cell) as Array[Vector2i]
	return not p.is_empty()

