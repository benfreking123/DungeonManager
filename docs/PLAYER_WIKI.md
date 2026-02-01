## Player Wiki

This is the player-facing reference for what exists in the game right now: core rules, categories, and a complete list of rooms/items/upgrades/classes by **ID** and **name**.

### Core rules (high level)
- **Phases**: You build your dungeon (**BUILD**), then adventurers run it (**DAY**), then you see outcomes (**RESULTS**).
- **Power**: Rooms cost power to place. Your total power capacity can be increased by Treasure (depending on your current rules/tunables).
- **Unique rooms**: Some rooms are “one only” (notably Entrance, Boss, Treasure).
- **Slots**: Some rooms have slots. You can install items into matching slot types (Monster/Trap/Treasure/Boss Upgrade, plus “Universal” slots in the Boss room).
- **Adventurer party behavior**:
  - Parties generally travel together and regroup after fights; stragglers catch up.
  - Adventurers can pick up treasure dropped on the ground. The more loot they carry, the more likely they are to leave with it.
  - Adventurers pause briefly after reaching a goal before choosing the next target.
  - Low-morality individuals may break off from the group if they strongly disagree with the party plan.

---

## Rooms
Rooms are placed during BUILD. Each room type has an `id` and a display label.

- **`entrance`**: Entrance
- **`boss`**: Boss
- **`treasure`**: Treasure
- **`monster`**: Monster
- **`trap`**: Trap
- **`hall`**: Hallway
- **`corridor`**: Corridor
- **`stairs`**: Stairs
- **`hall_plus`**: Hallway +
- **`hall_t_left`**: Hallway T (Left)

## Traps
Traps are installable items (usually into Trap room slots).

- **`spike_trap`**: Spike Trap
- **`floor_pit`**: Floor Pit

## Monsters
Monsters are installable items (usually into Monster room slots). Boss is its own monster.

- **`zombie`**: Zombie
- **`skeleton`**: Skeleton
- **`ogre`**: Ogre
- **`slime`**: Slime
- **`boss`**: Boss

## Treasure
Treasure items are installable (usually into Treasure room slots).

- **`treasure_base`**: Treasure
- **`treasure_warrior`**: Warrior Treasure
- **`treasure_rogue`**: Rogue Treasure
- **`treasure_mage`**: Mage Treasure
- **`treasure_priest`**: Priest Treasure

## Boss upgrades
Boss upgrades are installable items used to power up the boss.

- **`armor`**: Armor
- **`attack_speed`**: Attack Speed
- **`damage`**: Damage
- **`double_strike`**: Double Strike
- **`glop`**: Glop
- **`health`**: Health
- **`reflect`**: Reflect

## Adventurer classes
Adventurers come in classes; classes affect stats/behavior.

- **`warrior`**: Warrior
- **`rogue`**: Rogue
- **`mage`**: Mage
- **`priest`**: Priest

## Adventurer stats
Adventurers also have internal stats. You can view these by right-clicking an adventurer (tooltip).

- **Intelligence (INT)**: Reduces navigation/decision “mistakes” when choosing where to go next. Higher INT = fewer wrong turns.
- **Strength (STR)**: Placeholder for future combat/interaction scaling.
- **Agility (AGI)**: Placeholder for future speed/dodge/pathing finesse.

Stats can be modified by **traits** (e.g. `+1 Intelligence`, `+1 All Stats`).
