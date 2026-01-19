extends RefCounted
class_name AbilitySystem

# Loads abilities and routes triggers to effects, tracking cooldown and charges.

const ABILITIES_DIR := "res://assets/abilities"

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _abilities_by_id: Dictionary = {} # ability_id -> Ability Resource

# adv_id -> { ability_id, charges_left:int, next_ready_s:float, cooldown_s:float, single_use:bool }
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
	_state_by_adv[aid] = {
		"ability_id": ability_id,
		"charges_left": maxi(0, int(charges_per_day)),
		"cooldown_s": float(res.cooldown_s),
		"next_ready_s": 0.0,
		"single_use": single_use,
	}


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
	var st: Dictionary = _state_by_adv.get(int(adv_id), {}) as Dictionary
	if st.is_empty():
		return
	var ability_id := String(st.get("ability_id", ""))
	var res: Ability = _abilities_by_id.get(ability_id, null) as Ability
	if res == null:
		return
	if String(res.trigger_name) != String(trigger_name):
		return
	if int(st.get("charges_left", 0)) <= 0:
		return
	var now_s := float(Time.get_ticks_msec()) / 1000.0
	if now_s < float(st.get("next_ready_s", 0.0)):
		return
	# If -1 cooldown, single-use for the day.
	if bool(st.get("single_use", false)) and int(st.get("charges_left", 0)) <= 0:
		return

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
	_state_by_adv[int(adv_id)] = st

	# Fire effect after cast time (or immediately if 0).
	if cast_t <= 0.0 or _simulation == null:
		_execute_effect(int(adv_id), res)
		_emit_anim(int(adv_id), res)
		return
	var tree := (_simulation.get_tree() as SceneTree) if _simulation != null else null
	if tree == null:
		_execute_effect(int(adv_id), res)
		_emit_anim(int(adv_id), res)
		return
	var timer := tree.create_timer(cast_t)
	timer.timeout.connect(func():
		_execute_effect(int(adv_id), res)
		_emit_anim(int(adv_id), res)
	)


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
			pass
		"warrior_reflect":
			pass
		# Mage
		"mage_aoe_freeze":
			pass
		"mage_aoe_damage":
			pass
		"mage_single_stun":
			pass
		# Rogue
		"rogue_teleport_to_entrance":
			# TODO: move actor to entrance
			pass
		"rogue_notice_trap":
			pass
		"rogue_disarm_trap":
			pass
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
		if id.begins_with("priest_"):
			ring_color = Color(0.6, 1.0, 0.6, 1.0) # green for heals
		elif id.begins_with("mage_"):
			ring_color = Color(0.6, 0.9, 1.0, 1.0) # blue-ish for magic
		elif id.begins_with("warrior_"):
			ring_color = Color(1.0, 0.7, 0.4, 1.0) # orange
		elif id.begins_with("rogue_"):
			ring_color = Color(0.9, 0.8, 1.0, 1.0) # purple-ish
	var ring := preload("res://scripts/fx/AbilityRing.gd").new()
	ring.color = ring_color
	ring.duration_s = 0.35
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
	tween.parallel().tween_property(adv, "modulate", Color(1.0, 1.0, 0.6, 1.0), 0.12)
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
