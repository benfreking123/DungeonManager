extends Resource
class_name TrapItem

@export var id: String = ""
@export var display_name: String = ""
@export var icon: Texture2D

@export var proc_chance: float = 1.0

# Cooldown in seconds after a successful proc.
@export var cooldown_s: float = 0.0

# Optional integration hook (reserved for future trigger/event systems).
@export var trigger_id: String = ""

# Charges per day. -1 means unlimited.
@export var trigger_amount: int = -1

# Effect type (string enum). Examples:
# - "damage_single"
# - "damage_all"
# - "teleport_random_room"
# - "web_pause"
# - "rearm_buff"
@export var effect: String = "damage_single"

# Primary numeric magnitude for the effect (meaning depends on effect).
# - damage_*: damage amount
# - web_pause: pause duration in seconds
# - rearm_buff: buff duration in seconds
@export var value: int = 1

# If true, trap starts ready (no initial cooldown). If false, starts on cooldown.
@export var start_ready: bool = true

 # Optional delay before the trap effect is applied (seconds).
 # Useful for multi-target traps to feel like a brief windup.
@export var delay_s: float = 0.0
 
