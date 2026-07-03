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
