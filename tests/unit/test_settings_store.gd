extends GutTest


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SettingsStore.PATH))


func test_defaults_when_no_file() -> void:
	var settings := SettingsStore.load_settings()
	assert_eq(settings, SettingsStore.DEFAULTS)


func test_sanitize_clamps_volumes() -> void:
	var clean := SettingsStore.sanitize({"master_volume": 2.0, "music_volume": -0.5})
	assert_eq(clean.master_volume, 1.0)
	assert_eq(SettingsStore.sanitize({"nameplate_scale": 9.0}).nameplate_scale, 2.0)
	assert_eq(SettingsStore.sanitize({"nameplate_scale": 0.1}).nameplate_scale, 0.5)
	assert_eq(SettingsStore.DEFAULTS.master_volume, 0.2, "ships quiet (#143)")
	var named := SettingsStore.sanitize({"player_name": "  Jake  "})
	assert_eq(named.player_name, "Jake", "name is trimmed and persisted (#142)")
	assert_eq(SettingsStore.sanitize({"player_name": "x".repeat(99)}).player_name.length(), 24)
	assert_eq(clean.music_volume, 0.0)
	assert_eq(clean.sfx_volume, 1.0, "missing key falls back to default")


func test_sanitize_rejects_bad_port_and_strips_address() -> void:
	var clean := SettingsStore.sanitize(
		{"server_port": 99999, "server_address": "  play.example.com  "}
	)
	assert_eq(clean.server_port, 0, "out-of-range port resets to default")
	assert_eq(clean.server_address, "play.example.com")
	assert_eq(SettingsStore.sanitize({"server_port": -5}).server_port, 0)
	assert_eq(SettingsStore.sanitize({"server_port": 8080}).server_port, 8080)


func test_sanitize_drops_unknown_keys() -> void:
	var clean := SettingsStore.sanitize({"hax": true})
	assert_false(clean.has("hax"))
	assert_eq(clean, SettingsStore.DEFAULTS)


func test_save_load_round_trip() -> void:
	var settings := {
		"master_volume": 0.5,
		"music_volume": 0.25,
		"sfx_volume": 0.75,
		"fullscreen": true,
		"server_address": "play.example.com",
		"server_port": 4242,
		"nameplate_scale": 1.5,
		"player_name": "Jake",
		"colorblind": true,
		"reduced_motion": true,
		"show_names": true,
		"diagnostics_log": true,
		"keybinds": {"move_up": KEY_UP},
	}
	SettingsStore.save_settings(settings)
	assert_eq(SettingsStore.load_settings(), settings)


func test_load_sanitizes_hand_edited_file() -> void:
	var config := ConfigFile.new()
	config.set_value(SettingsStore.SECTION, "master_volume", 42.0)
	config.set_value(SettingsStore.SECTION, "server_port", "not a port")
	config.save(SettingsStore.PATH)
	var settings := SettingsStore.load_settings()
	assert_eq(settings.master_volume, 1.0, "42.0 clamps to max")
	assert_eq(settings.server_port, 0)


func test_apply_sets_bus_volumes_and_mute() -> void:
	SettingsStore.apply({"music_volume": 0.0, "sfx_volume": 0.5}, null)
	var music := AudioServer.get_bus_index("Music")
	var sfx := AudioServer.get_bus_index("SFX")
	assert_gt(music, 0, "Music bus exists in default layout")
	assert_gt(sfx, 0, "SFX bus exists in default layout")
	assert_true(AudioServer.is_bus_mute(music), "zero volume mutes")
	assert_false(AudioServer.is_bus_mute(sfx))
	assert_almost_eq(AudioServer.get_bus_volume_db(sfx), linear_to_db(0.5), 0.01)
	SettingsStore.apply(SettingsStore.DEFAULTS, null)


## M12-03 accessibility.


func test_sanitize_coerces_accessibility_flags() -> void:
	var clean := SettingsStore.sanitize({"colorblind": 1, "reduced_motion": 0})
	assert_true(clean.colorblind)
	assert_false(clean.reduced_motion)
	assert_false(SettingsStore.DEFAULTS.colorblind, "off out of the box")
	assert_false(SettingsStore.DEFAULTS.reduced_motion)


## #580: nameplates off by default, toggleable.
func test_sanitize_coerces_show_names() -> void:
	assert_true(SettingsStore.sanitize({"show_names": 1}).show_names)
	assert_false(SettingsStore.DEFAULTS.show_names, "off out of the box")


func test_sanitize_keybinds_keeps_valid_drops_junk() -> void:
	var clean := SettingsStore.sanitize(
		{"keybinds": {"move_up": KEY_UP, "not_an_action": KEY_X, "emote": 0}}
	)
	assert_eq(clean.keybinds, {"move_up": KEY_UP}, "unknown action and zero keycode dropped")
	assert_eq(SettingsStore.sanitize({"keybinds": "garbage"}).keybinds, {}, "non-dict is ignored")


func test_effective_keybinds_layers_overrides_on_defaults() -> void:
	var binds := SettingsStore.effective_keybinds({"keybinds": {"move_up": KEY_UP}})
	assert_eq(binds.move_up, KEY_UP, "override wins")
	assert_eq(binds.move_down, KEY_S, "unbound actions keep the factory key")
	assert_eq(binds.size(), SettingsStore.REBINDABLE_ACTIONS.size(), "every action resolves")


func test_apply_sets_accessibility_statics() -> void:
	SettingsStore.apply({"colorblind": true, "reduced_motion": true}, null)
	assert_true(PlayerPalette.use_colorblind)
	assert_true(ArenaFX.reduced_motion)
	SettingsStore.apply({"colorblind": false, "reduced_motion": false}, null)
	assert_false(PlayerPalette.use_colorblind)
	assert_false(ArenaFX.reduced_motion)


## #580: nameplates off by default, toggleable — reaches the shared view flag.
func test_apply_sets_show_names_static() -> void:
	SettingsStore.apply({"show_names": true}, null)
	assert_true(MinigameView.show_names)
	SettingsStore.apply({"show_names": false}, null)
	assert_false(MinigameView.show_names)


func test_apply_keybinds_rebinds_keyboard_keeps_gamepad() -> void:
	SettingsStore.apply({"keybinds": {"move_up": KEY_UP}}, null)
	var events := InputMap.action_get_events("move_up")
	var keys := events.filter(func(e: InputEvent) -> bool: return e is InputEventKey)
	var pads := events.filter(func(e: InputEvent) -> bool: return e is InputEventJoypadMotion)
	assert_eq(keys.size(), 1, "exactly one keyboard binding, not stacked")
	assert_eq((keys[0] as InputEventKey).physical_keycode, KEY_UP)
	assert_gt(pads.size(), 0, "the gamepad binding is left in place")
	# Restore the factory binding so later tests see a clean InputMap.
	SettingsStore.apply(SettingsStore.DEFAULTS, null)
	var restored := InputMap.action_get_events("move_up").filter(
		func(e: InputEvent) -> bool: return e is InputEventKey
	)
	assert_eq((restored[0] as InputEventKey).physical_keycode, KEY_W)


# --- Schema versioning, migration, reset (M18-01) ---


func test_celestrum_is_the_default_server_address() -> void:
	assert_eq(SettingsStore.DEFAULTS.server_address, "celestrum.com")
	assert_eq(SettingsStore.load_settings().server_address, "celestrum.com", "fresh install")


func test_save_stamps_the_current_schema_version() -> void:
	SettingsStore.save_settings({"master_volume": 0.5})
	var config := ConfigFile.new()
	config.load(SettingsStore.PATH)
	assert_eq(
		int(config.get_value(SettingsStore.SECTION, SettingsStore.SCHEMA_KEY, -1)),
		SettingsStore.SCHEMA_VERSION
	)


func test_legacy_unversioned_file_loads_and_keeps_choices() -> void:
	# A file written before versioning: no schema_version key, real values.
	var config := ConfigFile.new()
	config.set_value(SettingsStore.SECTION, "master_volume", 0.4)
	config.set_value(SettingsStore.SECTION, "player_name", "Jake")
	config.save(SettingsStore.PATH)
	var settings := SettingsStore.load_settings()
	assert_almost_eq(float(settings.master_volume), 0.4, 0.001, "the choice survives")
	assert_eq(settings.player_name, "Jake")


func test_migrate_carries_a_renamed_key_forward() -> void:
	# The mechanism the empty production MIGRATIONS list is built for: a value
	# stored under an old key name lands on the new key instead of being lost.
	var steps: Array[Dictionary] = [{"from": 0, "rename": {"old_name": "player_name"}}]
	var migrated := SettingsStore.migrate({"old_name": "Ada"}, 0, steps)
	assert_eq(migrated.get("player_name"), "Ada", "renamed forward")
	assert_false(migrated.has("old_name"), "the old key is gone")


func test_migrate_respects_an_already_present_new_key() -> void:
	var steps: Array[Dictionary] = [{"from": 0, "rename": {"old_name": "player_name"}}]
	var migrated := SettingsStore.migrate({"old_name": "Ada", "player_name": "Bo"}, 0, steps)
	assert_eq(migrated.get("player_name"), "Bo", "an existing new value is not clobbered")


func test_migrate_skips_steps_below_the_stored_version() -> void:
	var steps: Array[Dictionary] = [{"from": 0, "rename": {"old_name": "player_name"}}]
	# Stored version 1 is already past the from:0 step, so no rename applies.
	var migrated := SettingsStore.migrate({"old_name": "Ada"}, 1, steps)
	assert_true(migrated.has("old_name"), "already-migrated file is left alone")


func test_defaults_returns_a_fresh_independent_copy() -> void:
	var a := SettingsStore.defaults()
	a.keybinds["move_up"] = 999
	assert_false(SettingsStore.DEFAULTS.keybinds.has("move_up"), "deep copy, no shared state")


func test_reset_section_restores_only_that_section() -> void:
	var custom := SettingsStore.sanitize(
		{"master_volume": 0.9, "player_name": "Jake", "fullscreen": true}
	)
	var reset := SettingsStore.reset_section(custom, "Audio")
	assert_almost_eq(float(reset.master_volume), SettingsStore.DEFAULTS.master_volume, 0.001)
	assert_eq(reset.player_name, "Jake", "other sections untouched")
	assert_true(reset.fullscreen, "other sections untouched")


func test_sections_partition_defaults_exactly() -> void:
	# Every setting belongs to exactly one page — a new key with no section
	# would be invisible in the UI, so this guards the mapping.
	var covered := {}
	for section: String in SettingsStore.SECTIONS:
		for key: String in SettingsStore.SECTIONS[section]:
			assert_true(key in SettingsStore.DEFAULTS, "%s is a real setting" % key)
			assert_false(covered.has(key), "%s is in exactly one section" % key)
			covered[key] = true
	for key: String in SettingsStore.DEFAULTS:
		assert_true(covered.has(key), "%s is assigned a section" % key)


# --- Client diagnostics log opt-in (M18-07, #632) -----------------------------


func after_all() -> void:
	# Belt-and-suspenders: a test enabling diagnostics_log calls apply(), which
	# starts DiagnosticsLog for real — make sure nothing is left running/behind
	# for the tests that follow in the same GUT run.
	DiagnosticsLog._close()
	var dir := DirAccess.open(DiagnosticsLog.LOG_DIR)
	if dir != null:
		for name in dir.get_files():
			dir.remove(name)


func test_diagnostics_log_is_off_by_default() -> void:
	assert_false(SettingsStore.DEFAULTS.diagnostics_log)
	assert_false(bool(SettingsStore.load_settings().diagnostics_log))


func test_sanitize_coerces_diagnostics_log_to_a_bool() -> void:
	assert_true(SettingsStore.sanitize({"diagnostics_log": 1}).diagnostics_log)
	assert_false(SettingsStore.sanitize({}).diagnostics_log)


func test_apply_starts_and_stops_the_diagnostics_log_live() -> void:
	var settings := SettingsStore.defaults()
	settings.diagnostics_log = true
	SettingsStore.apply(settings, null)
	assert_true(DiagnosticsLog.is_active(), "the toggle starts logging immediately")
	settings.diagnostics_log = false
	SettingsStore.apply(settings, null)
	assert_false(DiagnosticsLog.is_active(), "and stops it immediately")
