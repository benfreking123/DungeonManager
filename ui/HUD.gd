extends Control

const DungeonSetupStatusServiceScript := preload("res://scripts/services/DungeonSetupStatusService.gd")
const SetupWarningPopupScene := preload("res://ui/SetupWarningPopup.tscn")
const PauseIconTexture: Texture2D = preload("res://assets/icons/pause.svg")
const PlayIconTexture: Texture2D = preload("res://assets/icons/play.svg")

var treasure_label: Label = null
var power_label: Label = null
var day_label: Label = null
var day_button: Button = null
var speed_1x: Button = null
var speed_2x: Button = null
var speed_4x: Button = null
var shop_button: Button = null
var _setup_warning: Control = null
var _setup_warning_popup: PanelContainer = null
@onready var _simulation: Node = get_node("/root/Simulation")
@onready var _game_over: PanelContainer = $GameOverPanel

# Optional paper FX nodes (some HUD layouts don't include these).
@onready var _paper_base: ColorRect = get_node_or_null("PaperBase") as ColorRect
@onready var _paper_grain: TextureRect = get_node_or_null("PaperGrain") as TextureRect
@onready var _paper_grain2: TextureRect = get_node_or_null("PaperGrain2") as TextureRect
@onready var _vignette: ColorRect = get_node_or_null("Vignette") as ColorRect
@onready var _placement_hint: Label = get_node_or_null("PlacementHint") as Label

var _world_frame: Control = null
var _world_canvas: Control = null
var _dungeon_view: Node = null
var _frame_paper_base: TextureRect = null
var _town_texture: TextureRect = null
var _town_view: Control = null
var _room_popup: PanelContainer = null
var _adventurer_popup: PanelContainer = null
var _popup_layer: CanvasLayer = null
var _shop: Control = null
var _shop_layer: CanvasLayer = null
var _room_inventory_panel: Control = null
var _history_panel: PanelContainer = null
var _history_button: Button = null

# Cache original mouse_filters for temporary shop interaction gating.
var _topbar_mouse_filter: Control.MouseFilter = Control.MOUSE_FILTER_STOP
var _world_frame_mouse_filter: Control.MouseFilter = Control.MOUSE_FILTER_STOP

var _world_zoom: float = 1.0
var _is_panning: bool = false
var _pan_start_mouse_parent: Vector2 = Vector2.ZERO
var _pan_start_canvas_pos: Vector2 = Vector2.ZERO

# Nodes under WorldFrame that should visually follow the same pan/zoom as the world canvas.
var _town_texture_base_pos: Vector2 = Vector2.ZERO
var _town_texture_base_scale: Vector2 = Vector2.ONE
var _frame_paper_base_pos: Vector2 = Vector2.ZERO
var _frame_paper_base_scale: Vector2 = Vector2.ONE

const ZOOM_MIN := 1.0
const ZOOM_MAX := 2.5
const ZOOM_STEP := 1.12

var _last_nonzero_speed: float = 1.0


func _ready() -> void:
	_resolve_topbar_nodes()
	_resolve_setup_warning()
	_resolve_setup_warning_popup()
	_resolve_world_nodes()
	_resolve_town_view()
	_maybe_set_sim_views()
	_apply_paper_theme()
	_layout_paper_fx()
	resized.connect(_layout_paper_fx)
	resized.connect(_apply_world_transform)
	_resolve_dungeon_view()
	_maybe_set_sim_views()
	_resolve_room_popup()
	_resolve_adventurer_popup()
	_resolve_history_panel()
	_connect_room_popup()
	_connect_adventurer_popup()
	_connect_history_button()
	_connect_town_view()
	_connect_placement_hint()
	_resolve_shop()
	_resolve_room_inventory_panel()
	_connect_setup_warning()
	set_process(true)
	if _game_over != null:
		# Ensure the overlay always renders above everything.
		_game_over.z_index = 4096
		_game_over.z_as_relative = false
	if day_button != null:
		day_button.pressed.connect(_on_action_pressed)
	if shop_button != null:
		shop_button.pressed.connect(_on_shop_pressed)
	_simulation.day_ended.connect(_on_day_ended)
	if _simulation.has_signal("boss_killed"):
		_simulation.connect("boss_killed", Callable(self, "_on_boss_killed"))
	if _game_over != null:
		_game_over.connect("restart_requested", Callable(self, "_restart_game"))

	var g := ButtonGroup.new()
	if speed_1x != null:
		speed_1x.button_group = g
	if speed_2x != null:
		speed_2x.button_group = g
	if speed_4x != null:
		speed_4x.button_group = g

	if speed_1x != null:
		speed_1x.pressed.connect(func(): GameState.set_speed(1.0))
	if speed_2x != null:
		speed_2x.pressed.connect(func(): GameState.set_speed(2.0))
	if speed_4x != null:
		speed_4x.pressed.connect(func(): GameState.set_speed(4.0))
	if GameState != null and GameState.has_signal("speed_changed"):
		GameState.speed_changed.connect(_on_speed_changed)
	if GameState != null and GameState.has_signal("phase_changed"):
		GameState.phase_changed.connect(func(_new_phase: int) -> void:
			_refresh_action_button()
			_refresh_day_label()
			_maybe_open_shop_for_phase(int(_new_phase))
		)
	# Keep day label in sync with explicit day changes.
	if GameState != null and GameState.has_signal("day_changed"):
		GameState.day_changed.connect(func(_new_day: int) -> void:
			_refresh_day_label()
		)
	# Ensure action button matches initial phase/speed immediately.
	_refresh_action_button()
	_refresh_day_label()
	_maybe_open_shop_for_phase(int(GameState.phase) if GameState != null else 0)
	_apply_world_transform()
	# Run once more after the first layout pass so sizes are valid and the initial
	# pan/zoom clamp + backdrop sync don't start slightly offset.
	call_deferred("_apply_world_transform")
	# Treasure counter removed; hide if present.
	if treasure_label != null:
		treasure_label.visible = false
	_refresh_setup_warning()

	# Subscribe to economy updates and paint initial power here (HUD owns its own updates).
	if GameState != null and GameState.has_signal("economy_changed"):
		GameState.economy_changed.connect(func():
			if has_method("set_power"):
				set_power(GameState.power_used, GameState.power_capacity)
		)
	if has_method("set_power"):
		set_power(GameState.power_used, GameState.power_capacity)

	# (Strength display moved to TownHistoryPanel)


func _resolve_topbar_nodes() -> void:
	# Support old and new layouts:
	# - TopBar/HBox/...
	# - VBoxContainer/TopBar/HBox/...
	# - (New) Right-side controls under VBoxContainer/HBoxContainer/VBoxContainer/HBoxContainer/...
	var bases := [
		"TopBar/HBox",
		"VBoxContainer/TopBar/HBox"
	]
	for base in bases:
		var tl := get_node_or_null("%s/TreasureLabel" % base) as Label
		var sb := get_node_or_null("%s/ShopButton" % base) as Button
		# Only require actual topbar widgets here (speed/pause may live elsewhere now).
		if tl != null:
			treasure_label = tl
		if sb != null:
			shop_button = sb
		if treasure_label != null and shop_button != null:
			break
	# Fallback to whatever was found, even if partial
	if treasure_label == null:
		treasure_label = get_node_or_null("TopBar/HBox/TreasureLabel") as Label
	if power_label == null:
		# New HUD layout (right-side column)
		power_label = get_node_or_null("VBoxContainer/HBoxContainer/VBoxContainer/HBoxContainer/VBoxContainer/HBoxContainer/PowerLabel") as Label
		if power_label == null:
			# Legacy layout
			power_label = get_node_or_null("TopBar/HBox/PowerLabel") as Label
	if day_label == null:
		day_label = get_node_or_null("VBoxContainer/HBoxContainer/VBoxContainer/HBoxContainer/VBoxContainer/DayLabel") as Label
		if day_label == null:
			# Newer right-side layout variant
			day_label = get_node_or_null("VBoxContainer/HBoxContainer/VBoxContainer/HBoxContainer/VBoxContainer/HBoxContainer3/DayLabel") as Label
		if day_label == null:
			# Legacy layout fallback
			day_label = get_node_or_null("TopBar/HBox/DayLabel") as Label
	if day_button == null:
		# New HUD layout (right-side column)
		day_button = get_node_or_null("VBoxContainer/HBoxContainer/VBoxContainer/HBoxContainer/PanelContainer/VBoxContainer2/DayButton") as Button
		if day_button == null:
			# Older new layout variant
			day_button = get_node_or_null("VBoxContainer/HBoxContainer/VBoxContainer/HBoxContainer/VBoxContainer/DayButton") as Button
		if day_button == null:
			# Newer right-side layout variant
			day_button = get_node_or_null("VBoxContainer/HBoxContainer/VBoxContainer/HBoxContainer/VBoxContainer/HBoxContainer3/DayButton") as Button
		if day_button == null:
			# Legacy layout
			day_button = get_node_or_null("TopBar/HBox/DayButton") as Button
	# History button (optional)
	_history_button = get_node_or_null("VBoxContainer/HBoxContainer/VBoxContainer/HBoxContainer/PanelContainer/VBoxContainer2/HistoryButton") as Button
	if _history_button == null:
		_history_button = get_node_or_null("VBoxContainer/HBoxContainer/VBoxContainer/HBoxContainer/VBoxContainer/HBoxContainer3/HistoryButton") as Button
	if speed_1x == null:
		# New HUD layout (right-side speed row)
		speed_1x = get_node_or_null("VBoxContainer/HBoxContainer/VBoxContainer/HBoxContainer/VBoxContainer/HBoxContainer2/Speed1x") as Button
		if speed_1x == null:
			speed_1x = get_node_or_null("TopBar/HBox/Speed1x") as Button
	if speed_2x == null:
		speed_2x = get_node_or_null("VBoxContainer/HBoxContainer/VBoxContainer/HBoxContainer/VBoxContainer/HBoxContainer2/Speed2x") as Button
		if speed_2x == null:
			speed_2x = get_node_or_null("TopBar/HBox/Speed2x") as Button
	if speed_4x == null:
		speed_4x = get_node_or_null("VBoxContainer/HBoxContainer/VBoxContainer/HBoxContainer/VBoxContainer/HBoxContainer2/Speed4x") as Button
		if speed_4x == null:
			speed_4x = get_node_or_null("TopBar/HBox/Speed4x") as Button
	if shop_button == null:
		shop_button = get_node_or_null("TopBar/HBox/ShopButton") as Button
	# (Strength label removed; now shown in TownHistoryPanel)


func _refresh_day_label() -> void:
	if day_label == null or GameState == null:
		return
	# NOTE: `GameState` is an autoload Object; `"day_index" in GameState` does NOT work reliably.
	var di := int(GameState.day_index)
	day_label.text = "Day: %d" % di
	# (Strength display handled by TownHistoryPanel)


#


func _on_action_pressed() -> void:
	if GameState == null:
		return
	match int(GameState.phase):
		int(GameState.Phase.BUILD):
			_on_day_pressed()
		int(GameState.Phase.DAY):
			_toggle_pause()
		_:
			return


func _toggle_pause() -> void:
	if GameState == null:
		return
	var s := float(GameState.speed)
	if s > 0.0:
		_last_nonzero_speed = s
		GameState.set_speed(0.0)
	else:
		GameState.set_speed(maxf(0.1, _last_nonzero_speed))


func _on_speed_changed(new_speed: float) -> void:
	# Track last non-zero speed for pause toggle restore.
	if float(new_speed) > 0.0:
		_last_nonzero_speed = float(new_speed)
	# Keep speed button UI in sync without triggering signals.
	if speed_1x != null and speed_1x.has_method("set_pressed_no_signal"):
		speed_1x.call("set_pressed_no_signal", is_equal_approx(float(new_speed), 1.0) or (float(new_speed) == 0.0 and is_equal_approx(_last_nonzero_speed, 1.0)))
	if speed_2x != null and speed_2x.has_method("set_pressed_no_signal"):
		speed_2x.call("set_pressed_no_signal", is_equal_approx(float(new_speed), 2.0) or (float(new_speed) == 0.0 and is_equal_approx(_last_nonzero_speed, 2.0)))
	if speed_4x != null and speed_4x.has_method("set_pressed_no_signal"):
		speed_4x.call("set_pressed_no_signal", is_equal_approx(float(new_speed), 4.0) or (float(new_speed) == 0.0 and is_equal_approx(_last_nonzero_speed, 4.0)))

	_refresh_action_button()


func _refresh_action_button() -> void:
	if day_button == null or GameState == null:
		return

	var phase := int(GameState.phase)
	var speed := float(GameState.speed)

	# Default styling for a single-button control.
	day_button.add_theme_constant_override("icon_margin", 0)
	day_button.add_theme_constant_override("h_separation", 0)
	if day_button.has_method("set") and _node_has_property(day_button, "icon_alignment"):
		day_button.set("icon_alignment", HORIZONTAL_ALIGNMENT_CENTER)

	if phase == int(GameState.Phase.BUILD):
		day_button.disabled = false
		day_button.text = "Start"
		day_button.icon = null
		day_button.tooltip_text = "Start Day"
		return

	if phase == int(GameState.Phase.DAY):
		day_button.disabled = false
		day_button.text = ""
		day_button.icon = PlayIconTexture if speed == 0.0 else PauseIconTexture
		day_button.tooltip_text = "Resume" if speed == 0.0 else "Pause"
		return

	# RESULTS (and any future phases): disable by default.
	day_button.disabled = true
	day_button.text = ""
	day_button.icon = null
	day_button.tooltip_text = "Results"


func _node_has_property(obj: Object, prop_name: String) -> bool:
	if obj == null or prop_name == "":
		return false
	for p in obj.get_property_list():
		if String(p.get("name", "")) == prop_name:
			return true
	return false


func _resolve_setup_warning() -> void:
	var bases := [
		# New HUD layout (right-side column)
		"VBoxContainer/HBoxContainer/VBoxContainer/HBoxContainer/VBoxContainer/HBoxContainer",
		# Legacy top bar layouts
		"TopBar/HBox",
		"VBoxContainer/TopBar/HBox"
	]
	for base in bases:
		var w := get_node_or_null("%s/SetupWarning" % base) as Control
		if w != null:
			_setup_warning = w
			return
	_setup_warning = null


func _resolve_setup_warning_popup() -> void:
	_setup_warning_popup = get_node_or_null("SetupWarningPopup") as PanelContainer
	if _setup_warning_popup == null:
		# Robustness if HUD.tscn changes: create it dynamically.
		var inst := SetupWarningPopupScene.instantiate() as PanelContainer
		add_child(inst)
		inst.name = "SetupWarningPopup"
		inst.z_as_relative = false
		inst.z_index = 4096
		_setup_warning_popup = inst
	if _setup_warning_popup != null:
		_setup_warning_popup.visible = false


func _connect_setup_warning() -> void:
	var dg := get_node_or_null("/root/DungeonGrid")
	if dg != null and dg.has_signal("layout_changed"):
		dg.layout_changed.connect(_refresh_setup_warning)
	if GameState != null and GameState.has_signal("phase_changed"):
		GameState.phase_changed.connect(func(_new_phase: int) -> void:
			_refresh_setup_warning()
		)
	if _setup_warning != null:
		_setup_warning.mouse_entered.connect(_on_setup_warning_hover_entered)
		_setup_warning.mouse_exited.connect(_on_setup_warning_hover_exited)


func _refresh_setup_warning() -> void:
	if _setup_warning == null:
		return

	# Hide during the DAY phase (setup errors are only relevant while building).
	if GameState != null and GameState.phase == GameState.Phase.DAY:
		_setup_warning.visible = false
		_hide_setup_warning_popup()
		return

	var dg := get_node_or_null("/root/DungeonGrid")
	var issues := DungeonSetupStatusServiceScript.get_setup_issues(dg)
	if issues.is_empty():
		_setup_warning.visible = false
		_hide_setup_warning_popup()
		return

	_setup_warning.visible = true
	# If popup is already visible (hovered), update its contents immediately.
	if _setup_warning_popup != null and _setup_warning_popup.visible:
		_show_setup_warning_popup(issues)


func _on_setup_warning_hover_entered() -> void:
	var dg := get_node_or_null("/root/DungeonGrid")
	var issues := DungeonSetupStatusServiceScript.get_setup_issues(dg)
	if issues.is_empty():
		_hide_setup_warning_popup()
		return
	_show_setup_warning_popup(issues)


func _on_setup_warning_hover_exited() -> void:
	_hide_setup_warning_popup()


func _hide_setup_warning_popup() -> void:
	if _setup_warning_popup == null:
		return
	if _setup_warning_popup.has_method("close"):
		_setup_warning_popup.call("close")
	else:
		_setup_warning_popup.visible = false


func _show_setup_warning_popup(issues: Array[String]) -> void:
	if _setup_warning == null or _setup_warning_popup == null:
		return
	# Single-line (horizontal) popup; avoid wrapping into tall vertical text.
	var text := " • ".join(issues)
	if _setup_warning_popup.has_method("set_text"):
		_setup_warning_popup.call("set_text", text)
	# Position using the warning icon's global rect.
	var anchor := _setup_warning.get_global_rect()
	if _setup_warning_popup.has_method("open_at"):
		_setup_warning_popup.call("open_at", anchor)
	else:
		_setup_warning_popup.visible = true


func _resolve_shop() -> void:
	if _shop_layer == null:
		_shop_layer = get_node_or_null("ShopLayer") as CanvasLayer
		if _shop_layer == null:
			_shop_layer = CanvasLayer.new()
			_shop_layer.name = "ShopLayer"
			_shop_layer.layer = 200
			add_child(_shop_layer)

	_shop = get_node_or_null("Shop") as Control
	if _shop == null:
		var scene := preload("res://ui/Shop.tscn")
		var inst := scene.instantiate() as Control
		_shop_layer.add_child(inst)
		inst.name = "Shop"
		inst.z_as_relative = false
		# Godot clamps CanvasItem z_index; keep within valid range.
		inst.z_index = 4096
		_shop = inst
	# Always ensure signals are connected (even if Shop node already existed in the scene).
	if _shop != null:
		if _shop.has_signal("shop_opened"):
			var cb_open := Callable(self, "_on_shop_opened")
			if not _shop.is_connected("shop_opened", cb_open):
				_shop.connect("shop_opened", cb_open)
		if _shop.has_signal("shop_closed"):
			var cb_close := Callable(self, "_on_shop_closed")
			if not _shop.is_connected("shop_closed", cb_close):
				_shop.connect("shop_closed", cb_close)


func _resolve_room_inventory_panel() -> void:
	# This is the right-side room menu panel (inventory).
	var paths := [
		"VBoxContainer/HBoxContainer/VBoxContainer/RoomInventoryPanel", # current HUD.tscn
		"VBoxContainer/HBoxContainer/RoomInventoryPanel",               # older/newer variants
		"RoomInventoryPanel"                                            # flat fallback
	]
	_room_inventory_panel = null
	for p in paths:
		var n := get_node_or_null(p) as Control
		if n != null:
			_room_inventory_panel = n
			break


func _on_shop_opened() -> void:
	# Lock room menu to Treasure tab and prevent tab changes until shop is closed.
	if _room_inventory_panel == null:
		_resolve_room_inventory_panel()
	if _room_inventory_panel != null:
		# Default to Treasure tab when shop opens (deferred to avoid race with layout).
		if _room_inventory_panel.has_method("select_tab"):
			_room_inventory_panel.call_deferred("select_tab", "treasure")
		# Disable item/room grid buttons while allowing tab changes.
		if _room_inventory_panel.has_method("set_grid_interactable"):
			_room_inventory_panel.call("set_grid_interactable", false)
	_set_shop_interaction_mode(true)
	# Extra enforcement after layout stabilizes.
	_enforce_shop_inventory_selection()


func _on_shop_closed() -> void:
	if _room_inventory_panel != null and _room_inventory_panel.has_method("unlock_tabs"):
		_room_inventory_panel.call("unlock_tabs")
	# Re-enable item/room buttons after shop closes.
	if _room_inventory_panel != null and _room_inventory_panel.has_method("set_grid_interactable"):
		_room_inventory_panel.call("set_grid_interactable", true)
	_set_shop_interaction_mode(false)
	# Closing the shop returns to BUILD phase.
	if GameState != null and GameState.phase == GameState.Phase.SHOP:
		# Advance the run's day counter once per full loop (end-of-day shop close).
		if GameState.has_method("advance_day"):
			GameState.advance_day()
		_refresh_day_label()
		# Restore non-zero speed so BUILD preview/wander resumes.
		var restore_speed := _last_nonzero_speed if _last_nonzero_speed > 0.0 else 1.0
		GameState.set_speed(restore_speed)
		GameState.set_phase(GameState.Phase.BUILD)


func _set_shop_interaction_mode(enabled: bool) -> void:
	# Goal: while shop is open, allow clicking Shop UI and the right-side RoomInventoryPanel only.
	# Everything else in the HUD should ignore mouse so it can't be interacted with.
	var topbar := get_node_or_null("VBoxContainer/TopBar") as Control
	if topbar != null:
		if enabled:
			_topbar_mouse_filter = topbar.mouse_filter
			topbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		else:
			topbar.mouse_filter = _topbar_mouse_filter

	if _world_frame != null:
		if enabled:
			_world_frame_mouse_filter = _world_frame.mouse_filter
			_world_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		else:
			_world_frame.mouse_filter = _world_frame_mouse_filter


func _on_shop_pressed() -> void:
	if _shop == null:
		_resolve_shop()
	if _shop == null:
		return
	if _shop.has_method("open"):
		_shop.call("open")
	else:
		_shop.visible = true


func _maybe_open_shop_for_phase(new_phase: int) -> void:
	if GameState == null:
		return
	if int(new_phase) != int(GameState.Phase.SHOP):
		return
	if _shop == null:
		_resolve_shop()
	if _shop == null:
		return
	# Pause time while shopping.
	GameState.set_speed(0.0)
	# Deterministic seeded offers per night.
	var shop_seed := 0
	if _simulation != null and _simulation.has_method("get_shop_seed"):
		shop_seed = int(_simulation.call("get_shop_seed"))
	if _shop.has_method("open_with_seed"):
		_shop.call("open_with_seed", shop_seed)
	else:
		_shop.call("open")
	# Proactively select Treasure tab and disable grid items here as well (belt-and-suspenders with _on_shop_opened).
	if _room_inventory_panel == null:
		_resolve_room_inventory_panel()
	if _room_inventory_panel != null:
		if _room_inventory_panel.has_method("select_tab"):
			_room_inventory_panel.call_deferred("select_tab", "treasure")
		if _room_inventory_panel.has_method("set_grid_interactable"):
			_room_inventory_panel.call("set_grid_interactable", false)
	# Extra enforcement after Shop creation/open animation.
	_enforce_shop_inventory_selection()

func _enforce_shop_inventory_selection() -> void:
	# Enforce selection a few times to survive any late layout/scene updates.
	var delays := [0.01, 0.06, 0.15]
	for d in delays:
		var t := get_tree().create_timer(d)
		t.timeout.connect(func():
			if _room_inventory_panel == null:
				_resolve_room_inventory_panel()
			if _room_inventory_panel != null:
				if Engine.has_singleton("DbgLog"):
					DbgLog.info("Enforce Treasure tab on Shop open (panel ok)", "ui")
				if _room_inventory_panel.has_method("select_tab"):
					_room_inventory_panel.call("select_tab", "treasure")
				if _room_inventory_panel.has_method("set_grid_interactable"):
					_room_inventory_panel.call("set_grid_interactable", false)
		)

func _apply_paper_theme() -> void:
	# Keep background nodes theme-driven (so changing the Theme updates everything).
	if _paper_base != null and has_theme_color("paper_base", "HUD"):
		_paper_base.color = get_theme_color("paper_base", "HUD")
	if _paper_grain != null:
		# Grain is a subtle ink tint; keep alpha low.
		if has_theme_color("ink_dim", "HUD"):
			var ink_dim := get_theme_color("ink_dim", "HUD")
			_paper_grain.modulate = Color(ink_dim.r, ink_dim.g, ink_dim.b, 0.03)
			if _paper_grain2 != null:
				_paper_grain2.modulate = Color(ink_dim.r, ink_dim.g, ink_dim.b, 0.018)
			if _vignette != null:
				# Vignette shader uses its own color uniform; keep node visible.
				_vignette.color = Color(1, 1, 1, 1)


#


func _layout_paper_fx() -> void:
	# Keep rotated grain centered and oversized across window resizes.
	if _paper_grain2 != null:
		_paper_grain2.pivot_offset = _paper_grain2.size * 0.5


func _resolve_dungeon_view() -> void:
	# Support multiple HUD layouts (matches _resolve_world_nodes philosophy).
	var paths := [
		"VBoxContainer/HBoxContainer/DungeonFrame/FrameLayer/Dungeon/WorldFrame/WorldCanvas/Grid/DungeonView",
		"Body/DungeonFrame/Dungeon/WorldFrame/WorldCanvas/Grid/DungeonView",
		"DungeonFrame/Dungeon/WorldFrame/WorldCanvas/Grid/DungeonView",
	]
	for p in paths:
		var n := get_node_or_null(p)
		if n != null:
			_dungeon_view = n
			_maybe_set_sim_views()
			return

func _maybe_set_sim_views() -> void:
	if _simulation == null:
		return
	if _town_view == null or _dungeon_view == null:
		return
	if _simulation.has_method("set_views"):
		_simulation.call("set_views", _town_view, _dungeon_view)


func _resolve_room_popup() -> void:
	if _popup_layer == null:
		_popup_layer = get_node_or_null("PopupLayer") as CanvasLayer
		if _popup_layer == null:
			_popup_layer = CanvasLayer.new()
			_popup_layer.name = "PopupLayer"
			_popup_layer.layer = 100
			add_child(_popup_layer)
	_room_popup = get_node_or_null("RoomPopup") as PanelContainer
	if _room_popup == null:
		# Robustness: create it dynamically (keeps working even if HUD.tscn changes).
		var scene := preload("res://ui/room_popup.tscn")
		var inst := scene.instantiate() as PanelContainer
		_popup_layer.add_child(inst)
		inst.name = "RoomPopup"
		inst.z_as_relative = false
		inst.z_index = 4096
		_room_popup = inst


func _resolve_adventurer_popup() -> void:
	if _popup_layer == null:
		_popup_layer = get_node_or_null("PopupLayer") as CanvasLayer
		if _popup_layer == null:
			_popup_layer = CanvasLayer.new()
			_popup_layer.name = "PopupLayer"
			_popup_layer.layer = 100
			add_child(_popup_layer)
	_adventurer_popup = get_node_or_null("AdventurerPopup") as PanelContainer
	if _adventurer_popup == null:
		var scene := preload("res://ui/adventurer_popup.tscn")
		var inst := scene.instantiate() as PanelContainer
		_popup_layer.add_child(inst)
		inst.name = "AdventurerPopup"
		inst.z_as_relative = false
		inst.z_index = 4096
		_adventurer_popup = inst


func _resolve_history_panel() -> void:
	if _popup_layer == null:
		_popup_layer = get_node_or_null("PopupLayer") as CanvasLayer
		if _popup_layer == null:
			_popup_layer = CanvasLayer.new()
			_popup_layer.name = "PopupLayer"
			_popup_layer.layer = 100
			add_child(_popup_layer)
	_history_panel = get_node_or_null("TownHistoryPanel") as PanelContainer
	if _history_panel == null:
		var scene: PackedScene = load("res://ui/TownHistoryPanel.tscn")
		if scene == null:
			DbgLog.warn("Failed to load TownHistoryPanel.tscn", "ui")
			return
		var inst := scene.instantiate() as PanelContainer
		_popup_layer.add_child(inst)
		inst.name = "TownHistoryPanel"
		inst.z_as_relative = false
		inst.z_index = 4096
		_history_panel = inst


func _connect_room_popup() -> void:
	if _dungeon_view == null or _room_popup == null:
		return
	if _dungeon_view.has_signal("room_clicked"):
		_dungeon_view.connect("room_clicked", Callable(self, "_on_room_clicked"))


func _connect_adventurer_popup() -> void:
	if _simulation == null:
		return
	if _simulation.has_signal("adventurer_right_clicked"):
		_simulation.connect("adventurer_right_clicked", Callable(self, "_on_adventurer_right_clicked"))


func _connect_history_button() -> void:
	if _history_button != null:
		_history_button.pressed.connect(_on_history_pressed)


func _resolve_town_view() -> void:
	var paths := [
		"VBoxContainer/HBoxContainer/DungeonFrame/FrameLayer/Dungeon/WorldFrame/WorldCanvas/Town/TownView",
		"Body/DungeonFrame/Dungeon/WorldFrame/WorldCanvas/Town/TownView",
		"DungeonFrame/Dungeon/WorldFrame/WorldCanvas/Town/TownView",
	]
	_town_view = null
	for p in paths:
		var n := get_node_or_null(p) as Control
		if n != null:
			_town_view = n
			_maybe_set_sim_views()
			return


func _connect_town_view() -> void:
	if _town_view == null:
		return
	if not _town_view.has_signal("town_icon_clicked"):
		return
	var cb := Callable(self, "_on_history_pressed")
	if not _town_view.is_connected("town_icon_clicked", cb):
		_town_view.connect("town_icon_clicked", cb)


func _on_room_clicked(room_id: int, screen_pos: Vector2) -> void:
	if _room_popup == null:
		_resolve_room_popup()
	if _room_popup == null:
		return
	if _room_popup.has_method("open_at"):
		_room_popup.call("open_at", room_id, screen_pos)
	else:
		# Fallback for older popup implementations.
		_room_popup.call("open", room_id)


func _on_adventurer_right_clicked(adv_id: int, screen_pos: Vector2) -> void:
	if _adventurer_popup == null:
		_resolve_adventurer_popup()
	if _adventurer_popup == null:
		return
	if _adventurer_popup.has_method("open_at"):
		_adventurer_popup.call("open_at", int(adv_id), screen_pos)
	else:
		_adventurer_popup.visible = true


func _connect_placement_hint() -> void:
	if _placement_hint == null or _dungeon_view == null:
		return
	if _dungeon_view.has_signal("preview_reason_changed"):
		_dungeon_view.connect("preview_reason_changed", Callable(self, "_on_preview_reason_changed"))


func _on_preview_reason_changed(text: String, ok: bool) -> void:
	if _placement_hint == null:
		return
	_placement_hint.text = text
	_placement_hint.visible = (not ok) and text != ""


func _process(_delta: float) -> void:
	if _placement_hint == null or not _placement_hint.visible:
		return
	var mouse := get_viewport().get_mouse_position()
	var offset := Vector2(14, 18)
	var pos := mouse + offset
	var vp := get_viewport_rect().size
	var hint_size := _placement_hint.get_combined_minimum_size()
	pos.x = clampf(pos.x, 6.0, vp.x - hint_size.x - 6.0)
	pos.y = clampf(pos.y, 6.0, vp.y - hint_size.y - 6.0)
	_placement_hint.position = pos


func _resolve_world_nodes() -> void:
	# Support multiple HUD layouts.
	# 1) New layout with VBoxContainer/HBoxContainer prefix
	_world_frame = get_node_or_null("VBoxContainer/HBoxContainer/DungeonFrame/FrameLayer/Dungeon/WorldFrame") as Control
	_world_canvas = get_node_or_null("VBoxContainer/HBoxContainer/DungeonFrame/FrameLayer/Dungeon/WorldFrame/WorldCanvas") as Control
	# 2) Legacy layout with Body container
	if _world_frame == null:
		_world_frame = get_node_or_null("Body/DungeonFrame/Dungeon/WorldFrame") as Control
	if _world_canvas == null:
		_world_canvas = get_node_or_null("Body/DungeonFrame/Dungeon/WorldFrame/WorldCanvas") as Control
	# 3) Flat layout without Body/VBoxContainer
	if _world_frame == null:
		_world_frame = get_node_or_null("DungeonFrame/Dungeon/WorldFrame") as Control
	if _world_canvas == null:
		_world_canvas = get_node_or_null("DungeonFrame/Dungeon/WorldFrame/WorldCanvas") as Control

	# Background paper texture that should pan/zoom with the world contents.
	_frame_paper_base = null
	if _world_frame != null:
		_frame_paper_base = _world_frame.get_node_or_null("FramePaperBase") as TextureRect
		_town_texture = _world_frame.get_node_or_null("TextureRect") as TextureRect

	# Cache baseline transforms so we can re-apply them consistently across zoom changes.
	if _frame_paper_base != null:
		_frame_paper_base_pos = _frame_paper_base.position
		_frame_paper_base_scale = _frame_paper_base.scale
	if _town_texture != null:
		_town_texture_base_pos = _town_texture.position
		_town_texture_base_scale = _town_texture.scale


func _sync_world_backdrops() -> void:
	# Keep any WorldFrame backdrops moving/scaling in lockstep with the world canvas.
	# This makes them behave as if they were parented under the pan/zoomed content.
	if _world_canvas == null:
		return
	if _town_texture != null:
		_town_texture.scale = _town_texture_base_scale * _world_zoom
		_town_texture.position = _world_canvas.position + (_town_texture_base_pos * _world_zoom)
	if _frame_paper_base != null:
		_frame_paper_base.scale = _frame_paper_base_scale * _world_zoom
		_frame_paper_base.position = _world_canvas.position + (_frame_paper_base_pos * _world_zoom)


func _on_day_pressed() -> void:
	if GameState.phase == GameState.Phase.BUILD:
		_simulation.call("start_day")
	_refresh_action_button()


func _on_day_ended() -> void:
	_refresh_action_button()


func set_power(used: int, cap: int) -> void:
	if power_label != null:
		power_label.text = "Power: %d/%d" % [used, cap]


func _input(event: InputEvent) -> void:
	if _shop != null and _shop.visible:
		# Let the Shop UI consume events; just prevent world/popup input logic from running.
		if event is InputEventKey:
			var k := event as InputEventKey
			if k.pressed and k.keycode == KEY_ESCAPE:
				if _shop.has_method("close"):
					_shop.call("close")
				else:
					_shop.visible = false
				get_viewport().set_input_as_handled()
		return
	if _world_frame == null or _world_canvas == null:
		return

	var mouse_global: Vector2 = get_viewport().get_mouse_position()
	var over_world: bool = _world_frame.get_global_rect().has_point(mouse_global)

	# Right-click an adventurer to open its tooltip.
	# We do this at the HUD level because Control mouse capture can prevent Area2D input events.
	if event is InputEventMouseButton:
		var mb_adv := event as InputEventMouseButton
		if mb_adv.button_index == MOUSE_BUTTON_RIGHT and mb_adv.pressed:
			if GameState != null and (GameState.phase == GameState.Phase.DAY or GameState.phase == GameState.Phase.BUILD) and over_world and _simulation != null:
				if _simulation.has_method("find_adventurer_at_screen_pos"):
					var adv_id := int(_simulation.call("find_adventurer_at_screen_pos", mouse_global, 16.0))
					if adv_id != 0:
						if _adventurer_popup == null:
							_resolve_adventurer_popup()
						if _adventurer_popup != null and _adventurer_popup.has_method("open_at"):
							_adventurer_popup.call("open_at", adv_id, mouse_global)
							DbgLog.debug("Adv tooltip open adv_id=%d" % adv_id, "ui")
							get_viewport().set_input_as_handled()
							return

	# If room popup is open, clicking anywhere outside closes it.
	# This runs in _input so it works even if other UI consumes the click; we rely on the
	# popup's short "ignore" window to avoid closing on the opening click.
	if _room_popup != null and _room_popup.visible and event is InputEventMouseButton:
		var mb0 := event as InputEventMouseButton
		if mb0.button_index == MOUSE_BUTTON_LEFT and mb0.pressed:
			var can_close := true
			if _room_popup.has_method("can_close_from_outside_click"):
				can_close = bool(_room_popup.call("can_close_from_outside_click"))
			if can_close and not _room_popup.get_global_rect().has_point(mouse_global):
				_room_popup.call("close")
				get_viewport().set_input_as_handled()
				# Still allow pan/zoom logic below if needed; but the popup is closed now.

	# If adventurer popup is open, clicking anywhere outside closes it.
	if _adventurer_popup != null and _adventurer_popup.visible and event is InputEventMouseButton:
		var mb1 := event as InputEventMouseButton
		if mb1.button_index == MOUSE_BUTTON_LEFT and mb1.pressed:
			var can_close2 := true
			if _adventurer_popup.has_method("can_close_from_outside_click"):
				can_close2 = bool(_adventurer_popup.call("can_close_from_outside_click"))
			if can_close2 and not _adventurer_popup.get_global_rect().has_point(mouse_global):
				_adventurer_popup.call("close")
				get_viewport().set_input_as_handled()
				# Still allow pan/zoom logic below if needed; but the popup is closed now.

	# Middle mouse pan
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				if not over_world:
					return
				_is_panning = true
				var parent := _world_canvas.get_parent() as CanvasItem
				var parent_inv: Transform2D = parent.get_global_transform().affine_inverse()
				_pan_start_mouse_parent = parent_inv * mouse_global
				_pan_start_canvas_pos = _world_canvas.position
				get_viewport().set_input_as_handled()
				return
			else:
				_is_panning = false
				get_viewport().set_input_as_handled()
				return

		# Wheel zoom (cursor-centered)
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if not over_world:
				return
			var old_zoom := _world_zoom
			var factor := ZOOM_STEP if mb.button_index == MOUSE_BUTTON_WHEEL_UP else (1.0 / ZOOM_STEP)
			_world_zoom = clampf(_world_zoom * factor, ZOOM_MIN, ZOOM_MAX)
			if absf(_world_zoom - old_zoom) < 0.0001:
				return

			var parent2 := _world_canvas.get_parent() as CanvasItem
			var parent_inv2: Transform2D = parent2.get_global_transform().affine_inverse()
			var mouse_parent: Vector2 = parent_inv2 * mouse_global

			# Keep the world point under cursor stable.
			var local_before: Vector2 = (mouse_parent - _world_canvas.position) / old_zoom
			_world_canvas.position = mouse_parent - local_before * _world_zoom
			_apply_world_transform()
			_clamp_world_canvas_position()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion and _is_panning:
		var parent3 := _world_canvas.get_parent() as CanvasItem
		var parent_inv3: Transform2D = parent3.get_global_transform().affine_inverse()
		var mouse_parent2: Vector2 = parent_inv3 * mouse_global
		_world_canvas.position = _pan_start_canvas_pos + (mouse_parent2 - _pan_start_mouse_parent)
		_clamp_world_canvas_position()
		get_viewport().set_input_as_handled()
		return

	# Toggle History panel with H key
	if event is InputEventKey:
		var k2 := event as InputEventKey
		if k2.pressed and k2.keycode == KEY_H:
			_on_history_pressed()
			get_viewport().set_input_as_handled()
			return


func _unhandled_input(_event: InputEvent) -> void:
	# (no-op) kept for future unhandled-only behaviors.
	return


func _clamp_world_canvas_position() -> void:
	# Clamp panning so the world stays within the visible WorldFrame.
	# If the world is smaller than the frame (at current zoom), keep it centered.
	if _world_frame == null or _world_canvas == null:
		return

	var frame_size := _world_frame.size
	if frame_size.x <= 0.0 or frame_size.y <= 0.0:
		return

	var scaled_size := _world_canvas.size * _world_zoom
	if scaled_size.x <= 0.0 or scaled_size.y <= 0.0:
		return

	var min_x: float
	var max_x: float
	if scaled_size.x <= frame_size.x:
		min_x = (frame_size.x - scaled_size.x) * 0.5
		max_x = min_x
	else:
		min_x = frame_size.x - scaled_size.x
		max_x = 0.0

	var min_y: float
	var max_y: float
	if scaled_size.y <= frame_size.y:
		min_y = (frame_size.y - scaled_size.y) * 0.5
		max_y = min_y
	else:
		min_y = frame_size.y - scaled_size.y
		max_y = 0.0

	_world_canvas.position = Vector2(
		clampf(_world_canvas.position.x, min_x, max_x),
		clampf(_world_canvas.position.y, min_y, max_y)
	)
	_sync_world_backdrops()


func _apply_world_transform() -> void:
	if _world_canvas == null:
		return
	_world_canvas.scale = Vector2(_world_zoom, _world_zoom)
	_clamp_world_canvas_position()
	_sync_world_backdrops()

	# We now draw paper inside `DungeonView` itself. Disable the separate
	# `FramePaperBase` background to avoid layout/z-order surprises.
	if _frame_paper_base != null:
		_frame_paper_base.visible = false


func _on_boss_killed() -> void:
	# Stop simulation and show game over overlay.
	GameState.set_speed(0.0)
	_simulation.call_deferred("end_day", "loss")
	if _game_over != null:
		_game_over.visible = true


func _on_history_pressed() -> void:
	if _history_panel == null:
		_resolve_history_panel()
	if _history_panel == null:
		return
	if _history_panel.has_method("toggle"):
		_history_panel.call("toggle")
	else:
		_history_panel.visible = not _history_panel.visible


func _restart_game() -> void:
	# Full reset of run state.
	var sim := get_node_or_null("/root/Simulation")
	if sim != null:
		sim.call("end_day", "loss")
	var dg := get_node_or_null("/root/DungeonGrid")
	if dg != null:
		dg.call("clear")
	GameState.reset_all()
	PlayerInventory.reset_all()
	RoomInventory.reset_all()
	# Reload main scene so entrance auto-placement runs again.
	get_tree().reload_current_scene()
