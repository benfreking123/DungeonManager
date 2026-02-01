extends RefCounted
class_name PartyAdventureSystem

const INTENT_EXPLORE := "explore"
const INTENT_BOSS := "boss"
const INTENT_LOOT := "loot"
const INTENT_EXIT := "exit"

var _grid: Node
var _item_db: Node
var _cfg: Node
var _fog: FogOfWarService
var _steal: TreasureStealService

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _boss_killed: bool = false
var _goals_cfg: Node = null

# member_id -> member_def dictionary (from PartyGenerator)
var _member_defs: Dictionary = {}

# party_id -> PartyState
var _parties: Dictionary = {}

# party_id -> Array[int adv_id] (stable order; used for round-robin stealing)
var _party_members: Dictionary = {}

# adv_id -> AdventurerBrain
var _brains: Dictionary = {}

# adv_id -> member_id (from generator)
var _adv_to_member_id: Dictionary = {}
# adv_id -> soft defy state { intent:String, rooms_left:int }
var _soft_defy: Dictionary = {}

var _next_party_id: int = 1000

# party_id -> bool (has entered any non-entrance room)
var _party_started: Dictionary = {}

# Bubble events consumed by Simulation/UI.
# Each event shape:
# { type: "party_intent", party_id: int, leader_adv_id: int, text: String }
# { type: "defect", adv_id: int, text: String }
# { type: "flee", adv_id: int, text: String }
var _bubble_events: Array[Dictionary] = []

# party_id -> last emitted intent (for leader bubble spam control)
var _last_party_intent_emitted: Dictionary = {}


func _to_int_array(a: Array) -> Array[int]:
	var out: Array[int] = []
	for v in a:
		out.append(int(v))
	return out


func _has_property(obj: Object, prop_name: String) -> bool:
	if obj == null:
		return false
	var plist: Array = obj.get_property_list()
	for p in plist:
		var d := p as Dictionary
		if String(d.get("name", "")) == String(prop_name):
			return true
	return false


func setup(dungeon_grid: Node, item_db: Node, cfg: Node, goals_cfg: Node, fog: FogOfWarService, steal: TreasureStealService, day_seed: int) -> void:
	_grid = dungeon_grid
	_item_db = item_db
	_cfg = cfg
	_goals_cfg = goals_cfg
	_fog = fog
	_steal = steal
	_rng.seed = int(day_seed)
	_boss_killed = false
	_member_defs.clear()
	_parties.clear()
	_party_members.clear()
	_brains.clear()
	_adv_to_member_id.clear()
	_soft_defy.clear()
	_next_party_id = 1000
	_party_started.clear()
	_bubble_events.clear()
	_last_party_intent_emitted.clear()


func init_from_generated(gen: Dictionary) -> void:
	_member_defs = gen.get("member_defs", {}) as Dictionary
	var party_defs: Array = gen.get("party_defs", []) as Array
	var max_pid := 0
	for p0 in party_defs:
		var pd := p0 as Dictionary
		var pid := int(pd.get("party_id", 0))
		if pid == 0:
			continue
		max_pid = maxi(max_pid, pid)
		var st := PartyState.new()
		st.party_id = pid
		st.member_ids = []
		st.intent = INTENT_EXPLORE
		_parties[pid] = st
		_party_members[pid] = []
		_party_started[pid] = false
		_last_party_intent_emitted[pid] = ""
	_next_party_id = max_pid + 1


func consume_bubble_events() -> Array[Dictionary]:
	var out := _bubble_events.duplicate(true)
	_bubble_events.clear()
	return out


func active_party_count() -> int:
	return _party_members.keys().size()


func get_adv_tooltip(adv_id: int) -> Dictionary:
	# Player-friendly tooltip fields for UI.
	# Returns:
	# {
	#   morality_label: String,
	#   top_goal_ids: Array[String],
	#   top_goals: Array[String] (labels)
	# }
	var b: AdventurerBrain = _brains.get(int(adv_id), null) as AdventurerBrain
	if b == null:
		return {}
	var out: Dictionary = {}
	out["morality_label"] = _morality_label(int(b.morality))

	var ids: Array[String] = _top_goal_ids(b, 3)
	out["top_goal_ids"] = ids

	var labels: Array[String] = []
	for gid in ids:
		var label := _goal_label(gid)
		if label != "":
			labels.append(label)
	out["top_goals"] = labels
	# Traits and ability (if asked by UI later).
	var md := {}
	var mid := int(_adv_to_member_id.get(int(adv_id), 0))
	if mid != 0:
		md = _member_defs.get(mid, {}) as Dictionary
	if not md.is_empty():
		out["traits"] = md.get("traits", [])
		out["ability_id"] = md.get("ability_id", "")
	return out


func _morality_label(m: int) -> String:
	m = clampi(int(m), -5, 5)
	if m <= -4:
		return "Ruthless"
	if m <= -2:
		return "Selfish"
	if m <= 1:
		return "Neutral"
	if m <= 3:
		return "Honorable"
	return "Noble"


func _goal_label(goal_id: String) -> String:
	if _goals_cfg != null and _goals_cfg.has_method("get_goal_def"):
		var def: Dictionary = _goals_cfg.call("get_goal_def", String(goal_id)) as Dictionary
		var label := String(def.get("label", ""))
		if label != "":
			return label
	return String(goal_id)


func _top_goal_ids(b: AdventurerBrain, max_count: int) -> Array[String]:
	var out: Array[String] = []
	if b == null:
		return out
	max_count = maxi(0, int(max_count))
	if max_count <= 0:
		return out

	# Pick top goals by absolute rolled weight, excluding base goals (base goals are always present).
	var w: Dictionary = b.goal_weights
	var pairs: Array[Dictionary] = []
	for k in w.keys():
		var gid := String(k)
		if gid in ["kill_boss", "loot_dungeon", "explore_dungeon"]:
			continue
		pairs.append({ "id": gid, "w": abs(int(w.get(k, 0))) })

	pairs.sort_custom(func(a: Dictionary, c: Dictionary) -> bool:
		return int(a.get("w", 0)) > int(c.get("w", 0))
	)

	for i in range(mini(max_count, pairs.size())):
		out.append(String((pairs[i] as Dictionary).get("id", "")))
	return out


func register_adventurer(adv: Node2D, member_id: int) -> void:
	# Called by Simulation after spawning an Adventurer actor.
	if adv == null or not is_instance_valid(adv):
		return
	var md: Dictionary = _member_defs.get(int(member_id), {}) as Dictionary
	if md.is_empty():
		return
	var pid := int(md.get("party_id", 0))
	if pid == 0:
		return
	var aid := int(adv.get_instance_id())

	adv.set("party_id", pid)

	# Apply rolled base stats (defaults already exist on the actor via class).
	var base_stats: Dictionary = md.get("base_stats", {}) as Dictionary
	if not base_stats.is_empty():
		if _has_property(adv, "intelligence"):
			adv.set("intelligence", int(base_stats.get("intelligence", int(adv.get("intelligence")))))
		if _has_property(adv, "strength"):
			adv.set("strength", int(base_stats.get("strength", int(adv.get("strength")))))
		if _has_property(adv, "agility"):
			adv.set("agility", int(base_stats.get("agility", int(adv.get("agility")))))

	# Apply rolled stat mods on top of class base stats.
	var mods: Dictionary = md.get("stat_mods", {}) as Dictionary
	var hp_bonus := int(mods.get("hp_bonus", 0))
	var dmg_bonus := int(mods.get("dmg_bonus", 0))
	if hp_bonus != 0:
		var hp_max := int(adv.get("hp_max")) + hp_bonus
		adv.set("hp_max", hp_max)
		adv.set("hp", hp_max)
	if dmg_bonus != 0:
		adv.set("attack_damage", int(adv.get("attack_damage")) + dmg_bonus)

	# Apply trait modifiers (percent first, then flat).
	var traits: Array = md.get("traits", []) as Array
	if not traits.is_empty():
		var traits_cfg: Node = load("res://autoloads/traits_config.gd").new()
		# Percent modifiers
		for t0 in traits:
			var tid := String(t0)
			var td: Dictionary = traits_cfg.get_trait_def(tid) if traits_cfg != null else {}
			var pct: Dictionary = (td.get("mods", {}) as Dictionary).get("pct", {}) as Dictionary
			for stat_key in pct.keys():
				var percent := int(pct.get(stat_key, 0))
				if percent == 0:
					continue
				var sk := String(stat_key)
				if not _has_property(adv, sk):
					continue
				var v: Variant = adv.get(sk)
				var cur_val := 0
				if v is int:
					cur_val = int(v)
				elif v is float:
					cur_val = int(round(float(v)))
				else:
					continue
				var new_val := int(round(float(cur_val) * (1.0 + float(percent) / 100.0)))
				adv.set(sk, new_val)
				if sk == "hp_max":
					adv.set("hp", int(adv.get("hp_max")))
		# Flat modifiers
		for t1 in traits:
			var tid2 := String(t1)
			var td2: Dictionary = traits_cfg.get_trait_def(tid2) if traits_cfg != null else {}
			var flat: Dictionary = (td2.get("mods", {}) as Dictionary).get("flat", {}) as Dictionary
			for stat_key2 in flat.keys():
				var delta := int(flat.get(stat_key2, 0))
				if delta == 0:
					continue
				var sk2 := String(stat_key2)
				if not _has_property(adv, sk2):
					continue
				var v2: Variant = adv.get(sk2)
				var cur_val2 := 0
				if v2 is int:
					cur_val2 = int(v2)
				elif v2 is float:
					cur_val2 = int(round(float(v2)))
				else:
					continue
				adv.set(sk2, cur_val2 + delta)
				if sk2 == "hp_max":
					adv.set("hp", int(adv.get("hp_max")))
		# Explicitly free temporary traits config Node to avoid leak warnings in headless CI.
		if traits_cfg != null:
			traits_cfg.free()

	# Brain
	var brain := AdventurerBrain.new()
	brain.setup(
		aid,
		pid,
		int(md.get("morality", 0)),
		md.get("goal_weights", {}) as Dictionary,
		md.get("goal_params", {}) as Dictionary,
		int(md.get("stolen_inv_cap", int(_cfg.get("STOLEN_INV_CAP_DEFAULT")) if _cfg != null else 2))
	)
	_brains[aid] = brain
	_adv_to_member_id[aid] = int(member_id)

	# Party membership
	if not _party_members.has(pid):
		_party_members[pid] = []
	var arr: Array = _party_members[pid] as Array
	arr.append(aid)
	_party_members[pid] = arr

	if _parties.has(pid):
		var st: PartyState = _parties[pid] as PartyState
		if st != null:
			st.member_ids = _to_int_array(arr)
			st.leader_adv_id = int(st.member_ids[0]) if not st.member_ids.is_empty() else 0


func on_adv_damaged(adv_id: int, hp: int = 0, hp_max: int = 0) -> void:
	var b: AdventurerBrain = _brains.get(int(adv_id), null) as AdventurerBrain
	if b != null:
		b.took_any_damage = true
		if hp_max > 0:
			b.last_hp = int(hp)
			b.last_hp_max = int(hp_max)
		# Flee-on-damage: delay from ai_tuning (low morality flees sooner); fallback to legacy mapping.
		if b.has_goal("flee_on_any_damage") and not bool(b.flee_triggered):
			var delay := 0
			if Engine.has_singleton("ai_tuning") and ai_tuning != null and ai_tuning.has_method("flee_delay_for_morality"):
				delay = int(ai_tuning.flee_delay_for_morality(int(b.morality)))
			else:
				if b.morality >= 4:
					delay = 2
				elif b.morality >= 2:
					delay = 1
			b.flee_delay_rooms_remaining = maxi(b.flee_delay_rooms_remaining, delay)
			if b.flee_delay_rooms_remaining <= 0:
				_trigger_flee(int(adv_id), b)


func _trigger_flee(adv_id: int, b: AdventurerBrain) -> void:
	if b == null or bool(b.flee_triggered):
		return
	b.flee_triggered = true
	b.flee_delay_rooms_remaining = 0
	_soft_defy[int(adv_id)] = { "intent": INTENT_EXIT, "rooms_left": 999999 }
	_bubble_events.append({
		"type": "flee",
		"adv_id": int(adv_id),
		"intent": INTENT_EXIT,
		"goal_id": "flee_on_any_damage",
	})


func on_boss_killed() -> void:
	_boss_killed = true


func on_monster_room_cleared(adv_ids: Array[int], killed: int) -> void:
	var k := maxi(0, int(killed))
	for aid0 in adv_ids:
		var aid := int(aid0)
		var b: AdventurerBrain = _brains.get(aid, null) as AdventurerBrain
		if b == null:
			continue
		b.monsters_killed += k


func on_adv_died(adv_id: int) -> Array[String]:
	# Returns stolen treasure item_ids to drop as forced extra drops.
	var b: AdventurerBrain = _brains.get(int(adv_id), null) as AdventurerBrain
	if b == null:
		return []
	var stolen := b.pop_all_stolen()
	_remove_adv_from_party(adv_id)
	_brains.erase(int(adv_id))
	_soft_defy.erase(int(adv_id))
	return stolen


func on_adv_exited(adv_id: int) -> void:
	# Move stolen treasure to stash (recoverable later).
	var b: AdventurerBrain = _brains.get(int(adv_id), null) as AdventurerBrain
	if b != null:
		DbgLog.info("Adv exited adv=%d party=%d stolen=%d" % [int(adv_id), int(b.party_id), b.stolen_treasure.size()], "theft")
		for tid in b.pop_all_stolen():
			if Engine.has_singleton("StolenStash"):
				StolenStash.add(String(tid), 1)
	_remove_adv_from_party(adv_id)
	_brains.erase(int(adv_id))
	_soft_defy.erase(int(adv_id))


func party_goal_cell(party_id: int, from_cell: Vector2i) -> Vector2i:
	# Computes and stores the party's next goal.
	var pid := int(party_id)
	if pid == 0:
		return from_cell
	var intent := decide_party_intent(pid)
	var goal := _intent_goal_cell(pid, intent, from_cell)
	_set_party_intent_and_goal(pid, intent, goal)
	_maybe_defect(pid, from_cell, intent)
	return goal


func goal_cell_for_adv_intent(adv_id: int, intent: String, from_cell: Vector2i) -> Vector2i:
	return _intent_goal_cell_for_adv(int(adv_id), String(intent), from_cell)


func party_id_for_adv(adv_id: int) -> int:
	var b: AdventurerBrain = _brains.get(int(adv_id), null) as AdventurerBrain
	return int(b.party_id) if b != null else 0


func decide_party_intent(party_id: int) -> String:
	var pid := int(party_id)
	var members: Array = _party_members.get(pid, []) as Array
	if members.is_empty():
		# During initial pre-spawn planning, parties may not have any registered actors yet.
		# Default to exploring rather than exiting immediately.
		return INTENT_EXPLORE

	var boss_known := false
	var boss_room: Dictionary = _grid.call("get_first_room_of_kind", "boss") as Dictionary if _grid != null else {}
	if not boss_room.is_empty():
		boss_known = _fog != null and _fog.is_room_known(int(boss_room.get("id", 0)))

	var loot_known := _has_any_known_treasure_room_with_loot()

	var stab: Dictionary = {}
	# Prefer ai_tuning for stability, fallback to config_goals for backward compatibility.
	if Engine.has_singleton("ai_tuning") and ai_tuning != null and ai_tuning.has_method("get_intent_stability"):
		stab = ai_tuning.get_intent_stability() as Dictionary
	elif _goals_cfg != null and _goals_cfg.has_method("get_intent_stability"):
		stab = _goals_cfg.call("get_intent_stability") as Dictionary
	var clamp_min := int(stab.get("clamp_member_min", -300))
	var clamp_max := int(stab.get("clamp_member_max", 500))
	var switch_margin := int(stab.get("switch_margin", 15))

	var totals := {
		INTENT_EXPLORE: 0,
		INTENT_BOSS: 0,
		INTENT_LOOT: 0,
		INTENT_EXIT: 0,
	}

	for aid0 in members:
		var aid := int(aid0)
		var b: AdventurerBrain = _brains.get(aid, null) as AdventurerBrain
		if b == null:
			continue
		totals[INTENT_EXPLORE] += clampi(_score_intent_for_member(b, INTENT_EXPLORE, boss_known, loot_known), clamp_min, clamp_max)
		totals[INTENT_BOSS] += clampi(_score_intent_for_member(b, INTENT_BOSS, boss_known, loot_known), clamp_min, clamp_max)
		totals[INTENT_LOOT] += clampi(_score_intent_for_member(b, INTENT_LOOT, boss_known, loot_known), clamp_min, clamp_max)
		totals[INTENT_EXIT] += clampi(_score_intent_for_member(b, INTENT_EXIT, boss_known, loot_known), clamp_min, clamp_max)

	# Deterministic tie-break order (prevents random “exit at entrance” when scores tie).
	var best_raw := INTENT_EXPLORE
	var best_score := int(totals[INTENT_EXPLORE])
	for k in [INTENT_BOSS, INTENT_LOOT, INTENT_EXIT]:
		var sc := int(totals[k])
		if sc > best_score:
			best_score = sc
			best_raw = String(k)

	# Intent hysteresis: require a margin to switch away from current party intent.
	var chosen := String(best_raw)
	var st0: PartyState = _parties.get(pid, null) as PartyState
	var current_intent := String(st0.intent) if st0 != null else ""
	if current_intent == "":
		current_intent = INTENT_EXPLORE
	if chosen != current_intent:
		var cur_sc := int(totals.get(current_intent, -999999))
		var new_sc := int(totals.get(chosen, -999999))
		if (new_sc - cur_sc) < switch_margin:
			chosen = current_intent

	DbgLog.throttle(
		"party_intent:%d" % pid,
		0.65,
		"Party intent pid=%d explore=%d boss=%d loot=%d exit=%d -> %s" % [
			pid,
			int(totals[INTENT_EXPLORE]),
			int(totals[INTENT_BOSS]),
			int(totals[INTENT_LOOT]),
			int(totals[INTENT_EXIT]),
			chosen,
		],
		"party",
		DbgLog.Level.DEBUG
	)

	# Emit a single bubble per party on intent change (leader speaks).
	var last: String = String(_last_party_intent_emitted.get(pid, ""))
	if last != chosen:
		var st: PartyState = _parties.get(pid, null) as PartyState
		var leader := int(st.leader_adv_id) if st != null else 0
		if leader != 0:
			_bubble_events.append({
				"type": "party_intent",
				"party_id": pid,
				"leader_adv_id": leader,
				"intent": chosen,
			})
			# Only mark as emitted if we actually had a leader and emitted a bubble.
			_last_party_intent_emitted[pid] = chosen

	return chosen


func on_party_enter_room(party_id: int, room: Dictionary) -> Dictionary:
	# Steal installed treasure (round robin) on room entry.
	if _steal == null:
		return {}
	var pid := int(party_id)
	# Mark party as “started” once it reaches any non-entrance room.
	if String(room.get("kind", "")) != "entrance":
		_party_started[pid] = true
	var members: Array = _party_members.get(pid, []) as Array
	if members.is_empty():
		return {}

	# If any member is in a delayed-flee state, count down per room entered and trigger when ready.
	for aid0 in members:
		var aid := int(aid0)
		var b0: AdventurerBrain = _brains.get(aid, null) as AdventurerBrain
		if b0 == null:
			continue
		if b0.has_goal("flee_on_any_damage") and b0.took_any_damage and not bool(b0.flee_triggered):
			if int(b0.flee_delay_rooms_remaining) > 0 and String(room.get("kind", "")) != "entrance":
				b0.flee_delay_rooms_remaining = maxi(0, int(b0.flee_delay_rooms_remaining) - 1)
				if int(b0.flee_delay_rooms_remaining) <= 0:
					_trigger_flee(aid, b0)

	var thieves: Array[AdventurerBrain] = []
	for aid0 in members:
		var b: AdventurerBrain = _brains.get(int(aid0), null) as AdventurerBrain
		if b != null:
			thieves.append(b)
	var evt := _steal.steal_from_room(room, _grid, _item_db, thieves)
	var stolen: Array = evt.get("stolen", [])
	if not stolen.is_empty():
		DbgLog.debug("Stole room_id=%d party=%d stolen=%d" % [int(room.get("id", 0)), pid, stolen.size()], "theft")
	return evt


func _set_party_intent_and_goal(party_id: int, intent: String, goal: Vector2i) -> void:
	if _parties.has(party_id):
		var st: PartyState = _parties[party_id] as PartyState
		if st != null:
			st.intent = intent
	# Store goal in PartyAI later; Simulation asks this system for goal and pushes it.


func party_intent(party_id: int) -> String:
	var st: PartyState = _parties.get(int(party_id), null) as PartyState
	return String(st.intent) if st != null else INTENT_EXPLORE


func _score_intent_for_member(b: AdventurerBrain, intent: String, boss_known: bool, loot_known: bool) -> int:
	var score := 0
	var is_exit := (intent == INTENT_EXIT)
	var is_loot := (intent == INTENT_LOOT)
	var is_boss := (intent == INTENT_BOSS)
	var is_explore := (intent == INTENT_EXPLORE)

	var isc: Dictionary = {}
	# Prefer ai_tuning for intent scoring, fallback to config_goals.
	if Engine.has_singleton("ai_tuning") and ai_tuning != null and ai_tuning.has_method("get_intent_score"):
		var all_a: Dictionary = ai_tuning.get_intent_score() as Dictionary
		isc = all_a.get(intent, {}) as Dictionary
	elif _goals_cfg != null and _goals_cfg.has_method("get_intent_score"):
		var all: Dictionary = _goals_cfg.call("get_intent_score") as Dictionary
		isc = all.get(intent, {}) as Dictionary

	# Base goal weights.
	if is_explore:
		score += b.goal_weight("explore_dungeon") * int(isc.get("base_goal_mult", 3))
	if is_boss:
		score += b.goal_weight("kill_boss") * int(isc.get("base_goal_mult", 5))
	if is_loot:
		score += b.goal_weight("loot_dungeon") * int(isc.get("base_goal_mult", 3))

	# Availability.
	if is_boss:
		if not boss_known:
			score += int(isc.get("unknown_penalty", -200))
		else:
			score += int(isc.get("known_bonus", 0))
	if is_loot and not loot_known:
		score += int(isc.get("unknown_penalty", -120))

	# Unique goal mods.
	if b.has_goal("flee_on_any_damage") and b.took_any_damage:
		if is_exit:
			score += 250
		else:
			score -= 25

	if b.has_goal("no_flee_until_boss_dead") and not _boss_killed:
		if is_exit:
			score -= 80
		if is_boss:
			score += 10

	# Full loot definition: inventory is full (no more capacity).
	var full_loot := not b.can_steal_more()

	# no_leave_until_full_loot: cannot exit until full.
	if b.has_goal("no_leave_until_full_loot") and not full_loot:
		if is_exit:
			score -= 120
		if is_loot:
			score += 35

	# exit_when_full_loot: strongly prefer exit once full, but morality may resist.
	if b.has_goal("exit_when_full_loot") and full_loot and is_exit:
		var bonus := int(isc.get("full_loot_exit_bonus", 260))
		var resist := int(isc.get("full_loot_morality_resist_per_point", 35))
		# Apply per-item resist decay from ai_tuning (more loot -> less resist).
		var loot_params := {}
		if Engine.has_singleton("ai_tuning") and ai_tuning != null and ai_tuning.has_method("exit_with_loot_params"):
			loot_params = ai_tuning.exit_with_loot_params()
		var per_item_resist_decay := int(loot_params.get("per_item_resist_decay", 0))
		var n_items := int(b.stolen_treasure.size())
		# morality [-5..+5]; only high morality resists.
		var eff_m := maxi(0, int(b.morality) - per_item_resist_decay * n_items)
		score += bonus - (eff_m * resist)

	if b.has_goal("explore_all_before_boss") and not _boss_killed:
		var fully_known := _is_dungeon_fully_known()
		if not fully_known:
			if is_boss:
				score -= 60
			if is_explore:
				score += 30

	# Loot greed: if you still have space, looting is attractive.
	if is_loot:
		score += int(isc.get("space_bonus", 25)) if b.can_steal_more() else int(isc.get("space_full_penalty", -25))
	if is_exit:
		# Prevent “immediate exit at entrance” unless there’s a real reason.
		var pid := int(b.party_id)
		var started := bool(_party_started.get(pid, false))
		if not started and b.stolen_treasure.is_empty() and not (b.has_goal("flee_on_any_damage") and b.took_any_damage):
			score += int(isc.get("start_day_penalty", -1000))
		# Exiting is more attractive once you have stolen something (they want to leave with it).
		var loot_bonus := 0
		var loot_params2 := {}
		if Engine.has_singleton("ai_tuning") and ai_tuning != null and ai_tuning.has_method("exit_with_loot_params"):
			loot_params2 = ai_tuning.exit_with_loot_params()
		# Base has-any bonus (fallback to config_goals intent score)
		var has_any_bonus := int(loot_params2.get("has_any_bonus", int(isc.get("has_any_loot_bonus", 10))))
		if not b.stolen_treasure.is_empty():
			loot_bonus += has_any_bonus
			# Per-item exit bonus (capped).
			var per_item := int(loot_params2.get("per_item_bonus", 0))
			var max_items := int(loot_params2.get("bonus_max_items", 0))
			if per_item != 0 and max_items > 0:
				var items := mini(int(b.stolen_treasure.size()), max_items)
				loot_bonus += per_item * items
		score += loot_bonus

	# New goals (rolled params)
	# flee_on_any_loot: once you have any loot, strongly prefer exit.
	if b.has_goal("flee_on_any_loot") and not b.stolen_treasure.is_empty() and is_exit:
		score += 220

	# no_leave_until_kill_x_monsters: gate exit until kill target reached.
	if b.has_goal("no_leave_until_kill_x_monsters"):
		var tgt := int(b.goal_param("no_leave_until_kill_x_monsters", "kills_target", 0))
		if tgt > 0 and int(b.monsters_killed) < tgt:
			if is_exit:
				score -= 160
			if is_boss or is_loot:
				score += 10
		elif tgt > 0 and int(b.monsters_killed) >= tgt:
			if is_exit:
				score += 35

	# cautious_hp_threshold: if HP% below rolled threshold, prefer exit.
	if b.has_goal("cautious_hp_threshold") and is_exit and int(b.last_hp_max) > 0:
		var pct := 100.0 * float(int(b.last_hp)) / float(int(b.last_hp_max))
		var thr := float(b.goal_param("cautious_hp_threshold", "hp_threshold_pct", 35))
		if pct <= thr:
			score += 220

	# boss_rush: once boss known, bias boss and de-bias loot.
	if b.has_goal("boss_rush") and boss_known:
		if is_boss:
			score += 80
		if is_loot:
			score -= 40

	# greedy_then_leave: steal X treasures then exit.
	if b.has_goal("greedy_then_leave"):
		var lt := int(b.goal_param("greedy_then_leave", "loot_target", 0))
		if lt > 0:
			var have := b.stolen_treasure.size()
			if have < lt:
				if is_loot:
					score += 60
				if is_exit:
					score -= 40
			else:
				if is_exit:
					score += 140

	return score


func _maybe_defect(party_id: int, from_cell: Vector2i, chosen_intent: String) -> void:
	# Decide defections into micro-parties (or soft-defy if at soft cap).
	var pid := int(party_id)
	var members: Array = _party_members.get(pid, []) as Array
	if members.size() <= 1:
		return

	var boss_known := false
	var boss_room: Dictionary = _grid.call("get_first_room_of_kind", "boss") as Dictionary if _grid != null else {}
	if not boss_room.is_empty():
		boss_known = _fog != null and _fog.is_room_known(int(boss_room.get("id", 0)))
	var loot_known := _has_any_known_treasure_room_with_loot()

	for aid0 in members.duplicate():
		var aid := int(aid0)
		var b: AdventurerBrain = _brains.get(aid, null) as AdventurerBrain
		if b == null:
			continue

		# Soft-defy countdown tick.
		if _soft_defy.has(aid):
			var sd: Dictionary = _soft_defy[aid] as Dictionary
			sd["rooms_left"] = maxi(0, int(sd.get("rooms_left", 0)) - 1)
			if int(sd.get("rooms_left", 0)) <= 0:
				_soft_defy.erase(aid)
			else:
				_soft_defy[aid] = sd

		var personal := {
			INTENT_EXPLORE: _score_intent_for_member(b, INTENT_EXPLORE, boss_known, loot_known),
			INTENT_BOSS: _score_intent_for_member(b, INTENT_BOSS, boss_known, loot_known),
			INTENT_LOOT: _score_intent_for_member(b, INTENT_LOOT, boss_known, loot_known),
			INTENT_EXIT: _score_intent_for_member(b, INTENT_EXIT, boss_known, loot_known),
		}
		var best_intent := INTENT_EXPLORE
		var best_score := -999999
		for k in personal.keys():
			var sc := int(personal[k])
			if sc > best_score:
				best_score = sc
				best_intent = String(k)
		if best_intent == chosen_intent:
			continue
		var chosen_score := int(personal.get(chosen_intent, 0))
		var pressure := best_score - chosen_score
		# Threshold from ai_tuning, with bias for very low morality.
		var thresh := 60
		if Engine.has_singleton("ai_tuning") and ai_tuning != null and ai_tuning.has_method("defect_pressure_threshold"):
			thresh = int(ai_tuning.defect_pressure_threshold())
		if int(b.morality) <= -5:
			thresh = maxi(0, thresh - 10)
		if pressure < thresh:
			continue
		# Low morality = more defection chance.
		if b.morality > -1:
			continue
		var m_factor := float(clampi(-b.morality, 0, 5)) / 5.0 # -5 => 1.0, 0 => 0.0
		var p_factor := clampf(float(pressure) / 200.0, 0.0, 1.0)
		var cap := 0.85
		if Engine.has_singleton("ai_tuning") and ai_tuning != null and ai_tuning.has_method("defect_chance_cap"):
			cap = float(ai_tuning.defect_chance_cap())
		# At morality = -5, use full cap; else keep as-is.
		var chance := clampf(m_factor * p_factor, 0.0, cap)
		if _rng.randf() > chance:
			continue

		var soft_cap := int(_cfg.get("SOFT_PARTY_CAP")) if _cfg != null else 15
		if active_party_count() >= soft_cap:
			var rooms := 3
			if Engine.has_singleton("ai_tuning") and ai_tuning != null and ai_tuning.has_method("soft_defy_rooms"):
				rooms = int(ai_tuning.soft_defy_rooms())
			_soft_defy[aid] = { "intent": best_intent, "rooms_left": rooms }
			DbgLog.info("Soft defy adv=%d party=%d intent=%s pressure=%d (cap=%d)" % [aid, pid, best_intent, pressure, soft_cap], "party")
			continue

		# Hard split into micro-party.
		var new_pid := _next_party_id
		_next_party_id += 1
		DbgLog.info("Micro-party split: adv=%d from_party=%d -> new_party=%d intent=%s pressure=%d" % [aid, pid, new_pid, best_intent, pressure], "party")
		# Bubble: defection line on the defector.
		_bubble_events.append({
			"type": "defect",
			"adv_id": aid,
			"intent": best_intent,
		})
		_create_micro_party(new_pid, [aid])
		_parties[new_pid].intent = best_intent

		# Immediate recruit: pull in other members that also strongly prefer this intent.
		for aid2_0 in members:
			var aid2 := int(aid2_0)
			if aid2 == aid:
				continue
			var b2: AdventurerBrain = _brains.get(aid2, null) as AdventurerBrain
			if b2 == null:
				continue
			if b2.morality > -2:
				continue
			var sc2_best := _score_intent_for_member(b2, best_intent, boss_known, loot_known)
			var sc2_chosen := _score_intent_for_member(b2, chosen_intent, boss_known, loot_known)
			if sc2_best - sc2_chosen < 60:
				continue
			var recruit_ch := 0.5
			if Engine.has_singleton("ai_tuning") and ai_tuning != null and ai_tuning.has_method("defect_recruit_chance"):
				recruit_ch = float(ai_tuning.defect_recruit_chance())
			if _rng.randf() < recruit_ch:
				_move_adv_to_party(aid2, new_pid)
		# Remove the original defector from the old party last (membership arrays update).
		_move_adv_to_party(aid, new_pid)


func effective_intent_for_adv(adv_id: int, party_intent: String) -> String:
	# If soft-defying, temporarily override party intent.
	var aid := int(adv_id)
	if _soft_defy.has(aid):
		var sd: Dictionary = _soft_defy[aid] as Dictionary
		var i := String(sd.get("intent", ""))
		if i != "":
			return i
	return party_intent


func decision_dialogue_for_adv(adv_id: int, effective_intent: String) -> String:
	# Choose a one-sentence dialogue line for a decision bubble.
	var b: AdventurerBrain = _brains.get(int(adv_id), null) as AdventurerBrain
	if b == null:
		return ""
	# Prefer goal-specific dialogue when relevant.
	if effective_intent == INTENT_EXPLORE and b.has_goal("explore_all_before_boss"):
		if _goals_cfg != null and _goals_cfg.has_method("pick_dialogue_for_goal"):
			return String(_goals_cfg.call("pick_dialogue_for_goal", _rng, "explore_all_before_boss"))
	if effective_intent == INTENT_EXIT and b.has_goal("flee_on_any_damage") and b.took_any_damage:
		if _goals_cfg != null and _goals_cfg.has_method("pick_dialogue_for_goal"):
			return String(_goals_cfg.call("pick_dialogue_for_goal", _rng, "flee_on_any_damage"))
	# Fall back to intent dialogue.
	if _goals_cfg != null and _goals_cfg.has_method("pick_dialogue_for_intent"):
		return String(_goals_cfg.call("pick_dialogue_for_intent", _rng, effective_intent))
	return ""


func _intent_goal_cell(party_id: int, intent: String, from_cell: Vector2i) -> Vector2i:
	match String(intent):
		INTENT_BOSS:
			return _boss_goal_cell(from_cell)
		INTENT_LOOT:
			return _loot_goal_cell(int(party_id), from_cell)
		INTENT_EXIT:
			return _entrance_goal_cell(from_cell)
		_:
			return _explore_goal_cell(int(party_id), from_cell)


# Public: allow Simulation (and other systems) to credit ground loot into a member's stolen stash.
func add_stolen_for_adv(adv_id: int, item_id: String) -> bool:
	var b: AdventurerBrain = _brains.get(int(adv_id), null) as AdventurerBrain
	if b == null:
		return false
	return b.add_stolen(String(item_id))


func _intent_goal_cell_for_adv(adv_id: int, intent: String, from_cell: Vector2i) -> Vector2i:
	# Like _intent_goal_cell, but uses the adventurer's own Intelligence for noise.
	match String(intent):
		INTENT_BOSS:
			return _boss_goal_cell(from_cell)
		INTENT_LOOT:
			return _loot_goal_cell_for_int(_adv_intelligence(adv_id), from_cell)
		INTENT_EXIT:
			return _entrance_goal_cell(from_cell)
		_:
			return _explore_goal_cell_for_int(_adv_intelligence(adv_id), from_cell)


func _adv_intelligence(adv_id: int) -> int:
	var mid := int(_adv_to_member_id.get(int(adv_id), 0))
	if mid == 0:
		return int(_cfg.get("ADV_STAT_DEFAULT")) if _cfg != null else 10
	var md: Dictionary = _member_defs.get(mid, {}) as Dictionary
	var bs: Dictionary = md.get("base_stats", {}) as Dictionary
	var v := int(bs.get("intelligence", int(_cfg.get("ADV_STAT_DEFAULT")) if _cfg != null else 10))
	return _clamp_stat(v)


func _party_avg_intelligence(party_id: int) -> int:
	var pid := int(party_id)
	var members: Array = _party_members.get(pid, []) as Array
	if members.is_empty():
		return int(_cfg.get("ADV_STAT_DEFAULT")) if _cfg != null else 10
	var sum := 0
	var n := 0
	for aid0 in members:
		var aid := int(aid0)
		var mid := int(_adv_to_member_id.get(aid, 0))
		if mid == 0:
			continue
		var md: Dictionary = _member_defs.get(mid, {}) as Dictionary
		var bs: Dictionary = md.get("base_stats", {}) as Dictionary
		sum += _clamp_stat(int(bs.get("intelligence", int(_cfg.get("ADV_STAT_DEFAULT")) if _cfg != null else 10)))
		n += 1
	if n <= 0:
		return int(_cfg.get("ADV_STAT_DEFAULT")) if _cfg != null else 10
	return _clamp_stat(int(round(float(sum) / float(n))))


func _clamp_stat(v: int) -> int:
	var min_s := int(_cfg.get("ADV_STAT_MIN")) if _cfg != null else 8
	var max_s := int(_cfg.get("ADV_STAT_MAX")) if _cfg != null else 12
	if min_s > max_s:
		var tmp := min_s
		min_s = max_s
		max_s = tmp
	return clampi(int(v), min_s, max_s)


func _epsilon_for_intelligence(intelligence: int) -> float:
	var min_s := int(_cfg.get("ADV_STAT_MIN")) if _cfg != null else 8
	var max_s := int(_cfg.get("ADV_STAT_MAX")) if _cfg != null else 12
	var base := 0.25
	var floor := 0.01
	# Prefer ai_tuning PATH_NOISE; fallback to game_config constants.
	if Engine.has_singleton("ai_tuning") and ai_tuning != null:
		if ai_tuning.has_method("epsilon_base"):
			base = float(ai_tuning.epsilon_base())
		if ai_tuning.has_method("epsilon_floor"):
			floor = float(ai_tuning.epsilon_floor())
	elif _cfg != null:
		base = float(_cfg.get("ADV_PATH_MISTAKE_CHANCE_BASE"))
		floor = float(_cfg.get("ADV_PATH_MISTAKE_MIN_CHANCE"))
	base = clampf(base, 0.0, 1.0)
	floor = clampf(floor, 0.0, 1.0)
	if base < floor:
		var tmp := base
		base = floor
		floor = tmp

	var denom := float(maxi(1, max_s - min_s))
	var t := clampf((float(intelligence) - float(min_s)) / denom, 0.0, 1.0)
	# t=0 (low INT) => epsilon ~ base, t=1 (high INT) => epsilon ~ floor
	return clampf(base * (1.0 - t), floor, base)


func _boss_goal_cell(fallback: Vector2i) -> Vector2i:
	if _grid == null:
		return fallback
	var boss_room: Dictionary = _grid.call("get_first_room_of_kind", "boss") as Dictionary
	if boss_room.is_empty():
		return fallback
	var rid := int(boss_room.get("id", 0))
	if _fog != null and not _fog.is_room_known(rid):
		return fallback
	return _room_center_cell(boss_room, fallback)


func _loot_goal_cell(party_id: int, fallback: Vector2i) -> Vector2i:
	return _loot_goal_cell_for_int(_party_avg_intelligence(int(party_id)), fallback)


func _loot_goal_cell_for_int(intelligence: int, fallback: Vector2i) -> Vector2i:
	if _grid == null:
		return fallback
	var candidates: Array[Dictionary] = []
	var rooms: Array = _grid.get("rooms") as Array
	for r0 in rooms:
		var r := r0 as Dictionary
		if String(r.get("kind", "")) != "treasure":
			continue
		var rid := int(r.get("id", 0))
		if _fog != null and not _fog.is_room_known(rid):
			continue
		if not _room_has_installed_treasure(r):
			continue
		var c := _room_center_cell(r, fallback)
		var p: Array[Vector2i] = _grid.call("find_path", fallback, c) as Array[Vector2i]
		if p.is_empty():
			continue
		candidates.append({ "cell": c, "len": int(p.size()) })

	return _pick_cell_epsilon_greedy(candidates, intelligence, fallback)


func _explore_goal_cell(party_id: int, fallback: Vector2i) -> Vector2i:
	return _explore_goal_cell_for_int(_party_avg_intelligence(int(party_id)), fallback)


func _explore_goal_cell_for_int(intelligence: int, fallback: Vector2i) -> Vector2i:
	# Target an unknown room adjacent to any known room (frontier).
	if _grid == null or _fog == null:
		return fallback
	var rooms: Array = _grid.get("rooms") as Array
	var unknown_candidates: Array[Dictionary] = []
	for r0 in rooms:
		var r := r0 as Dictionary
		var rid := int(r.get("id", 0))
		if rid == 0:
			continue
		if _fog.is_room_known(rid):
			continue
		# Unknown; check if any neighbor is known.
		var neigh: Array[int] = _fog.adjacent_room_ids(rid)
		for n0 in neigh:
			if _fog.is_room_known(int(n0)):
				unknown_candidates.append(r)
				break

	var candidates: Array[Dictionary] = []
	for r2 in unknown_candidates:
		var c := _room_center_cell(r2, fallback)
		var p: Array[Vector2i] = _grid.call("find_path", fallback, c) as Array[Vector2i]
		if p.is_empty():
			continue
		candidates.append({ "cell": c, "len": int(p.size()) })
	var chosen := _pick_cell_epsilon_greedy(candidates, intelligence, Vector2i(-1, -1))
	if chosen != Vector2i(-1, -1):
		return chosen

	# If nothing unknown adjacent remains, fall back to boss if known, else exit.
	var boss := _boss_goal_cell(Vector2i(-1, -1))
	if boss != Vector2i(-1, -1):
		return boss
	return _entrance_goal_cell(fallback)


func _pick_cell_epsilon_greedy(candidates: Array[Dictionary], intelligence: int, fallback: Vector2i) -> Vector2i:
	if candidates.is_empty():
		return fallback
	var eps := _epsilon_for_intelligence(intelligence)
	# Find best (min len) set.
	var best_len := 999999999
	for d0 in candidates:
		best_len = mini(best_len, int((d0 as Dictionary).get("len", 999999999)))
	var best_cells: Array[Vector2i] = []
	var worse: Array[Dictionary] = []
	for d1 in candidates:
		var d := d1 as Dictionary
		var l := int(d.get("len", 999999999))
		var cell: Vector2i = d.get("cell", Vector2i(-1, -1))
		if cell == Vector2i(-1, -1):
			continue
		if l <= best_len:
			best_cells.append(cell)
		else:
			# Store delta for weighting.
			worse.append({ "cell": cell, "delta": maxi(1, l - best_len) })
	if best_cells.is_empty() and worse.is_empty():
		return fallback

	# Epsilon-greedy: sometimes pick a non-best candidate (“mistake”).
	if not worse.is_empty() and _rng != null and _rng.randf() < eps:
		# Prefer near-misses over huge mistakes: weight = 1/delta.
		var total := 0.0
		for w0 in worse:
			var dd := float(int((w0 as Dictionary).get("delta", 1)))
			total += 1.0 / maxf(1.0, dd)
		var roll := _rng.randf() * total
		var acc := 0.0
		for w1 in worse:
			var cell2: Vector2i = (w1 as Dictionary).get("cell", Vector2i(-1, -1))
			var dd2 := float(int((w1 as Dictionary).get("delta", 1)))
			acc += 1.0 / maxf(1.0, dd2)
			if roll <= acc:
				return cell2
		return (worse[0] as Dictionary).get("cell", fallback)

	# Otherwise pick among best cells.
	if not best_cells.is_empty():
		return best_cells[_rng.randi_range(0, best_cells.size() - 1)]
	# No best set (shouldn't happen), pick from worse.
	return (worse[_rng.randi_range(0, worse.size() - 1)] as Dictionary).get("cell", fallback)


func _entrance_goal_cell(fallback: Vector2i) -> Vector2i:
	if _grid == null:
		return fallback
	var e: Dictionary = _grid.call("get_first_room_of_kind", "entrance") as Dictionary
	if e.is_empty():
		return fallback
	return _room_center_cell(e, fallback)


func _room_center_cell(room: Dictionary, fallback: Vector2i) -> Vector2i:
	var pos: Vector2i = room.get("pos", fallback)
	var size: Vector2i = room.get("size", Vector2i.ONE)
	return Vector2i(pos.x + int(size.x / 2), pos.y + int(size.y / 2))


func _is_dungeon_fully_known() -> bool:
	if _grid == null or _fog == null:
		return false
	var rooms: Array = _grid.get("rooms") as Array
	for r0 in rooms:
		var r := r0 as Dictionary
		var rid := int(r.get("id", 0))
		if rid == 0:
			continue
		if not _fog.is_room_known(rid):
			return false
	return true


func _room_has_installed_treasure(room: Dictionary) -> bool:
	if room.is_empty() or _item_db == null:
		return false
	var slots: Array = room.get("slots", [])
	for s0 in slots:
		var sd := s0 as Dictionary
		var installed := String(sd.get("installed_item_id", ""))
		if installed == "":
			continue
		var kind := String(_item_db.call("get_item_kind", installed)) if _item_db.has_method("get_item_kind") else ""
		if kind == "treasure":
			return true
	return false


func _has_any_known_treasure_room_with_loot() -> bool:
	if _grid == null:
		return false
	var rooms: Array = _grid.get("rooms") as Array
	for r0 in rooms:
		var r := r0 as Dictionary
		if String(r.get("kind", "")) != "treasure":
			continue
		var rid := int(r.get("id", 0))
		if _fog != null and not _fog.is_room_known(rid):
			continue
		if _room_has_installed_treasure(r):
			return true
	return false


func full_loot_member_ids(party_id: int) -> Array[int]:
	# Returns adv_ids for members whose stolen inventory is full (cannot steal more).
	var out: Array[int] = []
	var pid := int(party_id)
	var members: Array = _party_members.get(pid, []) as Array
	for aid0 in members:
		var aid := int(aid0)
		var b: AdventurerBrain = _brains.get(aid, null) as AdventurerBrain
		if b == null:
			continue
		if not b.can_steal_more():
			out.append(aid)
	return out


func _create_micro_party(party_id: int, adv_ids: Array[int]) -> void:
	var st := PartyState.new()
	st.party_id = int(party_id)
	st.member_ids = []
	st.intent = INTENT_EXPLORE
	_parties[party_id] = st
	_party_members[party_id] = []
	for aid in adv_ids:
		_move_adv_to_party(int(aid), int(party_id))


func _move_adv_to_party(adv_id: int, new_party_id: int) -> void:
	var aid := int(adv_id)
	var b: AdventurerBrain = _brains.get(aid, null) as AdventurerBrain
	if b == null:
		return
	var old_pid := int(b.party_id)
	if old_pid == new_party_id:
		return

	_remove_adv_from_party(aid)

	b.party_id = new_party_id
	if not _party_members.has(new_party_id):
		_party_members[new_party_id] = []
	var arr: Array = _party_members[new_party_id] as Array
	if not arr.has(aid):
		arr.append(aid)
	_party_members[new_party_id] = arr

	if _parties.has(new_party_id):
		var st: PartyState = _parties[new_party_id] as PartyState
		if st != null:
			st.member_ids = _to_int_array(arr)
			st.leader_adv_id = int(st.member_ids[0]) if not st.member_ids.is_empty() else 0


func _remove_adv_from_party(adv_id: int) -> void:
	var aid := int(adv_id)
	var b: AdventurerBrain = _brains.get(aid, null) as AdventurerBrain
	var pid := int(b.party_id) if b != null else 0
	if pid == 0:
		return
	var arr: Array = _party_members.get(pid, []) as Array
	if arr.has(aid):
		arr.erase(aid)
	_party_members[pid] = arr
	if arr.is_empty():
		_party_members.erase(pid)
		_parties.erase(pid)
	else:
		var st: PartyState = _parties.get(pid, null) as PartyState
		if st != null:
			st.member_ids = _to_int_array(arr)
			st.leader_adv_id = int(st.member_ids[0]) if not st.member_ids.is_empty() else 0


# History/tooltip helpers
func member_def_for_adv(adv_id: int) -> Dictionary:
	var aid := int(adv_id)
	var mid := int(_adv_to_member_id.get(aid, 0))
	if mid == 0:
		return {}
	return _member_defs.get(mid, {}) as Dictionary
