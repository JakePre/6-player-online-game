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
##            [--name=Dev] [--debug-bots=N] [--debug-duration=S]
##
## --debug-bots=N (#626): request N server-owned practice bots (#577) before
## force-starting, so the round is actually played instead of an empty arena —
## the render-bot-games pipeline records exactly this. --debug-duration=S
## overrides the round duration (seconds) so a render is a tight clip.

var minigame_id: StringName = &""
var bot_count := 0
var duration_sec := 0.0
var _address := "127.0.0.1"
var _port := NetConfig.DEFAULT_PORT
var _player_name := "Dev"
var _bots_requested := false


func _ready() -> void:
	configure(OS.get_cmdline_user_args())

	MinigameCatalog.register_builtins()
	# `gauntlet` is deliberately never in the catalog — the finale is entered
	# directly (#685), so it passes this gate by name.
	if minigame_id != &"gauntlet" and not MinigameCatalog.is_registered(minigame_id):
		var known: Array[String] = []
		for id: StringName in MinigameCatalog.registered_ids():
			known.append(String(id))
		push_warning(
			(
				"[debug-launcher] unknown minigame id '%s' (or 'gauntlet'); registered ids: %s"
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


## Arg parsing, split from _ready so tests can drive it without a network.
func configure(args: PackedStringArray) -> void:
	minigame_id = StringName(NetManager._arg_value(args, "--debug-minigame", ""))
	_address = NetManager._arg_value(args, "--address", _address)
	_port = int(NetManager._arg_value(args, "--port", str(_port)))
	_player_name = NetManager._arg_value(args, "--name", _player_name)
	# One slot is this client; a request past the cap would silently stall the
	# member-count wait in _on_room_updated, so clamp instead.
	bot_count = clampi(
		int(NetManager._arg_value(args, "--debug-bots", "0")), 0, NetConfig.MAX_PLAYERS_PER_ROOM - 1
	)
	duration_sec = maxf(0.0, float(NetManager._arg_value(args, "--debug-duration", "0")))


## The force-start payload (server honours it only under --debug-rpcs). Pure,
## so tests can assert the shapes without a live server. `gauntlet` is the
## finale, not a catalog game (#685) — same for every FinaleVariants id
## (#936): it skips the playlist entirely and opens
## on the buy-in shop (compressed, with the seeded debug purse) so a debug or
## render session shows shop -> finale in one tight clip.
func start_config() -> Dictionary:
	var config := {"debug_force_start": true}
	if FinaleVariants.is_finale(minigame_id):
		config["finale_only"] = true
		config["shop_sec"] = 8.0
		# #936/#685: pin the requested variant so the harness renders exactly
		# the finale it was asked for, not a random draw.
		config["finale_variant"] = String(minigame_id)
	else:
		config["playlist"] = [minigame_id]
		config["rounds"] = 1
	if duration_sec > 0.0:
		config["duration_override"] = duration_sec
	return config


func _on_connected() -> void:
	NetManager.request_create_room(_player_name)


func _on_joined_room(_code: String, _slot: int, _token: String) -> void:
	if bot_count <= 0:
		_start()
		return
	# Bots join asynchronously: each add triggers a room_updated broadcast, so
	# start once the roster shows everyone (#626).
	NetManager.room_updated.connect(_on_room_updated)
	_bots_requested = true
	for _i in bot_count:
		NetManager.request_add_bot()


func _on_room_updated(state: Dictionary) -> void:
	var members: Array = state.get("members", [])
	if _bots_requested and members.size() >= 1 + bot_count:
		_bots_requested = false
		_start()


func _start() -> void:
	NetManager.request_start_match(start_config())


func _on_match_event(event: Dictionary) -> void:
	# finale_started is the gauntlet path's start gate (#685); the line stays
	# identical either way — the render harness greps for it.
	if String(event.get("type", "")) in ["round_started", "finale_started"]:
		print("[debug-launcher] round started: %s" % minigame_id)
		queue_free()


func _abort(reason: String) -> void:
	push_warning("[debug-launcher] " + reason)
	queue_free()
