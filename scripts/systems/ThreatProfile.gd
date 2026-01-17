extends Resource
class_name ThreatProfile

# Controls how threat and distance combine into target selection.

@export var damage_weight: float = 1.0
@export var distance_weight: float = 20.0

# If the attacker's range is <= this cutoff, treat it as "melee" for distance scoring.
@export var melee_range_cutoff: float = 80.0

# Heavy multiplier for distance scoring when melee.
@export var melee_distance_weight_multiplier: float = 4.0

