extends Node

# Autoload name (recommended): `config_shop`
#
# Shop offer schema:
# {
#   id: String,            # unique config id
#   kind: "item"|"room",   # item -> PlayerInventory item_id, room -> RoomInventory room_type_id
#   target_id: String,     # item_id or room_type_id
#   cost: Dictionary,      # treasure_item_id -> int amount (supports multiple types)
# }

const ITEM_POOL: Array[Dictionary] = [
	# --- Traps ---
	{
		"id": "trap_spike",
		"kind": "item",
		"target_id": "spike_trap",
		"cost": { "treasure_rogue": 1 },
	},
	{
		"id": "trap_pit",
		"kind": "item",
		"target_id": "floor_pit",
		"cost": { "treasure_rogue": 1, "treasure_warrior": 1 },
	},

	# --- Monsters ---
	{
		"id": "mon_skeleton",
		"kind": "item",
		"target_id": "skeleton",
		"cost": { "treasure_warrior": 1 },
	},
	{
		"id": "mon_slime",
		"kind": "item",
		"target_id": "slime",
		"cost": { "treasure_mage": 1 },
	},
	{
		"id": "mon_zombie",
		"kind": "item",
		"target_id": "zombie",
		"cost": { "treasure_priest": 1 },
	},

	# --- Boss upgrades ---
	{
		"id": "boss_upgrade_health",
		"kind": "item",
		"target_id": "health",
		"cost": { "treasure_warrior": 1, "treasure_priest": 1 },
	},
	{
		"id": "boss_upgrade_damage",
		"kind": "item",
		"target_id": "damage",
		"cost": { "treasure_warrior": 1, "treasure_mage": 1 },
	},

	# --- Room pieces ---
	{
		"id": "room_hall_plus",
		"kind": "room",
		"target_id": "hall_plus",
		"cost": { "treasure_mage": 1 },
	},
	{
		"id": "room_hall_t_left",
		"kind": "room",
		"target_id": "hall_t_left",
		"cost": { "treasure_rogue": 1 },
	},
	{
		"id": "room_monster",
		"kind": "room",
		"target_id": "monster",
		"cost": { "treasure_warrior": 1, "treasure_rogue": 1 },
	},
	{
		"id": "room_trap",
		"kind": "room",
		"target_id": "trap",
		"cost": { "treasure_rogue": 1, "treasure_mage": 1 },
	},
]


func roll_shop_offers(rng: RandomNumberGenerator, slot_count: int = 8) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	slot_count = maxi(0, int(slot_count))
	if slot_count <= 0 or rng == null:
		return out
	if ITEM_POOL.is_empty():
		return out

	# Prefer sampling without replacement; if pool < slot_count, allow repeats.
	var pool: Array[Dictionary] = ITEM_POOL.duplicate(true)
	# Shuffle (Fisher-Yates)
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Dictionary = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp

	for i in range(slot_count):
		if i < pool.size():
			out.append(pool[i] as Dictionary)
		else:
			# Repeat from the shuffled pool if needed.
			out.append(pool[rng.randi_range(0, pool.size() - 1)] as Dictionary)
	return out
