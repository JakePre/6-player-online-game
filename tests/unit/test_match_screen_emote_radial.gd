extends GutTest
## Controller emote wheel wiring on the match HUD (#608 part 3): the emote
## button opens the wheel on a pad only, releasing resolves it, opening the
## pause menu drops it, and the emote hint reads for the active device.

const ROOM_STATE := {
	"code": "TEST42",
	"state": Room.State.IN_MATCH,
	"host_slot": 0,
	"round_count": 8,
	"members": [{"slot": 0, "name": "Alice", "score": 0, "connected": true, "ready": false}],
}

var screen: Control


func before_each() -> void:
	NetManager.my_room_state = {}
	screen = (load("res://src/match/match_screen.tscn") as PackedScene).instantiate()
	add_child_autofree(screen)
	NetManager.room_updated.emit(ROOM_STATE)
	InputGlyphs.active_device = InputGlyphs.Device.KEYBOARD
	InputGlyphs.active_layout = InputGlyphs.Layout.GENERIC


func after_each() -> void:
	InputGlyphs.active_device = InputGlyphs.Device.KEYBOARD
	InputGlyphs.active_layout = InputGlyphs.Layout.GENERIC


func after_all() -> void:
	NetManager.my_room_state = {}


func _emote_event(pressed: bool) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = &"emote"
	event.pressed = pressed
	return event


func test_emote_hint_reads_for_the_active_device() -> void:
	InputGlyphs.active_device = InputGlyphs.Device.KEYBOARD
	screen._refresh_emote_hint()
	assert_string_contains(screen._emote_hint.text, "1", "keyboard shows the number keys")
	InputGlyphs.active_device = InputGlyphs.Device.GAMEPAD
	InputGlyphs.active_layout = InputGlyphs.Layout.XBOX
	screen._refresh_emote_hint()
	assert_string_contains(screen._emote_hint.text.to_lower(), "hold", "pad shows the wheel hint")


func test_wheel_opens_only_on_a_pad() -> void:
	InputGlyphs.active_device = InputGlyphs.Device.KEYBOARD
	screen._handle_emote_input(_emote_event(true))
	assert_false(screen._emote_radial.is_open(), "keyboard keeps the 1-6 shortcuts")
	InputGlyphs.active_device = InputGlyphs.Device.GAMEPAD
	screen._handle_emote_input(_emote_event(true))
	assert_true(screen._emote_radial.is_open(), "the emote button opens the wheel on a pad")


func test_releasing_with_no_aim_cancels_and_closes() -> void:
	InputGlyphs.active_device = InputGlyphs.Device.GAMEPAD
	screen._handle_emote_input(_emote_event(true))
	assert_true(screen._emote_radial.is_open())
	var consumed: bool = screen._handle_emote_input(_emote_event(false))
	assert_true(consumed, "the release is consumed")
	assert_false(screen._emote_radial.is_open(), "un-aimed release just closes")


func test_opening_the_pause_menu_drops_the_wheel() -> void:
	InputGlyphs.active_device = InputGlyphs.Device.GAMEPAD
	screen._handle_emote_input(_emote_event(true))
	assert_true(screen._emote_radial.is_open())
	var esc := InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	screen._unhandled_input(esc)
	assert_false(screen._emote_radial.is_open(), "pause takes over from the wheel")
	assert_true(screen._pause_overlay.is_open())
