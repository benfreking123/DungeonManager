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
		# Flee-on-damage: high morality hesitates before fleeing.
		#  - morality >= 4: delay 2 rooms
		#  - morality >= 2: delay 1 room
		#  - else: flee immediately
		if b.has_goal("flee_on_any_damage") and not bool(b.flee_triggered):
			var delay := 0
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
	var fline := ""
	if _goals_cfg != null and _goals_cfg.has_method("pick_dialogue_for_flee"):
		fline = String(_goals_cfg.call("pick_dialogue_for_flee", _rng, "flee_on_any_damage"))
	if fline != "":
		_bubble_events.append({ "type": "flee", "adv_id": int(adv_id), "text": fline })


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
	var goal := _intent_goal_cell(intent, from_cell)
	_set_party_intent_and_goal(pid, intent, goal)
	_maybe_defect(pid, from_cell, intent)
	return goal


func goal_cell_for_intent(intent: String, from_cell: Vector2i) -> Vector2i:
	return _intent_goal_cell(String(intent), from_cell)


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
		totals[INTENT_EXPLORE] += _score_intent_for_member(b, INTENT_EXPLORE, boss_known, loot_known)
		totals[INTENT_BOSS] += _score_intent_for_member(b, INTENT_BOSS, boss_known, loot_known)
		totals[INTENT_LOOT] += _score_intent_for_member(b, INTENT_LOOT, boss_known, loot_known)
		totals[INTENT_EXIT] += _score_intent_for_member(b, INTENT_EXIT, boss_known, loot_known)

	# Deterministic tie-break order (prevents random “exit at entrance” when scores tie).
	var best := INTENT_EXPLORE
	var best_score := int(totals[INTENT_EXPLORE])
	for k in [INTENT_BOSS, INTENT_LOOT, INTENT_EXIT]:
		var sc := int(totals[k])
		if sc > best_score:
			best_score = sc
			best = String(k)
	DbgLog.throttle(
		"party_intent:%d" % pid,
		0.65,
		"Party intent pid=%d explore=%d boss=%d loot=%d exit=%d -> %s" % [
			pid,
			int(totals[INTENT_EXPLORE]),
			int(totals[INTENT_BOSS]),
			int(totals[INTENT_LOOT]),
			int(totals[INTENT_EXIT]),
			best,
		],
		"party",
		DbgLog.Level.DEBUG
	)

	# Emit a single bubble per party on intent change (leader speaks).
	var last: String = String(_last_party_intent_emitted.get(pid, ""))
	if last != best:
		var st: PartyState = _parties.get(pid, null) as PartyState
		var leader := int(st.leader_adv_id) if st != null else 0
		if leader != 0:
			var text := ""
			if _goals_cfg != null and _goals_cfg.has_method("pick_dialogue_for_intent"):
				text = String(_goals_cfg.call("pick_dialogue_for_intent", _rng, best))
			if text != "":
				_bubble_events.append({ "type": "party_intent", "party_id": pid, "leader_adv_id": leader, "text": text })
				# Only mark as emitted if we actually had a leader and emitted a bubble.
				_last_party_intent_emitted[pid] = best

	return best


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
	if _goals_cfg != null and _goals_cfg.has_method("get_intent_score"):
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
		# morality [-5..+5]; only high morality resists.
		var m := maxi(0, int(b.morality))
		score += bonus - (m * resist)

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
		score += int(isc.get("has_any_loot_bonus", 10)) if not b.stolen_treasure.is_empty() else 0

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
		if pressure < 60:
			continue
		# Low morality = more defection chance.
		if b.morality > -1:
			continue

		var m_factor := float(clampi(-b.morality, 0, 5)) / 5.0 # -5 => 1.0, 0 => 0.0
		var p_factor := clampf(float(pressure) / 200.0, 0.0, 1.0)
		var chance := clampf(m_factor * p_factor, 0.0, 0.85)
		if _rng.randf() > chance:
			continue

		var cap := int(_cfg.get("SOFT_PARTY_CAP")) if _cfg != null else 15
		if active_party_count() >= cap:
			_soft_defy[aid] = { "intent": best_intent, "rooms_left": 3 }
			DbgLog.info("Soft defy adv=%d party=%d intent=%s pressure=%d (cap=%d)" % [aid, pid, best_intent, pressure, cap], "party")
			continue

		# Hard split into micro-party.
		var new_pid := _next_party_id
		_next_party_id += 1
		DbgLog.info("Micro-party split: adv=%d from_party=%d -> new_party=%d intent=%s pressure=%d" % [aid, pid, new_pid, best_intent, pressure], "party")
		# Bubble: defection line on the defector.
		var dline := ""
		if _goals_cfg != null and _goals_cfg.has_method("pick_dialogue_for_defect"):
			dline = String(_goals_cfg.call("pick_dialogue_for_defect", _rng))
		if dline != "":
			_bubble_events.append({ "type": "defect", "adv_id": aid, "text": dline })
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
			if _rng.randf() < 0.5:
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


func _intent_goal_cell(intent: String, from_cell: Vector2i) -> Vector2i:
	match String(intent):
		INTENT_BOSS:
			return _boss_goal_cell(from_cell)
		INTENT_LOOT:
			return _loot_goal_cell(from_cell)
		INTENT_EXIT:
			return _entrance_goal_cell(from_cell)
		_:
			return _explore_goal_cell(from_cell)


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


func _loot_goal_cell(fallback: Vector2i) -> Vector2i:
	if _grid == null:
		return fallback
	var best_cell := Vector2i(-1, -1)
	var best_len := 1e18
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
		if p.size() < best_len:
			best_len = p.size()
			best_cell = c
	return fallback if best_cell == Vector2i(-1, -1) else best_cell


func _explore_goal_cell(fallback: Vector2i) -> Vector2i:
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

	var best_cell := Vector2i(-1, -1)
	var best_len := 1e18
	for r2 in unknown_candidates:
		var c := _room_center_cell(r2, fallback)
		var p: Array[Vector2i] = _grid.call("find_path", fallback, c) as Array[Vector2i]
		if p.is_empty():
			continue
		if p.size() < best_len:
			best_len = p.size()
			best_cell = c
	if best_cell != Vector2i(-1, -1):
		return best_cell

	# If nothing unknown adjacent remains, fall back to boss if known, else exit.
	var boss := _boss_goal_cell(Vector2i(-1, -1))
	if boss != Vector2i(-1, -1):
		return boss
	return _entrance_goal_cell(fallback)


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
