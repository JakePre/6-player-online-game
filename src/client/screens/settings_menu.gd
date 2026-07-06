extends Control
## Settings 2.0 (M18-01 part 2, #612; grown from M2-05/M12-03/M16-06): the
## screen is now sectioned into the exact pages SettingsStore.SECTIONS
## partitions — Gameplay / Video / Audio / Controls / Network — with a
## per-section "Reset section" and a global "Reset everything" wired to the
## part-1 store API (PR #613). Changes still apply live and persist
## immediately. Saving overlays this screen's values onto the stored settings
## (not a from-scratch dict), so keys edited elsewhere can never be wiped by
## touching an unrelated control here — the pre-part-2 screen erased
## player_name exactly that way.

## Picked up by the app shell router (see AppShell.goto_screen).
signal navigate(screen: StringName)

## Human labels for the rebindable actions, in display order.
const ACTION_LABELS := {
	"move_up": "Move up",
	"move_down": "Move down",
	"move_left": "Move left",
	"move_right": "Move right",
	"action_primary": "Primary action",
	"action_secondary": "Secondary action",
	"emote": "Emote",
}

## Stick past this magnitude counts as a deliberate axis bind, filtering pad
## dead-zone noise and the spring-back to center (M17-03).
const PAD_CAPTURE_THRESHOLD := 0.6

## Friendly names for the common face/D-pad buttons; anything else prints its
## index. Xbox-style letters (the DB maps every pad onto this layout).
const PAD_BUTTON_NAMES := {
	JOY_BUTTON_A: "Button A",
	JOY_BUTTON_B: "Button B",
	JOY_BUTTON_X: "Button X",
	JOY_BUTTON_Y: "Button Y",
	JOY_BUTTON_LEFT_SHOULDER: "L Bumper",
	JOY_BUTTON_RIGHT_SHOULDER: "R Bumper",
	JOY_BUTTON_DPAD_UP: "D-Pad Up",
	JOY_BUTTON_DPAD_DOWN: "D-Pad Down",
	JOY_BUTTON_DPAD_LEFT: "D-Pad Left",
	JOY_BUTTON_DPAD_RIGHT: "D-Pad Right",
}

## Live keyboard override map (action -> physical keycode), seeded from the
## effective binds and written back on every rebind.
var _keybinds := {}
## Live gamepad override map (action -> pad binding dict), same lifecycle (M17-03).
var _padbinds := {}
## The action whose binding is waiting for input, or "" when idle.
var _capturing := ""
## True while the armed row is capturing a gamepad binding, not a keyboard one.
var _capturing_pad := false
var _bind_buttons := {}
var _pad_buttons := {}
## Section name -> its page card, in SettingsStore.SECTIONS order.
var _cards := {}
## Guards live-apply while a seed/reset rewrites every control at once.
var _seeding := false
## Diagnostics page (M18-07): built in code, not the scene, mirroring the
## M18-03 pause-overlay precedent — no .tscn edit needed for a new page.
var _diagnostics_toggle: CheckButton
var _diagnostics_reset_button: Button

@onready var _section_bar: HBoxContainer = %SectionBar
@onready var _name_edit: LineEdit = %NameEdit
@onready var _master_slider: HSlider = %MasterSlider
@onready var _music_slider: HSlider = %MusicSlider
@onready var _sfx_slider: HSlider = %SfxSlider
@onready var _nameplate_slider: HSlider = %NameplateSlider
@onready var _fullscreen_toggle: CheckButton = %FullscreenToggle
@onready var _show_names_toggle: CheckButton = %ShowNamesToggle
@onready var _colorblind_toggle: CheckButton = %ColorblindToggle
@onready var _reduced_motion_toggle: CheckButton = %ReducedMotionToggle
@onready var _keybinds_list: VBoxContainer = %KeybindsList
@onready var _address_edit: LineEdit = %AddressEdit
@onready var _port_edit: LineEdit = %PortEdit
@onready var _reset_all_button: Button = %ResetAllButton
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_cards = {
		"Gameplay": %GameplayCard,
		"Video": %VideoCard,
		"Audio": %AudioCard,
		"Controls": %ControlsCard,
		"Network": %NetworkCard,
	}
	_build_diagnostics_card()
	_build_section_bar()
	_build_keybind_rows()
	_seed(SettingsStore.load_settings())
	for slider: HSlider in [_master_slider, _music_slider, _sfx_slider, _nameplate_slider]:
		slider.value_changed.connect(func(_value: float) -> void: _apply_and_save())
	for toggle: CheckButton in [
		_fullscreen_toggle, _show_names_toggle, _colorblind_toggle, _reduced_motion_toggle
	]:
		toggle.toggled.connect(func(_on: bool) -> void: _apply_and_save())
	for edit: LineEdit in [_name_edit, _address_edit, _port_edit]:
		edit.text_changed.connect(func(_text: String) -> void: _apply_and_save())
	_wire_reset(%ResetGameplayButton, "Gameplay")
	_wire_reset(%ResetVideoButton, "Video")
	_wire_reset(%ResetAudioButton, "Audio")
	_wire_reset(%ResetControlsButton, "Controls")
	_wire_reset(%ResetNetworkButton, "Network")
	_wire_reset(_diagnostics_reset_button, "Diagnostics")
	_reset_all_button.pressed.connect(_on_reset_all)
	_back_button.pressed.connect(func() -> void: navigate.emit(&"main_menu"))
	_back_button.grab_focus()
	ButtonMotion.attach(_reset_all_button)
	ButtonMotion.attach(_back_button)


## Diagnostics page (M18-07): a settings card built in code and appended
## beside the scene-authored cards, so a new page needs no .tscn edit. The
## opt-in toggle starts/stops DiagnosticsLog through SettingsStore.apply();
## Open/Copy help a tester actually find the file to attach to a bug report.
func _build_diagnostics_card() -> void:
	var card := PanelContainer.new()
	card.name = "DiagnosticsCard"
	card.theme_type_variation = PartyTheme.CARD_VARIATION
	card.visible = false
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", PartyTheme.SPACE_MD)
	card.add_child(column)
	var hint := Label.new()
	hint.text = (
		"Saves a detailed session log to help diagnose bugs during testing. "
		+ "The log stays on this machine unless you choose to share it."
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.theme_type_variation = PartyTheme.SMALL_VARIATION
	column.add_child(hint)
	_diagnostics_toggle = CheckButton.new()
	_diagnostics_toggle.text = "Save a diagnostics log"
	_diagnostics_toggle.toggled.connect(func(_on: bool) -> void: _apply_and_save())
	column.add_child(_diagnostics_toggle)
	var folder_row := HBoxContainer.new()
	folder_row.add_theme_constant_override(&"separation", PartyTheme.SPACE_SM)
	var open_button := Button.new()
	open_button.text = "Open log folder"
	open_button.pressed.connect(_on_open_log_folder_pressed)
	folder_row.add_child(open_button)
	var copy_button := Button.new()
	copy_button.text = "Copy log path"
	copy_button.pressed.connect(_on_copy_log_path_pressed)
	folder_row.add_child(copy_button)
	column.add_child(folder_row)
	_diagnostics_reset_button = Button.new()
	_diagnostics_reset_button.text = "Reset section"
	column.add_child(_diagnostics_reset_button)
	for button: Button in [open_button, copy_button, _diagnostics_reset_button]:
		ButtonMotion.attach(button)
	(%NetworkCard as PanelContainer).get_parent().add_child(card)
	_cards["Diagnostics"] = card


func _on_open_log_folder_pressed() -> void:
	OS.shell_open(ProjectSettings.globalize_path(DiagnosticsLog.LOG_DIR))


func _on_copy_log_path_pressed() -> void:
	var path := DiagnosticsLog.current_path()
	if path.is_empty():
		path = DiagnosticsLog.LOG_DIR
	DisplayServer.clipboard_set(ProjectSettings.globalize_path(path))


## One toggle button per store section; a ButtonGroup makes them radio-style,
## and the theme's pressed state marks the active page.
func _build_section_bar() -> void:
	var group := ButtonGroup.new()
	for section: String in SettingsStore.SECTIONS:
		var button := Button.new()
		button.text = section
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = section == "Gameplay"
		button.pressed.connect(_show_section.bind(section))
		ButtonMotion.attach(button)
		_section_bar.add_child(button)


func _show_section(section: String) -> void:
	for card_section: String in _cards:
		(_cards[card_section] as PanelContainer).visible = card_section == section


## Writes `settings` into every control without triggering live-apply — used
## at open and by both reset paths.
func _seed(settings: Dictionary) -> void:
	_seeding = true
	_name_edit.text = settings.player_name
	_master_slider.set_value_no_signal(settings.master_volume * 100.0)
	_music_slider.set_value_no_signal(settings.music_volume * 100.0)
	_sfx_slider.set_value_no_signal(settings.sfx_volume * 100.0)
	_nameplate_slider.set_value_no_signal(settings.nameplate_scale * 100.0)
	_fullscreen_toggle.set_pressed_no_signal(settings.fullscreen)
	_show_names_toggle.set_pressed_no_signal(settings.show_names)
	_colorblind_toggle.set_pressed_no_signal(settings.colorblind)
	_reduced_motion_toggle.set_pressed_no_signal(settings.reduced_motion)
	_address_edit.text = settings.server_address
	var port: int = settings.server_port
	_port_edit.text = str(port) if port > 0 else ""
	_diagnostics_toggle.set_pressed_no_signal(settings.diagnostics_log)
	_keybinds = SettingsStore.effective_keybinds(settings)
	for action: String in _bind_buttons:
		(_bind_buttons[action] as Button).text = _key_name(int(_keybinds[action]))
	_padbinds = SettingsStore.effective_padbinds(settings)
	for action: String in _pad_buttons:
		(_pad_buttons[action] as Button).text = _pad_name(_padbinds[action])
	_seeding = false


func _build_keybind_rows() -> void:
	_keybinds_list.add_child(_column_header())
	for action: String in ACTION_LABELS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		var label := Label.new()
		label.custom_minimum_size = Vector2(160, 0)
		label.text = ACTION_LABELS[action]
		row.add_child(label)
		var key_button := Button.new()
		key_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		key_button.pressed.connect(_begin_capture.bind(action, false))
		row.add_child(key_button)
		_bind_buttons[action] = key_button
		var pad_button := Button.new()
		pad_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pad_button.pressed.connect(_begin_capture.bind(action, true))
		row.add_child(pad_button)
		_pad_buttons[action] = pad_button
		_keybinds_list.add_child(row)


## Keyboard / Gamepad column headers over the two capture buttons.
func _column_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 8)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(160, 0)
	header.add_child(spacer)
	for title: String in ["Keyboard", "Gamepad"]:
		var label := Label.new()
		label.theme_type_variation = PartyTheme.DIM_VARIATION
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.text = title
		header.add_child(label)
	return header


func _wire_reset(button: Button, section: String) -> void:
	button.pressed.connect(_on_reset_section.bind(section))


## Per-section reset (M18-01): the store restores that page's keys to factory,
## the whole UI re-seeds from the result, and it applies + persists at once.
func _on_reset_section(section: String) -> void:
	var settings := SettingsStore.reset_section(_collect(), section)
	_seed(settings)
	SettingsStore.apply(settings, get_window())
	SettingsStore.save_settings(settings)


## The owner's "reset to default for everything" — factory defaults across
## every section, celestrum.com included.
func _on_reset_all() -> void:
	var settings := SettingsStore.defaults()
	_seed(settings)
	SettingsStore.apply(settings, get_window())
	SettingsStore.save_settings(settings)


func _begin_capture(action: String, pad: bool) -> void:
	# Only one capture at a time; re-arming any row restores the previous one.
	_restore_captured_label()
	_capturing = action
	_capturing_pad = pad
	if pad:
		_pad_buttons[action].text = "Press a button…"
	else:
		_bind_buttons[action].text = "Press a key…"


## Repaints the currently-armed button back to its bound value (used when a
## capture is cancelled or superseded).
func _restore_captured_label() -> void:
	if _capturing.is_empty():
		return
	if _capturing_pad and _pad_buttons.has(_capturing):
		_pad_buttons[_capturing].text = _pad_name(_padbinds[_capturing])
	elif _bind_buttons.has(_capturing):
		_bind_buttons[_capturing].text = _key_name(int(_keybinds[_capturing]))


func _input(event: InputEvent) -> void:
	if _capturing.is_empty():
		return
	if _capturing_pad:
		_capture_pad(event)
	else:
		_capture_key(event)


func _capture_key(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	var action := _capturing
	_capturing = ""
	# Escape cancels without rebinding.
	if key.keycode != KEY_ESCAPE:
		var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		_keybinds[action] = int(code)
	_bind_buttons[action].text = _key_name(int(_keybinds[action]))
	_apply_and_save()


## A pad button press or a deliberate stick push rebinds; the pad's B button
## cancels (mirroring Escape for keys). Key events and weak/settling axis
## motion are ignored so they cannot leak into the pad column.
func _capture_pad(event: InputEvent) -> void:
	var action := _capturing
	var binding := {}
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_B:
			# B cancels without rebinding (mirrors Escape for keys).
			get_viewport().set_input_as_handled()
			_capturing = ""
			_pad_buttons[action].text = _pad_name(_padbinds[action])
			return
		binding = {"button": int(event.button_index)}
	elif event is InputEventJoypadMotion and absf(event.axis_value) >= PAD_CAPTURE_THRESHOLD:
		binding = {"axis": int(event.axis), "dir": 1 if event.axis_value > 0.0 else -1}
	else:
		return
	get_viewport().set_input_as_handled()
	_capturing = ""
	_padbinds[action] = binding
	_pad_buttons[action].text = _pad_name(binding)
	_apply_and_save()


func _key_name(keycode: int) -> String:
	var name := OS.get_keycode_string(keycode)
	return name if not name.is_empty() else "Key %d" % keycode


## Readable label for a pad binding — "Button A", "L-Stick Up", or a fallback.
func _pad_name(binding: Dictionary) -> String:
	if binding.has("button"):
		var index := int(binding.button)
		return PAD_BUTTON_NAMES.get(index, "Button %d" % index)
	var axis := int(binding.get("axis", -1))
	var up := int(binding.get("dir", 0)) < 0
	match axis:
		JOY_AXIS_LEFT_X:
			return "L-Stick Left" if up else "L-Stick Right"
		JOY_AXIS_LEFT_Y:
			return "L-Stick Up" if up else "L-Stick Down"
		JOY_AXIS_RIGHT_X:
			return "R-Stick Left" if up else "R-Stick Right"
		JOY_AXIS_RIGHT_Y:
			return "R-Stick Up" if up else "R-Stick Down"
		_:
			return "Axis %d %s" % [axis, "-" if up else "+"]


## This screen's controls as a settings overlay on top of what's stored, so a
## key this screen doesn't own can never be silently reset (the pre-part-2
## screen wiped player_name this way).
func _collect() -> Dictionary:
	var settings := SettingsStore.load_settings()
	settings.player_name = _name_edit.text
	settings.master_volume = _master_slider.value / 100.0
	settings.music_volume = _music_slider.value / 100.0
	settings.sfx_volume = _sfx_slider.value / 100.0
	settings.nameplate_scale = _nameplate_slider.value / 100.0
	settings.fullscreen = _fullscreen_toggle.button_pressed
	settings.show_names = _show_names_toggle.button_pressed
	settings.colorblind = _colorblind_toggle.button_pressed
	settings.reduced_motion = _reduced_motion_toggle.button_pressed
	settings.keybinds = _stored_overrides()
	settings.padbinds = _stored_pad_overrides()
	settings.server_address = _address_edit.text
	settings.server_port = int(_port_edit.text) if _port_edit.text.is_valid_int() else 0
	settings.diagnostics_log = _diagnostics_toggle.button_pressed
	return settings


func _apply_and_save() -> void:
	if _seeding:
		return
	var settings := _collect()
	SettingsStore.apply(settings, get_window())
	SettingsStore.save_settings(settings)


## Only actions bound away from their factory key are persisted, so a later
## change to the defaults reaches players who never rebound that action.
func _stored_overrides() -> Dictionary:
	var overrides := {}
	for action: String in SettingsStore.REBINDABLE_ACTIONS:
		var code := int(_keybinds.get(action, SettingsStore.REBINDABLE_ACTIONS[action]))
		if code != int(SettingsStore.REBINDABLE_ACTIONS[action]):
			overrides[action] = code
	return overrides


## Same overrides-only rule for pad bindings (M17-03).
func _stored_pad_overrides() -> Dictionary:
	var overrides := {}
	for action: String in SettingsStore.REBINDABLE_PAD_ACTIONS:
		var factory: Dictionary = SettingsStore.REBINDABLE_PAD_ACTIONS[action]
		var current: Dictionary = _padbinds.get(action, factory)
		if not SettingsStore.pad_binding_equals(current, factory):
			overrides[action] = current
	return overrides


## Pad/keyboard back (M17-04): B / Esc returns to the menu from anywhere on
## this screen, matching the Back button.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	# Mid-capture, back means "cancel the capture", not "leave the screen".
	if not _capturing.is_empty():
		_restore_captured_label()
		_capturing = ""
		return
	navigate.emit(&"main_menu")
