extends RefCounted
class_name StrengthService

# Computes player Strength S from day number (configured in `game_config`).

func compute_strength_s_for_day(day_index: int, cfg: Node) -> int:
	var day := maxi(1, int(day_index))
	var s_f := 0.0
	if cfg != null and cfg.has_method("PARTY_SCALING"):
		s_f = float(cfg.call("PARTY_SCALING", day))
	var max_s := 999999
	if cfg != null and cfg.has_method("get"):
		max_s = int(cfg.get("STRENGTH_DAY_MAX"))
	var s_i := int(floor(s_f))
	return clampi(s_i, 0, max_s)

