extends Resource
class_name AdventurerClass

@export var id: String = ""
@export var display_name: String = ""
@export var icon: Texture2D

@export var threat_profile: ThreatProfile

@export var hp_max: int = 10
@export var attack_damage: int = 2
@export var attack_interval: float = 1.0

# Pixel/world distance required to hit a target in combat.
@export var range: float = 40.0

# Internal stats (used for behavior tuning; may influence combat later).
# Scale is configured in `game_config` (default narrow range around 10).
@export var intelligence: int = 10
@export var strength: int = 10
@export var agility: int = 10