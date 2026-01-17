extends Node

# Central registry for item resources (.tres).

var traps: Dictionary = {}
var monsters: Dictionary = {}
var classes: Dictionary = {}
var treasures: Dictionary = {}


func _ready() -> void:
	# Traps
	traps["spike_trap"] = load("res://scripts/items/SpikeTrap.tres")
	traps["floor_pit"] = load("res://scripts/items/FloorPit.tres")

	# Monsters
	monsters["zombie"] = load("res://scripts/items/Zombie.tres")
	monsters["boss"] = load("res://scripts/items/Boss.tres")

	# Classes (added later by this rollout)
	classes["warrior"] = load("res://scripts/classes/Warrior.tres")
	classes["rogue"] = load("res://scripts/classes/Rogue.tres")
	classes["mage"] = load("res://scripts/classes/Mage.tres")
	classes["priest"] = load("res://scripts/classes/Priest.tres")

	# Treasures
	treasures["treasure_base"] = load("res://scripts/items/Treasure_Base_Item.tres")
	treasures["treasure_mage"] = load("res://scripts/items/Treasure_Mage_Item.tres")
	treasures["treasure_priest"] = load("res://scripts/items/Treasure_Priest_Item.tres")
	treasures["treasure_rogue"] = load("res://scripts/items/Treasure_Rogue_Item.tres")
	treasures["treasure_warrior"] = load("res://scripts/items/Treasure_Warrior_Item.tres")


func get_trap(id: String) -> TrapItem:
	return traps.get(id, null) as TrapItem


func get_monster(id: String) -> MonsterItem:
	return monsters.get(id, null) as MonsterItem


func get_adv_class(id: String) -> AdventurerClass:
	return classes.get(id, null) as AdventurerClass


func get_treasure(id: String) -> TreasureItem:
	return treasures.get(id, null) as TreasureItem


func get_any_item(id: String) -> Resource:
	# Convenience for UI: look in traps then monsters.
	if traps.has(id):
		return traps[id] as Resource
	if monsters.has(id):
		return monsters[id] as Resource
	if treasures.has(id):
		return treasures[id] as Resource
	return null


func get_item_kind(id: String) -> String:
	if traps.has(id):
		return "trap"
	if monsters.has(id):
		return "monster"
	if treasures.has(id):
		return "treasure"
	return ""
