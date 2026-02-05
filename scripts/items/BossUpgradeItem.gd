extends Resource
class_name BossUpgradeItem

@export var upgrade_id: String = ""
@export var display_name: String = ""
@export var icon: Texture2D
@export_enum("common", "uncommon", "rare", "epic", "legendary") var rarity: String = "common"

# Unique effect identifier used by the boss upgrade system.
@export var effect_id: String = ""
@export var value: float = 0.0

# Optional extra tunables for upgrades that need more than one number.
@export var chance: float = 0.0
@export var cooldown_s: float = 0.0
@export var range_px: float = 0.0
@export var delay_s: float = 0.0

