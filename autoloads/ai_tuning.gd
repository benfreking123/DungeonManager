extends Node

# Centralized knobs for AI, party behavior, and path/pathing noise.
# All values are safe defaults; systems should fallback to legacy configs if this
# autoload is not present.

# Path decision “mistake” (epsilon-greedy) settings. Higher INT reduces chance.
const PATH_NOISE := {
	"base": 0.30,  # low-INT mistake chance (was 0.35)
	"floor": 0.02, # high-INT minimum mistake chance (was 0.01)
}

# Party-level behavior knobs.
const PARTY := {
	"leash_cells": 3,              # cohesion distance before leashing toward leader
	"retarget_cooldown_s": 0.6,    # soft delay after reaching a goal before retarget
	"defect_pressure_threshold": 60, # min pressure to consider defection
	"defect_chance_cap": 0.95,     # max probability cap for defection
	"soft_defy_rooms": 3,          # rooms a soft-defying member will persist
	"defect_recruit_chance": 0.5,  # chance to recruit other low-morality members
}

# Intent scoring knobs (migrated from config_goals.gd INTENT_SCORE).
const INTENT_SCORE := {
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

# Intent stability knobs (migrated from config_goals.gd INTENT_STABILITY),
# with slightly higher switch margin to reduce flip-flopping.
const INTENT_STABILITY := {
	"switch_margin": 22,    # was 15
	"clamp_member_min": -300,
	"clamp_member_max": 500,
}

# Hazard penalties applied when a room hazard is remembered.
const HAZARD_WEIGHT_PENALTIES := {
	"trap": -1,
	"monster": -1,
}

# Flee-on-damage: delay by morality bracket.
# Higher morality hesitates; low morality flees immediately (delay 0).
const FLEE_ON_DAMAGE := {
	# Ordered by descending min
	"delay_by_morality": [
		{ "min": 4, "delay": 2 },      # morality >= 4 -> delay 2 rooms
		{ "min": 2, "delay": 1 },      # morality >= 2 -> delay 1 room
		{ "min": -999, "delay": 0 },   # else -> immediate
	]
}

# Exit likelihood modifiers based on current stolen loot.
const EXIT_WITH_LOOT := {
	"has_any_bonus": 10,         # extra bias once any loot held
	"per_item_bonus": 35,        # add to exit score per item (capped)
	"per_item_resist_decay": 6,  # reduce morality resist per item
	"bonus_max_items": 6,        # max items to count toward per-item bonus/decay
}

# Ground loot pickup radius in pixels.
const LOOT_PICKUP := {
	"radius_px": 18.0
}

# ---- Helpers (lightweight getters; keep call sites tidy) ----

func epsilon_base() -> float:
	return float(PATH_NOISE.get("base", 0.30))

func epsilon_floor() -> float:
	return float(PATH_NOISE.get("floor", 0.02))

func party_leash_cells() -> int:
	return int(PARTY.get("leash_cells", 3))

func retarget_cooldown_s() -> float:
	return float(PARTY.get("retarget_cooldown_s", 0.6))

func defect_pressure_threshold() -> int:
	return int(PARTY.get("defect_pressure_threshold", 60))

func defect_chance_cap() -> float:
	return float(PARTY.get("defect_chance_cap", 0.95))

func soft_defy_rooms() -> int:
	return int(PARTY.get("soft_defy_rooms", 3))

func defect_recruit_chance() -> float:
	return float(PARTY.get("defect_recruit_chance", 0.5))

func get_intent_score() -> Dictionary:
	return INTENT_SCORE.duplicate(true)

func get_intent_stability() -> Dictionary:
	return INTENT_STABILITY.duplicate(true)

func hazard_penalty_for(kind: String) -> int:
	return int(HAZARD_WEIGHT_PENALTIES.get(String(kind), 0))

func flee_delay_for_morality(m: int) -> int:
	var arr: Array = FLEE_ON_DAMAGE.get("delay_by_morality", []) as Array
	if arr.is_empty():
		# Fallback to legacy: >=4 -> 2, >=2 -> 1, else -> 0
		if m >= 4:
			return 2
		if m >= 2:
			return 1
		return 0
	for br0 in arr:
		var br := br0 as Dictionary
		var minv := int(br.get("min", -999))
		if m >= minv:
			return int(br.get("delay", 0))
	return 0

func exit_with_loot_params() -> Dictionary:
	return EXIT_WITH_LOOT.duplicate(true)

func loot_pickup_radius() -> float:
	return float(LOOT_PICKUP.get("radius_px", 18.0))

