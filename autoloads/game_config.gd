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
