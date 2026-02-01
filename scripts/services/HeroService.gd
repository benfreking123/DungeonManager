extends RefCounted
class_name HeroService

var _heroes_by_id: Dictionary = {}
var _day_plan: Array = []
var _loaded: bool = false


func inject_heroes_into_generation(gen: Dictionary, day_index: int, cfg: Node, goals_cfg: Node) -> void:
	_ensure_loaded(cfg)
	if _heroes_by_id.is_empty() or _day_plan.is_empty():
		return
	var hero_ids: Array[String] = _hero_ids_for_day(day_index)
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
	if _day_plan.is_empty():
		return out
	var cur_day := 1
	if GameState != null:
		cur_day = int(GameState.day_index)
	for entry0 in _day_plan:
		var entry := entry0 as Dictionary
		var day := int(entry.get("day", 0))
		if day <= cur_day:
			continue
		var until := day - cur_day
		if until > horizon_days:
			continue
		var ids: Array = entry.get("heroes", []) as Array
		for hid0 in ids:
			var hid := String(hid0)
			var hero := _heroes_by_id.get(hid, {}) as Dictionary
			if hero.is_empty():
				continue
			var item := {
				"hero_id": hid,
				"name": String(hero.get("name", "")),
				"class_id": String(hero.get("class_id", "")),
				"days_until": until,
			}
			out.append(item)
	return out


func _ensure_loaded(cfg: Node) -> void:
	if _loaded:
		return
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
