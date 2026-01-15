extends Node

# Data-driven room definitions. For MVP we keep this in-code; later we can swap to Resources/JSON.

const ROOM_TYPES := {
	# Entrance is special: we render a 2x1 "cap" above ground, but it occupies 2x2 inside the dungeon grid.
	"entrance": { "id": "entrance", "label": "Entrance", "size": Vector2i(2, 2), "power_cost": 0, "kind": "entrance", "max_slots": 0 },
	"hall": { "id": "hall", "label": "Hallway", "size": Vector2i(1, 1), "power_cost": 1, "kind": "hall", "max_slots": 0 },
	"monster": { "id": "monster", "label": "Monster", "size": Vector2i(3, 2), "power_cost": 3, "kind": "monster", "max_slots": 2 },
	"trap": { "id": "trap", "label": "Trap", "size": Vector2i(2, 2), "power_cost": 2, "kind": "trap", "max_slots": 2 },
	"treasure": { "id": "treasure", "label": "Treasure", "size": Vector2i(2, 2), "power_cost": 2, "kind": "treasure", "max_slots": 0 },
	"boss": { "id": "boss", "label": "Boss", "size": Vector2i(2, 2), "power_cost": 0, "kind": "boss", "max_slots": 0 },
}


func get_room_type(id: String) -> Dictionary:
	return ROOM_TYPES.get(id, {})


func list_room_types() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k in ROOM_TYPES.keys():
		out.append(ROOM_TYPES[k])
	return out



