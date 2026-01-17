extends Node

enum Level { DEBUG, INFO, WARN, ERROR }

# Code-driven configuration: enable/disable and minimum level per category.
# This is the ONLY place categories are configured.
#
# Example usage:
#   DbgLog.log("Start day pressed", "game_state")
#   DbgLog.warn("Missing boss room", "game_state")
var enabled: Dictionary = {
	# category: { enabled: bool, level: Level }
	"game_state": { "enabled": true, "level": Level.DEBUG },
	"rooms": { "enabled": true, "level": Level.DEBUG },
	"monsters": { "enabled": true, "level": Level.DEBUG },
	"adventurers": { "enabled": true, "level": Level.DEBUG },
	"ui": { "enabled": true, "level": Level.DEBUG },
}


func is_enabled(category: String) -> bool:
	return bool((enabled.get(category, {}) as Dictionary).get("enabled", false))


func min_level(category: String) -> int:
	return int((enabled.get(category, {}) as Dictionary).get("level", Level.DEBUG))


func set_enabled(category: String, v: bool) -> void:
	var d: Dictionary = enabled.get(category, {}) as Dictionary
	d["enabled"] = v
	enabled[category] = d


func set_level(category: String, level: int) -> void:
	var d: Dictionary = enabled.get(category, {}) as Dictionary
	d["level"] = int(level)
	enabled[category] = d


func log(message: String, category: String, level: int = Level.DEBUG) -> void:
	if not is_enabled(category):
		return
	var lvl: int = int(level)
	if lvl < min_level(category):
		return
	var label := _level_label(lvl)
	print("[%s][%s] %s" % [category, label, message])


func debug(message: String, category: String) -> void:
	self.log(message, category, Level.DEBUG)


func info(message: String, category: String) -> void:
	self.log(message, category, Level.INFO)


func warn(message: String, category: String) -> void:
	self.log(message, category, Level.WARN)


func error(message: String, category: String) -> void:
	self.log(message, category, Level.ERROR)


func _level_label(level: int) -> String:
	match int(level):
		Level.DEBUG:
			return "DEBUG"
		Level.INFO:
			return "INFO"
		Level.WARN:
			return "WARN"
		Level.ERROR:
			return "ERROR"
		_:
			return "LOG"
