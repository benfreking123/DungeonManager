extends Control

signal hover_entered(slot: Control, offer: Dictionary, screen_pos: Vector2)
signal hover_exited()
signal purchase_pressed(slot: Control, offer: Dictionary, screen_pos: Vector2)

@onready var _icon_btn: TextureButton = $VBox/IconButton
@onready var _cost: Label = $VBox/Cost

var _offer: Dictionary = {}
var _icon: Texture2D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _icon_btn != null:
		_icon_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		_icon_btn.pressed.connect(_on_pressed)
		_icon_btn.mouse_entered.connect(func():
			hover_entered.emit(self, _offer, get_viewport().get_mouse_position())
		)
		_icon_btn.mouse_exited.connect(func():
			hover_exited.emit()
		)
	# Fallback hover if button is missing.
	mouse_entered.connect(func():
		hover_entered.emit(self, _offer, get_viewport().get_mouse_position())
	)
	mouse_exited.connect(func():
		hover_exited.emit()
	)


func set_offer(offer: Dictionary, icon: Texture2D, cost_text: String) -> void:
	_offer = offer.duplicate(true) if offer != null else {}
	_icon = icon
	if _icon_btn != null:
		_icon_btn.texture_normal = icon
	_cost.text = String(cost_text)


func get_icon() -> Texture2D:
	return _icon


func _on_pressed() -> void:
	purchase_pressed.emit(self, _offer, get_viewport().get_mouse_position())

