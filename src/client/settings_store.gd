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

## Factory gamepad binding per action (M17-03), matching project.godot's
## [input]. A binding is either a face/D-pad button `{"button": index}` or a
## stick axis direction `{"axis": axis, "dir": +1|-1}`. Rebinding one leaves
## the action's keyboard binding untouched, mirroring how the keyboard rebind
## leaves the pad binding alone.
const REBINDABLE_PAD_ACTIONS := {
	"move_up": {"axis": JOY_AXIS_LEFT_Y, "dir": -1},
	"move_down": {"axis": JOY_AXIS_LEFT_Y, "dir": 1},
	"move_left": {"axis": JOY_AXIS_LEFT_X, "dir": -1},
	"move_right": {"axis": JOY_AXIS_LEFT_X, "dir": 1},
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
	## Gamepad rebind overrides (M17-03): action -> {"button": i} or
	## {"axis": a, "dir": ±1}. Empty means all factory pad bindings; only
	## changed actions are stored.
	"padbinds": {},
	## Opt-in client diagnostics log (M18-07, docs/DIAGNOSTICS.md). Off by
	## default; when on, apply() starts DiagnosticsLog mirroring the session to
	## user://logs/client-*.log so a tester can attach it to a bug report.
	"diagnostics_log": false,
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


## Keeps only overrides for known actions with a well-formed binding (a button
## index >= 0, or an axis >= 0 with dir ±1); everything else is dropped so a
## stale or hand-edited file can never bind an action to garbage (M17-03).
static func _sanitize_padbinds(raw: Variant) -> Dictionary:
	var clean := {}
	if raw is Dictionary:
		for action: String in REBINDABLE_PAD_ACTIONS:
			if not raw.has(action):
				continue
			var norm := _normalize_pad_binding(raw[action])
			if not norm.is_empty():
				clean[action] = norm
	return clean


## Coerces a stored pad binding to its canonical {"button": i} / {"axis": a,
## "dir": ±1} shape, or {} if it is not a valid binding.
static func _normalize_pad_binding(binding: Variant) -> Dictionary:
	if not (binding is Dictionary):
		return {}
	if binding.has("button"):
		var index := int(binding.button)
		return {"button": index} if index >= 0 else {}
	if binding.has("axis"):
		var axis := int(binding.axis)
		var dir := int(binding.get("dir", 0))
		return {"axis": axis, "dir": dir} if axis >= 0 and (dir == 1 or dir == -1) else {}
	return {}


## True when two pad bindings name the same button or axis+direction. Explicit
## field compare rather than Dictionary == so a button/axis mismatch is never
## a false positive.
static func pad_binding_equals(a: Dictionary, b: Dictionary) -> bool:
	if a.has("button") or b.has("button"):
		return int(a.get("button", -1)) == int(b.get("button", -2))
	return (
		int(a.get("axis", -1)) == int(b.get("axis", -2))
		and int(a.get("dir", 0)) == int(b.get("dir", 99))
	)


## The full action -> pad binding map in force: factory pad bindings with the
## sanitized overrides on top. Pure, for apply() and the settings UI.
static func effective_padbinds(settings: Dictionary) -> Dictionary:
	var binds := {}
	for action: String in REBINDABLE_PAD_ACTIONS:
		binds[action] = (REBINDABLE_PAD_ACTIONS[action] as Dictionary).duplicate()
	var overrides := _sanitize_padbinds(settings.get("padbinds", {}))
	for action: String in overrides:
		binds[action] = overrides[action]
	return binds


## The live InputEvent for a pad binding, for InputMap application and previews.
static func pad_event_from(binding: Dictionary) -> InputEvent:
	if binding.has("button"):
		var button := InputEventJoypadButton.new()
		button.button_index = int(binding.button)
		button.pressed = true
		return button
	var motion := InputEventJoypadMotion.new()
	motion.axis = int(binding.get("axis", 0))
	motion.axis_value = float(int(binding.get("dir", 0)))
	return motion


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
	apply_padbinds(clean)
	# Diagnostics log (M18-07): starts/stops live so the toggle takes effect
	# immediately, same as every other setting here.
	if clean.diagnostics_log:
		if not DiagnosticsLog.is_active():
			DiagnosticsLog.configure("client", DiagnosticsLog.Level.INFO)
	elif DiagnosticsLog.is_active():
		DiagnosticsLog.stop()


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


## Rewrites each action's gamepad binding in the live InputMap to the effective
## pad binding, leaving that action's keyboard binding in place (M17-03). Safe
## to call repeatedly (replaces, never stacks).
static func apply_padbinds(settings: Dictionary) -> void:
	var binds := effective_padbinds(settings)
	for action: String in binds:
		if not InputMap.has_action(action):
			continue
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				InputMap.action_erase_event(action, event)
		InputMap.action_add_event(action, pad_event_from(binds[action]))
