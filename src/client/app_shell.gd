extends Control
## Client app shell (M2-01): owns screen routing and hosts the always-visible
## connection status indicator. Navigation follows the server's view of the
## session via NetManager signals (SPEC $4): main menu -> room after a join,
## back to the main menu on leave or server loss.

const SCREENS := {
	&"main_menu": "res://src/client/screens/main_menu.tscn",
	&"room": "res://src/client/screens/lobby_placeholder.tscn",
}

var _current_screen: Node

@onready var _screen_host: Control = $ScreenHost


func _ready() -> void:
	NetManager.joined_room.connect(_on_joined_room)
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
	_screen_host.add_child(_current_screen)


func _on_joined_room(_code: String, _slot: int, _token: String) -> void:
	goto_screen(&"room")
