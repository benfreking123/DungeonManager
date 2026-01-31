extends Node

# Centralized tunables (keep hard-coded values here).
# Autoload name: `game_config`

# 30% chance an adventurer drops 1 treasure when they die.
const ADV_DEATH_TREASURE_DROP_CHANCE: float = 1

# TreasureRoom special effect id (used for power capacity bonus).
const TREASURE_ROOM_EFFECT_ID: String = "treasure_room_power_capacity_plus_1"

# Each Treasure installed in a TreasureRoom slot grants this much power capacity (stacks).
const TREASURE_ROOM_POWER_CAPACITY_PER_TREASURE: int = 1

# Base power capacity (before treasure-based scaling).
const BASE_POWER_CAPACITY: int = 10

# Party/adventure scaling
const MAX_PARTIES: int = 5
const MAX_PARTY_SIZE: int = 5

# Soft cap includes micro-parties created by defections.
const SOFT_PARTY_CAP: int = 15

# Stolen treasure inventory per adventurer (member) defaults.
const STOLEN_INV_CAP_DEFAULT: int = 2

# === Adventurer stats + behavior knobs ===
# Base stat scale (kept narrow so traits matter). Default “normal” is 10.
const ADV_STAT_MIN: int = 8
const ADV_STAT_MAX: int = 12
const ADV_STAT_DEFAULT: int = 10
# Small per-day jitter applied around class baselines when generating members.
# (rolled stat = clamp(class_base + rng[-delta..+delta], MIN..MAX))
const ADV_STAT_ROLL_DELTA: int = 1

# Path decision “mistake” (epsilon-greedy) settings.
# Higher Intelligence reduces this chance.
const ADV_PATH_MISTAKE_CHANCE_BASE: float = 0.35
# Floor so even geniuses can very rarely err (set to 0 for perfect play at high INT).
const ADV_PATH_MISTAKE_MIN_CHANCE: float = 0.01

# Strength scaling (day-based):
# Strength is computed from day number via PARTY_SCALING(day).
# The curve is exponential (doubles roughly every S_DOUBLING_DAYS).
const STRENGTH_DAY_MAX: int = 999999

# Daily Strength S scaling (exponential ~2x every 5 days)
# S(1) ≈ 10, doubles roughly every S_DOUBLING_DAYS days.
const S_BASE: float = 10.0
const S_DOUBLING_DAYS: float = 5.0
const S_R: float = pow(2.0, 1.0 / S_DOUBLING_DAYS)

func PARTY_SCALING(day: int) -> float:
	# Returns the total daily strength budget S for the given day.
	var d: int = maxi(1, day)
	var s := S_BASE * pow(S_R, float(d - 1))
	return min(float(STRENGTH_DAY_MAX), s)

# Party generation weights/knobs (favor size 4; expose variance controls)
const PARTY_SIZE_WEIGHT_DEFAULTS := {
	4: 7,
	3: 4,
	5: 3,
	2: 2,
	1: 1
}
const PARTY_STRENGTH_SIZE_EXP: float = 1.1
const PARTY_STRENGTH_NOISE_PCT: float = 0.10

# Strength tiers: maps total Strength S -> party count + party-size distribution.
# Party size distribution is a weighted table (bias toward 4).
# Shape:
# {
#   "min_s": int, "max_s": int,
#   "party_count": int,
#   "party_size_weights": Dictionary[int, int]
# }
const PARTY_SCALING_TIERS: Array[Dictionary] = [
	# Early: one strong party of ~4.
	{ "min_s": 0, "max_s": 4, "party_count": 1, "party_size_weights": { 4: 10, 3: 2, 5: 1 } },
	# Mid: two parties, mostly 4.
	{ "min_s": 5, "max_s": 10, "party_count": 2, "party_size_weights": { 4: 12, 3: 2, 5: 2, 2: 1 } },
	# Late: three parties.
	{ "min_s": 11, "max_s": 20, "party_count": 3, "party_size_weights": { 4: 14, 5: 3, 3: 2, 2: 1 } },
	# Endgame-ish: four parties.
	{ "min_s": 21, "max_s": 999999, "party_count": 4, "party_size_weights": { 4: 16, 5: 4, 3: 2, 2: 1 } },
]

# Item ids for treasures.
const TREASURE_ID_WARRIOR := "treasure_warrior"
const TREASURE_ID_MAGE := "treasure_mage"
const TREASURE_ID_PRIEST := "treasure_priest"
const TREASURE_ID_ROGUE := "treasure_rogue"

const TREASURE_ID_BY_CLASS := {
	"warrior": TREASURE_ID_WARRIOR,
	"mage": TREASURE_ID_MAGE,
	"priest": TREASURE_ID_PRIEST,
	"rogue": TREASURE_ID_ROGUE,
}


func treasure_id_for_class(class_id: String) -> String:
	# Base treasure never drops right now. Unknown/empty class ids drop nothing.
	return String(TREASURE_ID_BY_CLASS.get(class_id, ""))

# === Class spawn weighting (configurable) ===
# Base weights before any treasure influence (sum arbitrary; UI normalizes to percentages).
const CLASS_BASE_WEIGHTS := {
	"warrior": 25,
	"mage": 25,
	"priest": 25,
	"rogue": 25,
}
# Per installed class-themed treasure, add this percentage-equivalent to the class weight.
# Example: 3 wizard treasures => +3.0 to mage weight.
const CLASS_TREASURE_WEIGHT_PCT_PER_ITEM: float = 1.0


# === History/Identity configuration ===
# Days after a flee that a returnee will be scheduled for by default.
const RETURN_DAYS: int = 2
# Default return buffs applied to scheduled returnees (merged additively).
const RETURN_BUFFS := { "hp_bonus": 2 }
# Data directories/files (res:// maps to project root).
const NAME_CONFIG_DIR: String = "res://data/names/"
const BIO_TEMPLATES_PATH: String = "res://data/bio_templates.json"
const EPITHETS_PATH: String = "res://data/epithets.json"
const DIALOGUE_CONFIG_PATH: String = "res://data/dialogue_rules.json"
# Max in-memory history entries (session-only).
const HISTORY_MAX_ENTRIES: int = 500
