extends RefCounted

# Owns the "ground loot" lifecycle:
# - roll drops on adventurer death
# - spawn visible loot icons at death position
# - collect + animate to UI target at end of day

const COLLECT_DUR := 0.55

var _world_canvas: CanvasItem
var _item_db: Node
var _cfg: Node
var _loot_scene: PackedScene = preload("res://scenes/LootDrop.tscn")

# Array[Dictionary] { node: Node2D, item_id: String }
var _active_loot: Array[Dictionary] = []


func setup(world_canvas: CanvasItem, item_db: Node, cfg: Node) -> void:
	_world_canvas = world_canvas
	_item_db = item_db
	_cfg = cfg


func reset() -> void:
	for d in _active_loot:
		var n: Variant = d.get("node", null)
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
	_active_loot.clear()


func on_adventurer_died(world_pos: Vector2, class_id: String) -> void:
	if _world_canvas == null or _item_db == null or _cfg == null:
		return

	var chance := float(_cfg.get("ADV_DEATH_TREASURE_DROP_CHANCE"))
	if randf() > chance:
		return

	# Base treasure never drops right now. Unknown classes drop nothing.
	var tid := ""
	if _cfg.has_method("treasure_id_for_class"):
		tid = String(_cfg.call("treasure_id_for_class", class_id))
	if tid == "":
		return
	spawn_treasure_drop(world_pos, tid)


func spawn_treasure_drop(world_pos: Vector2, treasure_item_id: String) -> void:
	# Spawns a ground loot node for a specific treasure item id (used for forced drops).
	if _world_canvas == null or _item_db == null:
		return
	if treasure_item_id == "":
		return

	var tr: TreasureItem = _item_db.call("get_treasure", treasure_item_id) as TreasureItem
	if tr == null or tr.icon == null:
		return

	var node := _loot_scene.instantiate() as Node2D
	_world_canvas.add_child(node)

	# Convert world position into WorldCanvas-local space.
	var inv: Transform2D = _world_canvas.get_global_transform().affine_inverse()
	node.position = inv * world_pos
	node.z_index = 8
	node.z_as_relative = false

	node.set("item_id", treasure_item_id)
	node.call("set_icon", tr.icon)

	_active_loot.append({ "node": node, "item_id": treasure_item_id })


# Collects any ground loot within radius of the given adventurer (same parent coordinate space).
# Returns Array[String] of item_ids picked up.
func collect_nearby_for_adv(adv: Node2D, radius_px: float) -> Array[String]:
	var out: Array[String] = []
	if adv == null or not is_instance_valid(adv):
		return out
	var r := maxf(0.0, float(radius_px))
	var r2 := r * r
	if _active_loot.is_empty():
		return out
	var keep: Array[Dictionary] = []
	for d0 in _active_loot:
		var d := d0 as Dictionary
		var node: Node2D = d.get("node", null) as Node2D
		var item_id := String(d.get("item_id", ""))
		var picked := false
		if node != null and is_instance_valid(node) and item_id != "":
			# Compare in WorldCanvas-local space (both adv and node are children of it).
			var dist2 := (node.position - adv.position).length_squared()
			if dist2 <= r2:
				out.append(item_id)
				if is_instance_valid(node):
					node.queue_free()
				picked = true
		if not picked:
			keep.append(d)
	_active_loot = keep
	return out


func has_loot() -> bool:
	return not _active_loot.is_empty()


func collect_all_to(target_world_pos: Vector2, on_done: Callable) -> void:
	if _active_loot.is_empty():
		if on_done.is_valid():
			on_done.call()
		return

	# Use shared mutable state to avoid fragile closure-captured locals.
	# Goal: ensure `on_done` is called exactly once, even if some nodes are invalid.
	var state: Dictionary = { "remaining": 0, "done": false }

	var finish_once := func() -> void:
		if bool(state.get("done", false)):
			return
		state["done"] = true
		_active_loot.clear()
		if DbgLog != null and DbgLog.is_enabled("game_state"):
			DbgLog.debug("Loot collection done (callback)", "game_state")
		if on_done.is_valid():
			on_done.call()

	for d in _active_loot:
		var node: Node2D = d.get("node", null) as Node2D
		var item_id: String = String(d.get("item_id", ""))
		if node == null or not is_instance_valid(node):
			continue

		state["remaining"] = int(state.get("remaining", 0)) + 1

		# Credit inventory at the end of the animation.
		var t := node.create_tween()
		t.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		t.tween_property(node, "global_position", target_world_pos, COLLECT_DUR)
		t.parallel().tween_property(node, "scale", Vector2.ONE * 0.05, COLLECT_DUR)
		t.parallel().tween_property(node, "modulate:a", 0.0, COLLECT_DUR)
		t.finished.connect(func():
			if item_id != "":
				PlayerInventory.refund(item_id, 1)
			if is_instance_valid(node):
				node.queue_free()
			state["remaining"] = int(state.get("remaining", 0)) - 1
			if int(state.get("remaining", 0)) <= 0:
				finish_once.call()
		)

	# If nothing was animating (all nodes invalid), finish immediately.
	if int(state.get("remaining", 0)) <= 0:
		finish_once.call()

