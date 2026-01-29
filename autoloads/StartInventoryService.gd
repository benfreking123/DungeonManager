extends Node

# Central service for resolving profile, loading, merging, and validating start inventories.
# Provides merged item/room arrays and helpers to convert to counts.

const BASE_PATH := "res://config/start_inventory/base.json"
const TEST_PATH := "res://config/start_inventory/test.json"


func get_merged_items() -> Array:
	var base := ConfigService.load_config(BASE_PATH)
	var overlay := {}
	if ConfigService.get_profile() == "test":
		overlay = ConfigService.load_config(TEST_PATH)
	var items_base: Array = base.get("items", []) if typeof(base.get("items", [])) == TYPE_ARRAY else []
	var items_overlay: Array = overlay.get("items", []) if typeof(overlay.get("items", [])) == TYPE_ARRAY else []
	var merged := _merge_sum(items_base, items_overlay)
	return _validate_items(merged)


func get_merged_rooms() -> Array:
	var base := ConfigService.load_config(BASE_PATH)
	var overlay := {}
	if ConfigService.get_profile() == "test":
		overlay = ConfigService.load_config(TEST_PATH)
	var rooms_base: Array = base.get("rooms", []) if typeof(base.get("rooms", [])) == TYPE_ARRAY else []
	var rooms_overlay: Array = overlay.get("rooms", []) if typeof(overlay.get("rooms", [])) == TYPE_ARRAY else []
	var merged := _merge_sum(rooms_base, rooms_overlay)
	return _validate_rooms(merged)


func to_item_counts(items: Array) -> Dictionary:
	var counts: Dictionary = {}
	for it in items:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var id := String(it.get("id", ""))
		var q := int(it.get("quantity", 0))
		if id == "" or q <= 0:
			continue
		counts[id] = int(counts.get(id, 0)) + q
	return counts


func to_room_counts(rooms: Array) -> Dictionary:
	var counts: Dictionary = {}
	for r in rooms:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var id := String(r.get("id", ""))
		var q := int(r.get("quantity", 0))
		if id == "" or q <= 0:
			continue
		counts[id] = int(counts.get(id, 0)) + q
	return counts


func _merge_sum(a: Array, b: Array) -> Array:
	var id_to_qty: Dictionary = {}
	for e in a:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var id := String(e.get("id", ""))
		var q := int(e.get("quantity", 0))
		if id == "" or q <= 0:
			continue
		id_to_qty[id] = int(id_to_qty.get(id, 0)) + q
	for e in b:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var id := String(e.get("id", ""))
		var q := int(e.get("quantity", 0))
		if id == "" or q <= 0:
			continue
		id_to_qty[id] = int(id_to_qty.get(id, 0)) + q
	var out: Array = []
	for id in id_to_qty.keys():
		out.append({"id": id, "quantity": int(id_to_qty[id])})
	return out


func _validate_items(items: Array) -> Array:
	var item_db := get_node_or_null("/root/ItemDB")
	if item_db == null:
		return items
	var out: Array = []
	for it in items:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var id := String(it.get("id", ""))
		var q := int(it.get("quantity", 0))
		if id == "" or q <= 0:
			continue
		if item_db.call("get_any_item", id) == null:
			push_warning("StartInventoryService: unknown item id '%s' — skipping" % id)
			continue
		out.append({"id": id, "quantity": q})
	return out


func _validate_rooms(rooms: Array) -> Array:
	var room_db := get_node_or_null("/root/RoomDB")
	if room_db == null:
		return rooms
	var out: Array = []
	for r in rooms:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var id := String(r.get("id", ""))
		var q := int(r.get("quantity", 0))
		if id == "" or q <= 0:
			continue
		var def: Dictionary = room_db.call("get_room_type", id) as Dictionary
		if def.is_empty():
			push_warning("StartInventoryService: unknown room type '%s' — skipping" % id)
			continue
		out.append({"id": id, "quantity": q})
	return out

