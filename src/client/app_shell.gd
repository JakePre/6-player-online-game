extends Control
## Client app shell (M2-01): owns screen routing and hosts the always-visible
## connection status indicator. Navigation follows the server's view of the
## session via NetManager signals (SPEC $4): main menu -> room after a join,
## back to the main menu on leave or server loss.

const SCREENS := {
	&"main_menu": "res://src/client/screens/main_menu.tscn",
	&"settings": "res://src/client/screens/settings_menu.tscn",
	&"room": "res://src/lobby/lobby.tscn",
	&"match": "res://src/match/match_screen.tscn",
}

var _current_screen: Node
var _current_id := &""

@onready var _screen_host: Control = $ScreenHost


func _ready() -> void:
	SettingsStore.apply(SettingsStore.load_settings(), get_window())
	NetManager.joined_room.connect(_on_joined_room)
	NetManager.room_updated.connect(_on_room_updated)
	NetManager.left_room.connect(func() -> void: goto_screen(&"main_menu"))
	NetManager.server_disconnected.connect(func() -> void: goto_screen(&"main_menu"))
	goto_screen(&"main_menu")


func goto_screen(id: StringName) -> void:
	assert(SCREENS.has(id), "Unknown screen id: %s" % id)
	if _current_screen != null:
		_current_screen.queue_free()
	var scene_path: String = SCREENS[id]
	var scene: PackedScene = load(scene_path)
	_current_screen = scene.instantiate()
	# Screens request navigation (e.g. main menu -> settings) by declaring a
	# `navigate(screen: StringName)` signal; server-driven routing stays above.
	if _current_screen.has_signal("navigate"):
		_current_screen.connect("navigate", goto_screen)
	_screen_host.add_child(_current_screen)
	_current_id = id


func _on_joined_room(_code: String, _slot: int, _token: String) -> void:
	goto_screen(&"room")


## The server's room state decides which screen is right (SPEC $4): lobby
## while LOBBY, match chrome while IN_MATCH. Covers match start, the podium
## returning everyone to the lobby, and rejoining into a running match.
func _on_room_updated(state: Dictionary) -> void:
	if state.state == Room.State.IN_MATCH and _current_id == &"room":
		goto_screen(&"match")
	elif state.state == Room.State.LOBBY and _current_id == &"match":
		goto_screen(&"room")
