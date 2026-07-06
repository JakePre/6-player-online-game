class_name ControllerDb
extends RefCounted
## Controller compatibility layer (M17-01, #569): Godot 4.4.1's built-in SDL
## mapping table froze at the engine's release, so newer or generic pads show
## up unmapped and dead. At client boot we load the bundled community
## SDL_GameControllerDB (zlib licensed, see assets/CREDITS.md) on top of it —
## `update_existing` keeps the freshest mapping for pads Godot already knows.
## Pure parsing lives in mappings_for() so it's unit-testable headless.

const DB_PATH := "res://assets/input/gamecontrollerdb.txt"


## SDL platform tag for the running OS, or "" where the DB doesn't apply
## (headless server exports never call install()).
static func platform_tag() -> String:
	match OS.get_name():
		"Windows":
			return "Windows"
		"macOS":
			return "Mac OS X"
		"Linux":
			return "Linux"
		_:
			return ""


## Every mapping line in `text` for `platform`, comments and blanks skipped.
## SDL DB lines end in ",platform:<name>," — match the field exactly so
## "Mac OS X" never collides with a hypothetical prefix.
static func mappings_for(text: String, platform: String) -> PackedStringArray:
	var out := PackedStringArray()
	if platform.is_empty():
		return out
	var needle := "platform:%s," % platform
	for line in text.split("\n"):
		line = line.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if line.ends_with(needle) or line.contains(needle):
			out.append(line)
	return out


## Loads the bundled DB into the Input singleton. Returns how many mappings
## were installed (0 on non-desktop platforms or if the file is missing —
## missing is a packaging bug worth a loud warning, not a crash).
static func install() -> int:
	var platform := platform_tag()
	if platform.is_empty():
		return 0
	if not FileAccess.file_exists(DB_PATH):
		push_warning("ControllerDb: %s missing from the export — generic pads limited" % DB_PATH)
		return 0
	var mappings := mappings_for(FileAccess.get_file_as_string(DB_PATH), platform)
	for mapping in mappings:
		Input.add_joy_mapping(mapping, true)
	print("[client] controller db: %d %s mappings installed" % [mappings.size(), platform])
	return mappings.size()
