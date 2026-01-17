extends Resource
class_name MonsterItem

@export var id: String = ""
@export var display_name: String = ""
@export var icon: Texture2D

@export var threat_profile: ThreatProfile

@export var max_hp: int = 1
@export var attack_damage: int = 1
@export var attack_interval: float = 1.0

# Pixel/world distance required to hit a target in combat.
@export var range: float = 40.0

# Size units for room capacity + spawn time scaling.
@export var size: float = 1.0


