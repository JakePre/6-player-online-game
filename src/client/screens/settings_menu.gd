extends Control
## Settings screen (M2-05, SPEC $11): audio volumes, window mode, and the
## server address override for self-hosters. Changes apply live and persist
## immediately via SettingsStore; Back returns to the main menu.

## Picked up by the app shell router (see AppShell.goto_screen).
signal navigate(screen: StringName)

@onready var _master_slider: HSlider = %MasterSlider
@onready var _music_slider: HSlider = %MusicSlider
@onready var _sfx_slider: HSlider = %SfxSlider
@onready var _fullscreen_toggle: CheckButton = %FullscreenToggle
@onready var _address_edit: LineEdit = %AddressEdit
@onready var _port_edit: LineEdit = %PortEdit
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	var settings := SettingsStore.load_settings()
	_master_slider.value = settings.master_volume * 100.0
	_music_slider.value = settings.music_volume * 100.0
	_sfx_slider.value = settings.sfx_volume * 100.0
	_fullscreen_toggle.set_pressed_no_signal(settings.fullscreen)
	_address_edit.text = settings.server_address
	var port: int = settings.server_port
	_port_edit.text = str(port) if port > 0 else ""
	for slider: HSlider in [_master_slider, _music_slider, _sfx_slider]:
		slider.value_changed.connect(func(_value: float) -> void: _apply_and_save())
	_fullscreen_toggle.toggled.connect(func(_on: bool) -> void: _apply_and_save())
	_address_edit.text_changed.connect(func(_text: String) -> void: _apply_and_save())
	_port_edit.text_changed.connect(func(_text: String) -> void: _apply_and_save())
	_back_button.pressed.connect(func() -> void: navigate.emit(&"main_menu"))
	_back_button.grab_focus()


func _apply_and_save() -> void:
	var settings := {
		"master_volume": _master_slider.value / 100.0,
		"music_volume": _music_slider.value / 100.0,
		"sfx_volume": _sfx_slider.value / 100.0,
		"fullscreen": _fullscreen_toggle.button_pressed,
		"server_address": _address_edit.text,
		"server_port": int(_port_edit.text) if _port_edit.text.is_valid_int() else 0,
	}
	SettingsStore.apply(settings, get_window())
	SettingsStore.save_settings(settings)
