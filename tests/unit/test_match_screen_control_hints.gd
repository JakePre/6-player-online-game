extends GutTest
## Device-aware intro-card control hints (#608 part 2): the intro card renders
## MinigameMeta.control_hints through InputGlyphs for the device the player is
## holding, re-renders live on device change, and falls back to the plain
## server-sent `controls` prose when a game declares no structured hints.

const ROOM_STATE := {
	"code": "TEST42",
	"state": Room.State.IN_MATCH,
	"host_slot": 0,
	"round_count": 8,
	"members": [{"slot": 0, "name": "Alice", "score": 0, "connected": true, "ready": false}],
}

var screen: Control


func before_each() -> void:
	MinigameCatalog.register_builtins()
	# A synthetic hints-only fixture (#844): once the fan-out gave every real
	# hinted game a control_spec, no registered game was left to exercise the
	# legacy hint-segment path on its own — this pins the framework mechanism
	# independent of any one game's copy.
	(
		MinigameCatalog
		. register(
			(
				MinigameMeta
				. create(
					{
						"id": &"legacy_hint_test_game",
						"name": "Legacy Hint Test",
						"controls": "prose ignored",
						"control_hints": ["Press ", {"action": &"action_primary"}, " to test"],
					}
				)
			),
			MinigameBase
		)
	)
	NetManager.my_room_state = {}
	screen = (load("res://src/match/match_screen.tscn") as PackedScene).instantiate()
	add_child_autofree(screen)
	NetManager.room_updated.emit(ROOM_STATE)
	InputGlyphs.active_device = InputGlyphs.Device.KEYBOARD
	InputGlyphs.active_layout = InputGlyphs.Layout.GENERIC


func after_each() -> void:
	# The autoload is shared state — restore the default between tests.
	InputGlyphs.active_device = InputGlyphs.Device.KEYBOARD
	InputGlyphs.active_layout = InputGlyphs.Layout.GENERIC


func after_all() -> void:
	NetManager.my_room_state = {}


func _intro_event(id: String, controls: String) -> Dictionary:
	return {
		"type": "round_intro",
		"round": 1,
		"rounds": 8,
		"minigame":
		{
			"id": id,
			"name": "Test Game",
			"category": MinigameMeta.Category.SKILL,
			"duration_sec": 60.0,
			"rules": "…",
			"controls": controls,
		},
	}


func _controls_label() -> Label:
	return screen.get_node("%IntroControls")


func test_intro_hint_reads_the_active_device_glyph() -> void:
	# Every real registered game now ships a control_spec (chips win over
	# hints — see the section below), so a synthetic fixture (registered in
	# before_each) is what actually exercises the legacy hint-segment path.
	NetManager.match_event_received.emit(_intro_event("legacy_hint_test_game", "prose ignored"))
	assert_eq(_controls_label().text, "Press Space to test")


func test_intro_hint_re_renders_on_device_change() -> void:
	NetManager.match_event_received.emit(_intro_event("legacy_hint_test_game", "prose ignored"))
	InputGlyphs.active_device = InputGlyphs.Device.GAMEPAD
	InputGlyphs.active_layout = InputGlyphs.Layout.PLAYSTATION
	InputGlyphs.device_changed.emit(InputGlyphs.Device.GAMEPAD)
	assert_eq(_controls_label().text, "Press ✕ to test")


func test_intro_falls_back_to_prose_without_structured_hints() -> void:
	# An id the local catalog doesn't know (an older server's game) has neither
	# spec rows nor hint segments — the server prose shows verbatim.
	NetManager.match_event_received.emit(_intro_event("unknown_game", "Grab coins — WASD"))
	assert_eq(_controls_label().text, "Grab coins — WASD")
	assert_true(_controls_label().visible)


func test_meta_carries_control_hints_but_to_dict_omits_them() -> void:
	# Structured hints are client-only (no protocol change): they live on the
	# meta but never serialize into the wire dict.
	var meta := QuickDraw.make_meta()
	assert_false(meta.control_hints.is_empty(), "quick_draw declares hints")
	assert_false(meta.to_dict().has("control_hints"), "hints stay off the wire")


# --- Structured control chips (#832) --------------------------------------------


func _chips() -> VBoxContainer:
	return screen.get_node("Center/IntroCard/IntroColumn/IntroControlChips")


func _chip_binding(row_index: int) -> Label:
	return _chips().get_child(row_index).get_node("Binding")


func test_spec_renders_chips_and_hides_the_prose_label() -> void:
	# blast_grid ships a control_spec (move + Bomb) — chips win over everything.
	NetManager.match_event_received.emit(_intro_event("blast_grid", "prose ignored"))
	assert_true(_chips().visible)
	assert_false(_controls_label().visible)
	assert_eq(_chips().get_child_count(), 2)
	assert_eq((_chips().get_child(0).get_node("Verb") as Label).text, "Move")
	assert_eq(_chip_binding(0).text, "WASD")
	assert_eq((_chips().get_child(1).get_node("Verb") as Label).text, "Bomb")
	assert_eq(_chip_binding(1).text, "Space")


func test_chips_show_only_the_active_device_and_swap_live() -> void:
	NetManager.match_event_received.emit(_intro_event("blast_grid", "prose ignored"))
	InputGlyphs.active_device = InputGlyphs.Device.GAMEPAD
	InputGlyphs.active_layout = InputGlyphs.Layout.XBOX
	InputGlyphs.device_changed.emit(InputGlyphs.Device.GAMEPAD)
	assert_eq(_chip_binding(0).text, "Left Stick")
	assert_eq(_chip_binding(1).text, "A")


func test_chips_re_render_on_rebind() -> void:
	NetManager.match_event_received.emit(_intro_event("blast_grid", "prose ignored"))
	assert_eq(_chip_binding(1).text, "Space")
	# A live remap (M12-03 settings flow) fires bindings_changed via
	# SettingsStore.apply_keybinds — the chip must show the new key at once.
	SettingsStore.apply_keybinds({"keybinds": {"action_primary": KEY_F}})
	assert_eq(_chip_binding(1).text, "F")
	SettingsStore.apply_keybinds({})  # restore factory binds


func test_hold_rows_carry_the_modifier_prefix() -> void:
	# laser_limbo's Duck row is hold-qualified.
	NetManager.match_event_received.emit(_intro_event("laser_limbo", "prose ignored"))
	var duck: HBoxContainer = _chips().get_child(2)
	assert_eq((duck.get_node("Verb") as Label).text, "Duck")
	var texts: Array[String] = []
	for child in duck.get_children():
		texts.append((child as Label).text)
	assert_has(texts, "hold")


func test_prose_label_returns_when_the_next_game_has_no_spec() -> void:
	# Spec chips for one game must not leak into the next intro (an unconverted
	# game right after a converted one, mid-fan-out).
	NetManager.match_event_received.emit(_intro_event("blast_grid", "prose ignored"))
	assert_true(_chips().visible)
	NetManager.match_event_received.emit(_intro_event("unknown_game", "Old prose"))
	assert_false(_chips().visible)
	assert_true(_controls_label().visible)
	assert_eq(_controls_label().text, "Old prose")


func test_turbo_lap_buttons_render_device_aware_while_steering_stays_literal() -> void:
	var segments := TurboLap.make_meta().control_hints
	InputGlyphs.active_device = InputGlyphs.Device.KEYBOARD
	var kb := InputGlyphs.hint_for(segments)
	assert_string_contains(kb, "Drift — Space · Item — E")
	assert_string_contains(kb, "left stick")  # movement stays literal prose
	InputGlyphs.active_device = InputGlyphs.Device.GAMEPAD
	InputGlyphs.active_layout = InputGlyphs.Layout.XBOX
	assert_string_contains(InputGlyphs.hint_for(segments), "Drift — A · Item — X")
