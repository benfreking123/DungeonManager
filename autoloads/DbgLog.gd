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
	"party": { "enabled": true, "level": Level.DEBUG },
	"fog": { "enabled": true, "level": Level.DEBUG },
	"theft": { "enabled": true, "level": Level.DEBUG },
	"ui": { "enabled": true, "level": Level.DEBUG },
	# Combat/encounter + boss-upgrade detail logs (safe to turn off in one place).
	"combat": { "enabled": true, "level": Level.INFO },
	"boss_upgrades": { "enabled": true, "level": Level.INFO },
}

var _once_keys: Dictionary = {} # String -> bool
var _throttle_next_s: Dictionary = {} # String -> float


func _now_s() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func once(key: String, message: String, category: String, level: int = Level.DEBUG) -> void:
	# Log a message only once per runtime (use a stable key).
	if bool(_once_keys.get(key, false)):
		return
	_once_keys[key] = true
	self.log(message, category, level)


func throttle(key: String, interval_s: float, message: String, category: String, level: int = Level.DEBUG) -> void:
	# Log a message at most once per interval per key.
	var now := _now_s()
	var next_ok := float(_throttle_next_s.get(key, -1.0))
	if next_ok >= 0.0 and now < next_ok:
		return
	_throttle_next_s[key] = now + maxf(0.0, interval_s)
	self.log(message, category, level)


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
