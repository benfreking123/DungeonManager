extends PanelContainer

@onready var _tex: TextureRect = $TextureRect

var _has_flip_v: bool = false
var _is_night: bool = false
var _flip_tween: Tween = null

const FLIP_DURATION_S := 0.22


func _ready() -> void:
	if _tex != null:
		_has_flip_v = _node_has_property(_tex, "flip_v")
		# Keep pivot correct for fallback scale-flip.
		_tex.resized.connect(_on_tex_resized)
		_on_tex_resized()

	_apply_phase(null, false)

	# Prefer the autoload singleton, but keep this robust if this scene is used elsewhere.
	if GameState != null and GameState.has_signal("phase_changed"):
		var cb := Callable(self, "_on_phase_changed")
		if not GameState.phase_changed.is_connected(cb):
			GameState.phase_changed.connect(cb)


func _on_phase_changed(new_phase: int) -> void:
	_apply_phase(new_phase, true)


func _apply_phase(phase_override: Variant = null, animate: bool = false) -> void:
	if _tex == null:
		return

	var phase_value: int
	if phase_override != null:
		phase_value = int(phase_override)
	elif GameState != null:
		phase_value = int(GameState.phase)
	else:
		phase_value = 0

	var is_night := true
	if GameState != null:
		is_night = phase_value != int(GameState.Phase.DAY)

	_set_night(is_night, animate)


func _set_night(is_night: bool, animate: bool) -> void:
	if _tex == null:
		return

	if _is_night == is_night:
		# Already correct; don't restart the tween.
		return
	_is_night = is_night

	# Cancel any in-flight flip so we always end in the correct state.
	if _flip_tween != null:
		_flip_tween.kill()
		_flip_tween = null

	if not animate:
		_apply_flip_property(is_night)
		_reset_scale_after_flip()
		return

	_on_tex_resized()

	# Animate a quick "rotate/flip" feel: squash -> swap -> unsquash.
	var base_scale := _tex.scale
	var base_y := absf(float(base_scale.y))
	if base_y < 0.0001:
		base_y = 1.0
	base_scale.y = base_y
	_tex.scale = base_scale

	var mid_scale := Vector2(base_scale.x, 0.0)
	var end_scale := Vector2(base_scale.x, base_y)

	_flip_tween = create_tween()
	_flip_tween.set_trans(Tween.TRANS_SINE)
	_flip_tween.set_ease(Tween.EASE_IN_OUT)
	_flip_tween.tween_property(_tex, "scale", mid_scale, FLIP_DURATION_S * 0.5)
	_flip_tween.tween_callback(func() -> void:
		_apply_flip_property(is_night)
	)
	_flip_tween.tween_property(_tex, "scale", end_scale, FLIP_DURATION_S * 0.5)


func _apply_flip_property(is_night: bool) -> void:
	if _tex == null:
		return
	# Godot 4: TextureRect has flip_v. If not, fall back to a scale flip.
	if _has_flip_v:
		_tex.set("flip_v", is_night)
		return
	# Fallback: sign of scale.y represents night/day.
	var s := _tex.scale
	var ay := absf(float(s.y))
	s.y = (-ay) if is_night else ay
	_tex.scale = s


func _reset_scale_after_flip() -> void:
	# Ensure scale is sane (especially if a flip happened mid-tween).
	if _tex == null:
		return
	var s := _tex.scale
	if _has_flip_v:
		s.y = absf(float(s.y))
	else:
		var ay := absf(float(s.y))
		s.y = (-ay) if _is_night else ay
	_tex.scale = s


func _on_tex_resized() -> void:
	# For scale-flip fallback, mirror around the horizontal axis through the center.
	if _tex == null:
		return
	_tex.pivot_offset = _tex.size * 0.5


func _node_has_property(obj: Object, prop_name: String) -> bool:
	if obj == null or prop_name == "":
		return false
	for p in obj.get_property_list():
		if String(p.get("name", "")) == prop_name:
			return true
	return false

