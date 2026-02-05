extends Resource
class_name TreasureItem

@export var id: String = ""
@export var display_name: String = ""
@export var icon: Texture2D
@export_enum("common", "uncommon", "rare", "epic", "legendary") var rarity: String = "common"

# Optional: which class this treasure is themed for ("" means generic).
@export var class_id: String = ""

