extends RefCounted
class_name TreasureStealService

# Implements stealing installed Treasure items from room slots during DAY.
# IMPORTANT: DungeonGrid.uninstall_item_from_slot is BUILD-only, so we mutate the room dict
# and call DungeonGrid.set_room_by_id(...) instead.

func steal_from_room(room: Dictionary, dungeon_grid: Node, item_db: Node, thieves: Array[AdventurerBrain]) -> Dictionary:
	# Returns:
	# {
	#   room_id: int,
	#   stolen: Array[Dictionary] # { adv_id:int, item_id:String }
	# }
	var out := { "room_id": int(room.get("id", 0)), "stolen": [] }
	if dungeon_grid == null or item_db == null:
		return out
	if room.is_empty():
		return out
	var room_id := int(room.get("id", 0))
	if room_id == 0:
		return out
	if thieves.is_empty():
		return out

	var slots: Array = room.get("slots", [])
	if slots.is_empty():
		return out

	# Build list of stealable slot indices.
	var stealable: Array[int] = []
	for i in range(slots.size()):
		var sd := slots[i] as Dictionary
		if sd.is_empty():
			continue
		var installed := String(sd.get("installed_item_id", ""))
		if installed == "":
			continue
		var kind := String(item_db.call("get_item_kind", installed)) if item_db.has_method("get_item_kind") else ""
		if kind != "treasure":
			continue
		stealable.append(i)

	if stealable.is_empty():
		return out

	var stolen_events: Array[Dictionary] = []

	# Round-robin pointer
	var idx := 0

	for slot_idx in stealable:
		# Find next thief with capacity.
		var loops := 0
		var picked: AdventurerBrain = null
		while loops < thieves.size():
			var t := thieves[idx % thieves.size()]
			idx += 1
			loops += 1
			if t != null and t.can_steal_more():
				picked = t
				break
		if picked == null:
			break # everyone is full

		var sd2 := slots[slot_idx] as Dictionary
		var item_id := String(sd2.get("installed_item_id", ""))
		if item_id == "":
			continue
		if not picked.add_stolen(item_id):
			continue
		sd2["installed_item_id"] = ""
		slots[slot_idx] = sd2
		stolen_events.append({ "adv_id": int(picked.adv_id), "item_id": item_id })

	if stolen_events.is_empty():
		return out

	# Persist slot changes safely during DAY.
	var room2 := room.duplicate(true)
	room2["slots"] = slots
	dungeon_grid.call("set_room_by_id", room_id, room2)

	out["stolen"] = stolen_events
	return out

