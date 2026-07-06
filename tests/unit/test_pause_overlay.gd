extends GutTest
## In-match pause/options overlay (M18-03): open/close, the live settings
## subset persisting immediately, leave-with-confirm, and focus on open.

var overlay: PauseOverlay


func before_each() -> void:
	overlay = PauseOverlay.new()
	add_child_autofree(overlay)


func after_each() -> void:
	# The overlay writes real settings — restore the file to defaults.
	SettingsStore.save_settings(SettingsStore.defaults())
	ArenaFX.reduced_motion = false


func test_starts_hidden_and_toggles_open_closed() -> void:
	assert_false(overlay.is_open(), "hidden until opened")
	overlay.open()
	assert_true(overlay.is_open())
	overlay.close()
	assert_false(overlay.is_open())


func test_open_focuses_resume_for_pad_navigation() -> void:
	overlay.open()
	assert_eq(
		overlay._resume_button, overlay.get_viewport().gui_get_focus_owner(), "focus on Resume"
	)


func test_close_emits_resumed() -> void:
	watch_signals(overlay)
	overlay.open()
	overlay.close()
	assert_signal_emitted(overlay, "resumed")


func test_reduced_motion_toggle_applies_and_persists_live() -> void:
	overlay.open()
	overlay._names_toggle.button_pressed = true  # emits toggled -> _apply_setting
	assert_true(bool(SettingsStore.load_settings().show_names), "persisted immediately")
	overlay._reduced_toggle.button_pressed = true
	assert_true(ArenaFX.reduced_motion, "applied live to the running client")


func test_volume_slider_persists_the_scaled_value() -> void:
	overlay.open()
	(overlay._sliders["music_volume"] as HSlider).value = 40.0
	assert_almost_eq(float(SettingsStore.load_settings().music_volume), 0.4, 0.001)


func test_leave_requires_a_confirm_step() -> void:
	overlay.open()
	assert_false(overlay._confirm_row.visible, "no confirm yet")
	assert_true(overlay._leave_button.visible)
	overlay._on_leave_pressed()
	assert_true(overlay._confirm_row.visible, "clicking Leave asks to confirm")
	assert_false(overlay._leave_button.visible, "the one-tap leave is hidden behind the confirm")


func test_syncs_controls_from_stored_settings_on_open() -> void:
	var settings := SettingsStore.defaults()
	settings.master_volume = 0.25
	SettingsStore.save_settings(settings)
	overlay.open()
	assert_almost_eq((overlay._sliders["master_volume"] as HSlider).value, 25.0, 0.001)
