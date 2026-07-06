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

## Rebindable gameplay actions and their factory keyboard keys (M12-03). Only
## the keyboard binding is remappable; the gamepad binding for each action is
## left untouched so a controller keeps working regardless. Values are
## physical keycodes (layout-independent) matching project.godot's [input].
const REBINDABLE_ACTIONS := {
	"move_up": KEY_W,
	"move_down": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"action_primary": KEY_SPACE,
	"action_secondary": KEY_E,
	"emote": KEY_T,
}

const DEFAULTS := {
	## 20% out of the box — first playtest note was "too loud" (#143).
	"master_volume": 0.2,
	"music_volume": 1.0,
	"sfx_volume": 1.0,
	"fullscreen": false,
	"server_address": "",
	## Remembered between sessions so you don't retype it (#142).
	"player_name": "",
	## Nameplate text scale multiplier (0.5–2.0), applied by CharacterRig.
	"nameplate_scale": 1.0,
	"server_port": 0,
	## Accessibility (M12-03).
	"colorblind": false,
	"reduced_motion": false,
	## Owner directive: nameplates off by default, toggleable (#580). The
	## slot/number badge (PlayerPalette.label_for_slot) stays visible either
	## way — only the player's chosen name is gated.
	"show_names": false,
	## Keyboard rebind overrides: action -> physical keycode. Empty means all
	## factory bindings; only changed actions are stored.
	"keybinds": {},
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
	if raw.has("nameplate_scale"):
		clean.nameplate_scale = clampf(float(raw.nameplate_scale), 0.5, 2.0)
	if raw.has("fullscreen"):
		clean.fullscreen = bool(raw.fullscreen)
	if raw.has("player_name"):
		clean.player_name = String(raw.player_name).strip_edges().left(24)
	if raw.has("server_address"):
		clean.server_address = String(raw.server_address).strip_edges()
	if raw.has("server_port"):
		var port := int(raw.server_port)
		clean.server_port = port if port > 0 and port <= 65535 else 0
	if raw.has("colorblind"):
		clean.colorblind = bool(raw.colorblind)
	if raw.has("reduced_motion"):
		clean.reduced_motion = bool(raw.reduced_motion)
	if raw.has("show_names"):
		clean.show_names = bool(raw.show_names)
	clean.keybinds = _sanitize_keybinds(raw.get("keybinds", {}))
	return clean


## Keeps only overrides for known actions with a plausible keycode; everything
## else is dropped so a stale or hand-edited file can never bind an action to
## garbage (unmapped actions fall back to REBINDABLE_ACTIONS at apply time).
static func _sanitize_keybinds(raw: Variant) -> Dictionary:
	var clean := {}
	if raw is Dictionary:
		for action: String in REBINDABLE_ACTIONS:
			if not raw.has(action):
				continue
			var keycode := int(raw[action])
			if keycode > 0:
				clean[action] = keycode
	return clean


## The full action -> physical keycode map actually in force: the factory
## bindings with the sanitized overrides layered on top. Pure, for apply() and
## the settings UI.
static func effective_keybinds(settings: Dictionary) -> Dictionary:
	var binds := REBINDABLE_ACTIONS.duplicate()
	var overrides := _sanitize_keybinds(settings.get("keybinds", {}))
	for action: String in overrides:
		binds[action] = overrides[action]
	return binds


## Applies audio volumes, window mode, accessibility flags, and key rebinds.
## `window` is the tree's root window (pass null to skip window changes, e.g.
## from tests).
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
	# Accessibility (M12-03): the flags live as statics on the classes that
	# consume them, set once here so every view and the palette see the change.
	PlayerPalette.use_colorblind = clean.colorblind
	ArenaFX.reduced_motion = clean.reduced_motion
	MinigameView.show_names = clean.show_names
	apply_keybinds(clean)


## Rewrites each rebindable action's keyboard binding in the live InputMap to
## the effective keycode, leaving that action's gamepad binding in place. Safe
## to call repeatedly (it replaces, never stacks).
static func apply_keybinds(settings: Dictionary) -> void:
	var binds := effective_keybinds(settings)
	for action: String in binds:
		if not InputMap.has_action(action):
			continue
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				InputMap.action_erase_event(action, event)
		var rebind := InputEventKey.new()
		rebind.physical_keycode = int(binds[action])
		InputMap.action_add_event(action, rebind)
