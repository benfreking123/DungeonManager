extends PanelContainer

@onready var _label: Label = $Label

const LIFE_S := 1.35


func show_text(t: String) -> void:
	if _label != null:
		_label.text = t
	visible = true
	modulate.a = 1.0

	# Resize to content a bit (bounded).
	await get_tree().process_frame
	if _label != null:
		custom_minimum_size = Vector2(clampf(_label.size.x + 16.0, 60.0, 260.0), clampf(_label.size.y + 10.0, 18.0, 70.0))

	var tw := create_tween()
	tw.tween_interval(max(0.1, LIFE_S - 0.35))
	tw.tween_property(self, "modulate:a", 0.0, 0.35)
	tw.finished.connect(func():
		if is_instance_valid(self):
			queue_free()
	)

