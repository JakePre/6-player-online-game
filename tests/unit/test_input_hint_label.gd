extends GutTest
## InputHintLabel (#608): renders an action's hint in the active device's
## glyph and re-renders live when the device changes.

var label: InputHintLabel


func before_each() -> void:
	label = InputHintLabel.new()
	add_child_autofree(label)
	InputGlyphs.active_device = InputGlyphs.Device.KEYBOARD
	InputGlyphs.active_layout = InputGlyphs.Layout.XBOX


func after_each() -> void:
	InputGlyphs.active_device = InputGlyphs.Device.KEYBOARD
	InputGlyphs.active_layout = InputGlyphs.Layout.GENERIC


func test_renders_the_active_device_glyph_with_the_prefix() -> void:
	label.set_hint(&"action_primary", "Fire — ")
	assert_eq(label.text, "Fire — Space", "keyboard glyph")


func test_re_renders_when_the_device_changes() -> void:
	label.set_hint(&"action_primary", "Fire — ")
	InputGlyphs.active_device = InputGlyphs.Device.GAMEPAD
	InputGlyphs.device_changed.emit(InputGlyphs.Device.GAMEPAD)
	assert_eq(label.text, "Fire — A", "swapped to the Xbox button live")


func test_empty_glyph_falls_back_to_the_trimmed_prefix() -> void:
	label.set_hint(&"not_an_action", "Nope — ")
	assert_eq(label.text, "Nope —", "no binding → just the label, trimmed")
