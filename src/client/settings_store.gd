class_name SettingsStore
extends RefCounted
## Client settings (M2-05, SPEC $11): audio volumes, window mode, and the
## server address override for self-hosters (SPEC $9). Persisted to
## user://settings.cfg. Load/save/sanitize are pure and unit-tested;
## apply() is the only part that touches AudioServer / the window.

const PATH := "user://settings.cfg"
const SECTION := "settings"

## Persisted schema version (M18-01). Bump when a key is renamed/restructured
## and add a MIGRATIONS entry, so a user's stored choice is carried across the
## rename instead of the per-key DEFAULTS fallback silently dropping it. Files
## written before versioning have no SCHEMA_KEY and read as version 0.
const SCHEMA_VERSION := 1
const SCHEMA_KEY := "schema_version"

## Ordered forward migrations, one per version step. Each renames stored keys
## (old -> new) when loading a file at `from` up to `to`. Empty today — the
## machinery is what M18-01 delivers; the first real rename adds an entry and
## every existing user keeps their value. Exercised by _migrate()'s tests.
const MIGRATIONS: Array[Dictionary] = []

## Which settings page each key belongs to (M18-01 sectioned UI + per-section
## reset). Partitions DEFAULTS exactly — a new key must be assigned a section
## (guarded by a test) so it can never be orphaned from the UI.
const SECTIONS := {
	"Gameplay": ["player_name", "nameplate_scale", "show_names"],
	"Video": ["fullscreen", "colorblind", "reduced_motion"],
	"Audio": ["master_volume", "music_volume", "sfx_volume"],
	"Controls": ["keybinds", "padbinds"],
	"Network": ["server_address", "server_port"],
	"Diagnostics": ["diagnostics_log"],
}

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

## Factory gamepad bindings per rebindable action (M17-03), mirroring
## project.godot's [input] joypad events: movement on the left stick axes,
## actions on face buttons. {button: index} or {axis: index, sign: -1|1}.
const REBINDABLE_PAD_ACTIONS := {
	"move_up": {"axis": JOY_AXIS_LEFT_Y, "sign": -1},
	"move_down": {"axis": JOY_AXIS_LEFT_Y, "sign": 1},
	"move_left": {"axis": JOY_AXIS_LEFT_X, "sign": -1},
	"move_right": {"axis": JOY_AXIS_LEFT_X, "sign": 1},
	"action_primary": {"button": JOY_BUTTON_A},
	"action_secondary": {"button": JOY_BUTTON_X},
	"emote": {"button": JOY_BUTTON_Y},
}

const DEFAULTS := {
	## 20% out of the box — first playtest note was "too loud" (#143).
	"master_volume": 0.2,
	"music_volume": 1.0,
	"sfx_volume": 1.0,
	"fullscreen": false,
	## The public default server (M18-01). Empty is still honored (main_menu
	## treats it as "use the default host"); self-hosters override to their
	## address or localhost, one field away in the Network page.
	"server_address": "celestrum.com",
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
	## Opt-in client diagnostics log (M18-07, docs/DIAGNOSTICS.md). Off by
	## default; when on, apply() starts DiagnosticsLog mirroring the session to
	## user://logs/client-*.log so a tester can attach it to a bug report.
	"diagnostics_log": false,
	## Gamepad rebind overrides (M17-03): action -> {button: idx} or
	## {axis: idx, sign: -1|1}. Same only-changed-actions convention.
	"padbinds": {},
}


static func load_settings() -> Dictionary:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return DEFAULTS.duplicate()
	# Read *every* stored key (not just today's DEFAULTS), so migrations can
	# see and carry forward a value stored under a since-renamed key.
	var raw := {}
	for key: String in config.get_section_keys(SECTION):
		raw[key] = config.get_value(SECTION, key)
	var from_version := int(raw.get(SCHEMA_KEY, 0))
	return sanitize(migrate(raw, from_version))


static func save_settings(settings: Dictionary) -> void:
	var clean := sanitize(settings)
	var config := ConfigFile.new()
	for key: String in clean:
		config.set_value(SECTION, key, clean[key])
	config.set_value(SECTION, SCHEMA_KEY, SCHEMA_VERSION)
	config.save(PATH)


## Applies the ordered forward migrations from `from_version` up to the current
## schema, renaming stored keys so a choice survives a key rename. Pure — takes
## the migration list as a param so it is directly testable. Unknown keys are
## left in place for sanitize() to drop.
static func migrate(
	raw: Dictionary, from_version: int, migrations: Array[Dictionary] = MIGRATIONS
) -> Dictionary:
	var out := raw.duplicate(true)
	for step: Dictionary in migrations:
		if int(step.get("from", -1)) < from_version:
			continue
		for old_key: String in step.get("rename", {}):
			var new_key: String = step.rename[old_key]
			if out.has(old_key) and not out.has(new_key):
				out[new_key] = out[old_key]
				out.erase(old_key)
	return out


## The full factory defaults — the target of a global "Reset to defaults".
static func defaults() -> Dictionary:
	return DEFAULTS.duplicate(true)


## Returns `settings` with only the given section's keys restored to their
## defaults (per-section reset, M18-01). Unknown section name is a no-op copy.
static func reset_section(settings: Dictionary, section: String) -> Dictionary:
	var out := sanitize(settings)
	for key: String in SECTIONS.get(section, []):
		out[key] = DEFAULTS[key].duplicate() if DEFAULTS[key] is Dictionary else DEFAULTS[key]
	return out


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
	if raw.has("diagnostics_log"):
		clean.diagnostics_log = bool(raw.diagnostics_log)
	clean.keybinds = _sanitize_keybinds(raw.get("keybinds", {}))
	clean.padbinds = _sanitize_padbinds(raw.get("padbinds", {}))
	return clean


## Keeps only overrides for known actions shaped like {button: idx} or
## {axis: idx, sign: -1|1} with plausible indices; everything else drops so a
## stale or hand-edited file can never bind an action to garbage.
static func _sanitize_padbinds(raw: Variant) -> Dictionary:
	var clean := {}
	if raw is not Dictionary:
		return clean
	for action: String in REBINDABLE_PAD_ACTIONS:
		if not raw.has(action) or raw[action] is not Dictionary:
			continue
		var bind: Dictionary = raw[action]
		if bind.has("button"):
			var button := int(bind.button)
			if button >= 0 and button < JOY_BUTTON_MAX:
				clean[action] = {"button": button}
		elif bind.has("axis"):
			var axis := int(bind.axis)
			var axis_sign := signi(int(bind.get("sign", 0)))
			if axis >= 0 and axis < JOY_AXIS_MAX and axis_sign != 0:
				clean[action] = {"axis": axis, "sign": axis_sign}
	return clean


## The full action -> pad binding map in force: factory bindings with the
## sanitized overrides layered on top (mirror of effective_keybinds).
static func effective_padbinds(settings: Dictionary) -> Dictionary:
	var binds := REBINDABLE_PAD_ACTIONS.duplicate(true)
	var overrides := _sanitize_padbinds(settings.get("padbinds", {}))
	for action: String in overrides:
		binds[action] = overrides[action]
	return binds


## Rewrites each rebindable action's JOYPAD binding in the live InputMap to
## the effective pad bind, leaving that action's keyboard events in place —
## the exact mirror of apply_keybinds. Safe to call repeatedly.
static func apply_padbinds(settings: Dictionary) -> void:
	var binds := effective_padbinds(settings)
	for action: String in binds:
		if not InputMap.has_action(action):
			continue
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				InputMap.action_erase_event(action, event)
		var bind: Dictionary = binds[action]
		if bind.has("button"):
			var press := InputEventJoypadButton.new()
			press.device = -1
			press.button_index = int(bind.button)
			press.pressed = true
			InputMap.action_add_event(action, press)
		else:
			var motion := InputEventJoypadMotion.new()
			motion.device = -1
			motion.axis = int(bind.axis)
			motion.axis_value = float(signi(int(bind.sign)))
			InputMap.action_add_event(action, motion)


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


## The window mode to hold for the given fullscreen preference, changing ONLY
## the fullscreen dimension (#821). A windowed window may legitimately be
## maximized or minimized, so those sub-states are left untouched when
## fullscreen already matches — apply() runs on every slider tick, and the old
## code force-set MODE_WINDOWED each time, un-maximizing (minimizing, on
## Windows) the window on every drag. Pure, so the decision is unit-testable
## without a real Window.
static func window_mode_for(current: int, is_fullscreen: bool) -> int:
	var currently_fullscreen := (
		current == Window.MODE_FULLSCREEN or current == Window.MODE_EXCLUSIVE_FULLSCREEN
	)
	if is_fullscreen == currently_fullscreen:
		return current
	return Window.MODE_FULLSCREEN if is_fullscreen else Window.MODE_WINDOWED


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
		var wanted := window_mode_for(window.mode, clean.fullscreen)
		if window.mode != wanted:
			window.mode = wanted
	# Accessibility (M12-03): the flags live as statics on the classes that
	# consume them, set once here so every view and the palette see the change.
	PlayerPalette.use_colorblind = clean.colorblind
	ArenaFX.reduced_motion = clean.reduced_motion
	MinigameView.show_names = clean.show_names
	apply_keybinds(clean)
	# Diagnostics log (M18-07): starts/stops live so the toggle takes effect
	# immediately, same as every other setting here.
	if clean.diagnostics_log:
		if not DiagnosticsLog.is_active():
			DiagnosticsLog.configure("client", DiagnosticsLog.Level.INFO)
	elif DiagnosticsLog.is_active():
		DiagnosticsLog.stop()
	apply_padbinds(clean)


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
