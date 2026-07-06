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

## Live keyboard override map (action -> physical keycode), seeded from the
## effective binds and written back on every rebind.
var _keybinds := {}
## The action whose button is waiting for a key press, or "" when idle.
var _capturing := ""
var _bind_buttons := {}
## Section name -> its page card, in SettingsStore.SECTIONS order.
var _cards := {}
## Guards live-apply while a seed/reset rewrites every control at once.
var _seeding := false

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
	_reset_all_button.pressed.connect(_on_reset_all)
	_back_button.pressed.connect(func() -> void: navigate.emit(&"main_menu"))
	_back_button.grab_focus()
	ButtonMotion.attach(_reset_all_button)
	ButtonMotion.attach(_back_button)


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
	_keybinds = SettingsStore.effective_keybinds(settings)
	for action: String in _bind_buttons:
		(_bind_buttons[action] as Button).text = _key_name(int(_keybinds[action]))
	_seeding = false


func _build_keybind_rows() -> void:
	for action: String in ACTION_LABELS:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.custom_minimum_size = Vector2(160, 0)
		label.text = ACTION_LABELS[action]
		row.add_child(label)
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_begin_capture.bind(action))
		row.add_child(button)
		_bind_buttons[action] = button
		_keybinds_list.add_child(row)


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
	settings.server_address = _address_edit.text
	settings.server_port = int(_port_edit.text) if _port_edit.text.is_valid_int() else 0
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
