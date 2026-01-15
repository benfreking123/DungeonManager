extends RefCounted
class_name ThemePalette

# Central helper for non-Control nodes that still want to use the project's Theme.
# This keeps Node2D draw code in sync with `project.godot` -> gui/theme/custom.

const THEME_PATH := "res://ui/DungeonManagerTheme.tres"

static var _theme: Theme = null


static func _get_theme() -> Theme:
	if _theme != null:
		return _theme
	var res: Resource = load(THEME_PATH)
	if res is Theme:
		_theme = res as Theme
	return _theme


static func color(type: String, name: String, fallback: Color) -> Color:
	var t := _get_theme()
	if t != null and t.has_color(name, type):
		return t.get_color(name, type)
	return fallback


static func constant(type: String, name: String, fallback: int) -> int:
	var t := _get_theme()
	if t != null and t.has_constant(name, type):
		return t.get_constant(name, type)
	return fallback
