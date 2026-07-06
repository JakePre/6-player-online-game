extends GutTest
## Settings menu (M12-03 accessibility UI): the scene builds one rebind row per
## action, a key press during capture rebinds that action, and the toggles
## drive the accessibility statics through SettingsStore.

var menu: Control


func before_each() -> void:
	var scene: PackedScene = load("res://src/client/screens/settings_menu.tscn")
	menu = scene.instantiate()
	add_child_autofree(menu)


func after_each() -> void:
	# The menu's _ready applies settings globally; restore factory state.
	SettingsStore.apply(SettingsStore.DEFAULTS, null)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SettingsStore.PATH))


func test_builds_one_rebind_row_per_action() -> void:
	var list: VBoxContainer = menu.get_node("%KeybindsList")
	assert_eq(
		list.get_child_count(),
		SettingsStore.REBINDABLE_ACTIONS.size(),
		"a row for every rebindable action"
	)
	assert_eq(menu._bind_buttons.size(), SettingsStore.REBINDABLE_ACTIONS.size())
	assert_eq(
		(menu._bind_buttons["move_up"] as Button).text,
		OS.get_keycode_string(KEY_W),
		"rows show the factory key"
	)


func test_capturing_a_key_rebinds_and_persists() -> void:
	menu._begin_capture("move_up")
	assert_eq((menu._bind_buttons["move_up"] as Button).text, "Press a key…")
	var press := InputEventKey.new()
	press.pressed = true
	press.physical_keycode = KEY_UP
	menu._input(press)
	assert_eq(int(menu._keybinds["move_up"]), KEY_UP, "the capture rebound the action")
	# It persisted only the changed action, as an override.
	var saved: Dictionary = SettingsStore.load_settings().keybinds
	assert_eq(saved, {"move_up": KEY_UP}, "only the rebound action is stored")
	# And it reached the live InputMap.
	var keys := InputMap.action_get_events("move_up").filter(
		func(e: InputEvent) -> bool: return e is InputEventKey
	)
	assert_eq((keys[0] as InputEventKey).physical_keycode, KEY_UP)


func test_escape_cancels_capture_without_rebinding() -> void:
	menu._begin_capture("emote")
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	menu._input(esc)
	assert_eq(int(menu._keybinds["emote"]), KEY_T, "emote keeps its factory key")
	assert_eq((menu._bind_buttons["emote"] as Button).text, OS.get_keycode_string(KEY_T))


func test_toggles_drive_accessibility_statics() -> void:
	var colorblind: CheckButton = menu.get_node("%ColorblindToggle")
	colorblind.button_pressed = true  # emits toggled -> _apply_and_save
	assert_true(PlayerPalette.use_colorblind, "colorblind toggle reaches the palette")
	var motion: CheckButton = menu.get_node("%ReducedMotionToggle")
	motion.button_pressed = true
	assert_true(ArenaFX.reduced_motion, "reduced-motion toggle reaches ArenaFX")


## #580: nameplates off by default; the toggle flips the shared view flag.
func test_show_names_toggle_off_by_default_and_reaches_minigame_view() -> void:
	var toggle: CheckButton = menu.get_node("%ShowNamesToggle")
	assert_false(toggle.button_pressed, "nameplates are off out of the box")
	toggle.button_pressed = true
	assert_true(MinigameView.show_names, "the toggle reaches every view")


# --- Settings 2.0 sectioned pages + reset (M18-01 part 2, #612) ----------------


func test_section_bar_has_a_button_per_store_section() -> void:
	var bar: HBoxContainer = menu.get_node("%SectionBar")
	assert_eq(bar.get_child_count(), SettingsStore.SECTIONS.size())


func test_section_buttons_switch_visible_page() -> void:
	assert_true((menu.get_node("%GameplayCard") as PanelContainer).visible, "Gameplay opens first")
	assert_false((menu.get_node("%AudioCard") as PanelContainer).visible)
	menu._show_section("Audio")
	assert_true((menu.get_node("%AudioCard") as PanelContainer).visible)
	assert_false((menu.get_node("%GameplayCard") as PanelContainer).visible)


## Regression for the pre-part-2 wipe: the old screen rebuilt settings from
## its own controls only, so touching any slider erased keys it didn't own
## (player_name). Saving now overlays onto the stored settings.
func test_touching_a_slider_preserves_player_name() -> void:
	var settings := SettingsStore.load_settings()
	settings.player_name = "Ada"
	SettingsStore.save_settings(settings)
	(menu.get_node("%NameEdit") as LineEdit).text = "Ada"  # mirror what a reopen would seed
	(menu.get_node("%MasterSlider") as HSlider).value = 42.0  # emits -> _apply_and_save
	assert_eq(
		String(SettingsStore.load_settings().player_name), "Ada", "unrelated edits keep the name"
	)


func test_reset_section_restores_only_that_page() -> void:
	(menu.get_node("%MasterSlider") as HSlider).value = 42.0
	(menu.get_node("%AddressEdit") as LineEdit).text = "myhost.example"
	menu._apply_and_save()
	menu._on_reset_section("Audio")
	var saved := SettingsStore.load_settings()
	assert_eq(float(saved.master_volume), float(SettingsStore.DEFAULTS.master_volume))
	assert_eq(String(saved.server_address), "myhost.example", "other sections keep their values")
	assert_eq(
		(menu.get_node("%MasterSlider") as HSlider).value,
		float(SettingsStore.DEFAULTS.master_volume) * 100.0,
		"the UI re-seeds from the reset"
	)


func test_reset_all_restores_factory_defaults_including_celestrum() -> void:
	(menu.get_node("%AddressEdit") as LineEdit).text = "myhost.example"
	(menu.get_node("%MasterSlider") as HSlider).value = 42.0
	menu._apply_and_save()
	menu._on_reset_all()
	var saved := SettingsStore.load_settings()
	assert_eq(String(saved.server_address), "celestrum.com", "the default server comes back")
	assert_eq(float(saved.master_volume), float(SettingsStore.DEFAULTS.master_volume))
	assert_eq((menu.get_node("%AddressEdit") as LineEdit).text, "celestrum.com")


# --- Pad navigation (M17-04) ----------------------------------------------------


func test_ui_cancel_navigates_back_to_main_menu() -> void:
	watch_signals(menu)
	var back := InputEventAction.new()
	back.action = &"ui_cancel"
	back.pressed = true
	menu._unhandled_input(back)
	assert_signal_emitted_with_parameters(menu, "navigate", [&"main_menu"])


func test_ui_cancel_mid_capture_cancels_capture_not_screen() -> void:
	menu._begin_capture("emote")
	watch_signals(menu)
	var back := InputEventAction.new()
	back.action = &"ui_cancel"
	back.pressed = true
	menu._unhandled_input(back)
	assert_signal_not_emitted(menu, "navigate", "back cancels the capture, not the screen")
	assert_eq(menu._capturing, "", "capture armed no more")
	assert_eq((menu._bind_buttons["emote"] as Button).text, OS.get_keycode_string(KEY_T))
