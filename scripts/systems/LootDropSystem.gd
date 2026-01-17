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

	var tr: TreasureItem = _item_db.call("get_treasure", tid) as TreasureItem
	if tr == null or tr.icon == null:
		return

	var node := _loot_scene.instantiate() as Node2D
	_world_canvas.add_child(node)

	# Convert world position into WorldCanvas-local space.
	var inv: Transform2D = _world_canvas.get_global_transform().affine_inverse()
	node.position = inv * world_pos
	node.z_index = 8
	node.z_as_relative = false

	node.set("item_id", tid)
	node.call("set_icon", tr.icon)

	_active_loot.append({ "node": node, "item_id": tid })


func has_loot() -> bool:
	return not _active_loot.is_empty()


func collect_all_to(target_world_pos: Vector2, on_done: Callable) -> void:
	if _active_loot.is_empty():
		if on_done.is_valid():
			on_done.call()
		return

	var remaining := _active_loot.size()
	for d in _active_loot:
		var node: Node2D = d.get("node", null) as Node2D
		var item_id: String = String(d.get("item_id", ""))
		if node == null or not is_instance_valid(node):
			remaining -= 1
			continue

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
			remaining -= 1
			if remaining <= 0:
				_active_loot.clear()
				if on_done.is_valid():
					on_done.call()
		)

