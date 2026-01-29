extends Node

# Provides profile selection for start inventory and JSON loading utilities.

const SETTING := "game/start_inventory_profile"
const VALID_VALUES := ["base", "test"]

func _ready() -> void:
	# Ensure the ProjectSetting exists and is visible as an enum in the editor.
	if not ProjectSettings.has_setting(SETTING):
		ProjectSettings.set_setting(SETTING, "base")
	ProjectSettings.add_property_info({
		"name": SETTING,
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": "base,test"
	})


func get_profile() -> String:
	# Priority: CLI flag > config file > ProjectSetting
	# 1) Command-line: --inventory_profile=test
	for arg in OS.get_cmdline_args():
		if String(arg).begins_with("--inventory_profile="):
			var v := String(arg).substr("--inventory_profile=".length())
			if v in VALID_VALUES:
				if Engine.has_singleton("DbgLog"):
					DbgLog.debug("ConfigService: profile from CLI = %s" % v, "inventory")
				return v
	# 2) File override: res://config/start_inventory/profile.json { "profile": "base|test" }
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
	# 3) Project setting (editor default)
	var value := str(ProjectSettings.get_setting(SETTING, "base"))
	if value in VALID_VALUES:
		if Engine.has_singleton("DbgLog"):
			DbgLog.debug("ConfigService: profile from ProjectSetting = %s" % value, "inventory")
		return value
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
