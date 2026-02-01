extends RefCounted
class_name AbilitySystem

# Loads abilities and routes triggers to effects, tracking cooldown and charges.

const ABILITIES_DIR := "res://assets/abilities"

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _abilities_by_id: Dictionary = {} # ability_id -> Ability Resource

# adv_id -> Array[{ ability_id, charges_left:int, next_ready_s:float, cooldown_s:float, single_use:bool }]
var _state_by_adv: Dictionary = {}

var _simulation: Node = null
var _grid: Node = null
var _combat: Node = null


func setup(simulation: Node, grid: Node, day_seed: int) -> void:
	_simulation = simulation
	_grid = grid
	_rng.seed = int(day_seed)
	_load_abilities()
	_state_by_adv.clear()


func get_ability_def(ability_id: String) -> Ability:
	# Read-only helper for UI/tooltips.
	if _abilities_by_id.is_empty():
		_load_abilities()
	return _abilities_by_id.get(String(ability_id), null) as Ability


func get_adv_ability_state(adv_id: int) -> Dictionary:
	# Read-only helper for UI/tooltips.
	var st: Variant = _state_by_adv.get(int(adv_id), null)
	if typeof(st) == TYPE_ARRAY:
		var arr := st as Array
		if not arr.is_empty():
			return arr[0] as Dictionary
	return st as Dictionary if st != null else {}


func get_adv_ability_states(adv_id: int) -> Array:
	# Read-only helper for UI/tooltips (multi-ability).
	var st: Variant = _state_by_adv.get(int(adv_id), [])
	if typeof(st) == TYPE_ARRAY:
		return st as Array
	var d := st as Dictionary
	return [d] if d != null and not d.is_empty() else []


func register_adv_ability(adv: Node2D, ability_id: String, charges_per_day: int) -> void:
	if adv == null or not is_instance_valid(adv):
		return
	var aid := int(adv.get_instance_id())
	if ability_id == "":
		return
	var res: Ability = _abilities_by_id.get(ability_id, null) as Ability
	if res == null:
		return
	var single_use := (float(res.cooldown_s) < 0.0)
	var entry := {
		"ability_id": ability_id,
		"charges_left": maxi(0, int(charges_per_day)),
		"cooldown_s": float(res.cooldown_s),
		"next_ready_s": 0.0,
		"single_use": single_use,
	}
	var cur: Variant = _state_by_adv.get(aid, [])
	if typeof(cur) == TYPE_ARRAY:
		var arr := cur as Array
		arr.append(entry)
		_state_by_adv[aid] = arr
	elif typeof(cur) == TYPE_DICTIONARY:
		var arr2: Array = [cur as Dictionary, entry]
		_state_by_adv[aid] = arr2
	else:
		_state_by_adv[aid] = [entry]


func on_adv_damaged(adv_id: int) -> void:
	_try_fire(adv_id, "WhenDamaged")


func on_party_member_damaged(party_adv_ids: Array[int]) -> void:
	for aid in party_adv_ids:
		_try_fire(int(aid), "PartyMemberDamaged")


func on_party_member_died(party_adv_ids: Array[int]) -> void:
	for aid in party_adv_ids:
		_try_fire(int(aid), "PartyMemberDie")
		_try_fire(int(aid), "PartyMemberDeath")


func on_enter_room(adv_id: int, room_kind: String) -> void:
	match String(room_kind):
		"monster":
			_try_fire(adv_id, "EnteringMonsterRoom")
			_try_fire(adv_id, "WhenMonster")
		"boss":
			_try_fire(adv_id, "EnteringBossRoom")
			_try_fire(adv_id, "WhenBoss")
		"trap":
			_try_fire(adv_id, "EnteringTrapRoom")
			_try_fire(adv_id, "WhenTrap")


func on_flee(adv_id: int) -> void:
	_try_fire(adv_id, "WhenFlee")


func on_attack(adv_id: int) -> void:
	_try_fire(adv_id, "WhenAttack")


func on_attacked(adv_id: int) -> void:
	_try_fire(adv_id, "WhenAttacked")


func _try_fire(adv_id: int, trigger_name: String) -> void:
	var st_arr := get_adv_ability_states(int(adv_id))
	if st_arr.is_empty():
		return
	var now_s := float(Time.get_ticks_msec()) / 1000.0
	var new_arr: Array = []
	for st0 in st_arr:
		var st := st0 as Dictionary
		if st.is_empty():
			continue
		var ability_id := String(st.get("ability_id", ""))
		var res: Ability = _abilities_by_id.get(ability_id, null) as Ability
		if res == null:
			new_arr.append(st)
			continue
		if String(res.trigger_name) != String(trigger_name):
			new_arr.append(st)
			continue
		if int(st.get("charges_left", 0)) <= 0:
			new_arr.append(st)
			continue
		if now_s < float(st.get("next_ready_s", 0.0)):
			new_arr.append(st)
			continue
		# If -1 cooldown, single-use for the day.
		if bool(st.get("single_use", false)) and int(st.get("charges_left", 0)) <= 0:
			new_arr.append(st)
			continue

		# Consume charge immediately and set next_ready including cast time.
		var left := maxi(0, int(st.get("charges_left", 0)) - 1)
		st["charges_left"] = left
		var cd := float(st.get("cooldown_s", 0.0))
		var cast_t := float(res.cast_time_s)
		if cd < 0.0:
			# Single-use: block further use
			st["next_ready_s"] = 1e18
			st["charges_left"] = 0
		else:
			st["next_ready_s"] = now_s + maxf(0.0, cast_t + cd)
		new_arr.append(st)

		# Fire effect after cast time (or immediately if 0).
		if cast_t <= 0.0 or _simulation == null:
			_execute_effect(int(adv_id), res)
			_emit_anim(int(adv_id), res)
		else:
			var tree := (_simulation.get_tree() as SceneTree) if _simulation != null else null
			if tree == null:
				_execute_effect(int(adv_id), res)
				_emit_anim(int(adv_id), res)
			else:
				var timer := tree.create_timer(cast_t)
				timer.timeout.connect(func():
					_execute_effect(int(adv_id), res)
					_emit_anim(int(adv_id), res)
				)
	_state_by_adv[int(adv_id)] = new_arr


func on_loot_gathered(party_adv_ids: Array[int]) -> void:
	for aid in party_adv_ids:
		_try_fire(int(aid), "LootGathered")


func on_full_loot(party_adv_ids: Array[int]) -> void:
	for aid in party_adv_ids:
		_try_fire(int(aid), "FullLoot")


func _execute_effect(adv_id: int, ab: Ability) -> void:
	# Minimal implementation for spec abilities
	var aid := int(adv_id)
	var label := String(ab.ability_id)
	DbgLog.debug("Ability fire adv=%d id=%s" % [aid, label], "party_gen")
	# For MVP, implement as no-ops with logs and simple heuristics.
	# Real effects (taunt, AoE dmg/heal, freeze) would call into combat system here.
	match String(ab.ability_id):
		# Warrior
		"warrior_taunt":
			# TODO: route to combat target system
			pass
		"warrior_whirlwind":
			_whirlwind_fx(int(adv_id), float(ab.cast_time_s) + 0.25)
		"warrior_reflect":
			_reflect_sparkle(int(adv_id))
		# Mage
		"mage_aoe_freeze":
			_mage_aoe_freeze(int(adv_id), int(ab.params.get("radius_px", 60)), float(ab.params.get("stun_s", 1.0)))
		"mage_aoe_damage":
			_mage_aoe_damage(int(adv_id), int(ab.params.get("radius_px", 60)), int(ab.params.get("damage", 2)))
		"mage_single_stun":
			_mage_single_stun(int(adv_id), float(ab.params.get("stun_s", 1.0)))
		# Rogue
		"rogue_teleport_to_entrance":
			# TODO: move actor to entrance
			pass
		"rogue_notice_trap":
			if _simulation != null and _simulation.has_method("get_adv_current_room_id"):
				var rid := int(_simulation.call("get_adv_current_room_id", int(adv_id)))
				if rid != 0 and _simulation.has_method("remember_hazard_room"):
					_simulation.call("remember_hazard_room", rid, "trap")
		"rogue_disarm_trap":
			if _simulation != null and _simulation.has_method("get_adv_current_room_id"):
				var rid2 := int(_simulation.call("get_adv_current_room_id", int(adv_id)))
				if rid2 != 0:
					# Also count as "remembered hazard".
					if _simulation.has_method("remember_hazard_room"):
						_simulation.call("remember_hazard_room", rid2, "trap")
					# Disable traps for the rest of the day.
					if _simulation.has_method("disarm_trap_room"):
						_simulation.call("disarm_trap_room", rid2)
		# Priest
		"priest_aoe_heal":
			_priest_aoe_heal(int(adv_id), int(ab.params.get("heal", 3)))
		"priest_single_heal":
			_priest_single_heal(int(adv_id), int(ab.params.get("heal", 4)))
		_:
			pass


func on_party_member_low(party_adv_ids: Array[int]) -> void:
	for aid in party_adv_ids:
		_try_fire(int(aid), "PartyMemberLow")


func on_party_member_half(party_adv_ids: Array[int]) -> void:
	for aid in party_adv_ids:
		_try_fire(int(aid), "PartyMemberHalf")


func _party_member_ids_for_adv(adv_id: int) -> Array[int]:
	if _simulation == null:
		return []
	var owner: Node2D = null
	if _simulation.has_method("_find_adv_by_id"):
		owner = _simulation.call("_find_adv_by_id", int(adv_id)) as Node2D
	if owner == null or not is_instance_valid(owner):
		return []
	var pid := int(owner.get("party_id"))
	if pid == 0:
		return [int(adv_id)]
	if _simulation.has_method("get_party_member_ids"):
		var ids: Array = _simulation.call("get_party_member_ids", pid)
		var out: Array[int] = []
		for v in ids:
			out.append(int(v))
		return out
	return [int(adv_id)]


func _priest_aoe_heal(adv_id: int, heal: int) -> void:
	var ids := _party_member_ids_for_adv(int(adv_id))
	for id in ids:
		var n: Node2D = null
		if _simulation.has_method("_find_adv_by_id"):
			n = _simulation.call("_find_adv_by_id", int(id)) as Node2D
		if n == null or not is_instance_valid(n):
			continue
		var hp := int(n.get("hp"))
		var hp_max := int(n.get("hp_max"))
		n.set("hp", mini(hp_max, hp + heal))
		_heal_pulse(n)


func _priest_single_heal(adv_id: int, heal: int) -> void:
	var ids := _party_member_ids_for_adv(int(adv_id))
	var target: Node2D = null
	var worst_ratio := 2.0
	for id in ids:
		var n: Node2D = null
		if _simulation.has_method("_find_adv_by_id"):
			n = _simulation.call("_find_adv_by_id", int(id)) as Node2D
		if n == null or not is_instance_valid(n):
			continue
		var hp := float(int(n.get("hp")))
		var hp_max := float(int(n.get("hp_max")))
		if hp_max <= 0.0:
			continue
		var ratio := hp / hp_max
		if ratio < worst_ratio:
			worst_ratio = ratio
			target = n
	if target != null:
		var thp := int(target.get("hp"))
		var thp_max := int(target.get("hp_max"))
		target.set("hp", mini(thp_max, thp + heal))
		_heal_pulse(target)


func _mage_aoe_damage(adv_id: int, radius_px: int, dmg: int) -> void:
	var adv: Node2D = null
	if _simulation.has_method("_find_adv_by_id"):
		adv = _simulation.call("_find_adv_by_id", int(adv_id)) as Node2D
	if adv == null or not is_instance_valid(adv):
		return
	var center := adv.global_position
	var monsters: Array = []
	if _simulation.has_method("get_monsters_in_radius"):
		monsters = _simulation.call("get_monsters_in_radius", center, float(radius_px))
	for m0 in monsters:
		var m := m0 as MonsterInstance
		if m == null or not m.is_alive():
			continue
		m.hp = maxi(0, int(m.hp) - int(dmg))
		if _simulation.has_method("sync_monster_actor"):
			_simulation.call("sync_monster_actor", m)


func _mage_aoe_freeze(adv_id: int, radius_px: int, stun_s: float) -> void:
	var adv: Node2D = null
	if _simulation.has_method("_find_adv_by_id"):
		adv = _simulation.call("_find_adv_by_id", int(adv_id)) as Node2D
	if adv == null or not is_instance_valid(adv):
		return
	var center := adv.global_position
	var monsters: Array = []
	if _simulation.has_method("get_monsters_in_radius"):
		monsters = _simulation.call("get_monsters_in_radius", center, float(radius_px))
	for m0 in monsters:
		var m := m0 as MonsterInstance
		if m == null or not m.is_alive():
			continue
		# Pause their next attack window to simulate stun.
		m.attack_timer = maxf(float(m.attack_timer), float(stun_s))


func _mage_single_stun(adv_id: int, stun_s: float) -> void:
	var adv: Node2D = null
	if _simulation.has_method("_find_adv_by_id"):
		adv = _simulation.call("_find_adv_by_id", int(adv_id)) as Node2D
	if adv == null or not is_instance_valid(adv):
		return
	var center := adv.global_position
	var monsters: Array = []
	if _simulation.has_method("get_monsters_in_radius"):
		monsters = _simulation.call("get_monsters_in_radius", center, 80.0)
	var best: MonsterInstance = null
	var best_d := 1e18
	for m0 in monsters:
		var m := m0 as MonsterInstance
		if m == null or not m.is_alive():
			continue
		var actor: Node2D = m.actor as Node2D
		if actor == null or not is_instance_valid(actor):
			continue
		var d := actor.global_position.distance_to(center)
		if d < best_d:
			best_d = d
			best = m
	if best != null:
		best.attack_timer = maxf(float(best.attack_timer), float(stun_s))
		var actor2: Node2D = best.actor as Node2D
		if actor2 != null and is_instance_valid(actor2):
			_stun_burst(actor2)


func _stun_burst(target: Node2D) -> void:
	var fx := preload("res://scripts/fx/StunBurst.gd").new()
	target.add_child(fx)
	fx.position = Vector2.ZERO


func _heal_pulse(target: Node2D) -> void:
	var fx := preload("res://scripts/fx/HealPulse.gd").new()
	target.add_child(fx)
	fx.position = Vector2.ZERO


func _reflect_sparkle(adv_id: int) -> void:
	var adv: Node2D = null
	if _simulation.has_method("_find_adv_by_id"):
		adv = _simulation.call("_find_adv_by_id", int(adv_id)) as Node2D
	if adv == null or not is_instance_valid(adv):
		return
	var fx := preload("res://scripts/fx/ReflectSparkle.gd").new()
	adv.add_child(fx)
	fx.position = Vector2.ZERO


func _whirlwind_fx(adv_id: int, duration_s: float) -> void:
	var adv: Node2D = null
	if _simulation.has_method("_find_adv_by_id"):
		adv = _simulation.call("_find_adv_by_id", int(adv_id)) as Node2D
	if adv == null or not is_instance_valid(adv):
		return
	var fx := preload("res://scripts/fx/WhirlwindCross.gd").new()
	fx.duration_s = duration_s
	adv.add_child(fx)
	fx.position = Vector2.ZERO


func _emit_anim(adv_id: int, _ab: Ability) -> void:
	# Simple color pulse + scale pop on the actor.
	if _simulation == null:
		return
	var adv: Node2D = null
	if _simulation.has_method("_find_adv_by_id"):
		adv = _simulation.call("_find_adv_by_id", int(adv_id)) as Node2D
	if adv == null or not is_instance_valid(adv):
		return
	# Spawn a ring FX as a child so it reads even if modulate isn't obvious in the scene.
	var ring_color := Color(1.0, 1.0, 0.6, 1.0) # default yellow
	if _ab != null:
		var id := String(_ab.ability_id)
		if id.begins_with("mage_"):
			ring_color = Color(0.4, 0.7, 1.0, 1.0) # Blue
		elif id.begins_with("warrior_"):
			ring_color = Color(1.0, 0.35, 0.35, 1.0) # Red
		elif id.begins_with("priest_"):
			ring_color = Color(1.0, 0.95, 0.45, 1.0) # Yellow
		elif id.begins_with("rogue_"):
			ring_color = Color(0.5, 1.0, 0.6, 1.0) # Green
	var ring := preload("res://scripts/fx/AbilityRing.gd").new()
	ring.color = ring_color
	# Tie size to params.radius_px when present (visual only; gameplay handled separately).
	var visual_radius := int(_ab.params.get("radius_px", 36))
	ring.end_radius = float(visual_radius)
	ring.thickness_px = 4.0
	ring.duration_s = 0.45
	if is_instance_valid(adv):
		adv.add_child(ring)
		ring.position = Vector2.ZERO
	var tween := adv.create_tween()
	var orig_scale := adv.scale
	var orig_mod := (adv as CanvasItem).modulate
	# Scale pop
	tween.tween_property(adv, "scale", orig_scale * 1.15, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(adv, "scale", orig_scale, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# Color pulse (yellowish)
	tween.parallel().tween_property(adv, "modulate", ring_color, 0.12)
	tween.tween_property(adv, "modulate", orig_mod, 0.12)


func _load_abilities() -> void:
	_abilities_by_id.clear()
	var dir := DirAccess.open(ABILITIES_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name == "":
			break
		if dir.current_is_dir():
			continue
		if not file_name.ends_with(".tres"):
			continue
		var res_path := "%s/%s" % [ABILITIES_DIR, file_name]
		var res := load(res_path)
		var ab := res as Ability
		if ab == null:
			continue
		var id := String(ab.ability_id)
		if id == "":
			continue
		_abilities_by_id[id] = ab
	dir.list_dir_end()
