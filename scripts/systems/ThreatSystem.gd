extends RefCounted

# Simple per-room threat/aggro tracker.
# Designed to be extended later (healing threat, taunts, threat decay rules, etc.).

# room_id -> monster_key -> adv_id -> threat(float)
var _threat: Dictionary = {}

# Threat decay. 1.0 = no decay, 0.0 = instant clear.
const THREAT_DECAY_PER_SECOND := 0.98
# How much raw threat is generated per point of damage dealt by an adventurer.
const THREAT_PER_DAMAGE := 0.35


func reset() -> void:
	_threat.clear()


func ensure_room(room_id: int) -> void:
	if room_id == 0:
		return
	if not _threat.has(room_id):
		_threat[room_id] = {}


func reset_room(room_id: int) -> void:
	if room_id == 0:
		return
	_threat.erase(room_id)


func decay_room(room_id: int, dt: float) -> void:
	if room_id == 0:
		return
	if not _threat.has(room_id):
		return
	var rooms: Dictionary = _threat[room_id]
	if rooms.is_empty():
		return
	var k := pow(THREAT_DECAY_PER_SECOND, maxf(0.0, dt))
	for mon_key in rooms.keys():
		var by_adv: Dictionary = rooms.get(mon_key, {})
		for adv_id in by_adv.keys():
			by_adv[adv_id] = float(by_adv.get(adv_id, 0.0)) * k
		rooms[mon_key] = by_adv
	_threat[room_id] = rooms


func on_adv_damage(room_id: int, monster_key: int, adv_id: int, amount: int) -> void:
	if room_id == 0 or monster_key == 0 or adv_id == 0:
		return
	if amount <= 0:
		return
	ensure_room(room_id)
	var by_mon: Dictionary = _threat.get(room_id, {})
	var by_adv: Dictionary = by_mon.get(monster_key, {})
	by_adv[adv_id] = float(by_adv.get(adv_id, 0.0)) + float(amount) * THREAT_PER_DAMAGE
	by_mon[monster_key] = by_adv
	_threat[room_id] = by_mon


func choose_adv_target(room_id: int, monster_key: int, candidates: Array, monster_world_pos: Vector2, monster_range: float = 0.0, profile: ThreatProfile = null) -> Node2D:
	# Returns the best candidate by combined threat + distance scoring; falls back to nearest.
	var best: Node2D = null
	var best_score := -1e18

	var by_mon: Dictionary = _threat.get(room_id, {})
	var by_adv: Dictionary = by_mon.get(monster_key, {})

	var dmg_w := 1.0
	var dist_w := 0.0
	var melee_cut := 80.0
	var melee_mult := 1.0
	if profile != null:
		dmg_w = float(profile.damage_weight)
		dist_w = float(profile.distance_weight)
		melee_cut = float(profile.melee_range_cutoff)
		melee_mult = float(profile.melee_distance_weight_multiplier)
	var is_melee := (monster_range > 0.0 and monster_range <= melee_cut)

	for c in candidates:
		if c == null or not is_instance_valid(c):
			continue
		var adv := c as Node2D
		var adv_id := int(adv.get_instance_id())
		var t := float(by_adv.get(adv_id, 0.0))
		var d := monster_world_pos.distance_to(adv.global_position)
		# Distance score: closer is better; very heavy when melee.
		var closeness := 1.0 / (d + 1.0)
		var dist_term := closeness * dist_w * (melee_mult if is_melee else 1.0)
		var score := t * dmg_w + dist_term
		if score > best_score:
			best_score = score
			best = adv

	# If no one has threat yet (or table is empty), best_threat will be 0 for some candidate
	# only if they exist in the table; ensure we still pick something sensible.
	if best == null:
		for c2 in candidates:
			if c2 != null and is_instance_valid(c2):
				best = c2 as Node2D
				break
	return best

