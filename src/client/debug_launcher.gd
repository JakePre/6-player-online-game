extends Node
## Dev-only shortcut (see scripts/dev-client.sh): launched via
## `--debug-minigame=<id>` (boot.gd) to skip the menu/lobby/character-select
## flow and jump straight into a single minigame, solo, for fast view-
## migration iteration. Requires the server to run with --debug-rpcs
## (net_manager.gd); connects, creates a room, and force-starts a 1-round
## match for the requested minigame via the debug_force_start config key
## (Room.force_start_match(), net_manager.gd's _rpc_start_match). Frees
## itself once the round starts or the request fails — app_shell's normal
## screens take it from there exactly as for a real player.
##
## User args: --debug-minigame=<id> [--address=127.0.0.1] [--port=7777]
##            [--name=Dev]

var minigame_id: StringName = &""
var _address := "127.0.0.1"
var _port := NetConfig.DEFAULT_PORT
var _player_name := "Dev"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	minigame_id = StringName(NetManager._arg_value(args, "--debug-minigame", ""))
	_address = NetManager._arg_value(args, "--address", _address)
	_port = int(NetManager._arg_value(args, "--port", str(_port)))
	_player_name = NetManager._arg_value(args, "--name", _player_name)

	MinigameCatalog.register_builtins()
	if not MinigameCatalog.is_registered(minigame_id):
		var known: Array[String] = []
		for id: StringName in MinigameCatalog.registered_ids():
			known.append(String(id))
		push_warning(
			(
				"[debug-launcher] unknown minigame id '%s'; registered ids: %s"
				% [minigame_id, ", ".join(known)]
			)
		)
		queue_free()
		return

	NetManager.connected_to_server.connect(_on_connected)
	NetManager.connection_failed.connect(
		func() -> void: _abort("connection to %s:%d failed" % [_address, _port])
	)
	NetManager.joined_room.connect(_on_joined_room)
	NetManager.join_failed.connect(
		func(reason: int) -> void: _abort("join_failed_" + NetConfig.join_result_name(reason))
	)
	NetManager.match_start_failed.connect(
		func(reason: String) -> void:
			_abort("match start failed: %s (is the server running --debug-rpcs?)" % reason)
	)
	NetManager.match_event_received.connect(_on_match_event)

	if NetManager.connect_to_server(_address, _port) != OK:
		_abort("connect_to_server call failed")


func _on_connected() -> void:
	NetManager.request_create_room(_player_name)


func _on_joined_room(_code: String, _slot: int, _token: String) -> void:
	NetManager.request_start_match(
		{"playlist": [minigame_id], "rounds": 1, "debug_force_start": true}
	)


func _on_match_event(event: Dictionary) -> void:
	if String(event.get("type", "")) == "round_started":
		print("[debug-launcher] round started: %s" % minigame_id)
		queue_free()


func _abort(reason: String) -> void:
	push_warning("[debug-launcher] " + reason)
	queue_free()
