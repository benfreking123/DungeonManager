extends RefCounted
class_name StrengthService

# Computes player Strength S from day number (configured in `game_config`).

func compute_strength_s_for_day(day_index: int, cfg: Node) -> int:
	var day := maxi(1, int(day_index))
	if cfg != null and cfg.has_method("PARTY_SCALING"):
		var s_f := float(cfg.call("PARTY_SCALING", day))
		var s_i := int(floor(s_f))
		return clampi(s_i, 0, int(cfg.get("STRENGTH_DAY_MAX")) if cfg != null else 999999)
	# Fallback to legacy formula if config function is missing.
	var base := 3
	var growth := 1.25
	var max_s := 999999
	if cfg != null:
		base = int(cfg.get("STRENGTH_DAY_BASE"))
		growth = float(cfg.get("STRENGTH_DAY_GROWTH"))
		max_s = int(cfg.get("STRENGTH_DAY_MAX"))
	var raw := float(base) + pow(float(day), growth)
	return clampi(int(floor(raw)), 0, max_s)

