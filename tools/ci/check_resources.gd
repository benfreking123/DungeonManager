extends SceneTree

# Simple CI-style validation for Godot projects:
# - Loads/parses all GDScript files under common code directories.
# - Loads all scenes under common scene directories.
# - Exits with non-zero status on the first failure.
#
# Run (Godot 4.x):
#   godot --headless --path . -s res://tools/ci/check_resources.gd

const SCRIPT_DIRS: PackedStringArray = [
	"res://autoloads",
	"res://scripts",
	"res://ui",
]

const SCENE_DIRS: PackedStringArray = [
	"res://scenes",
	"res://ui",
]

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Godot CI: resource validation ===")

	_failed = false

	print("--- Stage: script parse check (.gd) ---")
	for base in SCRIPT_DIRS:
		_load_all_with_extension(base, "gd")

	print("--- Stage: scene load check (.tscn) ---")
	for base in SCENE_DIRS:
		_load_all_with_extension(base, "tscn")

	if _failed:
		print("=== Godot CI: FAILED ===")
		quit(1)
	else:
		print("=== Godot CI: OK ===")
		quit(0)


func _load_all_with_extension(base_dir: String, ext_no_dot: String) -> void:
	# Treat missing directories as non-fatal; projects differ.
	if DirAccess.open(base_dir) == null:
		return

	for path in _walk_files(base_dir, false):
		if path.get_extension().to_lower() != ext_no_dot:
			continue

		var res := ResourceLoader.load(path)
		if res == null:
			_failed = true
			push_error("Failed to load: %s" % path)


func _walk_files(root_dir: String, fatal_on_missing: bool = true) -> PackedStringArray:
	var out: PackedStringArray = []
	var da := DirAccess.open(root_dir)
	if da == null:
		if fatal_on_missing:
			_failed = true
			push_error("Failed to open directory: %s" % root_dir)
		return out

	da.list_dir_begin()
	while true:
		var name := da.get_next()
		if name.is_empty():
			break

		# Skip hidden folders like .godot/
		if name.begins_with("."):
			continue

		var path := root_dir.path_join(name)
		if da.current_is_dir():
			out.append_array(_walk_files(path, true))
		else:
			out.append(path)

	da.list_dir_end()
	return out


