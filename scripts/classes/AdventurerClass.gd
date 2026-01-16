extends Resource
class_name AdventurerClass

@export var id: String = ""
@export var display_name: String = ""
@export var icon: Texture2D

@export var hp_max: int = 10
@export var attack_damage: int = 2
@export var attack_interval: float = 1.0

# Pixel/world distance required to hit a target in combat.
@export var range: float = 40.0
