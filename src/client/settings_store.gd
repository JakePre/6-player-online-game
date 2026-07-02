class_name SettingsStore
extends RefCounted
## Client settings (M2-05, SPEC $11): audio volumes, window mode, and the
## server address override for self-hosters (SPEC $9). Persisted to
## user://settings.cfg. Load/save/sanitize are pure and unit-tested;
## apply() is the only part that touches AudioServer / the window.

const PATH := "user://settings.cfg"
const SECTION := "settings"

## Volume keys map to the audio buses in default_bus_layout.tres.
const VOLUME_BUSES := {
	"master_volume": &"Master",
	"music_volume": &"Music",
	"sfx_volume": &"SFX",
}

const DEFAULTS := {
	"master_volume": 1.0,
	"music_volume": 1.0,
	"sfx_volume": 1.0,
	"fullscreen": false,
	"server_address": "",
	"server_port": 0,
}


static func load_settings() -> Dictionary:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return DEFAULTS.duplicate()
	var raw := {}
	for key: String in DEFAULTS:
		raw[key] = config.get_value(SECTION, key, DEFAULTS[key])
	return sanitize(raw)


static func save_settings(settings: Dictionary) -> void:
	var clean := sanitize(settings)
	var config := ConfigFile.new()
	for key: String in clean:
		config.set_value(SECTION, key, clean[key])
	config.save(PATH)


## Clamps and type-coerces every field; unknown keys are dropped and missing
## keys fall back to DEFAULTS, so a hand-edited or stale file cannot poison
## the client.
static func sanitize(raw: Dictionary) -> Dictionary:
	var clean := DEFAULTS.duplicate()
	for key: String in VOLUME_BUSES:
		if raw.has(key):
			clean[key] = clampf(float(raw[key]), 0.0, 1.0)
	if raw.has("fullscreen"):
		clean.fullscreen = bool(raw.fullscreen)
	if raw.has("server_address"):
		clean.server_address = String(raw.server_address).strip_edges()
	if raw.has("server_port"):
		var port := int(raw.server_port)
		clean.server_port = port if port > 0 and port <= 65535 else 0
	return clean


## Applies audio volumes and window mode. `window` is the tree's root window
## (pass null to skip window changes, e.g. from tests).
static func apply(settings: Dictionary, window: Window) -> void:
	var clean := sanitize(settings)
	for key: String in VOLUME_BUSES:
		var bus_index := AudioServer.get_bus_index(VOLUME_BUSES[key])
		if bus_index < 0:
			continue
		var volume: float = clean[key]
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(volume, 0.0001)))
		AudioServer.set_bus_mute(bus_index, volume < 0.005)
	if window != null:
		var is_fullscreen: bool = clean.fullscreen
		var wanted := Window.MODE_FULLSCREEN if is_fullscreen else Window.MODE_WINDOWED
		if window.mode != wanted:
			window.mode = wanted
