extends RefCounted
class_name HeroService

var _heroes_by_id: Dictionary = {}
var _day_plan: Array = []
var _loaded: bool = false
var _seed_salt: int = 0xA5A5A5A5
var _cfg_cached: Node = null


func inject_heroes_into_generation(gen: Dictionary, day_index: int, cfg: Node, goals_cfg: Node) -> void:
	_ensure_loaded(cfg)
	if _heroes_by_id.is_empty():
		return
	var hero_ids: Array[String] = _select_heroes_for_day(day_index, cfg)
	if hero_ids.is_empty():
		return

	var mdefs: Dictionary = gen.get("member_defs", {}) as Dictionary
	var pdefs: Array = gen.get("party_defs", []) as Array

	var next_member_id := 1
	for k in mdefs.keys():
		next_member_id = maxi(next_member_id, int(k) + 1)
	var max_party_id := 0
	for pd in pdefs:
		max_party_id = maxi(max_party_id, int((pd as Dictionary).get("party_id", 0)))
	var next_party_id := max_party_id + 1

	for hid in hero_ids:
		var hero := _heroes_by_id.get(String(hid), {}) as Dictionary
		if hero.is_empty():
			continue
		var mid := next_member_id
		next_member_id += 1
		var pid := next_party_id
		next_party_id += 1

		var member_def := _build_member_def_from_hero(hero, mid, pid, cfg, goals_cfg)
		if member_def.is_empty():
			continue
		mdefs[mid] = member_def
		pdefs.append({ "party_id": pid, "member_ids": [mid] })

	gen["member_defs"] = mdefs
	gen["party_defs"] = pdefs


func get_upcoming_heroes(horizon_days: int = 3) -> Array:
	_ensure_loaded(null)
	var out: Array = []
	var cur_day := 1
	if GameState != null:
		cur_day = int(GameState.day_index)
	var end_day := cur_day + maxi(0, horizon_days)
	for day in range(cur_day + 1, end_day + 1):
		var ids2 := _select_heroes_for_day(day, _cfg_cached)
		for hid0 in ids2:
			var hid := String(hid0)
			var hero := _heroes_by_id.get(hid, {}) as Dictionary
			if hero.is_empty():
				continue
			var item := {
				"hero_id": hid,
				"name": String(hero.get("name", "")),
				"class_id": String(hero.get("class_id", "")),
				"days_until": int(day - cur_day),
			}
			out.append(item)
	return out


func _ensure_loaded(cfg: Node) -> void:
	if _loaded:
		return
	if cfg != null:
		_cfg_cached = cfg
	_loaded = true
	_heroes_by_id.clear()
	_day_plan.clear()
	var hero_path := "res://config/hero_config.json"
	var plan_path := "res://config/day_plan.json"
	if cfg != null and cfg.has_method("get"):
		var h := String(cfg.get("HERO_CONFIG_PATH"))
		var p := String(cfg.get("DAY_PLAN_PATH"))
		if h != "":
			hero_path = h
		if p != "":
			plan_path = p
	_load_hero_config(hero_path)
	_load_day_plan(plan_path)


func _load_hero_config(path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var arr: Array = (parsed as Dictionary).get("heroes", []) as Array
	for h0 in arr:
		var h := h0 as Dictionary
		var hid := String(h.get("hero_id", ""))
		if hid == "":
			continue
		_heroes_by_id[hid] = h


func _load_day_plan(path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_day_plan = (parsed as Dictionary).get("days", []) as Array


func _hero_ids_for_day(day_index: int) -> Array[String]:
	var out: Array[String] = []
	for entry0 in _day_plan:
		var entry := entry0 as Dictionary
		if int(entry.get("day", 0)) != int(day_index):
			continue
		var ids: Array = entry.get("heroes", []) as Array
		for hid0 in ids:
			var hid := String(hid0)
			if hid != "":
				out.append(hid)
	return out


func _select_heroes_for_day(day_index: int, cfg: Node) -> Array[String]:
	var out: Array[String] = []
	var entry: Dictionary = {}
	for entry0 in _day_plan:
		var e := entry0 as Dictionary
		if int(e.get("day", 0)) == int(day_index):
			entry = e
			break
	if not entry.is_empty():
		var ids: Array = entry.get("heroes", []) as Array
		for hid0 in ids:
			var hid := String(hid0)
			if hid != "" and _heroes_by_id.has(hid) and not out.has(hid):
				out.append(hid)
		var random_count := int(entry.get("random_count", 0))
		if random_count > 0:
			var pool: Array = entry.get("hero_pool", []) as Array
			if pool.is_empty():
				pool = _heroes_by_id.keys()
			out.append_array(_pick_random_heroes(day_index, pool, random_count, out))
	else:
		# Optional global random spawn if no plan entry exists.
		var chance := 0.0
		var cmin := 1
		var cmax := 1
		if cfg != null and cfg.has_method("get"):
			chance = float(cfg.get("HERO_RANDOM_SPAWN_CHANCE"))
			cmin = int(cfg.get("HERO_RANDOM_COUNT_MIN"))
			cmax = int(cfg.get("HERO_RANDOM_COUNT_MAX"))
		if chance > 0.0:
			var rng := _rng_for_day(day_index)
			if rng.randf() <= chance:
				var count := clampi(rng.randi_range(cmin, cmax), 1, 5)
				var pool2: Array = _heroes_by_id.keys()
				out.append_array(_pick_random_heroes(day_index, pool2, count, out))
	return out


func _pick_random_heroes(day_index: int, pool: Array, count: int, exclude: Array) -> Array[String]:
	var rng := _rng_for_day(day_index)
	var ids: Array[String] = []
	var filtered: Array[String] = []
	for p0 in pool:
		var pid := String(p0)
		if pid == "" or not _heroes_by_id.has(pid):
			continue
		if exclude.has(pid):
			continue
		filtered.append(pid)
	filtered.sort()
	while ids.size() < count and not filtered.is_empty():
		var idx := rng.randi_range(0, filtered.size() - 1)
		var pick := String(filtered[idx])
		filtered.remove_at(idx)
		ids.append(pick)
	if Engine.has_singleton("DbgLog") and not ids.is_empty():
		DbgLog.debug("Hero random pick day=%d ids=%s" % [int(day_index), str(ids)], "heroes")
	return ids


func _rng_for_day(day_index: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(day_index) ^ int(_seed_salt)
	return rng


func _build_member_def_from_hero(hero: Dictionary, member_id: int, party_id: int, cfg: Node, goals_cfg: Node) -> Dictionary:
	var class_id := String(hero.get("class_id", "warrior"))
	var base_stats := hero.get("base_stats", {}) as Dictionary
	if base_stats.is_empty():
		base_stats = { "intelligence": 10, "strength": 10, "agility": 10 }
	if hero.has("strength"):
		base_stats["strength"] = int(hero.get("strength", 10))
	var morality := int(hero.get("morality", 0))
	var traits: Array = hero.get("traits", []) as Array
	var stat_mods: Dictionary = hero.get("stat_mods", {}) as Dictionary
	var ability_id := String(hero.get("ability_id", ""))
	var ability_charges := int(hero.get("ability_charges", 1))
	var ability_ids: Array = hero.get("ability_ids", []) as Array
	var ability_charges_by_id: Dictionary = hero.get("ability_charges_by_id", {}) as Dictionary
	var stolen_cap := int(cfg.get("STOLEN_INV_CAP_DEFAULT")) if cfg != null else 2

	var goal_weights: Dictionary = {}
	var goal_params: Dictionary = hero.get("goal_params", {}) as Dictionary
	if goals_cfg != null and goals_cfg.has_method("base_goal_ids"):
		var base_ids: Array = goals_cfg.call("base_goal_ids") as Array
		for gid0 in base_ids:
			var gid := String(gid0)
			if goals_cfg.has_method("roll_goal_weight"):
				goal_weights[gid] = int(goals_cfg.call("roll_goal_weight", RandomNumberGenerator.new(), gid))
	if hero.has("goal_weights"):
		var gw := hero.get("goal_weights", {}) as Dictionary
		for k in gw.keys():
			goal_weights[String(k)] = int(gw.get(k, 0))
	var goals: Array = hero.get("goals", []) as Array
	for g0 in goals:
		var g := String(g0)
		if g != "":
			goal_weights[g] = maxi(1, int(goal_weights.get(g, 5)))

	return {
		"member_id": int(member_id),
		"party_id": int(party_id),
		"class_id": class_id,
		"morality": morality,
		"goal_weights": goal_weights,
		"goal_params": goal_params,
		"stolen_inv_cap": stolen_cap,
		"stat_mods": stat_mods,
		"base_stats": base_stats,
		"traits": traits,
		"ability_id": ability_id,
		"ability_charges": ability_charges,
		"ability_ids": ability_ids,
		"ability_charges_by_id": ability_charges_by_id,
		"s_contrib": int(hero.get("s_contrib", 0)),
		"name": String(hero.get("name", "")),
		"origin": String(hero.get("origin", "")),
		"bio": String(hero.get("bio", "")),
		"gender": String(hero.get("gender", "")),
		"family_name": String(hero.get("family_name", "")),
		"lineage_id": int(hero.get("lineage_id", 0)),
		"is_hero": true,
		"hero_id": String(hero.get("hero_id", "")),
	}
