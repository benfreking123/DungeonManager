extends Node

# Config of adventurer Traits: stat modifiers and S impact.
# Each entry:
# {
#   "label": String,
#   "mods": {
#     "flat": { stat_name: int },    # e.g., { "attack_damage": 1, "armor": 1 }
#     "pct":  { stat_name: int },    # percent, e.g., { "hp_max": 25 } == +25%
#   },
#   "s_delta": int,                  # how much this trait shifts S (±)
#   "w": int,                        # selection weight for generator
# }
#
# Initial trait set from the spec.
const TRAITS := {
	"+1_damage": {
		"label": "+1 Damage",
		"mods": { "flat": { "attack_damage": 1 }, "pct": {} },
		"s_delta": 1,
		"w": 10,
	},
	"-1_damage": {
		"label": "-1 Damage",
		"mods": { "flat": { "attack_damage": -1 }, "pct": {} },
		"s_delta": -1,
		"w": 6,
	},
	"+2_damage": {
		"label": "+2 Damage",
		"mods": { "flat": { "attack_damage": 2 }, "pct": {} },
		"s_delta": 2,
		"w": 7,
	},
	"+1_armor": {
		"label": "+1 Armor",
		"mods": { "flat": { "armor": 1 }, "pct": {} },
		"s_delta": 1,
		"w": 8,
	},
	"+25pct_hp": {
		"label": "+25% HP",
		"mods": { "flat": {}, "pct": { "hp_max": 25 } },
		"s_delta": 2,
		"w": 6,
	},
	"-25pct_hp": {
		"label": "-25% HP",
		"mods": { "flat": {}, "pct": { "hp_max": -25 } },
		"s_delta": -2,
		"w": 5,
	},
	"+1_intelligence": {
		"label": "+1 Intelligence",
		"mods": { "flat": { "intelligence": 1 }, "pct": {} },
		"s_delta": 1,
		"w": 7,
	},
	"+1_strength": {
		"label": "+1 Strength",
		"mods": { "flat": { "strength": 1 }, "pct": {} },
		"s_delta": 1,
		"w": 7,
	},
	"+1_agility": {
		"label": "+1 Agility",
		"mods": { "flat": { "agility": 1 }, "pct": {} },
		"s_delta": 1,
		"w": 7,
	},
	"+10pct_speed": {
		"label": "+10% Speed",
		"mods": { "flat": {}, "pct": { "speed_mult": 10 } },
		"s_delta": 1,
		"w": 6,
	},
	"+1_all_stats": {
		"label": "+1 All Stats",
		"mods": { "flat": { "intelligence": 1, "strength": 1, "agility": 1 }, "pct": {} },
		"s_delta": 3,
		"w": 3,
	},
}


func trait_ids() -> Array[String]:
	var out: Array[String] = []
	for k in TRAITS.keys():
		out.append(String(k))
	return out


func get_trait_def(id: String) -> Dictionary:
	return TRAITS.get(String(id), {}) as Dictionary


func trait_weight(id: String) -> int:
	var d: Dictionary = get_trait_def(id)
	return int(d.get("w", 0))


func trait_s_delta(id: String) -> int:
	var d: Dictionary = get_trait_def(id)
	return int(d.get("s_delta", 0))
