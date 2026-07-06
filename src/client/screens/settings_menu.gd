extends Control
## Settings screen (M2-05, SPEC $11): audio volumes, window mode, and the
## server address override for self-hosters. M12-03 adds accessibility:
## colorblind-friendly colors, a reduced-motion toggle, and keyboard
## rebinding. Changes apply live and persist immediately via SettingsStore;
## Back returns to the main menu. M16-06: each section is a themed CardPanel.

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

## Live keyboard override map (action -> physical keycode), seeded from the
## effective binds and written back on every rebind.
var _keybinds := {}
## The action whose button is waiting for a key press, or "" when idle.
var _capturing := ""
var _bind_buttons := {}

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
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	var settings := SettingsStore.load_settings()
	_master_slider.value = settings.master_volume * 100.0
	_music_slider.value = settings.music_volume * 100.0
	_sfx_slider.value = settings.sfx_volume * 100.0
	_nameplate_slider.value = settings.nameplate_scale * 100.0
	_fullscreen_toggle.set_pressed_no_signal(settings.fullscreen)
	_show_names_toggle.set_pressed_no_signal(settings.show_names)
	_colorblind_toggle.set_pressed_no_signal(settings.colorblind)
	_reduced_motion_toggle.set_pressed_no_signal(settings.reduced_motion)
	_address_edit.text = settings.server_address
	var port: int = settings.server_port
	_port_edit.text = str(port) if port > 0 else ""
	_keybinds = SettingsStore.effective_keybinds(settings)
	_build_keybind_rows()
	for slider: HSlider in [_master_slider, _music_slider, _sfx_slider, _nameplate_slider]:
		slider.value_changed.connect(func(_value: float) -> void: _apply_and_save())
	for toggle: CheckButton in [
		_fullscreen_toggle, _show_names_toggle, _colorblind_toggle, _reduced_motion_toggle
	]:
		toggle.toggled.connect(func(_on: bool) -> void: _apply_and_save())
	_address_edit.text_changed.connect(func(_text: String) -> void: _apply_and_save())
	_port_edit.text_changed.connect(func(_text: String) -> void: _apply_and_save())
	_back_button.pressed.connect(func() -> void: navigate.emit(&"main_menu"))
	_back_button.grab_focus()
	ButtonMotion.attach(_back_button)


func _build_keybind_rows() -> void:
	for action: String in ACTION_LABELS:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.custom_minimum_size = Vector2(160, 0)
		label.text = ACTION_LABELS[action]
		row.add_child(label)
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text = _key_name(int(_keybinds[action]))
		button.pressed.connect(_begin_capture.bind(action))
		row.add_child(button)
		_bind_buttons[action] = button
		_keybinds_list.add_child(row)


func _begin_capture(action: String) -> void:
	# Only one capture at a time; re-arming a different row cancels the first.
	if not _capturing.is_empty() and _bind_buttons.has(_capturing):
		_bind_buttons[_capturing].text = _key_name(int(_keybinds[_capturing]))
	_capturing = action
	_bind_buttons[action].text = "Press a key…"


func _input(event: InputEvent) -> void:
	if _capturing.is_empty():
		return
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


func _key_name(keycode: int) -> String:
	var name := OS.get_keycode_string(keycode)
	return name if not name.is_empty() else "Key %d" % keycode


func _apply_and_save() -> void:
	var settings := {
		"master_volume": _master_slider.value / 100.0,
		"music_volume": _music_slider.value / 100.0,
		"sfx_volume": _sfx_slider.value / 100.0,
		"nameplate_scale": _nameplate_slider.value / 100.0,
		"fullscreen": _fullscreen_toggle.button_pressed,
		"show_names": _show_names_toggle.button_pressed,
		"colorblind": _colorblind_toggle.button_pressed,
		"reduced_motion": _reduced_motion_toggle.button_pressed,
		"keybinds": _stored_overrides(),
		"server_address": _address_edit.text,
		"server_port": int(_port_edit.text) if _port_edit.text.is_valid_int() else 0,
	}
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
