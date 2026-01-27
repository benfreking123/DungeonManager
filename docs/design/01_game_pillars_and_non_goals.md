# Game Pillars + Non-Goals (DungeonManager)

This is the 1-page “north star” for what the game should feel like, and what we are explicitly *not* building.

## Game pillars (what it must feel like)

- **I am the dungeon, not the heroes**: The player’s agency is in layout, loadout, and rules; the adventurers are autonomous and react to the dungeon and their own goals.
- **Readable cause → effect**: When something happens (fleeing, stealing, combat outcomes), you can trace it back to a placement decision, slot loadout, or a known rule.
- **Build is a craft phase; Day is a watch phase**: BUILD is deliberate and puzzle-like (space + power + slots); DAY is observation of emergent behavior and consequences.
- **Raid-scale pressure**: A *day* can spawn **many adventurers across multiple parties** (it should feel like a raid on the dungeon), with parties clustering, splitting, regrouping, fleeing, and exiting.
- **Emergent party stories**: Parties form intent, regroup, defect, flee, and steal; the “story” is the event log you watched unfold (not authored cutscenes).
- **Constraints create interesting tradeoffs**: Power capacity, unique rooms, slot kinds, and required paths force meaningful decisions rather than “place everything.”
- **Fast iteration**: The player can quickly edit during BUILD, run a day, see results, and iterate without long menus or build times.

## Non-goals (what we are explicitly not building)

- **Direct unit control / tactics gameplay**: No player-issued movement/attack commands during DAY; parties choose goals and pathing themselves.
- **Branching narrative campaign**: No authored dialogue trees, quest lines, or multi-hour story arcs; dialogue is lightweight flavor supporting simulation events.
- **Procedural “run map” / node-based roguelike meta**: No Slay-the-Spire style run graph; progression is day-indexed and dungeon-layout-driven.
- **Deep economy + crafting**: No multi-currency markets, crafting chains, or complex vendor systems; SHOP is a focused upgrade/refresh step.
- **Online or competitive features**: No multiplayer, PvP, leaderboards, or networked persistence requirements.
- **3D / physics-heavy simulation**: The game is 2D, grid-based layout with simple motion and combat resolution tuned for readability and pace.

## Design guardrails (quick checks)

- If a feature **reduces BUILD clarity** or **adds player micromanagement during DAY**, it probably violates the pillars.
- If a feature can’t be expressed as **data + small rules** (rooms/items/goals), it’s likely out of scope for this project phase.

