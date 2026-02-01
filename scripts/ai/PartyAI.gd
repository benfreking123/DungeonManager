extends RefCounted
class_name PartyAI

# Centralizes party-level goal selection, retargeting, and regroup logic.

var _grid: Node = null
var _path: PathService = null

# party_id -> goal cell
var _party_goal: Dictionary = {}
# party_id -> regroup target cell (-1,-1 if none)
var _party_regroup: Dictionary = {}

# Stable per-adventurer AI helpers (room weighting and visited tracking)
# key: int (adv_instance_id or party_id) -> AdventurerAI
var _ai_by_key: Dictionary = {}

func _leash_cells() -> int:
	# Prefer ai_tuning; fallback to legacy default.
	if Engine.has_singleton("ai_tuning") and ai_tuning != null and ai_tuning.has_method("party_leash_cells"):
		return int(ai_tuning.party_leash_cells())
	return 2


func setup(grid: Node, path_service: PathService) -> void:
	_grid = grid
	_path = path_service


func decide_initial_goal(party_id: int, start_cell: Vector2i) -> Vector2i:
	# Boss-first preference; fallback to weighted exploration.
	var goal: Vector2i = _boss_preferred_goal(start_cell)
	if goal == Vector2i(-1, -1):
		var ai: AdventurerAI = _get_or_make_ai(party_id)
		goal = ai.pick_goal_cell_weighted(_grid, start_cell)
	_party_goal[party_id] = goal
	return goal


func compute_initial_path(start_cell: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	if _path == null:
		return []
	var p: Array[Vector2i] = _path.path(start_cell, goal, true)
	if p.is_empty():
		return [start_cell]
	return p


func on_combat_ended(party_id: int, last_room: Dictionary, fallback_cell: Vector2i) -> Vector2i:
	# Regroup to room center, then resume goals.
	if last_room.is_empty():
		return Vector2i(-1, -1)
	var pos: Vector2i = last_room.get("pos", fallback_cell)
	var size: Vector2i = last_room.get("size", Vector2i.ONE)
	var center := Vector2i(pos.x + int(size.x / 2), pos.y + int(size.y / 2))
	_party_regroup[party_id] = center
	_party_goal[party_id] = center
	return center


func tick_regroup_and_paths(party_id: int, cells_by_adv: Dictionary) -> Dictionary:
	# Returns { adv_id: Array[Vector2i] } for members that need path updates.
	var updates: Dictionary = {}
	var regroup: Vector2i = _party_regroup.get(party_id, Vector2i(-1, -1)) as Vector2i
	if regroup != Vector2i(-1, -1):
		# Check if all are close enough; else force paths toward regroup.
		var all_close: bool = true
		for aid in cells_by_adv.keys():
			var c: Vector2i = cells_by_adv[aid]
			if c == Vector2i(-1, -1):
				all_close = false
				break
			var d: int = abs(c.x - regroup.x) + abs(c.y - regroup.y)
			if d > _leash_cells():
				all_close = false
				break
		if all_close:
			_party_regroup.erase(party_id)
			# Do NOT pick a new goal here. Higher-level systems (PartyAdventureSystem) own
			# goal selection; PartyAI is responsible only for regroup/leash/path application.
		else:
			for aid in cells_by_adv.keys():
				var c2: Vector2i = cells_by_adv[aid]
				if c2 == Vector2i(-1, -1):
					continue
				var p_to: Array[Vector2i] = []
				if _path != null:
					p_to = _path.path(c2, regroup, true)
				updates[int(aid)] = p_to
		return updates

	# Simple leash toward the current leader cell.
	var leader: Vector2i = Vector2i(-1, -1)
	for aid2 in cells_by_adv.keys():
		var c3: Vector2i = cells_by_adv[aid2]
		if c3 != Vector2i(-1, -1):
			leader = c3
			break
	if leader == Vector2i(-1, -1):
		return updates

	for aid3 in cells_by_adv.keys():
		var c4: Vector2i = cells_by_adv[aid3]
		if c4 == Vector2i(-1, -1):
			continue
		var dist: int = abs(c4.x - leader.x) + abs(c4.y - leader.y)
		if dist <= _leash_cells():
			continue
		var p: Array[Vector2i] = []
		if _path != null:
			p = _path.path(c4, leader, true)
		updates[int(aid3)] = p
	return updates


func set_goal(party_id: int, goal: Vector2i) -> void:
	_party_goal[int(party_id)] = goal


func retarget_from_cell(party_id: int, from_cell: Vector2i) -> void:
	_retarget_from_cell(party_id, from_cell)


func paths_to_current_goal(party_id: int, cells_by_adv: Dictionary) -> Dictionary:
	var updates: Dictionary = {}
	var goal: Vector2i = _party_goal.get(party_id, Vector2i(-1, -1))
	if goal == Vector2i(-1, -1):
		return updates
	for aid in cells_by_adv.keys():
		var c: Vector2i = cells_by_adv[aid]
		if c == Vector2i(-1, -1):
			continue
		var p: Array[Vector2i] = []
		if _path != null:
			p = _path.path(c, goal, true)
		updates[int(aid)] = p
	return updates


func get_current_goal(party_id: int) -> Vector2i:
	return _party_goal.get(party_id, Vector2i(-1, -1)) as Vector2i


func _retarget_from_cell(party_id: int, from_cell: Vector2i) -> void:
	var goal: Vector2i = _boss_preferred_goal(from_cell)
	if goal == Vector2i(-1, -1):
		var ai: AdventurerAI = _get_or_make_ai(party_id)
		goal = ai.pick_goal_cell_weighted(_grid, from_cell)
	_party_goal[party_id] = goal


func _boss_preferred_goal(from_cell: Vector2i) -> Vector2i:
	if _grid == null or _path == null:
		return Vector2i(-1, -1)
	var boss_room: Dictionary = _grid.call("get_first_room_of_kind", "boss") as Dictionary
	if boss_room.is_empty():
		return Vector2i(-1, -1)
	var boss_pos: Vector2i = boss_room.get("pos", Vector2i(-1, -1))
	var size: Vector2i = boss_room.get("size", Vector2i.ONE)
	var boss_center: Vector2i = Vector2i(boss_pos.x + int(size.x / 2), boss_pos.y + int(size.y / 2))
	if _path.is_reachable(from_cell, boss_center):
		return boss_center
	if _path.is_reachable(from_cell, boss_pos):
		return boss_pos
	return Vector2i(-1, -1)


func _get_or_make_ai(key: int) -> AdventurerAI:
	var ai := _ai_by_key.get(key, null) as AdventurerAI
	if ai == null:
		ai = AdventurerAI.new(key)
		_ai_by_key[key] = ai
	return ai

