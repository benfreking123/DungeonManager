# Dialogue Guide

This document explains how dialogue is authored, categorized, and triggered in DungeonManager.

## Where dialogue lives

- Rules and lines: `res://data/dialogue_rules.json`
- Token defaults and tuning: `res://autoloads/game_config.gd`
- Runtime selection + history logging: `res://scripts/services/DialogueService.gd`

## Categories (events)

Each rule in `dialogue_rules.json` uses a `when.event` value. These are the current categories:

- `party_intent` (intent change bubble)
- `callback` (references recent personal history)
- `call_forward` (rumors about upcoming heroes)
- `lineage_banter` (family flavor, sibling-focused)
- `callback_family_loss` (family death callback)
- `callback_family_flee` (family flee callback)
- `callback_family_returned` (family returned callback)
- `callback_family_hero` (family hero callback)
- `callback_family_rivalry` (family rivalry flavor)
- `callback_family_legacy` (family legacy flavor)
- `callback_family_vow` (family vow flavor)
- `flee` (flee bubble)
- `defect` (defection bubble)
- Fallback rule: `{ "*": true }`

## Rule structure

Each rule has:

- `when`: conditions that must match tokens
- `weight`: weighted selection
- `values`: array of one-line dialogue options

Example:

```
{ "when": { "event": "call_forward" }, "weight": 2, "values": ["I heard {hero_name} arrives in {days_until_hero} days."] }
```

## Tokens

Tokens are `"{token_name}"` placeholders replaced at runtime. If missing, defaults are taken from:
`game_config.gd -> DIALOGUE_TOKEN_DEFAULTS`.

Common tokens:

- `last_event_text` (callback)
- `hero_name`, `hero_class`, `days_until_hero` (call_forward)
- `relative_name`, `relative_relation_word`, `family_name` (family callbacks)

If you introduce a new token, also add a default in `DIALOGUE_TOKEN_DEFAULTS`.

## Tuning

Dialogue frequency is controlled in `game_config.gd`:

- `DIALOGUE_MAX_PER_PROFILE_PER_DAY`
- `DIALOGUE_MAX_PER_PARTY_PER_DAY`
- `DIALOGUE_MAX_PER_EVENT_PER_PROFILE`
- `DIALOGUE_EVENT_COOLDOWN_S`
- `DIALOGUE_EVENT_COOLDOWN_BY_EVENT`
- `DIALOGUE_CHANCE_*` (callback/call_forward/lineage/family)

## Adding more dialogue

1. Add new lines in `data/dialogue_rules.json` under the appropriate event.
2. Keep lines short for bubbles/history readability.
3. If you use new tokens, add them to `DIALOGUE_TOKEN_DEFAULTS`.
4. If you add a new event type, update `DialogueService` to emit it.

## Related systems

- **Multi-ability heroes**: hero configs can include `ability_ids` and `ability_charges_by_id` for multiple abilities.
- **avoid_monsters goal**: adds a behavioral bias in intent scoring to reduce monster-heavy paths.

