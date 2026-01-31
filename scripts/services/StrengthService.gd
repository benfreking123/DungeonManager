extends RefCounted
class_name StrengthService

# Computes player Strength S from day number (configured in `game_config`).

func compute_strength_s_for_day(day_index: int, cfg: Node) -> int:
	# Backwards-compatible wrapper that now includes treasure bonus in the returned total.
	var brk := compute_strength_breakdown(day_index, cfg)
	return int(brk.get("total", 0))


# Returns a breakdown of Strength components for the given day:
# {
#   base: int,               # from PARTY_SCALING(day)
#   treasure_count: int,     # number of treasures installed in treasure rooms
#   treasure_bonus: int,     # treasure_count * day
#   total: int               # clamp(base + treasure_bonus, 0..STRENGTH_DAY_MAX)
# }
func compute_strength_breakdown(day_index: int, cfg: Node) -> Dictionary:
	var day := maxi(1, int(day_index))
	var max_s := 999999
	if cfg != null and cfg.has_method("get"):
		max_s = int(cfg.get("STRENGTH_DAY_MAX"))

	# Base scaling from config
	var base_f := 0.0
	if cfg != null and cfg.has_method("PARTY_SCALING"):
		base_f = float(cfg.call("PARTY_SCALING", day))
	var base_i := clampi(int(floor(base_f)), 0, max_s)

	# Treasure bonus: +1 S per treasure in treasure rooms, per day (permanent daily gain).
	var dg: Node = null
	var item_db: Node = null
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var root := (ml as SceneTree).root
		if root != null:
			dg = root.get_node_or_null("DungeonGrid")
			item_db = root.get_node_or_null("ItemDB")
	var t_count := _count_treasures_in_treasure_rooms(dg, item_db)
	var t_bonus := int(t_count) * day

	var total_i := clampi(base_i + t_bonus, 0, max_s)
	return {
		"base": base_i,
		"treasure_count": int(t_count),
		"treasure_bonus": int(t_bonus),
		"total": total_i,
	}


func _count_treasures_in_treasure_rooms(dg: Node, item_db: Node) -> int:
	if dg == null:
		return 0
	var rooms: Array = dg.get("rooms") as Array
	if rooms.is_empty():
		return 0
	var count := 0
	for r0 in rooms:
		var r := r0 as Dictionary
		if r.is_empty():
			continue
		if String(r.get("kind", "")) != "treasure":
			continue
		var slots: Array = r.get("slots", []) as Array
		for s0 in slots:
			var sd := s0 as Dictionary
			if sd.is_empty():
				continue
			var id := String(sd.get("installed_item_id", ""))
			if id == "":
				continue
			# Validate the installed item is actually a treasure (defensive).
			if item_db != null and item_db.has_method("get_item_kind"):
				if String(item_db.call("get_item_kind", id)) != "treasure":
					continue
			count += 1
	return count
