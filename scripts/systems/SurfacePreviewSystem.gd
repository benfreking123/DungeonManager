extends RefCounted
class_name SurfacePreviewSystem

# BUILD-phase surface preview:
# - Generate + cache parties for the current day_index
# - Spawn adventurer actors on the town surface and make them wander (horizontal-only)
# - Provide hit-test + tooltip data during BUILD
# - Reuse the preview actors when Start Day is pressed (so no duplicates)

const PREVIEW_SURFACE_SPEED := 22.0
const PREVIEW_WANDER_X_RANGE_PX := 140.0
const PREVIEW_WANDER_INTERVAL_MIN := 0.65
const PREVIEW_WANDER_INTERVAL_MAX := 1.75

var _simulation: Node = null
var _town_view: Control = null
var _dungeon_view: Control = null
var _world_canvas: CanvasItem = null
var _adv_scene: PackedScene = null
var _item_db: Node = null

var _run_seed: int = 0

var _next_day_gen: Dictionary = {}
var _next_day_index: int = 0

var _preview_adventurers: Array[Node2D] = []
var _preview_actor_by_member_id: Dictionary = {} # member_id -> Node2D
var _preview_wander_timer_by_adv_id: Dictionary = {} # adv_id -> float
var _preview_party_center_local_by_party_id: Dictionary = {} # party_id -> Vector2
var _preview_rng: RandomNumberGenerator = null


func setup(simulation: Node, town_view: Control, dungeon_view: Control, world_canvas: CanvasItem, adv_scene: PackedScene, item_db: Node) -> void:
	_simulation = simulation
	_town_view = town_view
	_dungeon_view = dungeon_view
	_world_canvas = world_canvas
	_adv_scene = adv_scene
	_item_db = item_db
	if _run_seed == 0:
		_run_seed = int(Time.get_ticks_usec()) ^ int(randi())


func clear() -> void:
	for a in _preview_adventurers:
		if is_instance_valid(a):
			a.queue_free()
	_preview_adventurers.clear()
	_preview_actor_by_member_id.clear()
	_preview_wander_timer_by_adv_id.clear()
	_preview_party_center_local_by_party_id.clear()
	_preview_rng = null


func cached_gen_day_index() -> int:
	return int(_next_day_index)


func cached_gen() -> Dictionary:
	return _next_day_gen


func has_preview_actors() -> bool:
	return not _preview_adventurers.is_empty() and not _preview_actor_by_member_id.is_empty()


func _preview_day_seed(day_idx: int, strength_s: int) -> int:
	var di := maxi(1, int(day_idx))
	var s := maxi(0, int(strength_s))
	return int(_run_seed) ^ (di * 1103515245) ^ (s * 12345) ^ 0x9E3779B9


func maybe_prepare_for_build(day_idx: int, strength_service: Object, party_gen: Object, cfg: Object, goals_cfg: Object, history: Object) -> void:
	# Only meaningful when TownView layout is valid.
	if _town_view == null or _dungeon_view == null:
		return
	if _town_view is Control:
		var sz := (_town_view as Control).size
		if sz.x < 10.0 or sz.y < 10.0:
			# Layout not ready yet; caller can retry later.
			return
	var di := maxi(1, int(day_idx))
	if _next_day_index == di and not _next_day_gen.is_empty():
		return

	var strength_s := 0
	if strength_service != null and strength_service.has_method("compute_strength_s_for_day"):
		strength_s = int(strength_service.call("compute_strength_s_for_day", di, cfg))
	var preview_seed := _preview_day_seed(di, strength_s)
	var A_default := clampi(int(round(float(strength_s) / 3.0)), 4, 50)

	var gen := {}
	if party_gen != null and party_gen.has_method("generate_parties"):
		gen = party_gen.call("generate_parties", strength_s, cfg, goals_cfg, int(preview_seed), int(A_default)) as Dictionary
		# Attach identity (names/bios) for BUILD tooltips without recording day-start history.
		if history != null and history.has_method("attach_profiles_for_new_members_preview"):
			history.call("attach_profiles_for_new_members_preview", gen)

	_next_day_gen = gen
	_next_day_index = di
	_spawn_surface_preview(_next_day_gen)


func tick(delta: float, speed: float) -> void:
	# BUILD-only wandering tick; caller should gate on phase.
	if _preview_adventurers.is_empty():
		return
	if _preview_rng == null:
		_preview_rng = RandomNumberGenerator.new()
		_preview_rng.seed = int(_run_seed) ^ 0xBADC0DE
	var dt := float(delta) * clampf(float(speed), 0.0, 8.0)

	var alive: Array[Node2D] = []
	for a in _preview_adventurers:
		if a == null or not is_instance_valid(a):
			continue
		var aid := int(a.get_instance_id())
		var timer := float(_preview_wander_timer_by_adv_id.get(aid, 0.0)) - dt
		if timer <= 0.0:
			var pid := int(a.get("party_id"))
			var center: Vector2 = _preview_party_center_local_by_party_id.get(pid, a.position) as Vector2
			var dx := _preview_rng.randf_range(-PREVIEW_WANDER_X_RANGE_PX, PREVIEW_WANDER_X_RANGE_PX)
			var target := Vector2(center.x + dx, center.y)
			a.call("set_surface_target_local", target, PREVIEW_SURFACE_SPEED)
			timer = _preview_rng.randf_range(PREVIEW_WANDER_INTERVAL_MIN, PREVIEW_WANDER_INTERVAL_MAX)
		_preview_wander_timer_by_adv_id[aid] = timer
		a.call("tick", dt)
		alive.append(a)
	_preview_adventurers = alive


func find_preview_adventurer_at_screen_pos(screen_pos: Vector2, radius_px: float = 16.0) -> int:
	var best_id := 0
	var best_d2 := 0.0
	var r := maxf(0.0, float(radius_px))
	var r2 := r * r
	for a in _preview_adventurers:
		if a == null or not is_instance_valid(a):
			continue
		var d2: float = a.global_position.distance_squared_to(screen_pos)
		if d2 <= r2 and (best_id == 0 or d2 < best_d2):
			best_id = int(a.get_instance_id())
			best_d2 = d2
	return best_id


func preview_member_def_for_adv(adv: Node2D) -> Dictionary:
	if adv == null or not is_instance_valid(adv):
		return {}
	if not adv.has_meta("member_id"):
		return {}
	var member_id := int(adv.get_meta("member_id"))
	var mdefs: Dictionary = _next_day_gen.get("member_defs", {}) as Dictionary
	return mdefs.get(member_id, {}) as Dictionary


func get_preview_tooltip_fields(adv_id: int, goals_cfg: Object) -> Dictionary:
	# Returns UI-friendly fields from cached generation for BUILD preview.
	# {
	#   name, epithet, origin, bio,
	#   morality_label,
	#   top_goals: Array[String],
	#   traits: Array[String],
	#   ability_id: String,
	#   ability_charges: int,
	# }
	var out: Dictionary = {}
	var adv := preview_actor_by_adv_id(int(adv_id))
	if adv == null:
		return out
	var md: Dictionary = preview_member_def_for_adv(adv)
	if md.is_empty():
		return out

	out["name"] = String(md.get("name", ""))
	out["epithet"] = String(md.get("epithet", ""))
	out["origin"] = String(md.get("origin", ""))
	out["bio"] = String(md.get("bio", ""))

	var m := clampi(int(md.get("morality", 0)), -5, 5)
	var morality_label := "Neutral"
	if m <= -4:
		morality_label = "Ruthless"
	elif m <= -2:
		morality_label = "Selfish"
	elif m <= 1:
		morality_label = "Neutral"
	elif m <= 3:
		morality_label = "Honorable"
	else:
		morality_label = "Noble"
	out["morality_label"] = morality_label

	# Top goals: mimic PartyAdventureSystem._top_goal_ids (exclude base goals).
	var w: Dictionary = md.get("goal_weights", {}) as Dictionary
	var pairs: Array[Dictionary] = []
	for k in w.keys():
		var gid := String(k)
		if gid in ["kill_boss", "loot_dungeon", "explore_dungeon"]:
			continue
		pairs.append({ "id": gid, "w": abs(int(w.get(k, 0))) })
	pairs.sort_custom(func(a: Dictionary, c: Dictionary) -> bool:
		return int(a.get("w", 0)) > int(c.get("w", 0))
	)
	var ids: Array[String] = []
	for i in range(mini(3, pairs.size())):
		var gid2 := String((pairs[i] as Dictionary).get("id", ""))
		if gid2 != "":
			ids.append(gid2)
	var labels: Array[String] = []
	for gid3 in ids:
		var label := ""
		if goals_cfg != null and goals_cfg.has_method("get_goal_def"):
			var def: Dictionary = goals_cfg.call("get_goal_def", String(gid3)) as Dictionary
			label = String(def.get("label", ""))
		if label == "":
			label = String(gid3)
		labels.append(label)
	out["top_goals"] = labels

	out["traits"] = md.get("traits", [])
	out["ability_id"] = String(md.get("ability_id", ""))
	out["ability_charges"] = int(md.get("ability_charges", 1))
	# Party size (optional, for UI)
	var pid := int(md.get("party_id", int(adv.get("party_id"))))
	if pid != 0:
		var pdefs: Array = _next_day_gen.get("party_defs", []) as Array
		for p0 in pdefs:
			var pd := p0 as Dictionary
			if int(pd.get("party_id", 0)) == pid:
				var mids: Array = pd.get("member_ids", []) as Array
				out["party_size"] = mids.size()
				break
	return out


func preview_actor_for_member_id(member_id: int) -> Node2D:
	return _preview_actor_by_member_id.get(int(member_id), null) as Node2D


func preview_actor_by_adv_id(adv_id: int) -> Node2D:
	var aid := int(adv_id)
	for a in _preview_adventurers:
		if is_instance_valid(a) and int(a.get_instance_id()) == aid:
			return a
	return null


func consume_reuse_plan(gen: Dictionary, dungeon_grid: Node, path_service: Object, party_ai: Object, party_adv: Object) -> Dictionary:
	# Build a plan for start_day() that reuses preview actors where possible.
	# Returns:
	# {
	#   start_cell: Vector2i,
	#   spawn_world: Vector2,
	#   entrance_world: Vector2,
	#   paths_by_party_id: Dictionary[int -> Array[Vector2i]],
	#   spawn_queue: Array[Dictionary],           # entries for members without preview actors
	#   reused: Array[Dictionary],                # entries { adv:Node2D, member_id, party_id, member_def, idx_in_party }
	# }
	var out := {
		"start_cell": Vector2i.ZERO,
		"spawn_world": Vector2.ZERO,
		"entrance_world": Vector2.ZERO,
		"paths_by_party_id": {},
		"spawn_queue": [],
		"reused": [],
	}
	if _town_view == null or _dungeon_view == null or dungeon_grid == null:
		return out
	var entrance: Dictionary = dungeon_grid.call("get_first_room_of_kind", "entrance") as Dictionary
	if entrance.is_empty():
		return out
	var start_cell: Vector2i = entrance.get("pos", Vector2i.ZERO)
	out["start_cell"] = start_cell
	out["spawn_world"] = _town_view.call("get_spawn_world_pos") as Vector2
	out["entrance_world"] = _dungeon_view.call("entrance_surface_world_pos") as Vector2

	var member_defs: Dictionary = gen.get("member_defs", {}) as Dictionary
	var party_defs: Array = gen.get("party_defs", []) as Array
	var paths_by_party_id: Dictionary = {}
	for p0 in party_defs:
		var pd := p0 as Dictionary
		var pid := int(pd.get("party_id", 0))
		if pid == 0:
			continue
		var goal: Vector2i = start_cell
		if party_adv != null and party_adv.has_method("party_goal_cell"):
			goal = party_adv.call("party_goal_cell", pid, start_cell) as Vector2i
		if party_ai != null and party_ai.has_method("set_goal"):
			party_ai.call("set_goal", pid, goal)
		var path: Array[Vector2i] = []
		if path_service != null and path_service.has_method("path"):
			path = path_service.call("path", start_cell, goal, true) as Array[Vector2i]
		paths_by_party_id[pid] = path
	out["paths_by_party_id"] = paths_by_party_id

	var spawn_queue: Array[Dictionary] = []
	var reused: Array[Dictionary] = []
	for p1 in party_defs:
		var pd2 := p1 as Dictionary
		var pid2 := int(pd2.get("party_id", 0))
		if pid2 == 0:
			continue
		var mids: Array = pd2.get("member_ids", []) as Array
		for i in range(mids.size()):
			var mid := int(mids[i])
			var md: Dictionary = member_defs.get(mid, {}) as Dictionary
			if md.is_empty():
				continue
			var adv := _preview_actor_by_member_id.get(mid, null) as Node2D
			if adv != null and is_instance_valid(adv):
				reused.append({
					"adv": adv,
					"member_id": mid,
					"party_id": pid2,
					"member_def": md,
					"idx_in_party": i,
				})
			else:
				spawn_queue.append({
					"member_id": mid,
					"party_id": pid2,
					"class_id": String(md.get("class_id", "")),
					"ability_id": String(md.get("ability_id", "")),
					"ability_charges": int(md.get("ability_charges", 1)),
					"profile_id": int(md.get("profile_id", 0)),
					"idx_in_party": i,
				})
	out["spawn_queue"] = spawn_queue
	out["reused"] = reused

	# Clear preview bookkeeping (actors are now intended to be owned by the DAY loop).
	_preview_adventurers = []
	_preview_actor_by_member_id = {}
	_preview_wander_timer_by_adv_id.clear()
	_preview_party_center_local_by_party_id.clear()
	_preview_rng = null
	return out


func pop_preview_state_for_reuse() -> Dictionary:
	# Returns and clears preview actor bookkeeping. Actors are NOT freed.
	var out := {
		"adventurers": _preview_adventurers,
		"actor_by_member_id": _preview_actor_by_member_id,
	}
	_preview_adventurers = []
	_preview_actor_by_member_id = {}
	_preview_wander_timer_by_adv_id.clear()
	_preview_party_center_local_by_party_id.clear()
	_preview_rng = null
	return out


func _spawn_surface_preview(gen: Dictionary) -> void:
	if _town_view == null or _adv_scene == null:
		return
	clear()
	if gen.is_empty():
		return

	_preview_rng = RandomNumberGenerator.new()
	_preview_rng.seed = int(gen.get("day_seed", _run_seed)) ^ 0xA5A5A5A5

	var spawn_world := _town_view.call("get_spawn_world_pos") as Vector2
	if spawn_world == Vector2.ZERO and _town_view is Control:
		var r := (_town_view as Control).get_global_rect()
		if r.size.x > 1.0 and r.size.y > 1.0:
			spawn_world = r.position + r.size * 0.5

	var spawn_local := spawn_world
	if _world_canvas != null:
		var inv_wc: Transform2D = _world_canvas.get_global_transform().affine_inverse()
		spawn_local = inv_wc * spawn_world
	else:
		spawn_local = _town_view.get_global_transform().affine_inverse() * spawn_world

	var scatter := [
		Vector2(0, 0),
		Vector2(3, -1),
		Vector2(-2, 2),
		Vector2(2, 3),
	]

	var member_defs: Dictionary = gen.get("member_defs", {}) as Dictionary
	var party_defs: Array = gen.get("party_defs", []) as Array

	for p0 in party_defs:
		var pd := p0 as Dictionary
		var pid := int(pd.get("party_id", 0))
		if pid == 0:
			continue
		var party_offset := Vector2(float((pid - 1) * 18), float(((pid - 1) % 3) * 12))
		_preview_party_center_local_by_party_id[pid] = spawn_local + party_offset

		var mids: Array = pd.get("member_ids", []) as Array
		for i in range(mids.size()):
			var mid := int(mids[i])
			var md: Dictionary = member_defs.get(mid, {}) as Dictionary
			if md.is_empty():
				continue

			var adv := _adv_scene.instantiate() as Node2D
			if _world_canvas != null:
				_world_canvas.add_child(adv)
			else:
				_town_view.add_child(adv)
			adv.z_index = 5
			adv.z_as_relative = false
			adv.position = (spawn_local + party_offset + scatter[i % scatter.size()])

			var cls_res: Resource = null
			if _item_db != null:
				cls_res = _item_db.call("get_adv_class", String(md.get("class_id", ""))) as Resource
			adv.call("apply_class", cls_res)

			adv.set_meta("member_id", mid)
			adv.set("party_id", pid)
			adv.set("phase", 0) # Adventurer.Phase.SURFACE
			if adv.has_method("set_surface_hold"):
				adv.call("set_surface_hold", true)
			adv.call("set_surface_target_local", adv.position, PREVIEW_SURFACE_SPEED)

			_preview_adventurers.append(adv)
			_preview_actor_by_member_id[mid] = adv
			_preview_wander_timer_by_adv_id[int(adv.get_instance_id())] = _preview_rng.randf_range(0.05, 0.35)

