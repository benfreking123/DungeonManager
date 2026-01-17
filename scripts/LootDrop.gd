extends Node2D

# Simple visual for ground loot (no collisions).

@export var item_id: String = ""

@onready var _sprite: Sprite2D = $Sprite2D


func set_icon(tex: Texture2D) -> void:
	if _sprite != null:
		_sprite.texture = tex

