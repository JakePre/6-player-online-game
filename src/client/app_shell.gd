extends Control
## Client app shell (M2-01): owns screen routing and hosts the always-visible
## connection status indicator. Navigation follows the server's view of the
## session via NetManager signals (SPEC $4): main menu -> room after a join,
## back to the main menu on leave or server loss. Also hosts the shared error
## toasts and the reconnect overlay (M6-03): a drop while in a room retries
## the saved session instead of silently dumping the player to the menu.

const SCREENS := {
	&"main_menu": "res://src/client/screens/main_menu.tscn",
	&"settings": "res://src/client/screens/settings_menu.tscn",
	&"credits": "res://src/client/screens/credits_screen.tscn",
	&"room": "res://src/lobby/lobby.tscn",
	&"match": "res://src/match/match_screen.tscn",
}
const ROOM_SCREENS: Array[StringName] = [&"room", &"match"]

var _current_screen: Node
var _current_id := &""

@onready var _screen_host: Control = $ScreenHost
@onready var _reconnect_overlay: Control = $ReconnectOverlay
@onready var _toasts: Control = $Toasts


func _ready() -> void:
	SettingsStore.apply(SettingsStore.load_settings(), get_window())
	NetManager.joined_room.connect(_on_joined_room)
	NetManager.room_updated.connect(_on_room_updated)
	NetManager.join_failed.connect(_on_join_failed)
	NetManager.match_start_failed.connect(_on_match_start_failed)
	NetManager.left_room.connect(func() -> void: goto_screen(&"main_menu"))
	NetManager.server_disconnected.connect(_on_server_disconnected)
	_reconnect_overlay.closed.connect(_on_reconnect_closed)
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


## A drop while in a room goes to the reconnect overlay (SPEC $11) as long as
## there is a saved session to retry; everywhere else the menu is the right
## place, with a toast so the drop is not silent.
func _on_server_disconnected() -> void:
	if _current_id in ROOM_SCREENS:
		var saved := SessionStore.load_session()
		if not String(saved.get("code", "")).is_empty():
			_reconnect_overlay.begin(saved)
			return
	_toasts.show_toast("Connection to the server was lost.")
	goto_screen(&"main_menu")


func _on_reconnect_closed(rejoined: bool) -> void:
	if rejoined:
		return
	_toasts.show_toast("Left the session. You can rejoin from the menu.")
	goto_screen(&"main_menu")


## The main menu reports join failures inline next to its form, and the
## reconnect overlay owns failures during its own retries; toast everywhere
## else so refusals (room full, bad code, version mismatch) are never silent.
func _on_join_failed(reason: int) -> void:
	if _current_id == &"main_menu" or _reconnect_overlay.visible:
		return
	_toasts.show_toast(JoinFailureText.describe(reason))


func _on_match_start_failed(reason: String) -> void:
	_toasts.show_toast("Could not start the match: %s" % reason)
