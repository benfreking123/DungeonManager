extends RefCounted
class_name AdventurerBrain

# Runtime state and personality for a single adventurer member.

var adv_id: int = 0
var party_id: int = 0

var morality: int = 0 # [-5, +5] low = selfish/chaotic
var goal_weights: Dictionary = {} # goal_id -> int weight (includes base + unique)
var goal_params: Dictionary = {} # goal_id -> Dictionary params (spawn-rolled)

var stole_anything: bool = false
var took_any_damage: bool = false
var flee_triggered: bool = false
var flee_delay_rooms_remaining: int = 0

# Progress tracking for quantified goals
var monsters_killed: int = 0

var stolen_inv_cap: int = 2
var stolen_treasure: Array[String] = [] # treasure item_ids
var last_hp: int = 0
var last_hp_max: int = 0


func setup(p_adv_id: int, p_party_id: int, p_morality: int, p_goal_weights: Dictionary, p_goal_params: Dictionary, p_stolen_inv_cap: int) -> void:
	adv_id = p_adv_id
	party_id = p_party_id
	morality = clampi(int(p_morality), -5, 5)
	goal_weights = p_goal_weights.duplicate(true) if p_goal_weights != null else {}
	goal_params = p_goal_params.duplicate(true) if p_goal_params != null else {}
	stolen_inv_cap = maxi(0, int(p_stolen_inv_cap))


func can_steal_more() -> bool:
	return stolen_treasure.size() < stolen_inv_cap


func add_stolen(item_id: String) -> bool:
	if item_id == "":
		return false
	if not can_steal_more():
		return false
	stolen_treasure.append(item_id)
	stole_anything = true
	return true


func pop_all_stolen() -> Array[String]:
	var out := stolen_treasure.duplicate()
	stolen_treasure.clear()
	return out


func has_goal(goal_id: String) -> bool:
	return goal_id != "" and goal_weights.has(goal_id)


func goal_weight(goal_id: String) -> int:
	return int(goal_weights.get(goal_id, 0))


func goal_param(goal_id: String, key: String, fallback: Variant = null) -> Variant:
	var d: Dictionary = goal_params.get(String(goal_id), {}) as Dictionary
	return d.get(String(key), fallback)

