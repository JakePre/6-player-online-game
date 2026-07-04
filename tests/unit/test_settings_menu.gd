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
