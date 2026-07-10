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

## The live InputMap's bindings changed (a keyboard remap or pad rebind was
## applied, #832). Fired by SettingsStore after apply_keybinds/apply_padbinds
## so control hints re-render with the new keys, not just on device swap.
signal bindings_changed

enum Device { KEYBOARD, GAMEPAD }
enum Layout { XBOX, PLAYSTATION, SWITCH, GENERIC }

## Reserved control_spec input names (#832) that render as a movement cluster
## rather than a single action: the full WASD/stick cluster, its left-right
## slice (side-scrollers), and its up-down slice (lane games).
const CLUSTER_MOVE := &"move"
const CLUSTER_MOVE_LR := &"move_lr"
const CLUSTER_MOVE_UD := &"move_ud"

## Movement actions per cluster, in display order (up-left-down-right reads as
## "WASD" on factory keys).
const CLUSTER_ACTIONS := {
	CLUSTER_MOVE: [&"move_up", &"move_left", &"move_down", &"move_right"],
	CLUSTER_MOVE_LR: [&"move_left", &"move_right"],
	CLUSTER_MOVE_UD: [&"move_up", &"move_down"],
}

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


## Composes a structured control-hint segment list (MinigameMeta.control_hints,
## #608) into one device-aware string for the active device — literal String
## segments pass through verbatim, `{"action": &"..."}` segments render as the
## active glyph. Ignores unknown segment shapes so a malformed hint degrades to
## its literal parts rather than crashing the intro card.
func hint_for(segments: Array) -> String:
	return compose_hint(segments, glyph_for)


## Pure form of hint_for: same composition against any glyph resolver, so the
## segment format is unit-testable headless without a live device.
static func compose_hint(segments: Array, glyph: Callable) -> String:
	var out := ""
	for segment: Variant in segments:
		if segment is String:
			out += segment
		elif segment is Dictionary and (segment as Dictionary).has("action"):
			out += String(glyph.call((segment as Dictionary)["action"]))
	return out


## Rebinds landed in the live InputMap (SettingsStore.apply_keybinds /
## apply_padbinds, #832) — tell every live hint to re-read its labels.
func notify_bindings_changed() -> void:
	bindings_changed.emit()


## The display label for a control_spec input on the active device: movement
## clusters resolve to the actual bound keys ("WASD", or "Up Left Down Right"
## after a remap) on keyboard and the stick on a pad; anything else is an
## InputMap action rendered via glyph_for.
func binding_label(input: StringName) -> String:
	if CLUSTER_ACTIONS.has(input):
		return _cluster_label(input)
	return glyph_for(input)


## Keyboard: the cluster's bound keys, live from the InputMap — single-char
## keys pack tight ("WASD"), anything longer joins with a slash so a remap to
## the arrows reads "Up/Left/Down/Right". Pad: the stick (with an axis arrow
## for the half-clusters), or per-action button glyphs after a button rebind.
func _cluster_label(cluster: StringName) -> String:
	var actions: Array = CLUSTER_ACTIONS[cluster]
	if active_device == Device.KEYBOARD:
		var labels: Array[String] = []
		var all_single := true
		for action: StringName in actions:
			var label := glyph_for(action)
			if label.is_empty():
				continue
			labels.append(label)
			all_single = all_single and label.length() == 1
		if labels.is_empty():
			return ""
		# The full cluster packs single keys tight ("WASD"); the half-clusters
		# and any multi-char remap ("Up/Left/…") slash-join for readability.
		if cluster == CLUSTER_MOVE and all_single:
			return "".join(labels)
		return "/".join(labels)
	return _pad_cluster_label(cluster, actions)


## Pad side of the cluster: the stick (with an axis arrow for half-clusters)
## while every action rides a joypad axis; per-action button glyphs after a
## button rebind.
func _pad_cluster_label(cluster: StringName, actions: Array) -> String:
	if _cluster_is_stick_bound(actions):
		if cluster == CLUSTER_MOVE_LR:
			return "Left Stick ◀▶"
		if cluster == CLUSTER_MOVE_UD:
			return "Left Stick ▲▼"
		return "Left Stick"
	var glyphs: Array[String] = []
	for action: StringName in actions:
		var glyph := glyph_for(action)
		if not glyph.is_empty():
			glyphs.append(glyph)
	return "/".join(glyphs)


## True while every cluster action still rides a joypad axis (the factory left
## stick, or any stick after an axis rebind) — a button rebind drops to glyphs.
func _cluster_is_stick_bound(actions: Array) -> bool:
	for action: StringName in actions:
		if not InputMap.has_action(action):
			return false
		var has_motion := false
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadMotion:
				has_motion = true
		if not has_motion:
			return false
	return true


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
