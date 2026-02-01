extends RefCounted
class_name HistoryService

# Persistent identities and lightweight event history (session-only).
#
# Public APIs:
# - get_or_create_profile(member_def) -> int profile_id
# - attach_profiles_for_new_members(gen, day)
# - record_adv_exit(adv_id, reason, day)
# - record_death(adv_id, day)
# - schedule_return(profile_id, day, buffPlan)
# - inject_returns_into_generation(gen, day, cfg)
# - apply_returnee_buffs(member_def, buffPlan)
# - record_dialogue(profile_id, text, where := "", tags := [])
# - record_day_change(day, phase)
# - record_loot(profile_id, items, total_value, where := "")
# - record_loot_summary_on_exit(profile_id, summary)
# - get_events(filter := {}) -> Array[Dictionary]
# - format_event(e) -> Dictionary{text, color, icon}
#
# Notes:
# - Session-only storage (cleared when this object is discarded).
# - Ring buffer cap and rich formatting can be layered later (separate tasks).

const TYPE_DAY_CHANGE := "day_change"
const TYPE_SPAWNED := "spawned"
const TYPE_EXITED := "exited"
const TYPE_FLED := "fled"
const TYPE_RETURNED := "returned"
const TYPE_DIED := "died"
const TYPE_LOOT := "loot_gained"
const TYPE_DIALOGUE := "dialogue"
const TYPE_HERO_ARRIVED := "hero_arrived"

var _profiles_by_id: Dictionary = {}            # profile_id -> profile dict
var _next_profile_id: int = 1
var _families_by_id: Dictionary = {}            # family_id -> family dict
var _next_family_id: int = 1

var _events: Array[Dictionary] = []              # chronological list of events
var _history_cap: int = 500                      # default; may be overridden via cfg later

# Schedules due by day: day_index -> Array[Dictionary{returnee}]
var _return_schedules_by_day: Dictionary = {}

# Runtime mappings
var _adv_to_profile_id: Dictionary = {}          # adv_instance_id -> profile_id
var _member_to_profile_id: Dictionary = {}       # generator member_id -> profile_id (for the current day generation)

# Minimal name/backstory generator seed (data-driven rules can be added later)
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _cfg_loaded: bool = false
var _name_cfg_dir: String = ""
var _bio_templates_path: String = ""
var _epithets_path: String = ""
var _names_data: Dictionary = {}
var _bio_templates: Array = []
var _epithet_rules: Dictionary = {}

func _looks_like_generic_fallback_bio(bio: String) -> bool:
	bio = String(bio).strip_edges()
	# Our hard-coded fallback is: "A %s seeking fortune." % class_id
	# If templates failed to load previously, profiles may have cached this placeholder forever.
	return bio.begins_with("A ") and bio.ends_with(" seeking fortune.")

func reset_session(history_cap: int = 500) -> void:
	_profiles_by_id.clear()
	_next_profile_id = 1
	_families_by_id.clear()
	_next_family_id = 1
	_events.clear()
	_return_schedules_by_day.clear()
	_adv_to_profile_id.clear()
	_member_to_profile_id.clear()
	_history_cap = int(history_cap)
	_rng.randomize()

func _ensure_config_loaded() -> void:
	if _cfg_loaded:
		return
	# Access config constants by instantiating the script; avoid scene-tree lookups (this is a RefCounted)
	var cfg: Object = preload("res://autoloads/game_config.gd").new()
	var v1: Variant = cfg.get("NAME_CONFIG_DIR")
	if v1 == null or String(v1) == "":
		_name_cfg_dir = "res://data/names/"
	else:
		_name_cfg_dir = String(v1)
	var v2: Variant = cfg.get("BIO_TEMPLATES_PATH")
	if v2 == null or String(v2) == "":
		_bio_templates_path = "res://data/bio_templates.json"
	else:
		_bio_templates_path = String(v2)
	var v3: Variant = cfg.get("EPITHETS_PATH")
	if v3 == null or String(v3) == "":
		_epithets_path = "res://data/epithets.json"
	else:
		_epithets_path = String(v3)
	var v4: Variant = cfg.get("HISTORY_MAX_ENTRIES")
	if v4 != null and v4 is int:
		_history_cap = int(v4)
	_load_names()
	_load_bios()
	_load_epithets()
	# Explicitly free temporary Node to avoid leak warnings in headless CI.
	if cfg != null and cfg is Object:
		cfg.free()
	_cfg_loaded = true

func _load_names() -> void:
	_names_data.clear()
	var p: String = _name_cfg_dir.rstrip("/") + "/common.json"
	var f: FileAccess = FileAccess.open(p, FileAccess.READ)
	if f == null:
		return
	var txt: String = f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(txt)
	if typeof(data) == TYPE_DICTIONARY:
		_names_data = data as Dictionary

func _load_bios() -> void:
	_bio_templates.clear()
	if _bio_templates_path == "":
		return
	var f: FileAccess = FileAccess.open(_bio_templates_path, FileAccess.READ)
	if f == null:
		if Engine.has_singleton("DbgLog"):
			DbgLog.warn("HistoryService: failed to open bio templates at: %s" % _bio_templates_path, "history")
		return
	var txt: String = f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(txt)
	if typeof(data) == TYPE_ARRAY:
		_bio_templates = data as Array
		if Engine.has_singleton("DbgLog"):
			DbgLog.info("HistoryService: loaded %d bio templates" % _bio_templates.size(), "history")
	else:
		if Engine.has_singleton("DbgLog"):
			DbgLog.warn("HistoryService: bio templates JSON not an array: %s" % _bio_templates_path, "history")

func _load_epithets() -> void:
	_epithet_rules.clear()
	if _epithets_path == "":
		return
	var f: FileAccess = FileAccess.open(_epithets_path, FileAccess.READ)
	if f == null:
		return
	var txt: String = f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(txt)
	if typeof(data) == TYPE_DICTIONARY:
		_epithet_rules = data as Dictionary

func set_history_cap(cap: int) -> void:
	_history_cap = maxi(1, int(cap))
	# Trim immediately if needed
	if _events.size() > _history_cap:
		_events = _events.slice(_events.size() - _history_cap, _events.size())

func get_or_create_profile(member_def: Dictionary) -> int:
	# If member_def has a profile_id, return it; else create a new profile and attach.
	_ensure_config_loaded()
	if member_def.has("profile_id"):
		var pid := int(member_def.get("profile_id", 0))
		if pid != 0 and _profiles_by_id.has(pid):
			return pid
	# Create
	var pid_new := _next_profile_id
	_next_profile_id += 1
	var name_ep := _generate_name_and_epithet(member_def)
	var provided_name := String(member_def.get("name", ""))
	if provided_name != "":
		name_ep["name"] = provided_name
	var provided_origin := String(member_def.get("origin", ""))
	if provided_origin != "":
		name_ep["origin"] = provided_origin
	# Ensure origin is available to bio generation
	var md_for_bio := member_def.duplicate(true)
	md_for_bio["origin"] = String(name_ep.get("origin", "unknown"))
	var bio_line := _generate_bio(md_for_bio, false)
	var provided_bio := String(member_def.get("bio", ""))
	if provided_bio != "":
		bio_line = provided_bio
	var gender := String(member_def.get("gender", ""))
	if gender == "":
		gender = _roll_gender()
	if Engine.has_singleton("DbgLog"):
		DbgLog.throttle(
			"history_bio_create",
			0.5,
			"HistoryService: profile bio generated len=%d name=%s %s origin=%s" % [
				int(bio_line.length()),
				String(name_ep.get("name", "")),
				String(name_ep.get("epithet", "")),
				String(name_ep.get("origin", "")),
			],
			"history",
			DbgLog.Level.DEBUG
		)
	var p := {
		"profile_id": pid_new,
		"name": name_ep.get("name", "Adventurer %d" % pid_new),
		"epithet": name_ep.get("epithet", ""),
		"origin": name_ep.get("origin", ""),
		"bio": bio_line,
		"class_id": String(member_def.get("class_id", "")),
		"gender": gender,
		"family_id": 0,
		"family_name": "",
		"lineage_id": 0,
		"parents": [],
		"siblings": [],
		"children": [],
		"is_hero": bool(member_def.get("is_hero", false)),
		"hero_id": String(member_def.get("hero_id", "")),
		"class_history": [],
		"morality_base": int(member_def.get("morality", 0)),
		"quirks": [],
		"flags": {},
	}
	_profiles_by_id[pid_new] = p
	_assign_family_for_profile(pid_new, member_def)
	return pid_new


func attach_profiles_for_new_members(gen: Dictionary, day: int) -> void:
	# Enrich gen.member_defs with identity fields; maintain member_id -> profile_id mapping.
	_ensure_config_loaded()
	_member_to_profile_id.clear()
	var mdefs: Dictionary = gen.get("member_defs", {}) as Dictionary
	var new_profile_ids: Array[int] = []
	for k in mdefs.keys():
		var mid := int(k)
		var md := mdefs.get(k, {}) as Dictionary
		var pid := get_or_create_profile(md)
		new_profile_ids.append(pid)
		_member_to_profile_id[mid] = pid
		var p: Dictionary = _profiles_by_id.get(pid, {}) as Dictionary
		md["profile_id"] = pid
		md["name"] = String(p.get("name", ""))
		md["epithet"] = String(p.get("epithet", ""))
		md["origin"] = String(p.get("origin", ""))
		md["gender"] = String(p.get("gender", ""))
		md["family_id"] = int(p.get("family_id", 0))
		md["family_name"] = String(p.get("family_name", ""))
		var bio_str: String = String(p.get("bio", ""))
		# If bio looks empty or placeholder fallback, regenerate now that we know class+origin.
		var class_id := String(md.get("class_id", "adventurer"))
		if bio_str == "" or _looks_like_generic_fallback_bio(bio_str):
			_load_bios() # ensure latest
			var md_tokens := { "class_id": class_id, "origin": String(p.get("origin", "unknown")) }
			var regen := _generate_bio(md_tokens, bool(md.get("returnee", false)))
			if regen != "":
				bio_str = regen
				# Store back into profile for future days
				var prof := _profiles_by_id[pid] as Dictionary
				prof["bio"] = bio_str
				_profiles_by_id[pid] = prof
				if Engine.has_singleton("DbgLog"):
					DbgLog.debug("HistoryService: regenerated bio for pid=%d" % pid, "history")
			else:
				if Engine.has_singleton("DbgLog"):
					DbgLog.warn("HistoryService: bio regeneration still empty for pid=%d" % pid, "history")
		md["bio"] = bio_str
		mdefs[mid] = md
	gen["member_defs"] = mdefs
	_seed_family_links_for_profiles(new_profile_ids)
	_record_event({ "day": int(day), "type": TYPE_DAY_CHANGE, "payload": { "phase": "start" } })


func attach_profiles_for_new_members_preview(gen: Dictionary) -> void:
	# Like `attach_profiles_for_new_members`, but does NOT record day-change history.
	# Used for BUILD-phase preview so tooltips can show names/bios before the day starts.
	_ensure_config_loaded()
	_member_to_profile_id.clear()
	var mdefs: Dictionary = gen.get("member_defs", {}) as Dictionary
	var new_profile_ids: Array[int] = []
	for k in mdefs.keys():
		var mid := int(k)
		var md := mdefs.get(k, {}) as Dictionary
		var pid := get_or_create_profile(md)
		new_profile_ids.append(pid)
		_member_to_profile_id[mid] = pid
		var p: Dictionary = _profiles_by_id.get(pid, {}) as Dictionary
		md["profile_id"] = pid
		md["name"] = String(p.get("name", ""))
		md["epithet"] = String(p.get("epithet", ""))
		md["origin"] = String(p.get("origin", ""))
		md["gender"] = String(p.get("gender", ""))
		md["family_id"] = int(p.get("family_id", 0))
		md["family_name"] = String(p.get("family_name", ""))
		var bio_str: String = String(p.get("bio", ""))
		# If bio looks empty or placeholder fallback, regenerate now that we know class+origin.
		var class_id := String(md.get("class_id", "adventurer"))
		if bio_str == "" or _looks_like_generic_fallback_bio(bio_str):
			_load_bios() # ensure latest
			var md_tokens := { "class_id": class_id, "origin": String(p.get("origin", "unknown")) }
			var regen := _generate_bio(md_tokens, bool(md.get("returnee", false)))
			if regen != "":
				bio_str = regen
				# Store back into profile for future days
				var prof := _profiles_by_id[pid] as Dictionary
				prof["bio"] = bio_str
				_profiles_by_id[pid] = prof
		md["bio"] = bio_str
		mdefs[mid] = md
	gen["member_defs"] = mdefs
	_seed_family_links_for_profiles(new_profile_ids)


func record_adv_exit(adv_id: int, reason: String, day: int) -> void:
	var pid := int(_adv_to_profile_id.get(int(adv_id), 0))
	if reason == "flee":
		_record_event({ "day": int(day), "type": TYPE_FLED, "payload": { "profile_id": pid, "adv_id": int(adv_id) } })
		# Default schedule: return after RETURN_DAYS (picked up from cfg by caller of inject)
		_schedule_return_with_default(pid, int(day))
	else:
		_record_event({ "day": int(day), "type": TYPE_EXITED, "payload": { "profile_id": pid, "adv_id": int(adv_id) } })


func record_death(adv_id: int, day: int) -> void:
	var pid := int(_adv_to_profile_id.get(int(adv_id), 0))
	_record_event({ "day": int(day), "type": TYPE_DIED, "payload": { "profile_id": pid, "adv_id": int(adv_id) } })


func schedule_return(profile_id: int, scheduled_day: int, buffPlan: Dictionary) -> void:
	if profile_id == 0 or scheduled_day <= 0:
		return
	var arr: Array = _return_schedules_by_day.get(int(scheduled_day), []) as Array
	arr.append({
		"profile_id": int(profile_id),
		"scheduled_day": int(scheduled_day),
		"buffPlan": buffPlan.duplicate(true),
		"reason": String(buffPlan.get("reason", "flee")),
	})
	_return_schedules_by_day[int(scheduled_day)] = arr


func inject_returns_into_generation(gen: Dictionary, day: int, cfg: Object) -> void:
	# Pop schedules for this day and inject 1-member micro-parties with buffs applied.
	var due: Array = _return_schedules_by_day.get(int(day), []) as Array
	if due.is_empty():
		return
	_return_schedules_by_day.erase(int(day))
	if due.is_empty():
		return

	var mdefs: Dictionary = gen.get("member_defs", {}) as Dictionary
	var pdefs: Array = gen.get("party_defs", []) as Array

	# Find next available ids
	var next_member_id := 1
	for k in mdefs.keys():
		next_member_id = maxi(next_member_id, int(k) + 1)
	var max_party_id := 0
	for pd in pdefs:
		max_party_id = maxi(max_party_id, int((pd as Dictionary).get("party_id", 0)))
	var next_party_id := max_party_id + 1

	for r0 in due:
		var r := r0 as Dictionary
		var pid := int(r.get("profile_id", 0))
		if pid == 0:
			continue
		var prof: Dictionary = _profiles_by_id.get(pid, {}) as Dictionary
		# Minimal member template; class can be biased later. Default to warrior.
		var md := {
			"class_id": "warrior",
			"party_id": next_party_id,
			"traits": [],
			"ability_id": "",
			"ability_charges": 1,
			"stat_mods": {},
			"returnee": true,
			"profile_id": pid,
			"name": String(prof.get("name", "")),
			"epithet": String(prof.get("epithet", "")),
			"origin": String(prof.get("origin", "")),
			"bio": "",
		}
		var bio_str := String(prof.get("bio", ""))
		if bio_str == "" or _looks_like_generic_fallback_bio(bio_str):
			var regen := _generate_bio({ "class_id": String(md.get("class_id")), "origin": String(md.get("origin", "unknown")) }, true)
			if regen != "":
				bio_str = regen
				prof["bio"] = bio_str
				_profiles_by_id[pid] = prof
		md["bio"] = bio_str
		md = apply_returnee_buffs(md, r.get("buffPlan", {}) as Dictionary)
		var mid := next_member_id
		next_member_id += 1
		mdefs[mid] = md
		pdefs.append({ "party_id": next_party_id, "member_ids": [mid] })
		next_party_id += 1
		_record_event({ "day": int(day), "type": TYPE_RETURNED, "payload": { "profile_id": pid } })

	gen["member_defs"] = mdefs
	gen["party_defs"] = pdefs


func apply_returnee_buffs(member_def: Dictionary, buffPlan: Dictionary) -> Dictionary:
	if buffPlan.is_empty():
		return member_def
	var mods: Dictionary = member_def.get("stat_mods", {}) as Dictionary
	for k in buffPlan.keys():
		var key := String(k)
		if key.ends_with("_bonus"):
			mods[key] = int(buffPlan.get(key, 0)) + int(mods.get(key, 0))
	member_def["stat_mods"] = mods
	return member_def


func record_dialogue(profile_id: int, text: String, where: String = "", tags: Array = []) -> void:
	text = String(text).strip_edges()
	if text == "":
		return
	_record_event({
		"day": _guess_current_day(),
		"type": TYPE_DIALOGUE,
		"severity": "flavor",
		"payload": {
			"profile_id": int(profile_id),
			"text": text,
			"where": String(where),
			"tags": tags.duplicate(true),
		}
	})


func record_day_change(day: int, phase: String) -> void:
	_record_event({ "day": int(day), "type": TYPE_DAY_CHANGE, "severity": "minor", "payload": { "phase": String(phase) } })


func record_loot(profile_id: int, items: Array, total_value: int, where: String) -> void:
	_record_event({
		"day": _guess_current_day(),
		"type": TYPE_LOOT,
		"severity": "minor",
		"payload": {
			"profile_id": int(profile_id),
			"items": items.duplicate(true),
			"total_value": int(total_value),
			"where": String(where),
		}
	})


func record_loot_summary_on_exit(profile_id: int, summary: Array) -> void:
	_record_event({
		"day": _guess_current_day(),
		"type": TYPE_LOOT,
		"severity": "minor",
		"payload": {
			"profile_id": int(profile_id),
			"summary": summary.duplicate(true),
		}
	})


func record_hero_arrival(profile_id: int, hero_id: String, day: int) -> void:
	_record_event({
		"day": int(day),
		"type": TYPE_HERO_ARRIVED,
		"severity": "major",
		"payload": {
			"profile_id": int(profile_id),
			"hero_id": String(hero_id),
		}
	})


func register_adv_profile_mapping(adv_id: int, profile_id: int) -> void:
	if int(adv_id) == 0 or int(profile_id) == 0:
		return
	_adv_to_profile_id[int(adv_id)] = int(profile_id)


func get_events(filter: Dictionary = {}) -> Array[Dictionary]:
	# Simple filtering by keys: types (Array[String]), day_min, day_max, actor_id/profile_id, tags (Array), text_contains (String)
	if _events.is_empty():
		return []
	var out: Array[Dictionary] = []
	var types: Array = filter.get("types", []) as Array
	var type_set := {}
	for t in types:
		type_set[String(t)] = true
	var sev: Array = filter.get("severities", []) as Array
	var sev_set := {}
	for s in sev:
		sev_set[String(s)] = true
	var day_min := int(filter.get("day_min", -999999))
	var day_max := int(filter.get("day_max", 999999))
	var profile_id := int(filter.get("profile_id", 0))
	var text_contains := String(filter.get("text_contains", "")).strip_edges().to_lower()
	var want_tags: Array = filter.get("tags", []) as Array
	for e in _events:
		var day := int(e.get("day", 0))
		if day < day_min or day > day_max:
			continue
		if not type_set.is_empty() and not type_set.has(String(e.get("type", ""))):
			continue
		if not sev_set.is_empty() and not sev_set.has(String(e.get("severity", ""))):
			continue
		if profile_id != 0 and int((e.get("payload", {}) as Dictionary).get("profile_id", 0)) != profile_id:
			continue
		if text_contains != "":
			var payload := e.get("payload", {}) as Dictionary
			var text := String(payload.get("text", "")).to_lower()
			if text == "" or not text.findn(text_contains) >= 0:
				continue
		if not want_tags.is_empty():
			var payload2 := e.get("payload", {}) as Dictionary
			var tags2: Array = payload2.get("tags", []) as Array
			var ok := true
			for w in want_tags:
				if not tags2.has(w):
					ok = false
					break
			if not ok:
				continue
		out.append(e)
	return out


func get_profile(profile_id: int) -> Dictionary:
	if profile_id == 0:
		return {}
	if not _profiles_by_id.has(int(profile_id)):
		return {}
	return (_profiles_by_id[int(profile_id)] as Dictionary).duplicate(true)


func get_family(family_id: int) -> Dictionary:
	if family_id == 0:
		return {}
	if not _families_by_id.has(int(family_id)):
		return {}
	return (_families_by_id[int(family_id)] as Dictionary).duplicate(true)


func get_recent_context(profile_id: int, max_events: int = 5) -> Dictionary:
	if profile_id == 0:
		return {}
	var found: Dictionary = {}
	var count := 0
	for i in range(_events.size() - 1, -1, -1):
		var e := _events[i] as Dictionary
		var p := e.get("payload", {}) as Dictionary
		if int(p.get("profile_id", 0)) != int(profile_id):
			continue
		var t := str(e.get("type", ""))
		if t == "":
			continue
		var formatted := format_event(e)
		found["last_event_text"] = str(formatted.get("text", ""))
		found["last_event_type"] = t
		found["last_event_day"] = str(e.get("day", ""))
		count += 1
		if count >= max_events:
			break
	return found


func get_recent_family_context(profile_id: int, max_events: int = 10) -> Dictionary:
	if profile_id == 0:
		return {}
	var self_profile := _profiles_by_id.get(int(profile_id), {}) as Dictionary
	if self_profile.is_empty():
		return {}
	var family_id := int(self_profile.get("family_id", 0))
	if family_id == 0:
		return {}
	var members: Array = []
	var fam := _families_by_id.get(family_id, {}) as Dictionary
	if not fam.is_empty():
		members = fam.get("members", []) as Array
	if members.is_empty():
		return {}
	var count := 0
	for i in range(_events.size() - 1, -1, -1):
		var e := _events[i] as Dictionary
		var p := e.get("payload", {}) as Dictionary
		var pid := int(p.get("profile_id", 0))
		if pid == 0 or pid == int(profile_id):
			continue
		if not members.has(pid):
			continue
		var t := String(e.get("type", ""))
		if t == "":
			continue
		# Prefer major family beats.
		if t != TYPE_DIED and t != TYPE_FLED and t != TYPE_RETURNED and t != TYPE_HERO_ARRIVED:
			continue
		var rel_profile := _profiles_by_id.get(pid, {}) as Dictionary
		if rel_profile.is_empty():
			continue
		var rel_name := String(rel_profile.get("name", ""))
		var rel_word := _relation_word(profile_id, pid)
		var formatted := format_event(e)
		var rel_event_type := t
		if t == TYPE_RETURNED:
			rel_event_type = "returned"
		elif t == TYPE_HERO_ARRIVED:
			rel_event_type = "hero"
		return {
			"relative_id": pid,
			"relative_name": rel_name,
			"relative_relation_word": rel_word,
			"relative_event_type": rel_event_type,
			"relative_event_text": String(formatted.get("text", "")),
			"relative_hero_id": String(p.get("hero_id", "")),
		}
		count += 1
		if count >= max_events:
			break
	return {}


func format_event(e: Dictionary) -> Dictionary:
	# Minimal formatter; can be expanded later.
	var t := String(e.get("type", ""))
	var p := e.get("payload", {}) as Dictionary
	var pid := int(p.get("profile_id", 0))
	var name := ""
	if pid != 0 and _profiles_by_id.has(pid):
		name = String((_profiles_by_id[pid] as Dictionary).get("name", ""))
	match t:
		TYPE_DIALOGUE:
			return { "text": ("%s: %s" % [name, String(p.get("text", ""))]).strip_edges(), "color": Color.WHITE, "icon": "🗨" }
		TYPE_HERO_ARRIVED:
			var hid := String(p.get("hero_id", ""))
			var hero_label := (("Hero " + hid) if hid != "" else "Hero")
			return { "text": ("%s arrived (%s)" % [name, hero_label]).strip_edges(), "color": Color.SKY_BLUE, "icon": "★" }
		TYPE_FLED:
			return { "text": ("%s fled" % name).strip_edges(), "color": Color.SALMON, "icon": "🏃" }
		TYPE_EXITED:
			return { "text": ("%s exited" % name).strip_edges(), "color": Color.SILVER, "icon": "🚪" }
		TYPE_RETURNED:
			return { "text": ("%s returned" % name).strip_edges(), "color": Color.LIGHT_GREEN, "icon": "↩" }
		TYPE_DIED:
			return { "text": ("%s died" % name).strip_edges(), "color": Color.ORANGE_RED, "icon": "✖" }
		TYPE_LOOT:
			var items: Array = p.get("items", []) as Array
			var n := items.size()
			var val := int(p.get("total_value", 0))
			var text := "%s took loot" % name
			if n > 0 and val > 0:
				text = "%s took %d item(s) worth %dg" % [name, n, val]
			elif n > 0:
				text = "%s took %d item(s)" % [name, n]
			return { "text": text.strip_edges(), "color": Color.GOLD, "icon": "💰" }
		TYPE_DAY_CHANGE:
			return { "text": ("Day %d (%s)" % [int(e.get("day", 0)), String(p.get("phase", ""))]).strip_edges(), "color": Color.GRAY, "icon": "📜" }
		_:
			return { "text": t, "color": Color.WHITE, "icon": "" }


#
# Helpers
#

func _record_event(e: Dictionary) -> void:
	if not e.has("severity"):
		e["severity"] = _severity_for_type(String(e.get("type", "")))
	_events.append(e)
	# Enforce ring buffer cap.
	if _events.size() > _history_cap:
		_events = _events.slice(_events.size() - _history_cap, _events.size())


func _assign_family_for_profile(profile_id: int, member_def: Dictionary) -> void:
	if profile_id == 0:
		return
	var p := _profiles_by_id.get(profile_id, {}) as Dictionary
	if p.is_empty():
		return
	var family_id := int(member_def.get("family_id", 0))
	var family_name := String(member_def.get("family_name", ""))
	var lineage_id := int(member_def.get("lineage_id", 0))
	if family_name == "":
		var nm := String(p.get("name", ""))
		var parts := nm.split(" ")
		if parts.size() >= 2:
			family_name = String(parts[parts.size() - 1])
	if family_id == 0:
		family_id = _next_family_id
		_next_family_id += 1
	if lineage_id == 0:
		lineage_id = family_id
	p["family_id"] = family_id
	p["family_name"] = family_name
	p["lineage_id"] = lineage_id
	_profiles_by_id[profile_id] = p
	_ensure_family_record(family_id, family_name, lineage_id, profile_id)


func _ensure_family_record(family_id: int, family_name: String, lineage_id: int, profile_id: int) -> void:
	if family_id == 0:
		return
	var fam := _families_by_id.get(family_id, {}) as Dictionary
	if fam.is_empty():
		fam = {
			"family_id": family_id,
			"family_name": family_name,
			"lineage_id": lineage_id,
			"members": [],
		}
	var members: Array = fam.get("members", []) as Array
	if not members.has(profile_id):
		members.append(profile_id)
	fam["members"] = members
	_families_by_id[family_id] = fam


func _seed_family_links_for_profiles(profile_ids: Array[int]) -> void:
	if profile_ids.is_empty():
		return
	var by_family: Dictionary = {}
	for pid0 in profile_ids:
		var pid := int(pid0)
		var p := _profiles_by_id.get(pid, {}) as Dictionary
		if p.is_empty():
			continue
		var fid := int(p.get("family_id", 0))
		if fid == 0:
			continue
		if not by_family.has(fid):
			by_family[fid] = []
		(by_family[fid] as Array).append(pid)
	for fid_key in by_family.keys():
		var members: Array = by_family[fid_key] as Array
		if members.size() < 2:
			continue
		# Siblings: all members of the family for this day are siblings by default.
		for pid2_0 in members:
			var pid2 := int(pid2_0)
			var p2 := _profiles_by_id.get(pid2, {}) as Dictionary
			if p2.is_empty():
				continue
			var sibs: Array = p2.get("siblings", []) as Array
			for pid3_0 in members:
				var pid3 := int(pid3_0)
				if pid3 == pid2:
					continue
				if not sibs.has(pid3):
					sibs.append(pid3)
			p2["siblings"] = sibs
			_profiles_by_id[pid2] = p2
		# Occasional parent-child relation to create lineage flavor.
		if members.size() >= 2 and _rng.randf() < 0.25:
			var parent := int(members[0])
			var child := int(members[1])
			var p_parent := _profiles_by_id.get(parent, {}) as Dictionary
			var p_child := _profiles_by_id.get(child, {}) as Dictionary
			if not p_parent.is_empty() and not p_child.is_empty():
				var kids: Array = p_parent.get("children", []) as Array
				if not kids.has(child):
					kids.append(child)
				p_parent["children"] = kids
				var parents: Array = p_child.get("parents", []) as Array
				if not parents.has(parent):
					parents.append(parent)
				p_child["parents"] = parents
				_profiles_by_id[parent] = p_parent
				_profiles_by_id[child] = p_child


func _roll_gender() -> String:
	var opts := ["male", "female", "nonbinary"]
	return String(opts[_rng.randi() % opts.size()])


func _relation_word(profile_id: int, other_id: int) -> String:
	var p := _profiles_by_id.get(int(profile_id), {}) as Dictionary
	var o := _profiles_by_id.get(int(other_id), {}) as Dictionary
	if p.is_empty() or o.is_empty():
		return "kin"
	var gender := String(o.get("gender", ""))
	var parents: Array = p.get("parents", []) as Array
	var children: Array = p.get("children", []) as Array
	var siblings: Array = p.get("siblings", []) as Array
	if children.has(other_id):
		if gender == "female":
			return "daughter"
		if gender == "male":
			return "son"
		return "child"
	if parents.has(other_id):
		if gender == "female":
			return "mother"
		if gender == "male":
			return "father"
		return "parent"
	if siblings.has(other_id):
		if gender == "female":
			return "sister"
		if gender == "male":
			return "brother"
		return "sibling"
	return "kin"


func _severity_for_type(t: String) -> String:
	match String(t):
		TYPE_DIED:
			return "major"
		TYPE_HERO_ARRIVED:
			return "major"
		TYPE_DAY_CHANGE:
			return "minor"
		TYPE_DIALOGUE:
			return "flavor"
		TYPE_LOOT:
			return "minor"
		TYPE_FLED:
			return "minor"
		TYPE_EXITED:
			return "minor"
		TYPE_RETURNED:
			return "minor"
		_:
			return "minor"


func _generate_name_and_epithet(member_def: Dictionary) -> Dictionary:
	var class_id := String(member_def.get("class_id", ""))
	# Try data-driven pools first
	var f: String = ""
	var l: String = ""
	var epi: String = ""
	var org: String = ""
	if not _names_data.is_empty():
		var cul := (_names_data.get("cultures", {}) as Dictionary).get("common", {}) as Dictionary
		var male: Array = cul.get("male", []) as Array
		var female: Array = cul.get("female", []) as Array
		var unisex: Array = cul.get("unisex", []) as Array
		var surnames: Array = cul.get("surnames", []) as Array
		var pool: Array = []
		pool.append_array(unisex)
		pool.append_array(male)
		pool.append_array(female)
		if not pool.is_empty():
			f = String(pool[_rng.randi() % pool.size()])
		if not surnames.is_empty():
			l = String(surnames[_rng.randi() % surnames.size()])
	# Fallback lists
	if f == "" or l == "":
		var firsts := ["Eira", "Rowan", "Ash", "Lysa", "Borin", "Alaric", "Talia", "Cedric", "Mira", "Kestrel", "Vale", "Darin"]
		var lasts := ["Stonehand", "Northwind", "Quickstep", "Ironheart", "Ashdown", "Briar", "Greyford", "Westvale"]
		f = (f if f != "" else String(firsts[_rng.randi() % firsts.size()]))
		l = (l if l != "" else String(lasts[_rng.randi() % lasts.size()]))
	# Epithets (data-driven if available)
	if not _epithet_rules.is_empty():
		var rules: Array = _epithet_rules.get("rules", []) as Array
		var candidates: Array[String] = []
		for r0 in rules:
			var r := r0 as Dictionary
			var match := r.get("match", {}) as Dictionary
			if _tokens_match({ "class_id": class_id, "fled": false, "returnee": false }, match):
				for v in (r.get("values", []) as Array):
					var s := String(v)
					if s != "":
						candidates.append(s)
		if not candidates.is_empty():
			epi = String(candidates[_rng.randi() % candidates.size()])
	if epi == "":
		var ep_all := ["the Cautious", "the Brave", "the Wary", "the Stalwart", "Ironheart", "Quickstep"]
		epi = String(ep_all[_rng.randi() % ep_all.size()])
	# Origin
	var o_all := ["Northreach", "Westvale", "Greyford", "Stoneford", "Briar Glen"]
	org = String(o_all[_rng.randi() % o_all.size()])
	return {
		"name": "%s %s" % [f, l],
		"epithet": epi,
		"origin": org,
	}


func _generate_bio(member_def: Dictionary, returnee: bool) -> String:
	var class_id := str(member_def.get("class_id", "adventurer"))
	var tokens := {
		"class_id": class_id,
		"origin": str(member_def.get("origin", "unknown")),
		"fled": false,
		"returnee": bool(returnee),
		"kills": 0,
		"rooms_seen": 0,
		"loot_value": 0,
		"scars": 0,
	}
	if not _bio_templates.is_empty():
		var pool: Array[Dictionary] = []
		for t0 in _bio_templates:
			var d := t0 as Dictionary
			var when := d.get("when", {}) as Dictionary
			if _tokens_match(tokens, when):
				pool.append(d)
		if pool.is_empty():
			pool = _bio_templates.duplicate()
		if not pool.is_empty():
			# Weighted pick
			var total := 0
			for d2 in pool:
				total += int((d2 as Dictionary).get("weight", 1))
			if total <= 0:
				total = pool.size()
			var pick: int = int(_rng.randi() % total)
			var acc: int = 0
			var templ: String = ""
			for d3 in pool:
				acc += int((d3 as Dictionary).get("weight", 1))
				if pick < acc:
					templ = str((d3 as Dictionary).get("template", ""))
					break
			for k in tokens.keys():
				var key := str(k)
				templ = templ.replace("{%s}" % key, str(tokens.get(key, "")))
			if templ != "":
				if Engine.has_singleton("DbgLog"):
					DbgLog.throttle(
						"history_bio_pick",
						0.5,
						"HistoryService: picked bio template (pool=%d): %s" % [pool.size(), templ],
						"history",
						DbgLog.Level.DEBUG
					)
				return templ
	# Fallback
	if Engine.has_singleton("DbgLog"):
		DbgLog.throttle(
			"history_bio_fallback",
			0.5,
			"HistoryService: bio fallback used (templates=%d)" % [_bio_templates.size()],
		 "history",
		 DbgLog.Level.DEBUG
		)
	return "A %s seeking fortune." % class_id

func _tokens_match(tokens: Dictionary, cond: Dictionary) -> bool:
	if cond.is_empty():
		return true
	for k in cond.keys():
		var kk := str(k)
		if kk == "*":
			return true
		var want: Variant = cond[k]
		var have: Variant = tokens.get(kk, null)
		if typeof(want) == TYPE_BOOL:
			if bool(have) != bool(want):
				return false
		elif typeof(want) == TYPE_INT:
			if int(have) < int(want):
				return false
		else:
			# Some tokens may be missing; avoid casting null via String(...)
			if have == null:
				return false
			if str(have) != str(want):
				return false
	return true

func _schedule_return_with_default(profile_id: int, fled_day: int) -> void:
	if profile_id == 0:
		return
	# Default: 2 days later with a small hp bonus; caller may override via explicit schedule.
	var buff := { "hp_bonus": 2, "reason": "flee" }
	schedule_return(int(profile_id), int(fled_day) + 2, buff)

func _guess_current_day() -> int:
	# NOTE: `GameState` is an autoload Object; `"day_index" in GameState` does NOT work reliably.
	if GameState != null:
		return int(GameState.day_index)
	return 0
