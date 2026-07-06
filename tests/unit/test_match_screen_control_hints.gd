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
	# Quick Draw's control_hints are anchored on action_primary (Space on kb).
	NetManager.match_event_received.emit(_intro_event("quick_draw", "prose ignored"))
	assert_eq(_controls_label().text, "Press Space the instant it flashes DRAW!")


func test_intro_hint_re_renders_on_device_change() -> void:
	NetManager.match_event_received.emit(_intro_event("quick_draw", "prose ignored"))
	InputGlyphs.active_device = InputGlyphs.Device.GAMEPAD
	InputGlyphs.active_layout = InputGlyphs.Layout.PLAYSTATION
	InputGlyphs.device_changed.emit(InputGlyphs.Device.GAMEPAD)
	assert_eq(_controls_label().text, "Press ✕ the instant it flashes DRAW!")


func test_intro_falls_back_to_prose_without_structured_hints() -> void:
	# Coin Scramble ships no control_hints — the server prose shows verbatim.
	NetManager.match_event_received.emit(_intro_event("coin_scramble", "Grab coins — WASD"))
	assert_eq(_controls_label().text, "Grab coins — WASD")


func test_meta_carries_control_hints_but_to_dict_omits_them() -> void:
	# Structured hints are client-only (no protocol change): they live on the
	# meta but never serialize into the wire dict.
	var meta := QuickDraw.make_meta()
	assert_false(meta.control_hints.is_empty(), "quick_draw declares hints")
	assert_false(meta.to_dict().has("control_hints"), "hints stay off the wire")


func test_turbo_lap_buttons_render_device_aware_while_steering_stays_literal() -> void:
	var segments := TurboLap.make_meta().control_hints
	InputGlyphs.active_device = InputGlyphs.Device.KEYBOARD
	var kb := InputGlyphs.hint_for(segments)
	assert_string_contains(kb, "Drift — Space · Item — E")
	assert_string_contains(kb, "left stick")  # movement stays literal prose
	InputGlyphs.active_device = InputGlyphs.Device.GAMEPAD
	InputGlyphs.active_layout = InputGlyphs.Layout.XBOX
	assert_string_contains(InputGlyphs.hint_for(segments), "Drift — A · Item — X")
