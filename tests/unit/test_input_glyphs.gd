extends GutTest
## Device-aware input glyphs (#608): pad-layout classification, per-layout
## face-button labels, keyboard key labels, and glyph_for() picking the
## active device's binding for a real action.


func after_each() -> void:
	# The autoload is shared state — restore the default between tests.
	InputGlyphs.active_device = InputGlyphs.Device.KEYBOARD
	InputGlyphs.active_layout = InputGlyphs.Layout.GENERIC


func test_pad_layout_classifies_by_name() -> void:
	assert_eq(InputGlyphs.pad_layout_for("Xbox Series Controller"), InputGlyphs.Layout.XBOX)
	assert_eq(InputGlyphs.pad_layout_for("Sony DualSense"), InputGlyphs.Layout.PLAYSTATION)
	assert_eq(InputGlyphs.pad_layout_for("PS4 Controller"), InputGlyphs.Layout.PLAYSTATION)
	assert_eq(
		InputGlyphs.pad_layout_for("Nintendo Switch Pro Controller"), InputGlyphs.Layout.SWITCH
	)
	assert_eq(InputGlyphs.pad_layout_for("Some Off-Brand Gamepad"), InputGlyphs.Layout.GENERIC)


func test_pad_layout_is_case_insensitive() -> void:
	assert_eq(InputGlyphs.pad_layout_for("XBOX ONE"), InputGlyphs.Layout.XBOX)
	assert_eq(InputGlyphs.pad_layout_for("playstation 5"), InputGlyphs.Layout.PLAYSTATION)


func test_face_buttons_read_per_layout() -> void:
	# Godot's SDL index: 0=A 1=B 2=X 3=Y (Xbox-positional).
	assert_eq(InputGlyphs.pad_button_label(JOY_BUTTON_A, InputGlyphs.Layout.XBOX), "A")
	assert_eq(InputGlyphs.pad_button_label(JOY_BUTTON_Y, InputGlyphs.Layout.XBOX), "Y")
	assert_eq(InputGlyphs.pad_button_label(JOY_BUTTON_A, InputGlyphs.Layout.PLAYSTATION), "✕")
	assert_eq(InputGlyphs.pad_button_label(JOY_BUTTON_Y, InputGlyphs.Layout.PLAYSTATION), "▲")


func test_switch_swaps_the_ab_xy_prints() -> void:
	# Nintendo's bottom button is B, right is A — the classic swap.
	assert_eq(InputGlyphs.pad_button_label(JOY_BUTTON_A, InputGlyphs.Layout.SWITCH), "B")
	assert_eq(InputGlyphs.pad_button_label(JOY_BUTTON_B, InputGlyphs.Layout.SWITCH), "A")
	assert_eq(InputGlyphs.pad_button_label(JOY_BUTTON_X, InputGlyphs.Layout.SWITCH), "Y")
	assert_eq(InputGlyphs.pad_button_label(JOY_BUTTON_Y, InputGlyphs.Layout.SWITCH), "X")


func test_generic_falls_back_to_xbox_then_numbered() -> void:
	assert_eq(InputGlyphs.pad_button_label(JOY_BUTTON_B, InputGlyphs.Layout.GENERIC), "B")
	assert_eq(InputGlyphs.pad_button_label(JOY_BUTTON_START, InputGlyphs.Layout.GENERIC), "Start")
	assert_string_contains(InputGlyphs.pad_button_label(20, InputGlyphs.Layout.GENERIC), "Btn")


func test_key_label_reads_the_physical_keycode() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SPACE
	assert_eq(InputGlyphs.key_label(event), "Space")


func test_glyph_for_keyboard_shows_the_bound_key() -> void:
	InputGlyphs.active_device = InputGlyphs.Device.KEYBOARD
	# action_primary is Space on keyboard (project.godot).
	assert_eq(InputGlyphs.glyph_for(&"action_primary"), "Space")


func test_glyph_for_gamepad_shows_the_layout_button() -> void:
	InputGlyphs.active_device = InputGlyphs.Device.GAMEPAD
	# action_primary is button 0 (A) on the pad.
	InputGlyphs.active_layout = InputGlyphs.Layout.XBOX
	assert_eq(InputGlyphs.glyph_for(&"action_primary"), "A")
	InputGlyphs.active_layout = InputGlyphs.Layout.PLAYSTATION
	assert_eq(InputGlyphs.glyph_for(&"action_primary"), "✕")


func test_glyph_for_unknown_action_is_empty() -> void:
	assert_eq(InputGlyphs.glyph_for(&"not_an_action"), "")


func test_compose_hint_interleaves_literals_and_action_glyphs() -> void:
	# A fake resolver keeps this pure — no live device needed.
	var glyph := func(action: StringName) -> String: return "[%s]" % action
	var segments := ["Press ", {"action": &"action_primary"}, " to draw"]
	assert_eq(InputGlyphs.compose_hint(segments, glyph), "Press [action_primary] to draw")


func test_compose_hint_ignores_malformed_segments() -> void:
	# A dict without "action", or a non-string/dict, degrades to the literals.
	var glyph := func(_action: StringName) -> String: return "X"
	var segments := ["a", {"nope": 1}, 42, "b"]
	assert_eq(InputGlyphs.compose_hint(segments, glyph), "ab")


func test_hint_for_renders_against_the_active_device() -> void:
	InputGlyphs.active_device = InputGlyphs.Device.GAMEPAD
	InputGlyphs.active_layout = InputGlyphs.Layout.PLAYSTATION
	var segments := ["Drift — ", {"action": &"action_primary"}]
	assert_eq(InputGlyphs.hint_for(segments), "Drift — ✕")
	InputGlyphs.active_device = InputGlyphs.Device.KEYBOARD
	assert_eq(InputGlyphs.hint_for(segments), "Drift — Space")
