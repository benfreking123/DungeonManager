extends RefCounted
class_name BlueprintTheme

# Classic palette + drawing constants.
# Note: the real source of truth is now `ui/DungeonManagerTheme.tres`. These are fallbacks.

# Parchment paper fallback
const BG := Color(0.975, 0.95, 0.88, 1.0)

# Ink fallback
const LINE := Color(0.18, 0.13, 0.08, 0.60)
const LINE_DIM := Color(0.18, 0.13, 0.08, 0.28)
const LINE_FAINT := Color(0.18, 0.13, 0.08, 0.10)

const ACCENT_OK := Color(0.40, 0.95, 0.65, 0.90)
const ACCENT_BAD := Color(1.00, 0.35, 0.35, 0.90)
const ACCENT_WARN := Color(1.00, 0.80, 0.35, 0.90)

const OUTLINE_W := 2.0
const GRID_W := 1.0

static func grid_color(is_major: bool) -> Color:
	return LINE_DIM if is_major else LINE_FAINT



