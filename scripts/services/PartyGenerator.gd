extends RefCounted
class_name PartyGenerator

const DEFAULT_CLASSES := ["warrior", "mage", "priest", "rogue"]
const CLASS_RES_PATH := {
	"warrior": "res://scripts/classes/Warrior.tres",
	"rogue": "res://scripts/classes/Rogue.tres",
	"mage": "res://scripts/classes/Mage.tres",
	"priest": "res://scripts/classes/Priest.tres",
}


func _clamp_stat(v: int, cfg: Node) -> int:
	var min_s := 8
	var max_s := 12
	if cfg != null and cfg.has_method("get"):
		min_s = int(cfg.get("ADV_STAT_MIN"))
		max_s = int(cfg.get("ADV_STAT_MAX"))
	if min_s > max_s:
		var tmp := min_s
		min_s = max_s
		max_s = tmp
	return clampi(int(v), min_s, max_s)


func _roll_base_stats(rng: RandomNumberGenerator, cfg: Node, class_id: String) -> Dictionary:
	var base := { "intelligence": 10, "strength": 10, "agility": 10 }
	var path := String(CLASS_RES_PATH.get(String(class_id), ""))
	if path != "":
		var res := load(path)
		var c := res as AdventurerClass
		if c != null:
			base["intelligence"] = int(c.intelligence)
			base["strength"] = int(c.strength)
			base["agility"] = int(c.agility)

	var delta := 1
	if cfg != null and cfg.has_method("get"):
		delta = int(cfg.get("ADV_STAT_ROLL_DELTA"))
	delta = maxi(0, delta)

	return {
		"intelligence": _clamp_stat(int(base["intelligence"]) + (rng.randi_range(-delta, delta) if delta > 0 else 0), cfg),
		"strength": _clamp_stat(int(base["strength"]) + (rng.randi_range(-delta, delta) if delta > 0 else 0), cfg),
		"agility": _clamp_stat(int(base["agility"]) + (rng.randi_range(-delta, delta) if delta > 0 else 0), cfg),
	}


func generate_parties(strength_s: int, cfg: Node, goals_cfg: Node, day_seed: int, adventurers_count: int = 0) -> Dictionary:
	# Returns:
	# {
	#   "day_seed": int,
	#   "party_defs": Array[Dictionary], # { party_id, member_ids:Array[int] }
	#   "member_defs": Dictionary, # member_id -> { member_id, party_id, class_id, morality, goal_weights, goal_params, stolen_inv_cap, stat_mods }
	# }
	var rng := RandomNumberGenerator.new()
	rng.seed = int(day_seed)

	# Determine adventurer count A (fallback from S) and party count P with a soft bias toward 3–4 sizes.
	var max_parties := int(cfg.get("MAX_PARTIES")) if cfg != null else 10
	var max_party_size := int(cfg.get("MAX_PARTY_SIZE")) if cfg != null else 5
	var stolen_cap := int(cfg.get("STOLEN_INV_CAP_DEFAULT")) if cfg != null else 2

	var S_total := maxi(0, int(strength_s))
	var A := int(adventurers_count)
	if A <= 0:
		# Default: ~3 strength per adventurer, clamped to [4, 50].
		A = clampi(int(round(float(S_total) / 3.0)), 4, 50)
	else:
		A = clampi(A, 1, 50)

	var party_count := clampi(int(round(float(A) / 3.6)), 1, max_parties)

	# Party size weights (favor 4). Read from config if provided.
	var size_weights: Dictionary = {
		4: 12,
		3: 4,
		5: 3,
		2: 1,
	}
	if cfg != null and cfg.has_method("get"):
		var maybe: Variant = cfg.get("PARTY_SIZE_WEIGHT_DEFAULTS")
		if typeof(maybe) == TYPE_DICTIONARY and not (maybe as Dictionary).is_empty():
			size_weights = maybe as Dictionary

	# Sample party sizes, then adjust to hit the exact A members target (±0).
	var sizes: Array[int] = []
	for _i in range(party_count):
		sizes.append(clampi(_weighted_pick_int(rng, size_weights, 4), 1, max_party_size))
	var size_sum := 0
	for s in sizes:
		size_sum += int(s)
	# If short, increment the smallest parties first; if over, decrement the largest parties first.
	while size_sum < A:
		var idx_small := _index_of_smallest(sizes)
		if idx_small < 0:
			break
		if sizes[idx_small] < max_party_size:
			sizes[idx_small] += 1
			size_sum += 1
		else:
			# All at max; append a size-1 micro party if within cap.
			if sizes.size() < max_parties:
				sizes.append(1)
				size_sum += 1
			else:
				break
	while size_sum > A and not sizes.is_empty():
		var idx_large := _index_of_largest(sizes)
		if idx_large < 0:
			break
		if sizes[idx_large] > 1:
			sizes[idx_large] -= 1
			size_sum -= 1
		else:
			# Remove empty/size-0 parties defensively (shouldn't happen).
			if sizes[idx_large] <= 0:
				sizes.remove_at(idx_large)

	var party_defs: Array[Dictionary] = []
	var member_defs: Dictionary = {}
	var next_member_id := 1
	# Load traits and abilities index once per generation.
	var traits_cfg: Node = load("res://autoloads/traits_config.gd").new()
	var abilities_by_class := _index_abilities_by_class()

	for pid in range(1, sizes.size() + 1):
		var party_size := clampi(int(sizes[pid - 1]), 1, max_party_size)
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
			var unique_ids: Array[String] = []
			if goals_cfg != null:
				# Roll base goal weights
				var base_ids: Array = goals_cfg.call("base_goal_ids") as Array if goals_cfg.has_method("base_goal_ids") else []
				for gid0 in base_ids:
					var gid := String(gid0)
					if gid == "":
						continue
					if goals_cfg.has_method("roll_goal_weight"):
						goal_weights[gid] = int(goals_cfg.call("roll_goal_weight", rng, gid))
					if goals_cfg.has_method("roll_goal_params"):
						goal_params[gid] = goals_cfg.call("roll_goal_params", rng, gid)

				# Roll 1–3 unique goals (uniform sample for now).
				var uniq_n := rng.randi_range(1, 3)
				var uniq: Array = goals_cfg.call("pick_unique_goal_ids", rng, uniq_n) as Array if goals_cfg.has_method("pick_unique_goal_ids") else []
				for gid2_0 in uniq:
					var gid2 := String(gid2_0)
					if gid2 == "":
						continue
					unique_ids.append(gid2)
					if goals_cfg.has_method("roll_goal_weight"):
						goal_weights[gid2] = int(goals_cfg.call("roll_goal_weight", rng, gid2))
					if goals_cfg.has_method("roll_goal_params"):
						goal_params[gid2] = goals_cfg.call("roll_goal_params", rng, gid2)

			var stat_mods := _roll_stat_mods(rng)
			var base_stats := _roll_base_stats(rng, cfg, String(ci))
			# Roll 0–2 traits by weight.
			var traits: Array[String] = []
			if traits_cfg != null:
				var tcount := rng.randi_range(0, 2)
				var ids: Array[String] = traits_cfg.trait_ids()
				for _ti in range(tcount):
					if ids.is_empty():
						break
					var tid := _weighted_pick_trait(rng, traits_cfg, ids)
					if tid == "" or traits.has(tid):
						# Prevent duplicates; remove and continue.
						ids.erase(tid)
						continue
					traits.append(tid)
					# Remove picked id to prevent duplicates.
					ids.erase(tid)
			# Pick 0–1 ability based on class, if available.
			var ability_id := ""
			var ability_charges := 1
			var ability_s_delta := 0
			if abilities_by_class.has(String(ci)):
				var opts: Array = abilities_by_class[String(ci)] as Array
				if not opts.is_empty() and rng.randf() < 0.9:
					ability_id = String(opts[rng.randi_range(0, opts.size() - 1)])
					# Load resource to read charges and s_delta
					var ab_res := _load_ability(ability_id)
					if ab_res != null:
						ability_charges = int(ab_res.charges_per_day)
						ability_s_delta = int(ab_res.s_delta)
			# S contribution (for logging/budgeting): sum trait s_deltas + ability s_delta
			var s_contrib := 0
			for t_id in traits:
				s_contrib += int(traits_cfg.trait_s_delta(String(t_id)))
			s_contrib += int(ability_s_delta)

			member_defs[mid] = {
				"member_id": mid,
				"party_id": pid,
				"class_id": String(ci),
				"morality": morality,
				"goal_weights": goal_weights,
				"goal_params": goal_params,
				"stolen_inv_cap": stolen_cap,
				"stat_mods": stat_mods,
				"base_stats": base_stats,
				"traits": traits,
				"ability_id": ability_id,
				"ability_charges": ability_charges,
				"s_contrib": s_contrib,
			}

			# Debug visibility: log each adventurer's roll once per day seed.
			DbgLog.once(
				"goals_roll:%d:%d" % [int(day_seed), int(mid)],
				"Adv roll mid=%d party=%d unique=%s weights=%s params=%s" % [
					int(mid),
					int(pid),
					str(unique_ids),
					str(goal_weights),
					str(goal_params),
				],
				"party",
				DbgLog.Level.DEBUG
			)

		party_defs.append({ "party_id": pid, "member_ids": member_ids })

	# Explicitly free temporary traits config Node to avoid leak warnings in headless CI.
	if traits_cfg != null:
		traits_cfg.free()

	return {
		"day_seed": int(day_seed),
		"party_defs": party_defs,
		"member_defs": member_defs,
	}

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

func _weighted_pick_trait(rng: RandomNumberGenerator, traits_cfg: Node, ids: Array[String]) -> String:
	if traits_cfg == null or ids.is_empty():
		return ""
	var total := 0
	var weights: Dictionary = {}
	for id in ids:
		var w := int(traits_cfg.trait_weight(String(id)))
		weights[String(id)] = w
		total += maxi(0, w)
	if total <= 0:
		return String(ids[rng.randi_range(0, ids.size() - 1)])
	var roll := rng.randi_range(1, total)
	var acc := 0
	for id2 in ids:
		acc += maxi(0, int(weights.get(String(id2), 0)))
		if roll <= acc:
			return String(id2)
	return String(ids[0])


func _index_abilities_by_class() -> Dictionary:
	# Scan abilities dir and group ability_ids by class prefix.
	var out := {
		"warrior": [],
		"mage": [],
		"rogue": [],
		"priest": [],
	}
	var dir := DirAccess.open("res://assets/abilities")
	if dir == null:
		return out
	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name == "":
			break
		if dir.current_is_dir():
			continue
		if not file_name.ends_with(".tres"):
			continue
		var res_path := "res://assets/abilities/%s" % file_name
		var res := load(res_path)
		var ab := res as Ability
		if ab == null:
			continue
		var id := String(ab.ability_id)
		if id.begins_with("warrior_"):
			(out["warrior"] as Array).append(id)
		elif id.begins_with("mage_"):
			(out["mage"] as Array).append(id)
		elif id.begins_with("rogue_"):
			(out["rogue"] as Array).append(id)
		elif id.begins_with("priest_"):
			(out["priest"] as Array).append(id)
	dir.list_dir_end()
	return out


func _load_ability(ability_id: String) -> Ability:
	# Find and load an ability resource by id (linear scan once).
	var dir := DirAccess.open("res://assets/abilities")
	if dir == null:
		return null
	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name == "":
			break
		if dir.current_is_dir() or not file_name.ends_with(".tres"):
			continue
		var res_path := "res://assets/abilities/%s" % file_name
		var res := load(res_path)
		var ab := res as Ability
		if ab != null and String(ab.ability_id) == String(ability_id):
			dir.list_dir_end()
			return ab
	dir.list_dir_end()
	return null

func _index_of_smallest(a: Array[int]) -> int:
	if a.is_empty():
		return -1
	var idx := 0
	var best := a[0]
	for i in range(1, a.size()):
		if a[i] < best:
			best = a[i]
			idx = i
	return idx


func _index_of_largest(a: Array[int]) -> int:
	if a.is_empty():
		return -1
	var idx := 0
	var best := a[0]
	for i in range(1, a.size()):
		if a[i] > best:
			best = a[i]
			idx = i
	return idx
