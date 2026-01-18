extends RefCounted
class_name PartyState

# Runtime party state.

var party_id: int = 0
var member_ids: Array[int] = []

# High-level intent for this party (interpreted by PartyAdventureSystem).
var intent: String = "explore" # explore, boss, loot, exit

var leader_adv_id: int = 0


func setup(p_party_id: int, p_member_ids: Array[int]) -> void:
	party_id = p_party_id
	member_ids = []
	for v in p_member_ids:
		member_ids.append(int(v))
	leader_adv_id = member_ids[0] if not member_ids.is_empty() else 0

