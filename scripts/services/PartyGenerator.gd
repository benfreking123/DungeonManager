extends RefCounted
class_name PartyGenerator

const DEFAULT_CLASSES := ["warrior", "mage", "priest", "rogue"]


func generate_parties(strength_s: int, cfg: Node, goals_cfg: Node, day_seed: int) -> Dictionary:
	# Returns:
	# {
	#   "day_seed": int,
	#   "party_defs": Array[Dictionary], # { party_id, member_ids:Array[int] }
	#   "member_defs": Dictionary, # member_id -> { member_id, party_id, class_id, morality, goal_weights, stolen_inv_cap, stat_mods }
	# }
	var rng := RandomNumberGenerator.new()
	rng.seed = int(day_seed)

	var tier: Dictionary = _pick_tier(int(strength_s), cfg)
	var party_count := int(tier.get("party_count", 1))
	var size_weights: Dictionary = tier.get("party_size_weights", { 4: 1 }) as Dictionary
	party_count = clampi(party_count, 1, int(cfg.get("MAX_PARTIES")) if cfg != null else 10)

	var stolen_cap := int(cfg.get("STOLEN_INV_CAP_DEFAULT")) if cfg != null else 2

	var party_defs: Array[Dictionary] = []
	var member_defs: Dictionary = {}
	var next_member_id := 1

	for pid in range(1, party_count + 1):
		var party_size := clampi(_weighted_pick_int(rng, size_weights, 4), 1, int(cfg.get("MAX_PARTY_SIZE")) if cfg != null else 5)
		var class_ids := _pick_party_classes(rng, party_size)
		var member_ids: Array[int] = []

		for ci in class_ids:
			var mid := next_member_id
			next_member_id += 1
			member_ids.append(mid)

			var morality := rng.randi_range(-5, 5)

			# Base goals are always present, but weights/params are rolled per adventurer.
			var goal_weights: Dictionary = {}
			var goal_params: Dictionary = {}
			if goals_cfg != null:
				# Roll base goal weights
				var base_goals: Array[Dictionary] = goals_cfg.call("all_base_goals") as Array[Dictionary] if goals_cfg.has_method("all_base_goals") else []
				for g0 in base_goals:
					var g := g0 as Dictionary
					var gid := String(g.get("id", ""))
					if gid == "":
						continue
					if goals_cfg.has_method("roll_goal_weight"):
						goal_weights[gid] = int(goals_cfg.call("roll_goal_weight", rng, gid))
					if goals_cfg.has_method("roll_goal_params"):
						goal_params[gid] = goals_cfg.call("roll_goal_params", rng, gid)

				# Roll 1–3 unique goals (uniform sample for now).
				var uniq_n := rng.randi_range(1, 3)
				var uniq: Array[Dictionary] = goals_cfg.call("pick_unique_goals", rng, uniq_n) as Array[Dictionary] if goals_cfg.has_method("pick_unique_goals") else []
				for g1 in uniq:
					var gd := g1 as Dictionary
					var gid2 := String(gd.get("id", ""))
					if gid2 == "":
						continue
					if goals_cfg.has_method("roll_goal_weight"):
						goal_weights[gid2] = int(goals_cfg.call("roll_goal_weight", rng, gid2))
					if goals_cfg.has_method("roll_goal_params"):
						goal_params[gid2] = goals_cfg.call("roll_goal_params", rng, gid2)

			var stat_mods := _roll_stat_mods(rng)

			member_defs[mid] = {
				"member_id": mid,
				"party_id": pid,
				"class_id": String(ci),
				"morality": morality,
				"goal_weights": goal_weights,
				"goal_params": goal_params,
				"stolen_inv_cap": stolen_cap,
				"stat_mods": stat_mods,
			}

		party_defs.append({ "party_id": pid, "member_ids": member_ids })

	return {
		"day_seed": int(day_seed),
		"party_defs": party_defs,
		"member_defs": member_defs,
	}


func _pick_tier(strength_s: int, cfg: Node) -> Dictionary:
	if cfg == null:
		return {}
	var tiers: Array = cfg.get("PARTY_SCALING_TIERS") as Array
	for t0 in tiers:
		var t := t0 as Dictionary
		if t.is_empty():
			continue
		var mn := int(t.get("min_s", -999999))
		var mx := int(t.get("max_s", 999999))
		if strength_s >= mn and strength_s <= mx:
			return t
	return tiers[0] as Dictionary if not tiers.is_empty() else {}


func _weighted_pick_int(rng: RandomNumberGenerator, weights: Dictionary, fallback: int) -> int:
	if rng == null or weights == null or weights.is_empty():
		return fallback
	var total := 0
	for k in weights.keys():
		total += maxi(0, int(weights.get(k, 0)))
	if total <= 0:
		return fallback
	var roll := rng.randi_range(1, total)
	var acc := 0
	for k2 in weights.keys():
		acc += maxi(0, int(weights.get(k2, 0)))
		if roll <= acc:
			return int(k2)
	return fallback


func _pick_party_classes(rng: RandomNumberGenerator, party_size: int) -> Array[String]:
	var out: Array[String] = []
	if party_size <= 0:
		return out
	var pool: Array[String] = []
	for c0 in DEFAULT_CLASSES:
		pool.append(String(c0))
	# Strong bias: a 4-person party tends to be the classic 4.
	if party_size == 4 and pool.size() == 4:
		# Shuffle and return all 4.
		for i in range(pool.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp: String = pool[i]
			pool[i] = pool[j]
			pool[j] = tmp
		for c in pool:
			out.append(String(c))
		return out

	# Otherwise sample with replacement.
	for _i in range(party_size):
		out.append(String(pool[rng.randi_range(0, pool.size() - 1)]))
	return out


func _roll_stat_mods(rng: RandomNumberGenerator) -> Dictionary:
	# Simple starter modifiers; tuned later.
	var hp_bonus := 0
	var dmg_bonus := 0
	if rng.randf() < 0.5:
		hp_bonus = rng.randi_range(0, 5)
	if rng.randf() < 0.35:
		dmg_bonus = rng.randi_range(0, 1)
	return {
		"hp_bonus": hp_bonus,
		"dmg_bonus": dmg_bonus,
	}
