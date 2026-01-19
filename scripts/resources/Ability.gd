extends Resource
class_name Ability

enum AbilityTrigger {
	WhenFlee,
	WhenDamaged,
	PartyMemberDie,
	PartyMemberDamaged,
	EnteringMonsterRoom,
	EnteringTrapRoom,
	EnteringBossRoom,
	LootGathered,
	FullLoot,
	WhenMonster,
	WhenTrap,
	WhenAttack,
	WhenAttacked,
}

@export var ability_id: String
@export_enum(
	"WhenFlee",
	"WhenDamaged",
	"PartyMemberDie",
	"PartyMemberDeath",
	"PartyMemberLow",
	"PartyMemberHalf",
	"PartyMemberDamaged",
	"WhenMonster",
	"WhenTrap",
	"WhenBoss",
	"EnteringMonsterRoom",
	"EnteringTrapRoom",
	"EnteringBossRoom",
	"LootGathered",
	"FullLoot",
	"WhenAttack",
	"WhenAttacked"
) var trigger_name: String = "WhenDamaged"
@export var cooldown_s: float = 0.0 # 0=no wait; -1 = single-use/day regardless of charges
@export var charges_per_day: int = 1
@export var s_delta: int = 0
@export var params: Dictionary
@export var cast_time_s: float = 0.0 # time before effect fires (0.0 = instant)
