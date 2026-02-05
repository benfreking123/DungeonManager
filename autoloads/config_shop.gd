extends Node

# Autoload name (recommended): `config_shop`
#
# Shop offer schema (from config):
# {
#   id: String,              # unique config id
#   kind: "item"|"room",     # item -> PlayerInventory item_id, room -> RoomInventory room_type_id
#   target_id: String,       # item_id or room_type_id
#   cost: Dictionary,        # treasure_item_id -> int amount (supports multiple types)
#   enabled: bool,           # optional (default true)
#   min_s: int, max_s: int,  # optional strength gating
#   rarity_override: String  # optional (common/uncommon/rare/epic/legendary)
# }

const CATALOG_PATH := "res://config/shop_catalog.json"
const RARITY_CURVE_PATH := "res://config/shop_rarity_curve.json"
const RARITY_TIERS := ["common", "uncommon", "rare", "epic", "legendary"]
const DEFAULT_RARITY := "common"

var _catalog_loaded := false
var _catalog_cache: Array[Dictionary] = []
var _rarity_curve_loaded := false
var _rarity_curve_cache: Dictionary = {}


func roll_shop_offers(rng: RandomNumberGenerator, slot_count: int = 8, strength_s: int = 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	slot_count = maxi(0, int(slot_count))
	if slot_count <= 0 or rng == null:
		return out

	var offers := _build_catalog_offers()
	offers = _filter_by_strength(offers, int(strength_s))
	if offers.is_empty():
		return out

	var rarity_weights := _rarity_weights_for_strength(int(strength_s))
	var pool := _build_weighted_pool(offers, rarity_weights)
	if pool.is_empty():
		return out

	var base_pool := pool.duplicate(true)
	for _i in range(slot_count):
		if pool.is_empty():
			pool = base_pool.duplicate(true)
		var picked := _weighted_pick(pool, rng)
		if picked.is_empty():
			break
		out.append(picked.get("offer", {}) as Dictionary)
	return out


func _build_catalog_offers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var catalog := _load_catalog()
	if catalog.is_empty():
		return out

	var item_db := get_node_or_null("/root/ItemDB")
	var room_db := get_node_or_null("/root/RoomDB")
	for entry0 in catalog:
		var entry := entry0 as Dictionary
		if entry.is_empty():
			continue
		if entry.has("enabled") and not bool(entry.get("enabled")):
			continue
		var kind := String(entry.get("kind", ""))
		var target_id := String(entry.get("target_id", ""))
		if kind == "" or target_id == "":
			continue
		if kind != "item" and kind != "room":
			continue

		if kind == "item":
			if item_db == null or item_db.call("get_any_item", target_id) == null:
				continue
		else:
			if room_db == null:
				continue
			var def := room_db.call("get_room_type", target_id) as Dictionary
			if def.is_empty():
				continue

		var rarity := String(entry.get("rarity_override", ""))
		if rarity == "":
			rarity = _resolve_rarity(kind, target_id, item_db, room_db)
		if rarity == "":
			rarity = DEFAULT_RARITY

		var offer_id := String(entry.get("id", ""))
		if offer_id == "":
			offer_id = "%s_%s" % [kind, target_id]

		var cost := entry.get("cost", {}) as Dictionary
		out.append({
			"id": offer_id,
			"kind": kind,
			"target_id": target_id,
			"cost": cost,
			"rarity": rarity,
			"min_s": int(entry.get("min_s", -1)),
			"max_s": int(entry.get("max_s", -1)),
		})
	return out


func _filter_by_strength(offers: Array[Dictionary], strength_s: int) -> Array[Dictionary]:
	if offers.is_empty():
		return offers
	var out: Array[Dictionary] = []
	for offer in offers:
		var min_s := int(offer.get("min_s", -1))
		var max_s := int(offer.get("max_s", -1))
		if min_s >= 0 and strength_s < min_s:
			continue
		if max_s >= 0 and strength_s > max_s:
			continue
		out.append(offer)
	return out


func _resolve_rarity(kind: String, target_id: String, item_db: Node, room_db: Node) -> String:
	if kind == "item":
		if item_db == null:
			return DEFAULT_RARITY
		var res := item_db.call("get_any_item", target_id) as Resource
		if res == null:
			return DEFAULT_RARITY
		var v: Variant = res.get("rarity")
		return String(v) if v != null else DEFAULT_RARITY

	if kind == "room":
		if room_db == null:
			return DEFAULT_RARITY
		var def := room_db.call("get_room_type", target_id) as Dictionary
		return String(def.get("rarity", DEFAULT_RARITY))

	return DEFAULT_RARITY


func _build_weighted_pool(offers: Array[Dictionary], rarity_weights: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if offers.is_empty():
		return out

	var counts: Dictionary = {}
	for offer in offers:
		var r := _normalize_rarity(String(offer.get("rarity", DEFAULT_RARITY)))
		counts[r] = int(counts.get(r, 0)) + 1

	for offer in offers:
		var r := _normalize_rarity(String(offer.get("rarity", DEFAULT_RARITY)))
		var count := int(counts.get(r, 0))
		if count <= 0:
			continue
		var w := float(rarity_weights.get(r, 0.0))
		if w <= 0.0:
			continue
		out.append({
			"offer": offer,
			"weight": w / float(count),
		})
	return out


func _weighted_pick(pool: Array[Dictionary], rng: RandomNumberGenerator) -> Dictionary:
	if pool.is_empty():
		return {}
	var total := 0.0
	for p in pool:
		total += float(p.get("weight", 0.0))
	if total <= 0.0:
		return {}
	var roll := rng.randf_range(0.0, total)
	var acc := 0.0
	for i in range(pool.size()):
		acc += float(pool[i].get("weight", 0.0))
		if roll <= acc:
			var picked := pool[i] as Dictionary
			pool.remove_at(i)
			return picked
	# Fallback if numerical drift happens.
	return pool.pop_back() as Dictionary if not pool.is_empty() else {}


func _rarity_weights_for_strength(strength_s: int) -> Dictionary:
	var curve := _load_rarity_curve()
	var s_min := float(curve.get("s_min", 0.0))
	var s_max := float(curve.get("s_max", 100.0))
	var t := 0.0
	if s_max > s_min:
		t = clampf((float(strength_s) - s_min) / (s_max - s_min), 0.0, 1.0)

	var w_min := curve.get("weights_at_min", {}) as Dictionary
	var w_max := curve.get("weights_at_max", {}) as Dictionary
	var out: Dictionary = {}
	for r in RARITY_TIERS:
		var a := float(w_min.get(r, 0.0))
		var b := float(w_max.get(r, 0.0))
		out[r] = lerp(a, b, t)
	return out


func _normalize_rarity(rarity: String) -> String:
	var r := rarity.strip_edges().to_lower()
	if r in RARITY_TIERS:
		return r
	return DEFAULT_RARITY


func _load_catalog() -> Array[Dictionary]:
	if _catalog_loaded:
		return _catalog_cache
	_catalog_loaded = true
	_catalog_cache.clear()

	var data := _load_json_dict(CATALOG_PATH)
	var entries_var: Variant = data.get("offers", [])
	if typeof(entries_var) != TYPE_ARRAY:
		push_warning("config_shop: catalog offers missing or not an array: %s" % CATALOG_PATH)
		return _catalog_cache
	var entries: Array = entries_var as Array
	for e in entries:
		if typeof(e) == TYPE_DICTIONARY:
			_catalog_cache.append(e as Dictionary)
	return _catalog_cache


func _load_rarity_curve() -> Dictionary:
	if _rarity_curve_loaded:
		return _rarity_curve_cache
	_rarity_curve_loaded = true
	_rarity_curve_cache = {}

	var data := _load_json_dict(RARITY_CURVE_PATH)
	if data.is_empty():
		_rarity_curve_cache = {
			"s_min": 0,
			"s_max": 100,
			"weights_at_min": { "common": 70, "uncommon": 25, "rare": 5, "epic": 0, "legendary": 0 },
			"weights_at_max": { "common": 30, "uncommon": 30, "rare": 20, "epic": 15, "legendary": 5 },
		}
	else:
		_rarity_curve_cache = data
	return _rarity_curve_cache


func _load_json_dict(res_path: String) -> Dictionary:
	var f := FileAccess.open(res_path, FileAccess.READ)
	if f == null:
		push_warning("config_shop: missing config file: %s" % res_path)
		return {}
	var text := f.get_as_text()
	var data: Variant = JSON.parse_string(text)
	if typeof(data) == TYPE_DICTIONARY:
		return data as Dictionary
	return {}
