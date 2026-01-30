extends Node

# Autoload name (recommended): `config_goals`
#
# Goals are intentionally data-driven Dictionaries (not Resources) to keep iteration fast.
# PartyAdventureSystem will interpret these weights when scoring candidate intents.

# Intent scoring knobs (externalized).
# These values replace the hard-coded coefficients in PartyAdventureSystem.
const INTENT_SCORE: Dictionary = {
	"explore": {
		"base_goal_mult": 3,
		"baseline_bonus": 0,
	},
	"loot": {
		"base_goal_mult": 3,
		"unknown_penalty": -120,
		"space_bonus": 25,
		"space_full_penalty": -25,
	},
	"boss": {
		"base_goal_mult": 5,
		"unknown_penalty": -200,
		"known_bonus": 20,
	},
	"exit": {
		"base_goal_mult": 0,
		"start_day_penalty": -1000,
		"has_any_loot_bonus": 10,
		"full_loot_exit_bonus": 260,
		"full_loot_morality_resist_per_point": 35,
	},
}

# Intent stability knobs: clamp outliers and require a margin to switch.
const INTENT_STABILITY: Dictionary = {
	"switch_margin": 15,
	"clamp_member_min": -300,
	"clamp_member_max": 500,
}

# One canonical definition per goal id, including spawn-time roll rules and params.
var GOAL_DEFS: Dictionary = {
	# Base goals (always present)
	"kill_boss": {
		"kind": "base",
		"pickable": true,
		"order": 10,
		"label": "Kill the Boss",
		"dialogue": [
			"I want to kill the boss.",
			"Let's take down the boss.",
			"Straight to the boss.",
		],
		"spawn_roll": { "base_weight": 1, "jitter": 2, "mult_min": 0.7, "mult_max": 1.6, "spike_chance": 0.08, "spike_bonus": 4 },
		"params_roll": {},
	},
	"loot_dungeon": {
		"kind": "base",
		"pickable": true,
		"order": 20,
		"label": "Loot the Dungeon",
		"dialogue": [
			"Let's grab the loot and get out.",
			"I smell treasure nearby.",
			"Keep your eyes open for loot.",
		],
		"spawn_roll": { "base_weight": 1, "jitter": 2, "mult_min": 0.7, "mult_max": 1.6, "spike_chance": 0.08, "spike_bonus": 4 },
		"params_roll": {},
	},
	"explore_dungeon": {
		"kind": "base",
		"pickable": true,
		"order": 30,
		"label": "Explore the Dungeon",
		"dialogue": [
			"Let's explore the dungeon.",
			"Keep moving, map it all out.",
			"Stay sharp—unknown rooms ahead.",
		],
		"spawn_roll": { "base_weight": 1, "jitter": 2, "mult_min": 0.7, "mult_max": 1.6, "spike_chance": 0.08, "spike_bonus": 4 },
		"params_roll": {},
	},

	# Unique goals
	"flee_on_any_damage": {
		"kind": "unique",
		"pickable": true,
		"order": 110,
		"label": "Will flee the dungeon after taking ANY damage",
		"dialogue": [
			"One scratch and I'm out of here.",
			"If I get hit, I'm gone.",
			"Not risking it—one hit and I bail.",
		],
		"spawn_roll": { "base_weight": 0, "jitter": 1, "mult_min": 0.9, "mult_max": 1.2, "spike_chance": 0.10, "spike_bonus": 2 },
		"params_roll": {},
		"incompatible_with": ["no_flee_until_boss_dead"],
	},
	"flee_on_any_loot": {
		"kind": "unique",
		"pickable": true,
		"order": 120,
		"label": "Will flee once they get any loot",
		"dialogue": [
			"Got loot—I'm out of here.",
			"That's enough treasure. I'm leaving.",
			"One haul is plenty—back to the entrance.",
		],
		"spawn_roll": { "base_weight": 1, "jitter": 2, "mult_min": 0.9, "mult_max": 1.3, "spike_chance": 0.12, "spike_bonus": 3 },
		"params_roll": {},
		"incompatible_with": ["no_leave_until_full_loot"],
	},
	"no_flee_until_boss_dead": {
		"kind": "unique",
		"pickable": true,
		"order": 130,
		"label": "Won't flee until the Boss is killed",
		"dialogue": [
			"We're not leaving until the boss is dead.",
			"We stay until the boss falls.",
			"No retreat until we win.",
		],
		"spawn_roll": { "base_weight": 2, "jitter": 1, "mult_min": 0.8, "mult_max": 1.4, "spike_chance": 0.08, "spike_bonus": 2 },
		"params_roll": {},
		"incompatible_with": ["flee_on_any_damage"],
	},
	"no_leave_until_full_loot": {
		"kind": "unique",
		"pickable": true,
		"order": 140,
		"label": "Won't leave until they have full loot",
		"dialogue": [
			"I won't leave until my pockets are full.",
			"Not leaving empty-handed.",
			"I want every piece of loot we can carry.",
		],
		"spawn_roll": { "base_weight": 2, "jitter": 2, "mult_min": 0.8, "mult_max": 1.5, "spike_chance": 0.10, "spike_bonus": 3 },
		"params_roll": {},
		"incompatible_with": ["flee_on_any_loot"],
	},
	"exit_when_full_loot": {
		"kind": "unique",
		"pickable": true,
		"order": 150,
		"label": "Will flee once fully looted",
		"dialogue": [
			"My pack is full—time to leave.",
			"That's all I can carry. Heading out.",
			"I'm loaded with loot. Back we go.",
		],
		"spawn_roll": { "base_weight": 2, "jitter": 2, "mult_min": 0.8, "mult_max": 1.5, "spike_chance": 0.10, "spike_bonus": 3 },
		"params_roll": {},
	},
	"explore_all_before_boss": {
		"kind": "unique",
		"pickable": true,
		"order": 160,
		"label": "Wants to explore everything before killing the boss",
		"dialogue": [
			"I want to explore every inch of this dungeon.",
			"No shortcuts—check every room.",
			"We explore first, then we fight.",
		],
		"spawn_roll": { "base_weight": 1, "jitter": 2, "mult_min": 0.8, "mult_max": 1.5, "spike_chance": 0.08, "spike_bonus": 2 },
		"params_roll": {},
		"incompatible_with": ["boss_rush"],
	},
	"no_leave_until_kill_x_monsters": {
		"kind": "unique",
		"pickable": true,
		"order": 170,
		"label": "Won't leave until they kill X monsters",
		"dialogue": [
			"I'm not leaving until we kill enough monsters.",
			"We need more kills before we go.",
			"Not yet—more monsters to slay.",
		],
		"spawn_roll": { "base_weight": 2, "jitter": 2, "mult_min": 0.8, "mult_max": 1.5, "spike_chance": 0.10, "spike_bonus": 3 },
		"params_roll": { "kills_target_min": 3, "kills_target_max": 10 },
	},
	"cautious_hp_threshold": {
		"kind": "unique",
		"pickable": true,
		"order": 180,
		"label": "Will flee when hurt badly",
		"dialogue": [
			"I'm hurt—I'm leaving.",
			"This is getting dangerous. I'm out.",
			"I'm not dying in here. Retreat!",
		],
		"spawn_roll": { "base_weight": 2, "jitter": 2, "mult_min": 0.8, "mult_max": 1.4, "spike_chance": 0.08, "spike_bonus": 2 },
		"params_roll": { "hp_threshold_pct_min": 20, "hp_threshold_pct_max": 60 },
	},
	"boss_rush": {
		"kind": "unique",
		"pickable": true,
		"order": 190,
		"label": "Wants to rush the boss once it is known",
		"dialogue": [
			"Forget the loot—go for the boss.",
			"Boss first. Everything else can wait.",
			"Now that we know where it is—straight to the boss.",
		],
		"spawn_roll": { "base_weight": 2, "jitter": 2, "mult_min": 0.8, "mult_max": 1.4, "spike_chance": 0.08, "spike_bonus": 2 },
		"params_roll": {},
		"incompatible_with": ["explore_all_before_boss"],
	},
	"greedy_then_leave": {
		"kind": "unique",
		"pickable": true,
		"order": 200,
		"label": "Wants to steal X treasures then leave",
		"dialogue": [
			"We steal a few more treasures, then we leave.",
			"Just a little more loot—then out.",
			"A couple more treasures and I'm done.",
		],
		"spawn_roll": { "base_weight": 2, "jitter": 2, "mult_min": 0.8, "mult_max": 1.4, "spike_chance": 0.08, "spike_bonus": 2 },
		"params_roll": { "loot_target_min": 1, "loot_target_max": 3 },
	},
}

# Expose incompatible goals map for systems that need it. Built from GOAL_DEFS.
func get_incompatible_goals() -> Dictionary:
	var out: Dictionary = {}
	for k in GOAL_DEFS.keys():
		var gid := String(k)
		var def: Dictionary = GOAL_DEFS.get(gid, {}) as Dictionary
		var arr: Array = def.get("incompatible_with", []) as Array
		if arr.is_empty():
			continue
		if not out.has(gid):
			out[gid] = []
		for other in arr:
			var oid := String(other)
			if oid == "":
				continue
			# Add forward
			if not (out[gid] as Array).has(oid):
				(out[gid] as Array).append(oid)
			# Add symmetric
			if not out.has(oid):
				out[oid] = []
			if not (out[oid] as Array).has(gid):
				(out[oid] as Array).append(gid)
	return out

# One-sentence dialogue strings, used for decision bubbles.
const INTENT_DIALOGUE: Dictionary = {
	"boss": [
		"I want to kill the boss.",
		"Let's take down the boss.",
		"Straight to the boss.",
	],
	"loot": [
		"Let's grab the loot and get out.",
		"I smell treasure nearby.",
		"Keep your eyes open for loot.",
	],
	"explore": [
		"Let's explore the dungeon.",
		"Keep moving, map it all out.",
		"Stay sharp—unknown rooms ahead.",
	],
	"exit": [
		"I'm leaving this dungeon.",
		"Back to the entrance, now.",
		"We're done here—head out.",
	],
}

const GOAL_DIALOGUE: Dictionary = {
	"explore_all_before_boss": [
		"I want to explore every inch of this dungeon.",
		"No shortcuts—check every room.",
		"We explore first, then we fight.",
	],
	"no_flee_until_boss_dead": [
		"We're not leaving until the boss is dead.",
		"We stay until the boss falls.",
		"No retreat until we win.",
	],
	"no_leave_until_full_loot": [
		"I won't leave until my pockets are full.",
		"Not leaving empty-handed.",
		"I want every piece of loot we can carry.",
	],
	"flee_on_any_damage": [
		"One scratch and I'm out of here.",
		"If I get hit, I'm gone.",
		"Not risking it—one hit and I bail.",
	],
}

const DEFECT_DIALOGUE: Array[String] = [
	"I'm not following this plan.",
	"I'm doing this my way.",
	"You can keep marching—I'm splitting off.",
]

const FLEE_DIALOGUE: Array[String] = [
	"That's it—I'm leaving!",
	"Nope, I'm out!",
	"I didn't sign up for this—run!",
]


func get_intent_score() -> Dictionary:
	return INTENT_SCORE.duplicate(true)


func get_intent_stability() -> Dictionary:
	return INTENT_STABILITY.duplicate(true)


func _goal_order_lt(a: String, b: String) -> bool:
	var da: Dictionary = GOAL_DEFS.get(String(a), {}) as Dictionary
	var db: Dictionary = GOAL_DEFS.get(String(b), {}) as Dictionary
	return int(da.get("order", 0)) < int(db.get("order", 0))


func _goal_ids_by_kind(kind: String) -> Array[String]:
	var out: Array[String] = []
	for k in GOAL_DEFS.keys():
		var id := String(k)
		var d: Dictionary = GOAL_DEFS.get(id, {}) as Dictionary
		if d.is_empty():
			continue
		if String(d.get("kind", "")) != String(kind):
			continue
		if not bool(d.get("pickable", true)):
			continue
		out.append(id)
	out.sort_custom(Callable(self, "_goal_order_lt"))
	return out


func base_goal_ids() -> Array[String]:
	return _goal_ids_by_kind("base")


func unique_goal_ids() -> Array[String]:
	return _goal_ids_by_kind("unique")


func get_goal_def(goal_id: String) -> Dictionary:
	return GOAL_DEFS.get(String(goal_id), {}) as Dictionary


func roll_goal_weight(rng: RandomNumberGenerator, goal_id: String) -> int:
	var def := get_goal_def(goal_id)
	if def.is_empty():
		return 0
	var sr: Dictionary = def.get("spawn_roll", {}) as Dictionary
	var base := int(sr.get("base_weight", 0))
	var jitter := int(sr.get("jitter", 0))
	var mult_min := float(sr.get("mult_min", 1.0))
	var mult_max := float(sr.get("mult_max", 1.0))
	var spike_ch := float(sr.get("spike_chance", 0.0))
	var spike_bonus := int(sr.get("spike_bonus", 0))

	var w := base
	if rng != null and jitter > 0:
		w += rng.randi_range(-jitter, jitter)
	var mult := 1.0
	if rng != null:
		mult = rng.randf_range(mult_min, mult_max)
	w = int(round(float(w) * mult))
	if rng != null and spike_ch > 0.0 and rng.randf() <= spike_ch:
		w += spike_bonus
	return w


func roll_goal_params(rng: RandomNumberGenerator, goal_id: String) -> Dictionary:
	var def := get_goal_def(goal_id)
	var pr: Dictionary = def.get("params_roll", {}) as Dictionary
	if pr.is_empty() or rng == null:
		return {}
	var out: Dictionary = {}
	if pr.has("kills_target_min") and pr.has("kills_target_max"):
		out["kills_target"] = rng.randi_range(int(pr.get("kills_target_min")), int(pr.get("kills_target_max")))
	if pr.has("loot_target_min") and pr.has("loot_target_max"):
		out["loot_target"] = rng.randi_range(int(pr.get("loot_target_min")), int(pr.get("loot_target_max")))
	if pr.has("hp_threshold_pct_min") and pr.has("hp_threshold_pct_max"):
		out["hp_threshold_pct"] = rng.randi_range(int(pr.get("hp_threshold_pct_min")), int(pr.get("hp_threshold_pct_max")))
	return out


func pick_unique_goal_ids(rng: RandomNumberGenerator, max_count: int = 2) -> Array[String]:
	# Picks up to max_count unique goals (uniform for now).
	if rng == null:
		return []
	max_count = maxi(0, max_count)
	if max_count <= 0:
		return []
	var pool: Array[String] = unique_goal_ids()
	if pool.is_empty():
		return []
	# Shuffle (Fisher-Yates)
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: String = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	return pool.slice(0, mini(max_count, pool.size()))


func pick_dialogue_for_intent(rng: RandomNumberGenerator, intent_id: String) -> String:
	var arr: Array = INTENT_DIALOGUE.get(String(intent_id), []) as Array
	if arr.is_empty():
		return ""
	if rng == null:
		return String(arr[0])
	return String(arr[rng.randi_range(0, arr.size() - 1)])


func pick_dialogue_for_goal(rng: RandomNumberGenerator, goal_id: String) -> String:
	var def: Dictionary = get_goal_def(String(goal_id))
	var arr: Array = def.get("dialogue", []) as Array
	if arr.is_empty():
		arr = GOAL_DIALOGUE.get(String(goal_id), []) as Array
	if arr.is_empty():
		return ""
	if rng == null:
		return String(arr[0])
	return String(arr[rng.randi_range(0, arr.size() - 1)])


func pick_dialogue_for_defect(rng: RandomNumberGenerator) -> String:
	if DEFECT_DIALOGUE.is_empty():
		return ""
	if rng == null:
		return String(DEFECT_DIALOGUE[0])
	return String(DEFECT_DIALOGUE[rng.randi_range(0, DEFECT_DIALOGUE.size() - 1)])


func pick_dialogue_for_flee(rng: RandomNumberGenerator, goal_id_optional: String = "") -> String:
	# Prefer goal-specific flee line if provided.
	if goal_id_optional != "":
		var g := pick_dialogue_for_goal(rng, goal_id_optional)
		if g != "":
			return g
	if FLEE_DIALOGUE.is_empty():
		return ""
	if rng == null:
		return String(FLEE_DIALOGUE[0])
	return String(FLEE_DIALOGUE[rng.randi_range(0, FLEE_DIALOGUE.size() - 1)])
