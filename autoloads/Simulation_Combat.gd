extends RefCounted

# Combat subsystem extracted from Simulation.gd.
# Handles:
# - room_id -> combat state
# - join combat on room entry (only if monsters exist)
# - warmup delay before attacks
# - purely-visual formation positioning
# - tick combat + cleanup

const COMBAT_WARMUP_SECONDS := 1.0
const COMBAT_MOVE_SPEED := 220.0

const DEFAULT_MELEE_RANGE := 40.0

# When units are out of range, we steer them toward an offset position near the target.
# For melee ranges, we MUST close to contact distance (not a % of range), otherwise two
# melee units on opposite sides can stabilize at a distance > range and never hit.
const MELEE_RANGE_CUTOFF := 80.0
const MELEE_CONTACT_DISTANCE := 8.0
const RANGED_STANDOFF_RATIO := 0.9

# Small motion noise to make fights feel less robotic.
const MOVE_REACTION_DELAY_MIN := 0.05
const MOVE_REACTION_DELAY_MAX := 0.25
const WANDER_RADIUS_PX := 5.0
const WANDER_REROLL_MIN := 0.35
const WANDER_REROLL_MAX := 0.95
const ROOM_INTERIOR_PAD_PX := 6.0

const RANGED_KITE_HIT_WINDOW := 0.85
const RANGED_KITE_EXTRA_DISTANCE := 60.0

var combats_by_room_id: Dictionary = {}

var _dungeon_view: Control
var _dungeon_grid: Node
var _simulation: Node
var _threat: RefCounted
var _monster_roster: RefCounted


func setup(dungeon_view: Control, dungeon_grid: Node, simulation: Node, monster_roster: RefCounted) -> void:
	_dungeon_view = dungeon_view
	_dungeon_grid = dungeon_grid
	_simulation = simulation
	_threat = preload("res://scripts/systems/ThreatSystem.gd").new()
	_monster_roster = monster_roster


func reset() -> void:
	combats_by_room_id.clear()
	if _threat != null:
		_threat.call("reset")


func is_room_in_combat(room_id: int) -> bool:
	return combats_by_room_id.has(room_id)


func join_room(room: Dictionary, adv: Node2D) -> void:
	var room_id: int = int(room.get("id", 0))
	if room_id == 0:
		return

	# Only enter combat if monsters currently exist in this room.
	if _monster_roster == null:
		return
	var monsters: Array = _monster_roster.call("get_monsters_in_room", room_id)
	if monsters.is_empty():
		return

	var combat: Dictionary = combats_by_room_id.get(room_id, {})
	if combat.is_empty():
		# Warmup: wait a bit before attacks start, and let units slide into position.
		var rng := RandomNumberGenerator.new()
		rng.seed = int(Time.get_ticks_usec()) ^ (room_id * 1103515245)
		combat = {
			"room_id": room_id,
			"participants": [],
			"adv_attack_timers": {},
			"warmup_remaining": COMBAT_WARMUP_SECONDS,
			"adv_targets": {},  # adv_instance_id -> world pos
			"mon_targets": {},  # actor_instance_id -> world pos
			"adv_move_pause": {},  # adv_instance_id -> seconds until retarget allowed
			"mon_move_pause": {},  # actor_instance_id -> seconds until retarget allowed
			"adv_wander_offset": {},  # adv_instance_id -> local offset
			"mon_wander_offset": {},  # actor_instance_id -> local offset
			"adv_wander_t": {},  # adv_instance_id -> seconds until reroll
			"mon_wander_t": {},  # actor_instance_id -> seconds until reroll
			"rng": rng,
			"room_rect_local": Rect2(),
			"adv_recently_hit": {}, # adv_instance_id -> seconds remaining
		}
		if _simulation != null and _simulation.has_signal("combat_started"):
			_simulation.emit_signal("combat_started", room_id)
		DbgLog.once(
			"combat_started:%d" % room_id,
			"Combat started room_id=%d (warmup=%.2fs participants=0 monsters=%d)" % [
				room_id,
				float(COMBAT_WARMUP_SECONDS),
				monsters.size(),
			],
			"combat",
			DbgLog.Level.INFO
		)

	var participants: Array = combat.get("participants", [])
	if not participants.has(adv):
		participants.append(adv)
	combat["participants"] = participants

	_assign_combat_positions(room, combat)
	combats_by_room_id[room_id] = combat

	adv.call("enter_combat", room_id)
	DbgLog.log("Adventurer entered combat room_id=%d monsters=%d" % [room_id, monsters.size()], "monsters")


func on_monster_spawned(room_id: int) -> void:
	if not combats_by_room_id.has(room_id):
		return
	if _dungeon_grid == null:
		return
	var room: Dictionary = _dungeon_grid.call("get_room_by_id", room_id) as Dictionary
	var combat: Dictionary = combats_by_room_id[room_id]
	_assign_combat_positions(room, combat)
	combats_by_room_id[room_id] = combat


func tick(dt: float, room_spawners_by_room_id: Dictionary) -> void:
	var to_remove: Array[int] = []
	for k in combats_by_room_id.keys():
		var room_id: int = int(k)
		var combat: Dictionary = combats_by_room_id[room_id]
		var alive := _tick_one_combat(room_id, combat, dt, room_spawners_by_room_id)
		if not alive:
			to_remove.append(room_id)
		else:
			combats_by_room_id[room_id] = combat
	for rid in to_remove:
		combats_by_room_id.erase(rid)


func _tick_one_combat(room_id: int, combat: Dictionary, dt: float, room_spawners_by_room_id: Dictionary) -> bool:
	if _monster_roster == null:
		return false
	var monsters: Array = _monster_roster.call("get_monsters_in_room", room_id)

	var participants: Array = combat.get("participants", [])
	var p2: Array[Node2D] = []
	for p in participants:
		if is_instance_valid(p):
			p2.append(p)
	participants = p2
	combat["participants"] = participants
	if participants.is_empty():
		if _simulation != null and _simulation.has_signal("combat_ended"):
			_simulation.emit_signal("combat_ended", room_id)
		DbgLog.once(
			"combat_ended:%d:no_participants" % room_id,
			"Combat ended room_id=%d (reason=no_participants)" % room_id,
			"combat",
			DbgLog.Level.INFO
		)
		return false

	if monsters.is_empty():
		for p in participants:
			if is_instance_valid(p):
				p.call("exit_combat")
		if _threat != null:
			_threat.call("reset_room", room_id)
		if _simulation != null and _simulation.has_signal("combat_ended"):
			_simulation.emit_signal("combat_ended", room_id)
		DbgLog.once(
			"combat_ended:%d:no_monsters" % room_id,
			"Combat ended room_id=%d (reason=no_monsters)" % room_id,
			"combat",
			DbgLog.Level.INFO
		)
		return false

	_tick_motion_noise(combat, dt)
	_tick_recent_hits(combat, dt)

	# Visual staging: slide units to formation spots.
	_animate_combat_positions(combat, dt)

	# Delay attacks briefly when combat starts (pure feel/animation).
	var warm: float = float(combat.get("warmup_remaining", 0.0))
	if warm > 0.0:
		warm = max(0.0, warm - dt)
		combat["warmup_remaining"] = warm
		return true

	if _threat != null:
		_threat.call("decay_room", room_id, dt)
	_tick_adv_attacks(room_id, combat, dt)
	_tick_monster_attacks(room_id, combat, dt)

	# remove dead monsters
	var any_alive := false
	for mon in monsters:
		var mi := mon as MonsterInstance
		if mi == null:
			continue
		if mi.is_alive():
			any_alive = true
			continue
			# Boss death triggers game over.
		if mi.is_boss():
				if _simulation != null and _simulation.has_signal("boss_killed"):
					_simulation.emit_signal("boss_killed")
		if mi.actor != null and is_instance_valid(mi.actor):
			mi.actor.queue_free()
		_monster_roster.call("remove", mi.instance_id)

	if not any_alive:
		# Notify Simulation: attribute monster clears to participants (first pass).
		if _simulation != null and _simulation.has_method("_on_monster_room_cleared"):
			var adv_ids: Array[int] = []
			for p0 in participants:
				if p0 != null and is_instance_valid(p0):
					adv_ids.append(int((p0 as Node2D).get_instance_id()))
			var killed := monsters.size()
			_simulation.call("_on_monster_room_cleared", room_id, adv_ids, killed)
		# Reset monster spawn cooldown when combat ends (prevents immediate respawn as party leaves).
		if room_spawners_by_room_id.has(room_id):
			var rec: Dictionary = room_spawners_by_room_id[room_id]
			# New spawner shape: per-room record with per-slot spawners.
			var spawners: Array = rec.get("spawners", [])
			for i in range(spawners.size()):
				var sd := spawners[i] as Dictionary
				if sd.is_empty():
					continue
				sd["spawn_timer"] = 0.0
				spawners[i] = sd
			rec["spawners"] = spawners
			room_spawners_by_room_id[room_id] = rec
		for p in participants:
			if is_instance_valid(p):
				p.call("exit_combat")
		if _threat != null:
			_threat.call("reset_room", room_id)
		if _simulation != null and _simulation.has_signal("combat_ended"):
			_simulation.emit_signal("combat_ended", room_id)
		DbgLog.once(
			"combat_ended:%d:all_monsters_dead" % room_id,
			"Combat ended room_id=%d (reason=all_monsters_dead)" % room_id,
			"combat",
			DbgLog.Level.INFO
		)
		return false

	return true


func _tick_recent_hits(combat: Dictionary, dt: float) -> void:
	var hit: Dictionary = combat.get("adv_recently_hit", {})
	for k in hit.keys():
		hit[k] = maxf(0.0, float(hit.get(k, 0.0)) - dt)
	combat["adv_recently_hit"] = hit


func _ensure_rng(combat: Dictionary) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = combat.get("rng", null) as RandomNumberGenerator
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.seed = int(Time.get_ticks_usec()) ^ (int(combat.get("room_id", 0)) * 1103515245)
		combat["rng"] = rng
	return rng


func _clamp_to_room_rect(combat: Dictionary, p_local: Vector2) -> Vector2:
	var r: Rect2 = combat.get("room_rect_local", Rect2()) as Rect2
	if r == Rect2():
		return p_local
	var minx := r.position.x
	var maxx := r.position.x + r.size.x
	var miny := r.position.y
	var maxy := r.position.y + r.size.y
	return Vector2(clampf(p_local.x, minx, maxx), clampf(p_local.y, miny, maxy))


func _tick_motion_noise(combat: Dictionary, dt: float) -> void:
	# Decrement reaction delays and occasionally re-roll wander offsets so units feel alive.
	var rng := _ensure_rng(combat)

	var adv_pause: Dictionary = combat.get("adv_move_pause", {})
	for k in adv_pause.keys():
		adv_pause[k] = maxf(0.0, float(adv_pause.get(k, 0.0)) - dt)
	combat["adv_move_pause"] = adv_pause

	var mon_pause: Dictionary = combat.get("mon_move_pause", {})
	for k2 in mon_pause.keys():
		mon_pause[k2] = maxf(0.0, float(mon_pause.get(k2, 0.0)) - dt)
	combat["mon_move_pause"] = mon_pause

	var adv_targets: Dictionary = combat.get("adv_targets", {})
	var adv_off: Dictionary = combat.get("adv_wander_offset", {})
	var adv_t: Dictionary = combat.get("adv_wander_t", {})
	for aid in adv_targets.keys():
		var t := float(adv_t.get(aid, 0.0)) - dt
		if t <= 0.0 or not adv_off.has(aid):
			adv_off[aid] = Vector2(rng.randf_range(-WANDER_RADIUS_PX, WANDER_RADIUS_PX), rng.randf_range(-WANDER_RADIUS_PX, WANDER_RADIUS_PX))
			t = rng.randf_range(WANDER_REROLL_MIN, WANDER_REROLL_MAX)
		adv_t[aid] = t
	combat["adv_wander_offset"] = adv_off
	combat["adv_wander_t"] = adv_t

	var mon_targets: Dictionary = combat.get("mon_targets", {})
	var mon_off: Dictionary = combat.get("mon_wander_offset", {})
	var mon_t: Dictionary = combat.get("mon_wander_t", {})
	for mid in mon_targets.keys():
		var t2 := float(mon_t.get(mid, 0.0)) - dt
		if t2 <= 0.0 or not mon_off.has(mid):
			mon_off[mid] = Vector2(rng.randf_range(-WANDER_RADIUS_PX, WANDER_RADIUS_PX), rng.randf_range(-WANDER_RADIUS_PX, WANDER_RADIUS_PX))
			t2 = rng.randf_range(WANDER_REROLL_MIN, WANDER_REROLL_MAX)
		mon_t[mid] = t2
	combat["mon_wander_offset"] = mon_off
	combat["mon_wander_t"] = mon_t


func _tick_adv_attacks(room_id: int, combat: Dictionary, dt: float) -> void:
	var participants: Array = combat.get("participants", [])
	var monsters: Array = _monster_roster.call("get_monsters_in_room", room_id) if _monster_roster != null else []
	if participants.is_empty() or monsters.is_empty():
		return
	var adv_timers: Dictionary = combat.get("adv_attack_timers", {})
	var adv_targets: Dictionary = combat.get("adv_targets", {})
	var adv_pause: Dictionary = combat.get("adv_move_pause", {})
	var adv_hit: Dictionary = combat.get("adv_recently_hit", {})
	var rng0 := _ensure_rng(combat)

	for p in participants:
		if not is_instance_valid(p):
			continue
		var pid: int = int(p.get_instance_id())
		var t: float = float(adv_timers.get(pid, 0.0)) - dt
		if t <= 0.0:
			# Adventurers hit ONE monster per attack.
			var dmg: int = int(p.get("attack_damage"))
			var rng: float = float(p.get("range"))
			if rng <= 0.0:
				rng = DEFAULT_MELEE_RANGE

			# Find closest alive monster that has a valid actor for distance checks.
			var best_i := -1
			var best_dist := 1e18
			var best_actor_pos := Vector2.ZERO
			var adv_pos := (p as Node2D).global_position
			for i in range(monsters.size()):
				var m0: MonsterInstance = monsters[i] as MonsterInstance
				if m0 == null or not m0.is_alive():
					continue
				var actor0: Variant = m0.actor
				if actor0 == null or not is_instance_valid(actor0):
					continue
				var mon_pos := (actor0 as Node2D).global_position
				var d := adv_pos.distance_to(mon_pos)
				if d < best_dist:
					best_dist = d
					best_i = i
					best_actor_pos = mon_pos

			if best_i != -1:
				if best_dist <= rng:
					var m: MonsterInstance = monsters[best_i] as MonsterInstance
					var dealt := dmg
					if m != null:
						# Boss upgrades: armor blocks damage per hit.
						if m.is_boss() and int(m.dmg_block) > 0:
							dealt = max(0, dealt - int(m.dmg_block))
						m.hp = int(m.hp) - dealt
						# Boss upgrades: reflect damage back to the attacker.
						if m.is_boss() and int(m.reflect_damage) > 0:
							p.call("apply_damage", int(m.reflect_damage))
					_sync_monster_actor(m)
					# Threat: the damaged monster will focus this adventurer more.
					if _threat != null:
						var actor_hit: Variant = m.actor if m != null else null
						var mon_key: int = 0
						if actor_hit != null and is_instance_valid(actor_hit):
							mon_key = int((actor_hit as Node2D).get_instance_id())
						_threat.call("on_adv_damage", room_id, mon_key, pid, dealt)
					# Add a touch of jitter so parties don't swing in perfect unison.
					var base_int := float(p.get("attack_interval"))
					t += base_int * randf_range(0.9, 1.1)
				else:
					# Ranged units "kite" (reposition) when they've been hit recently.
					# Important: avoid stalemates where a ranged unit is already out of range and keeps
					# running away forever (especially vs long-range boss attacks like Glop).
					# Instead, pick a standoff point at ~90% of range: this moves AWAY if too close,
					# and moves TOWARD if too far, guaranteeing they can re-enter attack range.
					if rng > MELEE_RANGE_CUTOFF and float(adv_hit.get(pid, 0.0)) > 0.0:
						if float(adv_pause.get(pid, 0.0)) > 0.0:
							t = 0.0
							continue
						var away := (adv_pos - best_actor_pos)
						if away.length() <= 0.001:
							away = Vector2.LEFT
						away = away.normalized()
						var desired_sep := clampf(rng * RANGED_STANDOFF_RATIO, 10.0, maxf(10.0, rng - 2.0))
						var standoff_world := best_actor_pos + away * (desired_sep + rng0.randf_range(-6.0, 6.0))
						var standoff_local := _dungeon_world_to_local(standoff_world)
						adv_targets[pid] = _clamp_to_room_rect(combat, standoff_local)
						adv_pause[pid] = rng0.randf_range(MOVE_REACTION_DELAY_MIN, MOVE_REACTION_DELAY_MAX)
						t = 0.0
						continue
					# Close distance: steer this adventurer toward a point left of the target.
					if float(adv_pause.get(pid, 0.0)) > 0.0:
						t = 0.0
						continue
					var keep_y: float = adv_pos.y
					var cur_t: Variant = adv_targets.get(pid, adv_pos)
					if cur_t is Vector2:
						keep_y = _dungeon_local_to_world(cur_t as Vector2).y
					var desired_sep: float = _closing_separation(rng)
					var desired_world := best_actor_pos + Vector2(-desired_sep, keep_y - best_actor_pos.y)
					var desired_local := _dungeon_world_to_local(desired_world)
					adv_targets[pid] = _clamp_to_room_rect(combat, desired_local)
					adv_pause[pid] = rng0.randf_range(MOVE_REACTION_DELAY_MIN, MOVE_REACTION_DELAY_MAX)
					# Keep trying next tick without resetting cooldown.
					t = 0.0
		adv_timers[pid] = t

	combat["adv_attack_timers"] = adv_timers
	combat["adv_targets"] = adv_targets
	combat["adv_move_pause"] = adv_pause
	combat["adv_recently_hit"] = adv_hit


func _tick_monster_attacks(room_id: int, combat: Dictionary, dt: float) -> void:
	var participants: Array = combat.get("participants", [])
	var monsters: Array = _monster_roster.call("get_monsters_in_room", room_id) if _monster_roster != null else []
	if participants.is_empty() or monsters.is_empty():
		return
	var mon_targets: Dictionary = combat.get("mon_targets", {})
	var mon_pause: Dictionary = combat.get("mon_move_pause", {})
	var adv_hit: Dictionary = combat.get("adv_recently_hit", {})
	var rng0 := _ensure_rng(combat)

	for i in range(monsters.size()):
		var m: MonsterInstance = monsters[i] as MonsterInstance
		if m == null or not m.is_alive():
			continue

		# Boss upgrades: resolve any pending double-strike hit.
		if m.is_boss() and bool(m._double_strike_pending):
			m._double_strike_t = float(m._double_strike_t) - dt
			if float(m._double_strike_t) <= 0.0:
				var target: Node2D = null
				for p0 in participants:
					if is_instance_valid(p0) and int((p0 as Node2D).get_instance_id()) == int(m._double_strike_target_adv_id):
						target = p0 as Node2D
						break
				if target != null:
					target.call("apply_damage", int(m.attack_damage()))
					adv_hit[int(target.get_instance_id())] = RANGED_KITE_HIT_WINDOW
				m._double_strike_pending = false
				m._double_strike_t = 0.0
				m._double_strike_target_adv_id = 0

		# Boss upgrades: glop attack (separate cooldown).
		if m.is_boss() and int(m.glop_damage) > 0:
			m.glop_t = maxf(0.0, float(m.glop_t) - dt)
			if float(m.glop_t) <= 0.0:
				var gr := float(m.glop_range_px)
				if gr <= 0.0:
					gr = 160.0
				var actor_glop: Variant = m.actor
				var mon_pos_glop := (actor_glop as Node2D).global_position if actor_glop != null and is_instance_valid(actor_glop) else Vector2.ZERO
				var best_adv_glop: Node2D = null
				var best_dist_glop := 1e18
				for p1 in participants:
					if not is_instance_valid(p1):
						continue
					var a1 := p1 as Node2D
					var d1 := mon_pos_glop.distance_to(a1.global_position)
					if d1 <= gr and d1 < best_dist_glop:
						best_dist_glop = d1
						best_adv_glop = a1
				if best_adv_glop != null:
					DbgLog.info(
						"Glop cast room_id=%d dmg=%d range=%.0f target_adv=%d dist=%.1f" % [
							room_id,
							int(m.glop_damage),
							gr,
							int(best_adv_glop.get_instance_id()),
							float(best_dist_glop),
						],
						"boss_upgrades"
					)
					best_adv_glop.call("apply_damage", int(m.glop_damage))
					adv_hit[int(best_adv_glop.get_instance_id())] = RANGED_KITE_HIT_WINDOW
					var cd := float(m.glop_cooldown_s)
					if cd <= 0.0:
						cd = 3.0
					m.glop_t = cd
				else:
					DbgLog.throttle(
						"glop_no_target:%d" % room_id,
						2.0,
						"Glop ready but no target in range room_id=%d range=%.0f" % [room_id, gr],
						"boss_upgrades",
						DbgLog.Level.DEBUG
					)

		var t: float = float(m.attack_timer) - dt
		if t <= 0.0:
			# Monsters hit ONE adventurer per attack.
			var dmg: int = int(m.attack_damage())
			var rng: float = float(m.range_px())
			if rng <= 0.0:
				rng = DEFAULT_MELEE_RANGE

			# Find closest alive adventurer.
			var actor: Variant = m.actor
			var mon_pos := (actor as Node2D).global_position if actor != null and is_instance_valid(actor) else Vector2.ZERO
			var best_adv: Node2D = null
			if _threat != null and actor != null and is_instance_valid(actor):
				var mon_key := int((actor as Node2D).get_instance_id())
				var prof: ThreatProfile = null
				if m.template != null:
					prof = m.template.threat_profile
				var picked: Variant = _threat.call("choose_adv_target", room_id, mon_key, participants, mon_pos, rng, prof)
				if picked != null and is_instance_valid(picked):
					best_adv = picked as Node2D
			# Fallback: nearest.
			if best_adv == null:
				var best_dist0 := 1e18
				for p in participants:
					if not is_instance_valid(p):
						continue
					var adv0 := p as Node2D
					var d0 := mon_pos.distance_to(adv0.global_position)
					if d0 < best_dist0:
						best_dist0 = d0
						best_adv = adv0

			if best_adv != null:
				var best_dist := mon_pos.distance_to(best_adv.global_position)
				if best_dist <= rng:
					best_adv.call("apply_damage", dmg)
					# Mark this adventurer as "recently hit" so ranged units can kite briefly.
					adv_hit[int(best_adv.get_instance_id())] = RANGED_KITE_HIT_WINDOW
					# Boss upgrades: double strike (bonus hit after a short delay).
					if m.is_boss() and float(m.double_strike_chance) > 0.0 and not bool(m._double_strike_pending):
						var ch := clampf(float(m.double_strike_chance), 0.0, 1.0)
						if rng0.randf() <= ch:
							m._double_strike_pending = true
							m._double_strike_target_adv_id = int(best_adv.get_instance_id())
							var dly := float(m.double_strike_delay_s)
							if dly <= 0.0001:
								dly = 0.1
							m._double_strike_t = dly
					# Add a touch of jitter so monsters don't swing in perfect unison.
					t += float(m.attack_interval()) * randf_range(0.9, 1.1)
				else:
					# Close distance: steer this monster toward a point right of the target.
					var actor2: Variant = m.actor
					if actor2 != null and is_instance_valid(actor2):
						var aid := int((actor2 as Node2D).get_instance_id())
						if float(mon_pause.get(aid, 0.0)) > 0.0:
							t = 0.0
							continue
						var keep_y: float = mon_pos.y
						var cur_t: Variant = mon_targets.get(aid, mon_pos)
						if cur_t is Vector2:
							keep_y = _dungeon_local_to_world(cur_t as Vector2).y
						var desired_sep: float = _closing_separation(rng)
						var desired_world := best_adv.global_position + Vector2(desired_sep, keep_y - best_adv.global_position.y)
						var desired_local := _dungeon_world_to_local(desired_world)
						mon_targets[aid] = _clamp_to_room_rect(combat, desired_local)
						mon_pause[aid] = rng0.randf_range(MOVE_REACTION_DELAY_MIN, MOVE_REACTION_DELAY_MAX)
					# Keep trying next tick without resetting cooldown.
					t = 0.0
		m.attack_timer = t

	combat["mon_targets"] = mon_targets
	combat["mon_move_pause"] = mon_pause
	combat["adv_recently_hit"] = adv_hit


func _dungeon_local_to_world(local_pos: Vector2) -> Vector2:
	if _dungeon_view == null:
		return local_pos
	return (_dungeon_view as CanvasItem).get_global_transform() * local_pos


func _dungeon_world_to_local(world_pos: Vector2) -> Vector2:
	if _dungeon_view == null:
		return world_pos
	return (_dungeon_view as CanvasItem).get_global_transform().affine_inverse() * world_pos


func _closing_separation(rng: float) -> float:
	# Melee: close to contact distance so distance can fall BELOW melee range.
	if rng <= MELEE_RANGE_CUTOFF:
		return MELEE_CONTACT_DISTANCE
	# Ranged: keep a standoff so ranged units don't stack on top of targets.
	# Also clamp so we never try to keep a separation larger than range itself.
	return clampf(rng * RANGED_STANDOFF_RATIO, 10.0, maxf(10.0, rng - 2.0))


func _assign_combat_positions(room: Dictionary, combat: Dictionary) -> void:
	# Create deterministic-ish positions for participants/monsters inside the room (pure animation).
	if _dungeon_view == null:
		return
	var center_local: Vector2 = _dungeon_view.call("room_center_local", room) as Vector2
	combat["room_rect_local"] = _dungeon_view.call("room_interior_rect_local", room, ROOM_INTERIOR_PAD_PX) as Rect2

	var participants: Array = combat.get("participants", [])
	var adv_targets: Dictionary = combat.get("adv_targets", {})
	var mon_targets: Dictionary = combat.get("mon_targets", {})

	# Adventurers line up on the left side of the room center.
	var n_adv := participants.size()
	for i in range(n_adv):
		var p: Node2D = participants[i] as Node2D
		if not is_instance_valid(p):
			continue
		var t_y := (float(i) - float(n_adv - 1) * 0.5) * 14.0
		var r: float = float(p.get("range"))
		if r <= 0.0:
			r = DEFAULT_MELEE_RANGE
		var x := -60.0 if r >= 100.0 else -28.0
		# Store targets in DungeonView-local space so zoom/pan can't desync combat positions.
		adv_targets[int(p.get_instance_id())] = _clamp_to_room_rect(combat, center_local + Vector2(x, t_y))

	# Monsters line up on the right side of the room center.
	var room_id: int = int(room.get("id", 0))
	var monsters: Array = _monster_roster.call("get_monsters_in_room", room_id) if _monster_roster != null else []
	var mon_actors: Array[Node2D] = []
	for m in monsters:
		var md := m as MonsterInstance
		var actor: Variant = md.actor if md != null else null
		if actor != null and is_instance_valid(actor):
			mon_actors.append(actor as Node2D)

	var n_mon := mon_actors.size()
	for j in range(n_mon):
		var a: Node2D = mon_actors[j]
		var t_y2 := (float(j) - float(n_mon - 1) * 0.5) * 14.0
		# Monsters are currently melee by default; keep them near the front.
		# Store targets in DungeonView-local space so zoom/pan can't desync combat positions.
		mon_targets[int(a.get_instance_id())] = _clamp_to_room_rect(combat, center_local + Vector2(28.0, t_y2))

	combat["adv_targets"] = adv_targets
	combat["mon_targets"] = mon_targets


func _animate_combat_positions(combat: Dictionary, dt: float) -> void:
	var adv_targets: Dictionary = combat.get("adv_targets", {})
	var mon_targets: Dictionary = combat.get("mon_targets", {})
	var adv_off: Dictionary = combat.get("adv_wander_offset", {})
	var mon_off: Dictionary = combat.get("mon_wander_offset", {})
	var room_rect: Rect2 = combat.get("room_rect_local", Rect2()) as Rect2

	var participants: Array = combat.get("participants", [])
	for p in participants:
		var adv: Node2D = p as Node2D
		if not is_instance_valid(adv):
			continue
		var key: int = int(adv.get_instance_id())
		if not adv_targets.has(key):
			continue
		var target_local: Vector2 = adv_targets[key] as Vector2
		if adv_off.has(key):
			target_local += adv_off[key] as Vector2
		if room_rect != Rect2():
			target_local = _clamp_to_room_rect(combat, target_local)
		var target_world := _dungeon_local_to_world(target_local)
		adv.global_position = adv.global_position.move_toward(target_world, COMBAT_MOVE_SPEED * dt)
		# Enforce room bounds.
		if room_rect != Rect2():
			var adv_local := _dungeon_world_to_local(adv.global_position)
			adv_local = _clamp_to_room_rect(combat, adv_local)
			adv.global_position = _dungeon_local_to_world(adv_local)

	var room_id: int = int(combat.get("room_id", 0))
	var monsters: Array = _monster_roster.call("get_monsters_in_room", room_id) if _monster_roster != null else []
	for m in monsters:
		var md := m as MonsterInstance
		var actor: Variant = md.actor if md != null else null
		if actor == null or not is_instance_valid(actor):
			continue
		var a: Node2D = actor as Node2D
		var key2: int = int(a.get_instance_id())
		if not mon_targets.has(key2):
			continue
		var target2_local: Vector2 = mon_targets[key2] as Vector2
		if mon_off.has(key2):
			target2_local += mon_off[key2] as Vector2
		if room_rect != Rect2():
			target2_local = _clamp_to_room_rect(combat, target2_local)
		var target2_world := _dungeon_local_to_world(target2_local)
		a.global_position = a.global_position.move_toward(target2_world, COMBAT_MOVE_SPEED * dt)
		# Enforce room bounds.
		if room_rect != Rect2():
			var mon_local := _dungeon_world_to_local(a.global_position)
			mon_local = _clamp_to_room_rect(combat, mon_local)
			a.global_position = _dungeon_local_to_world(mon_local)


func _sync_monster_actor(m: MonsterInstance) -> void:
	if m == null:
		return
	var actor: Variant = m.actor
	if actor != null and is_instance_valid(actor):
		(actor as Node).call("set_hp", int(m.hp), int(m.max_hp))
