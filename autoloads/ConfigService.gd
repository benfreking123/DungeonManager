extends Node

# Provides profile selection for start inventory and JSON loading utilities.

const VALID_VALUES := ["base", "test"]

func _ready() -> void:
	# No ProjectSettings or CLI registration; profile is resolved via file only.
	pass


func get_profile() -> String:
	# File override: res://config/start_inventory/profile.json { "profile": "base|test" }
	var override_path := "res://config/start_inventory/profile.json"
	if FileAccess.file_exists(override_path):
		var f2 := FileAccess.open(override_path, FileAccess.READ)
		if f2 != null:
			var txt := f2.get_as_text()
			var data: Variant = JSON.parse_string(txt)
			if typeof(data) == TYPE_DICTIONARY:
				var prof := String((data as Dictionary).get("profile", ""))
				if prof in VALID_VALUES:
					if Engine.has_singleton("DbgLog"):
						DbgLog.debug("ConfigService: profile from file = %s" % prof, "inventory")
					return prof
	return "base"


func load_config(res_path: String) -> Dictionary:
	var f := FileAccess.open(res_path, FileAccess.READ)
	if f == null:
		push_warning("ConfigService: missing config file: %s" % res_path)
		return {}
	var text := f.get_as_text()
	var data: Variant = JSON.parse_string(text)
	if typeof(data) == TYPE_DICTIONARY:
		return data as Dictionary
	return {}
