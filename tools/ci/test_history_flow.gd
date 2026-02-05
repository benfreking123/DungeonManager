extends Node

func _ready() -> void:
	print("History flow test (manual):")
	var sim := get_node_or_null("/root/Simulation")
	var cfg := get_node_or_null("/root/game_config")
	if sim == null:
		print("Simulation not found; open main scene and run.")
		return
	if cfg == null:
		print("game_config not found; ensure autoloads are set.")
	# Start a day; observe in UI:
	if sim.has_method("start_day"):
		sim.call("start_day")
	print("Right-click an adventurer to view identity tooltip (name/epithet/origin/bio).")
	print("Force some damage/exit to log flee/exit; after RETURN_DAYS, a returnee should spawn with a dialogue line.")
	print("If day_plan schedules a hero for this day, check history for hero_arrived entries.")
	# Print a few history lines if available:
	if sim.has_method("get_history_events"):
		var events: Array = sim.call("get_history_events")
		var n: int = min(10, events.size())
		for i in range(n):
			var e := events[i] as Dictionary
			print("Event: ", e)
