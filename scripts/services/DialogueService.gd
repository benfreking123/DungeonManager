extends RefCounted
class_name DialogueService

const DEFAULT_COOLDOWN_KEY := "dialogue"

var _rules: Array = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _history: HistoryService = null
var _bubble: DialogueBubbleService = null
var _cfg: Node = null
var _hero_service: Object = null
var _rules_loaded: bool = false
var _day_index: int = -1
var _counts_by_profile: Dictionary = {} # profile_id -> count
var _counts_by_party: Dictionary = {} # party_id -> count
var _counts_by_profile_event: Dictionary = {} # profile_id -> Dictionary[event_id -> count]
var _next_ok_ms_by_profile_event: Dictionary = {} # profile_id -> Dictionary[event_id -> ms]
var _max_per_profile_day: int = 6
var _max_per_party_day: int = 4
var _max_per_event_profile: int = 2
var _event_cooldown_s: float = 3.0
var _event_cooldown_by_event: Dictionary = {}
var _token_defaults: Dictionary = {}
var _debug_token_warn: bool = false
var _debug_verbose: bool = false
var _chance_callback: float = 0.25
var _chance_call_forward: float = 0.2
var _chance_lineage_banter: float = 0.2
var _chance_family_flavor: float = 0.2


func setup(history: HistoryService, bubble: DialogueBubbleService, cfg: Node, hero_service: Object = null) -> void:
	_history = history
	_bubble = bubble
	_cfg = cfg
	_hero_service = hero_service
	_rng.randomize()
	_load_config()


func reset_rules() -> void:
	_rules.clear()
	_rules_loaded = false


func emit_event(evt: Dictionary) -> void:
	if evt.is_empty():
		return
	var event_id := str(evt.get("event", ""))
	if event_id == "":
		return
	_log_debug("emit_event", evt, "start")
	_rollover_day_if_needed()
	if not _within_budget(evt):
		_log_skip("budget", evt)
		return
	if not _cooldown_ok(evt):
		_log_skip("cooldown", evt)
		return
	_ensure_rules_loaded()
	if _rules.is_empty():
		_log_skip("no_rules", evt)
		return

	var profile_id := int(evt.get("profile_id", 0))
	var actor: Node2D = evt.get("actor", null)
	var where := str(evt.get("where", ""))
	var tags: Array = evt.get("tags", []) as Array
	var tokens := _build_tokens(evt, profile_id)

	# Optionally emit callback/call-forward lines using history + day plan.
	if bool(evt.get("allow_callback", false)):
		_maybe_emit_callback(actor, profile_id, where, tags, tokens)
		_maybe_emit_family_callback(actor, profile_id, where, tags, tokens)
	if bool(evt.get("allow_call_forward", false)):
		_maybe_emit_call_forward(actor, profile_id, where, tags, tokens)
	if bool(evt.get("allow_lineage_banter", false)):
		_maybe_emit_lineage_banter(actor, profile_id, where, tags, tokens)
		_maybe_emit_family_flavor(actor, profile_id, where, tags, tokens)

	var line := _pick_line(event_id, tokens)
	if line == "":
		_log_debug("emit_event", evt, "no_line")
		return
	_emit_line(actor, profile_id, line, where, tags, evt.get("cooldown_key", DEFAULT_COOLDOWN_KEY))
	_apply_budget(evt)
	_log_emit(evt, line, tokens)


func _emit_line(actor: Node2D, profile_id: int, line: String, where: String, tags: Array, cooldown_key: String) -> void:
	line = str(line).strip_edges()
	if line == "":
		return
	if _bubble != null and actor != null and is_instance_valid(actor):
		_bubble.show_for_actor(actor, line, str(cooldown_key))
	if _history != null and profile_id != 0:
		_history.record_dialogue(profile_id, line, where, tags)


func _maybe_emit_callback(actor: Node2D, profile_id: int, where: String, tags: Array, base_tokens: Dictionary) -> void:
	if _history == null or profile_id == 0:
		return
	if _rng.randf() > _chance_callback:
		return
	if not _within_budget_for(profile_id, int(base_tokens.get("party_id", 0)), "callback"):
		return
	if not _cooldown_ok_for(profile_id, "callback"):
		return
	var ctx := _history.get_recent_context(profile_id)
	if ctx.is_empty():
		return
	var tokens := base_tokens.duplicate(true)
	for k in ctx.keys():
		tokens[k] = ctx[k]
	var line := _pick_line("callback", tokens)
	if line == "":
		_log_debug("callback", { "event": "callback", "profile_id": profile_id }, "no_line")
		return
	var tags2 := tags.duplicate()
	if not tags2.has("callback"):
		tags2.append("callback")
	_emit_line(actor, profile_id, line, where, tags2, "callback")
	_apply_budget_for(profile_id, int(base_tokens.get("party_id", 0)), "callback")
	_log_emit({ "event": "callback", "profile_id": profile_id }, line, tokens)


func _maybe_emit_family_callback(actor: Node2D, profile_id: int, where: String, tags: Array, base_tokens: Dictionary) -> void:
	if _history == null or profile_id == 0:
		return
	var ctx := _history.get_recent_family_context(profile_id)
	if ctx.is_empty():
		return
	var event_id := ""
	var rel_type := String(ctx.get("relative_event_type", ""))
	if rel_type == "died":
		event_id = "callback_family_loss"
	elif rel_type == "fled":
		event_id = "callback_family_flee"
	elif rel_type == "returned":
		event_id = "callback_family_returned"
	elif rel_type == "hero":
		event_id = "callback_family_hero"
	if event_id == "":
		return
	if not _within_budget_for(profile_id, int(base_tokens.get("party_id", 0)), event_id):
		return
	if not _cooldown_ok_for(profile_id, event_id):
		return
	var tokens := base_tokens.duplicate(true)
	for k in ctx.keys():
		tokens[k] = ctx[k]
	var line := _pick_line(event_id, tokens)
	if line == "":
		_log_debug(event_id, { "event": event_id, "profile_id": profile_id }, "no_line")
		return
	var tags2 := tags.duplicate()
	if not tags2.has("callback"):
		tags2.append("callback")
	if not tags2.has("lineage"):
		tags2.append("lineage")
	_emit_line(actor, profile_id, line, where, tags2, event_id)
	_apply_budget_for(profile_id, int(base_tokens.get("party_id", 0)), event_id)
	_log_emit({ "event": event_id, "profile_id": profile_id }, line, tokens)


func _maybe_emit_family_flavor(actor: Node2D, profile_id: int, where: String, tags: Array, base_tokens: Dictionary) -> void:
	if profile_id == 0:
		return
	if not base_tokens.has("family_name"):
		return
	if _rng.randf() > _chance_family_flavor:
		return
	var event_id := _pick_family_flavor_event()
	if event_id == "":
		return
	if not _within_budget_for(profile_id, int(base_tokens.get("party_id", 0)), event_id):
		return
	if not _cooldown_ok_for(profile_id, event_id):
		return
	var line := _pick_line(event_id, base_tokens)
	if line == "":
		_log_debug(event_id, { "event": event_id, "profile_id": profile_id }, "no_line")
		return
	var tags2 := tags.duplicate()
	if not tags2.has("lineage"):
		tags2.append("lineage")
	_emit_line(actor, profile_id, line, where, tags2, event_id)
	_apply_budget_for(profile_id, int(base_tokens.get("party_id", 0)), event_id)
	_log_emit({ "event": event_id, "profile_id": profile_id }, line, base_tokens)


func _maybe_emit_call_forward(actor: Node2D, profile_id: int, where: String, tags: Array, base_tokens: Dictionary) -> void:
	if _hero_service == null or not _hero_service.has_method("get_upcoming_heroes"):
		return
	if _rng.randf() > _chance_call_forward:
		return
	if not _within_budget_for(profile_id, int(base_tokens.get("party_id", 0)), "call_forward"):
		return
	if not _cooldown_ok_for(profile_id, "call_forward"):
		return
	var upcoming: Array = _hero_service.call("get_upcoming_heroes") as Array
	if upcoming.is_empty():
		_log_skip("no_upcoming_heroes", { "event": "call_forward", "profile_id": profile_id })
		return
	var pick := upcoming[_rng.randi_range(0, upcoming.size() - 1)] as Dictionary
	if pick.is_empty():
		return
	var tokens := base_tokens.duplicate(true)
	tokens["hero_name"] = str(pick.get("name", ""))
	tokens["hero_class"] = str(pick.get("class_id", ""))
	tokens["days_until_hero"] = str(pick.get("days_until", ""))
	var line := _pick_line("call_forward", tokens)
	if line == "":
		_log_debug("call_forward", { "event": "call_forward", "profile_id": profile_id }, "no_line")
		return
	var tags2 := tags.duplicate()
	if not tags2.has("hero"):
		tags2.append("hero")
	if not tags2.has("call_forward"):
		tags2.append("call_forward")
	_emit_line(actor, profile_id, line, where, tags2, "call_forward")
	_apply_budget_for(profile_id, int(base_tokens.get("party_id", 0)), "call_forward")
	_log_emit({ "event": "call_forward", "profile_id": profile_id }, line, tokens)


func _maybe_emit_lineage_banter(actor: Node2D, profile_id: int, where: String, tags: Array, base_tokens: Dictionary) -> void:
	if not base_tokens.has("relative_name"):
		return
	if _rng.randf() > _chance_lineage_banter:
		return
	if not _within_budget_for(profile_id, int(base_tokens.get("party_id", 0)), "lineage_banter"):
		return
	if not _cooldown_ok_for(profile_id, "lineage_banter"):
		return
	var line := _pick_line("lineage_banter", base_tokens)
	if line == "":
		_log_debug("lineage_banter", { "event": "lineage_banter", "profile_id": profile_id }, "no_line")
		return
	var tags2 := tags.duplicate()
	if not tags2.has("lineage"):
		tags2.append("lineage")
	_emit_line(actor, profile_id, line, where, tags2, "lineage_banter")
	_apply_budget_for(profile_id, int(base_tokens.get("party_id", 0)), "lineage_banter")
	_log_emit({ "event": "lineage_banter", "profile_id": profile_id }, line, base_tokens)


func _ensure_rules_loaded() -> void:
	if _rules_loaded:
		return
	_rules_loaded = true
	_rules.clear()
	if _cfg == null or not _cfg.has_method("get"):
		_log_debug("rules", { "event": "rules_loaded" }, "no_cfg")
		return
	var path := str(_cfg.get("DIALOGUE_CONFIG_PATH"))
	if path == "":
		_log_debug("rules", { "event": "rules_loaded" }, "empty_path")
		return
	if not ResourceLoader.exists(path):
		_log_debug("rules", { "event": "rules_loaded" }, "missing_path=%s" % path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_log_debug("rules", { "event": "rules_loaded" }, "open_failed")
		return
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) == TYPE_DICTIONARY:
		var r: Array = (parsed as Dictionary).get("rules", []) as Array
		if not r.is_empty():
			_rules = r
			_log_debug("rules", { "event": "rules_loaded" }, "count=%d" % _rules.size())


func _pick_line(event_id: String, tokens: Dictionary) -> String:
	if _rules.is_empty():
		return ""
	var candidates: Array[Dictionary] = []
	for r0 in _rules:
		var r := r0 as Dictionary
		if r.is_empty():
			continue
		var when := r.get("when", {}) as Dictionary
		if not _when_matches(when, event_id, tokens):
			continue
		candidates.append(r)
	if candidates.is_empty():
		return ""
	var pick := _weighted_pick(candidates)
	var values: Array = pick.get("values", []) as Array
	if values.is_empty():
		return ""
	var raw := str(values[_rng.randi_range(0, values.size() - 1)])
	return _apply_tokens(raw, tokens)


func _when_matches(when: Dictionary, event_id: String, tokens: Dictionary) -> bool:
	if when.is_empty():
		return false
	if when.has("*") and bool(when.get("*")):
		return true
	if str(when.get("event", "")) != str(event_id):
		return false
	for k in when.keys():
		var key := str(k)
		if key == "event":
			continue
		if key == "*":
			continue
		var want := str(when.get(key, ""))
		var have := str(tokens.get(key, ""))
		if want == "":
			continue
		if have != want:
			return false
	return true


func _weighted_pick(candidates: Array[Dictionary]) -> Dictionary:
	var total := 0
	for c in candidates:
		total += maxi(1, int((c as Dictionary).get("weight", 1)))
	if total <= 0:
		return candidates[0]
	var pick := _rng.randi_range(1, total)
	var acc := 0
	for c2 in candidates:
		acc += maxi(1, int((c2 as Dictionary).get("weight", 1)))
		if pick <= acc:
			return c2
	return candidates[0]


func _apply_tokens(text: String, tokens: Dictionary) -> String:
	var out := str(text)
	var idx := 0
	while true:
		var start := out.find("{", idx)
		if start < 0:
			break
		var end := out.find("}", start + 1)
		if end < 0:
			break
		var key := out.substr(start + 1, end - start - 1)
		if key == "":
			idx = end + 1
			continue
		var repl := ""
		if tokens.has(key):
			repl = str(tokens.get(key, ""))
		elif _token_defaults.has(key):
			repl = str(_token_defaults.get(key, ""))
			if _debug_token_warn and Engine.has_singleton("DbgLog"):
				DbgLog.warn("DialogueService: missing token '%s', using default '%s'" % [key, repl], "dialogue")
		else:
			repl = ""
			if _debug_token_warn and Engine.has_singleton("DbgLog"):
				DbgLog.warn("DialogueService: missing token '%s' with no default" % key, "dialogue")
		out = out.substr(0, start) + repl + out.substr(end + 1)
		idx = start + repl.length()
	return out


func _build_tokens(evt: Dictionary, profile_id: int) -> Dictionary:
	var tokens: Dictionary = {}
	for k in evt.keys():
		if k == "actor" or k == "tags" or k == "where" or k == "cooldown_key":
			continue
		tokens[str(k)] = evt[k]
	if _history != null and profile_id != 0:
		var p := _history.get_profile(profile_id)
		if not p.is_empty():
			tokens["name"] = str(p.get("name", ""))
			tokens["class_id"] = str(p.get("class_id", ""))
			tokens["origin"] = str(p.get("origin", ""))
			tokens["family_name"] = str(p.get("family_name", ""))
			tokens["lineage_id"] = str(p.get("lineage_id", ""))
			tokens["gender"] = str(p.get("gender", ""))
			tokens["hero_id"] = str(p.get("hero_id", ""))
			var sibs: Array = p.get("siblings", []) as Array
			if not sibs.is_empty():
				var sib_id := int(sibs[_rng.randi_range(0, sibs.size() - 1)])
				var sib := _history.get_profile(sib_id)
				if not sib.is_empty():
					tokens["relative_name"] = str(sib.get("name", ""))
					tokens["relative_relation"] = "sibling"
	return tokens


func _load_config() -> void:
	if _cfg == null or not _cfg.has_method("get"):
		return
	_max_per_profile_day = int(_cfg.get("DIALOGUE_MAX_PER_PROFILE_PER_DAY"))
	_max_per_party_day = int(_cfg.get("DIALOGUE_MAX_PER_PARTY_PER_DAY"))
	_max_per_event_profile = int(_cfg.get("DIALOGUE_MAX_PER_EVENT_PER_PROFILE"))
	_event_cooldown_s = float(_cfg.get("DIALOGUE_EVENT_COOLDOWN_S"))
	var maybe_cd: Variant = _cfg.get("DIALOGUE_EVENT_COOLDOWN_BY_EVENT")
	if typeof(maybe_cd) == TYPE_DICTIONARY:
		_event_cooldown_by_event = maybe_cd as Dictionary
	var maybe_defs: Variant = _cfg.get("DIALOGUE_TOKEN_DEFAULTS")
	if typeof(maybe_defs) == TYPE_DICTIONARY:
		_token_defaults = maybe_defs as Dictionary
	_debug_token_warn = bool(_cfg.get("DIALOGUE_DEBUG_TOKEN_WARN"))
	_debug_verbose = bool(_cfg.get("DIALOGUE_DEBUG_VERBOSE"))
	_chance_callback = float(_cfg.get("DIALOGUE_CHANCE_CALLBACK"))
	_chance_call_forward = float(_cfg.get("DIALOGUE_CHANCE_CALL_FORWARD"))
	_chance_lineage_banter = float(_cfg.get("DIALOGUE_CHANCE_LINEAGE_BANTER"))
	_chance_family_flavor = float(_cfg.get("DIALOGUE_CHANCE_FAMILY_FLAVOR"))
	_chance_callback = clampf(_chance_callback, 0.0, 1.0)
	_chance_call_forward = clampf(_chance_call_forward, 0.0, 1.0)
	_chance_lineage_banter = clampf(_chance_lineage_banter, 0.0, 1.0)
	_chance_family_flavor = clampf(_chance_family_flavor, 0.0, 1.0)


func _rollover_day_if_needed() -> void:
	var di := 1
	if GameState != null:
		di = int(GameState.day_index)
	if di != _day_index:
		_day_index = di
		_counts_by_profile.clear()
		_counts_by_party.clear()
		_counts_by_profile_event.clear()
		_next_ok_ms_by_profile_event.clear()


func _within_budget(evt: Dictionary) -> bool:
	var profile_id := int(evt.get("profile_id", 0))
	var party_id := int(evt.get("party_id", 0))
	var event_id := str(evt.get("event", ""))
	return _within_budget_for(profile_id, party_id, event_id)


func _within_budget_for(profile_id: int, party_id: int, event_id: String) -> bool:
	if profile_id != 0:
		var c := int(_counts_by_profile.get(profile_id, 0))
		if c >= _max_per_profile_day:
			return false
		var per_event: Dictionary = _counts_by_profile_event.get(profile_id, {}) as Dictionary
		var ce := int(per_event.get(event_id, 0))
		if ce >= _max_per_event_profile:
			return false
	if party_id != 0:
		var cp := int(_counts_by_party.get(party_id, 0))
		if cp >= _max_per_party_day:
			return false
	return true


func _apply_budget(evt: Dictionary) -> void:
	var profile_id := int(evt.get("profile_id", 0))
	var party_id := int(evt.get("party_id", 0))
	var event_id := str(evt.get("event", ""))
	_apply_budget_for(profile_id, party_id, event_id)


func _apply_budget_for(profile_id: int, party_id: int, event_id: String) -> void:
	if profile_id != 0:
		_counts_by_profile[profile_id] = int(_counts_by_profile.get(profile_id, 0)) + 1
		var per_event: Dictionary = _counts_by_profile_event.get(profile_id, {}) as Dictionary
		per_event[event_id] = int(per_event.get(event_id, 0)) + 1
		_counts_by_profile_event[profile_id] = per_event
	if party_id != 0:
		_counts_by_party[party_id] = int(_counts_by_party.get(party_id, 0)) + 1


func _cooldown_ok(evt: Dictionary) -> bool:
	var profile_id := int(evt.get("profile_id", 0))
	if profile_id == 0:
		return true
	var event_id := str(evt.get("event", ""))
	return _cooldown_ok_for(profile_id, event_id)


func _cooldown_ok_for(profile_id: int, event_id: String) -> bool:
	var cd := _event_cooldown_s
	if _event_cooldown_by_event.has(event_id):
		cd = float(_event_cooldown_by_event.get(event_id, _event_cooldown_s))
	if cd <= 0.0:
		return true
	var now_ms := Time.get_ticks_msec()
	var per: Dictionary = _next_ok_ms_by_profile_event.get(profile_id, {}) as Dictionary
	var next_ok := int(per.get(event_id, 0))
	if now_ms < next_ok:
		return false
	per[event_id] = now_ms + int(cd * 1000.0)
	_next_ok_ms_by_profile_event[profile_id] = per
	return true


func _log_skip(reason: String, evt: Dictionary) -> void:
	if not Engine.has_singleton("DbgLog"):
		return
	if not DbgLog.is_enabled("dialogue"):
		return
	var eid := String(evt.get("event", ""))
	var pid := int(evt.get("profile_id", 0))
	var msg := "Dialogue skipped reason=%s event=%s profile=%d" % [reason, eid, pid]
	DbgLog.throttle("dialogue_skip:%s:%s" % [reason, eid], 1.0, msg, "dialogue", DbgLog.Level.DEBUG)


func _log_emit(evt: Dictionary, line: String, tokens: Dictionary) -> void:
	if not Engine.has_singleton("DbgLog"):
		return
	if not DbgLog.is_enabled("dialogue"):
		return
	if not _debug_verbose:
		return
	var eid := str(evt.get("event", ""))
	var pid := int(evt.get("profile_id", 0))
	var msg := "Dialogue emit event=%s profile=%d line=\"%s\" tokens=%s" % [eid, pid, str(line), str(tokens)]
	DbgLog.throttle("dialogue_emit:%s" % eid, 0.5, msg, "dialogue", DbgLog.Level.DEBUG)


func _log_debug(stage: String, evt: Dictionary, detail: String) -> void:
	if not Engine.has_singleton("DbgLog"):
		return
	if not DbgLog.is_enabled("dialogue"):
		return
	if not _debug_verbose:
		return
	var eid := str(evt.get("event", ""))
	var pid := int(evt.get("profile_id", 0))
	var msg := "Dialogue debug stage=%s event=%s profile=%d detail=%s" % [stage, eid, pid, detail]
	DbgLog.throttle("dialogue_debug:%s:%s" % [stage, eid], 0.5, msg, "dialogue", DbgLog.Level.DEBUG)


func _pick_family_flavor_event() -> String:
	var pool := ["callback_family_rivalry", "callback_family_legacy", "callback_family_vow"]
	return String(pool[_rng.randi_range(0, pool.size() - 1)])
