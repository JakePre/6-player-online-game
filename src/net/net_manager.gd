extends Node
## Autoload `NetManager`: the single owner of the ENet transport and the
## client<->server RPC protocol (SPEC $9). Server-authoritative: clients only
## send requests; every gameplay-relevant mutation happens server-side.
##
## The same script runs on both sides. Requests are @rpc("any_peer") and are
## only honoured when this instance is the server; responses/broadcasts are
## @rpc("authority") and only handled on clients.

# Client-side signals (UI listens to these).
signal connected_to_server
signal connection_failed
signal server_disconnected
signal joined_room(code: String, slot: int, token: String)
signal join_failed(reason: int)
signal left_room
signal room_updated(state: Dictionary)
signal snapshot_received(snapshot: Dictionary)
signal pong_received(rtt_ms: int)
signal match_event_received(event: Dictionary)
signal match_start_failed(reason: String)

# Server-side signals (server systems listen to these).
signal peer_joined_room(room: Room, member: RoomMember)
signal peer_left_room(room: Room)

const SNAPSHOT_INTERVAL := 1.0 / NetConfig.SNAPSHOT_HZ
## Round counts the host may pick in the lobby (SPEC $4).
const ALLOWED_ROUND_COUNTS: Array[int] = [8, 12, 15]

var is_server := false
var room_manager: RoomManager

# Server-only: live matches keyed by room code.
var match_controllers := {}

# Server-only: allows test harnesses to force room state via RPC. Enabled by
# the `--debug-rpcs` user arg; never enable on a public server.
var debug_rpcs_enabled := false

# Client-side session mirror of the last successful join.
var my_room_code := ""
var my_slot := -1
var my_session_token := ""

# Artificial latency/loss applied to client-received snapshots, for testing
# minigames under bad network conditions (M1-05). Configured via
# `--fake-lag=<ms> --fake-loss=<0..1>` user args.
var fake_lag_ms := 0
var fake_loss := 0.0

var _lag_rng := RandomNumberGenerator.new()
var _lag_queue: Array[Dictionary] = []
var _snapshot_accum := 0.0
var _server_tick := 0
var _expiry_accum := 0.0


func _ready() -> void:
	_lag_rng.seed = 1337
	var args := OS.get_cmdline_user_args()
	fake_lag_ms = int(_arg_value(args, "--fake-lag", "0"))
	fake_loss = float(_arg_value(args, "--fake-loss", "0"))
	debug_rpcs_enabled = args.has("--debug-rpcs")
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	if is_server:
		_run_server_ticks(delta)
	else:
		_drain_lag_queue()


# --- Lifecycle -------------------------------------------------------------


func start_server(port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_server = true
	room_manager = RoomManager.new()
	return OK


func connect_to_server(address: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func disconnect_from_server() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	_reset_client_session()


# --- Client request API (thin wrappers so UI never touches rpc_id) ---------


func request_create_room(display_name: String) -> void:
	_rpc_create_room.rpc_id(1, display_name, NetConfig.PROTOCOL_VERSION)


func request_join_room(code: String, display_name: String) -> void:
	_rpc_join_room.rpc_id(1, code, display_name, NetConfig.PROTOCOL_VERSION)


func request_rejoin_room(code: String, token: String) -> void:
	_rpc_rejoin_room.rpc_id(1, code, token, NetConfig.PROTOCOL_VERSION)


func request_leave_room() -> void:
	_rpc_leave_room.rpc_id(1)


func send_ping() -> void:
	_rpc_ping.rpc_id(1, Time.get_ticks_msec())


## Host only. `config` supports "rounds" (8/12/15); every other MatchController
## key ("seed", "playlist", timing overrides) is stripped server-side unless
## the server runs with --debug-rpcs.
func request_start_match(config: Dictionary = {}) -> void:
	_rpc_start_match.rpc_id(1, config)


## Per-frame gameplay intent for the minigame in progress; shape is defined by
## each minigame's handle_input.
func send_match_input(data: Dictionary) -> void:
	_rpc_match_input.rpc_id(1, data)


## Test-harness only: asks the server to flip this room's state so rejoin
## behaviour can be exercised before the match framework (M3) exists.
## Ignored unless the server runs with --debug-rpcs.
func request_debug_set_match_state(active: bool) -> void:
	_rpc_debug_set_match_state.rpc_id(1, active)


# --- RPCs: client -> server ------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _rpc_create_room(display_name: String, protocol: int) -> void:
	if not is_server:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var outcome: Dictionary = room_manager.create_room(peer_id, display_name, protocol)
	_deliver_join_outcome(peer_id, outcome)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_join_room(code: String, display_name: String, protocol: int) -> void:
	if not is_server:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var outcome: Dictionary = room_manager.join_room(peer_id, code, display_name, protocol)
	_deliver_join_outcome(peer_id, outcome)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_rejoin_room(code: String, token: String, protocol: int) -> void:
	if not is_server:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var outcome: Dictionary = room_manager.rejoin_room(peer_id, code, token, protocol)
	_deliver_join_outcome(peer_id, outcome)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_leave_room() -> void:
	if not is_server:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var room: Room = room_manager.leave_room(peer_id, Time.get_ticks_msec())
	_rpc_left_room.rpc_id(peer_id)
	if room != null:
		_broadcast_room_state(room)
		peer_left_room.emit(room)


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_ping(client_ms: int) -> void:
	if not is_server:
		return
	_rpc_pong.rpc_id(multiplayer.get_remote_sender_id(), client_ms)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_start_match(config: Dictionary) -> void:
	if not is_server:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var room: Room = room_manager.room_of_peer(peer_id)
	if room == null:
		return
	var reason := _match_start_error(room, peer_id, config)
	if not reason.is_empty():
		_rpc_match_start_failed.rpc_id(peer_id, reason)
		return
	if not debug_rpcs_enabled:
		config = {"rounds": int(config.get("rounds", 12))}
	_start_match(room, config)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_match_input(data: Dictionary) -> void:
	if not is_server:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var room: Room = room_manager.room_of_peer(peer_id)
	if room == null:
		return
	var controller: MatchController = match_controllers.get(room.code)
	if controller == null:
		return
	var member := room.find_by_peer(peer_id)
	if member != null:
		controller.handle_input(member.slot, data)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_debug_set_match_state(active: bool) -> void:
	if not is_server or not debug_rpcs_enabled:
		return
	var room: Room = room_manager.room_of_peer(multiplayer.get_remote_sender_id())
	if room == null:
		return
	room.state = Room.State.IN_MATCH if active else Room.State.LOBBY
	_broadcast_room_state(room)


# --- RPCs: server -> client ------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _rpc_room_joined(code: String, slot: int, token: String, state: Dictionary) -> void:
	my_room_code = code
	my_slot = slot
	my_session_token = token
	joined_room.emit(code, slot, token)
	room_updated.emit(state)


@rpc("authority", "call_remote", "reliable")
func _rpc_join_failed(reason: int) -> void:
	join_failed.emit(reason)


@rpc("authority", "call_remote", "reliable")
func _rpc_left_room() -> void:
	_reset_client_session()
	left_room.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_room_state(state: Dictionary) -> void:
	room_updated.emit(state)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_snapshot(snapshot: Dictionary) -> void:
	if fake_loss > 0.0 and _lag_rng.randf() < fake_loss:
		return
	if fake_lag_ms > 0:
		_lag_queue.append({"deliver_at": Time.get_ticks_msec() + fake_lag_ms, "snapshot": snapshot})
		return
	snapshot_received.emit(snapshot)


@rpc("authority", "call_remote", "unreliable")
func _rpc_pong(client_ms: int) -> void:
	pong_received.emit(Time.get_ticks_msec() - client_ms)


@rpc("authority", "call_remote", "reliable")
func _rpc_match_event(event: Dictionary) -> void:
	match_event_received.emit(event)


@rpc("authority", "call_remote", "reliable")
func _rpc_match_start_failed(reason: String) -> void:
	match_start_failed.emit(reason)


# --- Server internals -------------------------------------------------------


func _run_server_ticks(delta: float) -> void:
	_tick_matches(delta)
	_snapshot_accum += delta
	if _snapshot_accum >= SNAPSHOT_INTERVAL:
		_snapshot_accum = fmod(_snapshot_accum, SNAPSHOT_INTERVAL)
		_server_tick += 1
		_broadcast_snapshots()
	_expiry_accum += delta
	if _expiry_accum >= 30.0:
		_expiry_accum = 0.0
		for code in room_manager.expire_rooms(Time.get_ticks_msec()):
			match_controllers.erase(code)
			print("[server] room %s expired" % code)


func _tick_matches(delta: float) -> void:
	for code: String in match_controllers.keys():
		if not room_manager.rooms.has(code):
			# Room emptied or expired out from under the match.
			match_controllers.erase(code)
			continue
		var controller: MatchController = match_controllers[code]
		controller.tick(delta)
		if controller.is_done():
			match_controllers.erase(code)
			_broadcast_room_state(controller.room)


func _broadcast_snapshots() -> void:
	for room: Room in room_manager.rooms.values():
		var payload := {"tick": _server_tick, "server_ms": Time.get_ticks_msec()}
		var controller: MatchController = match_controllers.get(room.code)
		if controller != null:
			payload["match"] = controller.get_snapshot()
		for member: RoomMember in room.members:
			if member.connected:
				_rpc_snapshot.rpc_id(member.peer_id, payload)


func _match_start_error(room: Room, peer_id: int, config: Dictionary) -> String:
	if room.state != Room.State.LOBBY:
		return "already_in_match"
	var host := room.host()
	if host == null or host.peer_id != peer_id:
		return "not_host"
	if room.connected_count() < 2:
		return "not_enough_players"
	var rounds := int(config.get("rounds", 12))
	if not debug_rpcs_enabled and rounds not in ALLOWED_ROUND_COUNTS:
		return "bad_round_count"
	return ""


func _start_match(room: Room, config: Dictionary) -> void:
	var controller := MatchController.new(room, config)
	match_controllers[room.code] = controller
	controller.event_emitted.connect(_relay_match_event.bind(room))
	controller.start()
	_broadcast_room_state(room)


func _relay_match_event(event: Dictionary, room: Room) -> void:
	for member: RoomMember in room.members:
		if member.connected:
			_rpc_match_event.rpc_id(member.peer_id, event)


func _deliver_join_outcome(peer_id: int, outcome: Dictionary) -> void:
	if outcome.result != NetConfig.JoinResult.OK:
		_rpc_join_failed.rpc_id(peer_id, outcome.result)
		return
	var room: Room = outcome.room
	var member: RoomMember = outcome.member
	_rpc_room_joined.rpc_id(
		peer_id, room.code, member.slot, member.session_token, room.to_state_dict()
	)
	_broadcast_room_state(room)
	peer_joined_room.emit(room, member)


func _broadcast_room_state(room: Room) -> void:
	var state := room.to_state_dict()
	for member: RoomMember in room.members:
		if member.connected:
			_rpc_room_state.rpc_id(member.peer_id, state)


# --- Signal handlers ---------------------------------------------------------


func _on_peer_connected(peer_id: int) -> void:
	if is_server:
		print("[server] peer %d connected" % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if not is_server:
		return
	print("[server] peer %d disconnected" % peer_id)
	var room: Room = room_manager.handle_disconnect(peer_id, Time.get_ticks_msec())
	if room != null and room_manager.rooms.has(room.code):
		_broadcast_room_state(room)
		peer_left_room.emit(room)


func _on_connected_to_server() -> void:
	connected_to_server.emit()


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	connection_failed.emit()


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	_reset_client_session()
	server_disconnected.emit()


# --- Helpers -----------------------------------------------------------------


func _drain_lag_queue() -> void:
	if _lag_queue.is_empty():
		return
	var now := Time.get_ticks_msec()
	while not _lag_queue.is_empty() and _lag_queue[0].deliver_at <= now:
		var entry: Dictionary = _lag_queue.pop_front()
		snapshot_received.emit(entry.snapshot)


func _reset_client_session() -> void:
	my_room_code = ""
	my_slot = -1
	my_session_token = ""


static func _arg_value(args: PackedStringArray, key: String, fallback: String) -> String:
	for arg in args:
		if arg.begins_with(key + "="):
			return arg.get_slice("=", 1)
	return fallback
