extends Node
## Device-aware input glyphs (#608): control hints should read as what the
## player is actually holding — "press Space" on keyboard, "press Ⓐ" on an
## Xbox pad, "press ✕" on a DualSense. Autoload: tracks the active device
## class from the last input event and the pad layout from Input.get_joy_name,
## emits `device_changed` so live UI can re-render, and maps an action to the
## right label via glyph_for(). Text-first — no icon assets; the pure
## classification/label functions are static and unit-tested headless.

## The active device changed (last-input class flipped, or a pad connected /
## swapped layout). Listeners re-render their hints.
signal device_changed(device: Device)

enum Device { KEYBOARD, GAMEPAD }
enum Layout { XBOX, PLAYSTATION, SWITCH, GENERIC }

var active_device: Device = Device.KEYBOARD
var active_layout: Layout = Layout.GENERIC


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_refresh_layout()


## Watches every input to know what the player last touched. A key/mouse event
## flips to keyboard; a pad button/stick flips to gamepad (and re-reads layout).
func _input(event: InputEvent) -> void:
	var device := active_device
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		device = Device.KEYBOARD
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		device = Device.GAMEPAD
		_refresh_layout()
	_set_device(device)


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_refresh_layout()
	device_changed.emit(active_device)


func _set_device(device: Device) -> void:
	if device == active_device:
		return
	active_device = device
	device_changed.emit(device)


func _refresh_layout() -> void:
	var pads := Input.get_connected_joypads()
	active_layout = (
		pad_layout_for(Input.get_joy_name(pads[0])) if not pads.is_empty() else Layout.GENERIC
	)


## The label to show for an input action on the *active* device: the keyboard
## key (respecting rebinds already in the InputMap) or the pad button glyph.
func glyph_for(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	if active_device == Device.KEYBOARD:
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				return key_label(event as InputEventKey)
	else:
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton:
				return pad_button_label(
					(event as InputEventJoypadButton).button_index, active_layout
				)
	return ""


# --- Pure, testable classification + labels -----------------------------------


## Classifies a controller by its reported name (Input.get_joy_name), so the
## face-button glyphs match the physical print. Unknown pads read as GENERIC
## (Xbox-style, the safest default under SDL mappings).
static func pad_layout_for(joy_name: String) -> Layout:
	var name := joy_name.to_lower()
	if "xbox" in name or "xinput" in name:
		return Layout.XBOX
	if (
		"playstation" in name
		or "dualsense" in name
		or "dualshock" in name
		or "ps5" in name
		or "ps4" in name
		or "ps3" in name
		or "sony" in name
	):
		return Layout.PLAYSTATION
	if "switch" in name or "nintendo" in name or "joy-con" in name or "joycon" in name:
		return Layout.SWITCH
	return Layout.GENERIC


## Face-button label per layout. Godot's SDL button_index is Xbox-positional
## (0=A bottom, 1=B right, 2=X left, 3=Y top); PlayStation shows shapes and
## Nintendo swaps the A/B and X/Y prints, so the same index reads differently.
static func pad_button_label(button_index: int, layout: Layout) -> String:
	match layout:
		Layout.PLAYSTATION:
			return _ps_label(button_index)
		Layout.SWITCH:
			return _switch_label(button_index)
		_:
			return _xbox_label(button_index)


static func _xbox_label(button_index: int) -> String:
	match button_index:
		JOY_BUTTON_A:
			return "A"
		JOY_BUTTON_B:
			return "B"
		JOY_BUTTON_X:
			return "X"
		JOY_BUTTON_Y:
			return "Y"
		_:
			return _shared_label(button_index)


static func _ps_label(button_index: int) -> String:
	match button_index:
		JOY_BUTTON_A:
			return "✕"
		JOY_BUTTON_B:
			return "●"
		JOY_BUTTON_X:
			return "■"
		JOY_BUTTON_Y:
			return "▲"
		_:
			return _shared_label(button_index)


static func _switch_label(button_index: int) -> String:
	# Nintendo's physical print swaps A/B (bottom/right) and X/Y (left/top).
	match button_index:
		JOY_BUTTON_A:
			return "B"
		JOY_BUTTON_B:
			return "A"
		JOY_BUTTON_X:
			return "Y"
		JOY_BUTTON_Y:
			return "X"
		_:
			return _shared_label(button_index)


## Non-face buttons read the same across layouts (or fall back to a number).
static func _shared_label(button_index: int) -> String:
	match button_index:
		JOY_BUTTON_LEFT_SHOULDER:
			return "LB"
		JOY_BUTTON_RIGHT_SHOULDER:
			return "RB"
		JOY_BUTTON_START:
			return "Start"
		JOY_BUTTON_BACK:
			return "Select"
		_:
			return "Btn %d" % button_index


## The printed key for a keyboard event, respecting the physical keycode so it
## reflects the layout-independent binding the InputMap actually holds.
static func key_label(event: InputEventKey) -> String:
	var keycode := event.physical_keycode if event.physical_keycode != 0 else event.keycode
	var label := OS.get_keycode_string(keycode)
	return label if not label.is_empty() else "Key"
