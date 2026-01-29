extends Node

signal db_ready()

# Central registry for item resources (.tres).

var traps: Dictionary = {}
var monsters: Dictionary = {}
var classes: Dictionary = {}
var treasures: Dictionary = {}
var boss_upgrades: Dictionary = {}

const MONSTERS_DIR := "res://scripts/monsters"


func _ready() -> void:
	# Traps
	traps["spike_trap"] = load("res://scripts/items/SpikeTrap.tres")
	traps["floor_pit"] = load("res://scripts/items/FloorPit.tres")
	traps["teleport_trap"] = load("res://scripts/items/TeleportTrap.tres")
	traps["web_trap"] = load("res://scripts/items/WebTrap.tres")
	traps["rearm_trap"] = load("res://scripts/items/RearmTrap.tres")

	# Monsters
	_load_monsters()

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

	# Boss upgrades
	_load_boss_upgrades()

	if Engine.has_singleton("DbgLog"):
		DbgLog.debug("ItemDB: ready traps=%d monsters=%d treasures=%d boss_upgrades=%d" % [
			traps.size(), monsters.size(), treasures.size(), boss_upgrades.size()
		], "inventory")
	db_ready.emit()


func _load_monsters() -> void:
	monsters.clear()

	# Load monsters from res://scripts/monsters (drop-in content).
	var dir := DirAccess.open(MONSTERS_DIR)
	if dir == null:
		push_warning("ItemDB: missing monsters dir %s" % MONSTERS_DIR)
	else:
		dir.list_dir_begin()
		while true:
			var file_name := dir.get_next()
			if file_name == "":
				break
			if dir.current_is_dir():
				continue
			if not file_name.ends_with(".tres"):
				continue
			var res_path := "%s/%s" % [MONSTERS_DIR, file_name]
			_register_monster_resource(load(res_path))
		dir.list_dir_end()

	# Fallback: ensure core monsters are present even if directory scanning fails/misses.
	# (This also makes behavior more stable in exports / edge-case filesystem issues.)
	_try_load_monster("%s/Zombie.tres" % MONSTERS_DIR)
	_try_load_monster("%s/Skeleton.tres" % MONSTERS_DIR)
	_try_load_monster("%s/Ogre.tres" % MONSTERS_DIR)
	_try_load_monster("%s/Slime.tres" % MONSTERS_DIR)

	# Boss is still kept in scripts/items, but treated as a monster.
	_register_monster_resource(load("res://scripts/items/Boss.tres"))


func _register_monster_resource(res: Resource) -> void:
	var mon := res as MonsterItem
	if mon == null:
		return
	var id := String(mon.id)
	if id == "":
		return
	monsters[id] = mon


func _try_load_monster(res_path: String) -> void:
	_register_monster_resource(load(res_path))


func _load_boss_upgrades() -> void:
	boss_upgrades.clear()
	var dir := DirAccess.open("res://assets/icons/boss_upgrades")
	if dir == null:
		push_warning("ItemDB: missing boss upgrades dir")
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
		if file_name.ends_with("BossUpgradeAtlas.tres"):
			continue
		var res_path := "res://assets/icons/boss_upgrades/%s" % file_name
		var res: Resource = load(res_path)
		var up := res as BossUpgradeItem
		if up == null:
			continue
		var id := String(up.upgrade_id)
		if id == "":
			continue
		boss_upgrades[id] = up
	dir.list_dir_end()


func get_trap(id: String) -> TrapItem:
	return traps.get(id, null) as TrapItem


func get_monster(id: String) -> MonsterItem:
	return monsters.get(id, null) as MonsterItem


func get_adv_class(id: String) -> AdventurerClass:
	return classes.get(id, null) as AdventurerClass


func get_treasure(id: String) -> TreasureItem:
	return treasures.get(id, null) as TreasureItem


func get_boss_upgrade(id: String) -> BossUpgradeItem:
	return boss_upgrades.get(id, null) as BossUpgradeItem


func get_any_item(id: String) -> Resource:
	# Convenience for UI: look in traps then monsters.
	if traps.has(id):
		return traps[id] as Resource
	if monsters.has(id):
		return monsters[id] as Resource
	if treasures.has(id):
		return treasures[id] as Resource
	if boss_upgrades.has(id):
		return boss_upgrades[id] as Resource
	return null


func get_item_kind(id: String) -> String:
	if traps.has(id):
		return "trap"
	if monsters.has(id):
		return "monster"
	if treasures.has(id):
		return "treasure"
	if boss_upgrades.has(id):
		return "boss_upgrade"
	return ""
