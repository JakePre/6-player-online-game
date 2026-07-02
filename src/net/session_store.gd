class_name SessionStore
extends RefCounted
## Persists the last joined room's code + session token to disk so the player
## can rejoin a match after a crash or restart (SPEC $9).

const PATH := "user://last_session.cfg"
const SECTION := "session"


static func save_session(address: String, port: int, code: String, token: String) -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "address", address)
	config.set_value(SECTION, "port", port)
	config.set_value(SECTION, "code", code)
	config.set_value(SECTION, "token", token)
	config.save(PATH)


## Returns {address, port, code, token} or an empty Dictionary if none saved.
static func load_session() -> Dictionary:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return {}
	return {
		"address": config.get_value(SECTION, "address", ""),
		"port": config.get_value(SECTION, "port", NetConfig.DEFAULT_PORT),
		"code": config.get_value(SECTION, "code", ""),
		"token": config.get_value(SECTION, "token", ""),
	}


static func clear() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
