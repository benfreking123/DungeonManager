extends Resource
class_name RoomType

@export var id: String = ""
@export var label: String = ""
@export var size: Vector2i = Vector2i.ONE
@export var power_cost: int = 0
@export var kind: String = ""
@export var max_slots: int = 0
@export var effect_id: String = ""
@export_enum("common", "uncommon", "rare", "epic", "legendary") var rarity: String = "common"

# Monster spawning knobs (used by monster rooms; also used by boss rooms for minion spawns).
@export var monster_capacity: int = 3
# Spawn interval is (monster.size * monster_cooldown_per_size) seconds.
@export var monster_cooldown_per_size: float = 5.0
