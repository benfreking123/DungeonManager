extends PanelContainer

signal restart_requested()

@onready var _restart_btn: Button = $VBox/Restart


func _ready() -> void:
	_restart_btn.pressed.connect(func(): restart_requested.emit())


