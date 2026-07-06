class_name PauseOverlay
extends Control
## In-match pause / options overlay (M18-03). Esc / pad Start opens it during
## a match; it dims the arena and offers Resume, a live settings subset
## (volumes, reduced-motion, nameplates), and Leave-match-with-confirm.
##
## It does NOT pause the server sim — matches are live and authoritative, so
## the round keeps running behind the panel. This only captures local input
## and overlays; a title reminds the player the match goes on. Settings apply
## and persist immediately via SettingsStore. Built in code (no .tscn) on the
## M16 design system; focus lands on Resume when opened (M17-04).

signal resumed

const VOLUME_KEYS := {"master_volume": "Master", "music_volume": "Music", "sfx_volume": "Effects"}

var _panel: PanelContainer
var _resume_button: Button
var _leave_button: Button
var _confirm_row: HBoxContainer
var _sliders := {}
var _reduced_toggle: CheckButton
var _names_toggle: CheckButton


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Above the live match, blocking input to what's behind while open.
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(PartyTheme.BG_DARKER, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_build_panel()
	visible = false


func _build_panel() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = PartyTheme.CARD_VARIATION
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", PartyTheme.SPACE_MD)
	_panel.add_child(box)

	var title := Label.new()
	title.text = "Paused"
	title.theme_type_variation = PartyTheme.TITLE_VARIATION
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var note := Label.new()
	note.text = "The match keeps going — hurry back!"
	note.theme_type_variation = PartyTheme.SMALL_VARIATION
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(note)

	for key: String in VOLUME_KEYS:
		box.add_child(_build_slider(key, VOLUME_KEYS[key]))
	_reduced_toggle = _build_toggle("Reduced motion", "reduced_motion")
	box.add_child(_reduced_toggle)
	_names_toggle = _build_toggle("Show nameplates", "show_names")
	box.add_child(_names_toggle)

	_resume_button = Button.new()
	_resume_button.text = "Resume"
	_resume_button.pressed.connect(close)
	box.add_child(_resume_button)
	_leave_button = Button.new()
	_leave_button.text = "Leave match"
	_leave_button.pressed.connect(_on_leave_pressed)
	box.add_child(_leave_button)
	_confirm_row = _build_confirm_row()
	box.add_child(_confirm_row)
	for button: Button in [_resume_button, _leave_button]:
		ButtonMotion.attach(button)


func _build_slider(key: String, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", PartyTheme.SPACE_MD)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 110.0
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.custom_minimum_size.x = 200.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(value: float) -> void: _apply_setting(key, value / 100.0))
	row.add_child(slider)
	_sliders[key] = slider
	return row


func _build_toggle(label_text: String, key: String) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = label_text
	toggle.toggled.connect(func(on: bool) -> void: _apply_setting(key, on))
	return toggle


func _build_confirm_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", PartyTheme.SPACE_MD)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var prompt := Label.new()
	prompt.text = "Really leave?"
	row.add_child(prompt)
	var yes := Button.new()
	yes.text = "Leave"
	yes.pressed.connect(func() -> void: NetManager.request_leave_room())
	row.add_child(yes)
	var no := Button.new()
	no.text = "Stay"
	no.pressed.connect(func() -> void: _set_confirming(false))
	row.add_child(no)
	for button: Button in [yes, no]:
		ButtonMotion.attach(button)
	row.visible = false
	return row


## Reflect the current settings into the controls, show the panel, fade in,
## and land focus on Resume (M17-04). Reduced-motion skips the fade.
func open() -> void:
	if visible:
		return
	_sync_from_settings()
	_set_confirming(false)
	visible = true
	if ArenaFX.reduced_motion:
		modulate.a = 1.0
	else:
		modulate.a = 0.0
		var tween := create_tween()
		tween.set_trans(PartyTheme.TRANS_DEFAULT).set_ease(PartyTheme.EASE_DEFAULT)
		tween.tween_property(self, "modulate:a", 1.0, PartyTheme.DUR_FAST)
	_resume_button.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	resumed.emit()


func is_open() -> bool:
	return visible


func _sync_from_settings() -> void:
	var settings := SettingsStore.load_settings()
	for key: String in _sliders:
		(_sliders[key] as HSlider).set_value_no_signal(float(settings[key]) * 100.0)
	_reduced_toggle.set_pressed_no_signal(bool(settings.reduced_motion))
	_names_toggle.set_pressed_no_signal(bool(settings.show_names))


## Live-apply + persist a single setting without disturbing the rest.
func _apply_setting(key: String, value: Variant) -> void:
	var settings := SettingsStore.load_settings()
	settings[key] = value
	SettingsStore.apply(settings, get_window())
	SettingsStore.save_settings(settings)


func _on_leave_pressed() -> void:
	_set_confirming(true)


func _set_confirming(confirming: bool) -> void:
	_confirm_row.visible = confirming
	_leave_button.visible = not confirming
	if not confirming and visible:
		_resume_button.grab_focus()
