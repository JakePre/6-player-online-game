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
signal kicked
signal room_updated(state: Dictionary)
signal snapshot_received(snapshot: Dictionary)
signal pong_received(rtt_ms: int)
signal match_event_received(event: Dictionary)
signal match_start_failed(reason: String)
signal emote_received(slot: int, emote: int)

# Server-side signals (server systems listen to these).
signal peer_joined_room(room: Room, member: RoomMember)
signal peer_left_room(room: Room)
signal match_started(room: Room)

const SNAPSHOT_INTERVAL := 1.0 / NetConfig.SNAPSHOT_HZ
## How often the server pumps a practice bot's intent (#577), matching the
## human client input cadence.
const BOT_INPUT_INTERVAL_SEC := 0.25
## Server-side emote anti-spam (#592): a token bucket, not a flat cooldown —
## a burst reads as snappy party chat, the sustained rate after it still caps
## a 24-player room. EMOTE_BURST_MAX spends instantly; each EMOTE_REFILL_MS
## regains one token (so the sustained rate is 1000.0 / EMOTE_REFILL_MS/sec).
const EMOTE_BURST_MAX := 3.0
const EMOTE_REFILL_MS := 500.0

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
# Last room state broadcast, kept so screens instantiated mid-session can
# seed themselves (a node connected during an emission misses that emission).
var my_room_state := {}

# Artificial latency/loss applied to client-received snapshots, for testing
# minigames under bad network conditions (M1-05). Configured via
# `--fake-lag=<ms> --fake-loss=<0..1>` user args.
var fake_lag_ms := 0
var fake_loss := 0.0

# Server-only: per-peer emote token-bucket state, {tokens: float, last_ms: int}.
var _emote_tokens := {}
var _lag_rng := RandomNumberGenerator.new()
var _lag_queue: Array[Dictionary] = []
var _snapshot_accum := 0.0
var _server_tick := 0
var _expiry_accum := 0.0
## Practice-bot input cadence (#577): drivers keyed "code:slot", pumped every
## BOT_INPUT_INTERVAL_SEC like a human client's send_match_input.
var _bot_input_accum := 0.0
var _bot_drivers := {}


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
	DiagnosticsLog.event(&"net", &"connect_attempt", {"address": address, "port": port})
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


func request_set_ready(ready: bool) -> void:
	_rpc_set_ready.rpc_id(1, ready)


## Host-only: remove another lobby member from the room (#141).
func request_kick(slot: int) -> void:
	_rpc_kick.rpc_id(1, slot)


## Host-only: add / remove a server-owned practice bot (#577).
func request_add_bot() -> void:
	_rpc_add_bot.rpc_id(1)


func request_remove_bot() -> void:
	_rpc_remove_bot.rpc_id(1)


func request_set_character(character_id: StringName) -> void:
	_rpc_set_character.rpc_id(1, character_id)


func request_set_series_length(length: int) -> void:
	_rpc_set_series_length.rpc_id(1, length)


func request_set_round_count(count: int) -> void:
	_rpc_set_round_count.rpc_id(1, count)


## Host-only lobby setting (M9-02); ids are Strings over the wire.
func request_set_mutator_pool(pool: Array) -> void:
	_rpc_set_mutator_pool.rpc_id(1, pool)


## Host-only lobby setting (#572); ids are Strings over the wire. Sends the
## full excluded set every toggle, mirroring request_set_mutator_pool.
func request_set_excluded_games(ids: Array) -> void:
	_rpc_set_excluded_games.rpc_id(1, ids)


func send_ping() -> void:
	_rpc_ping.rpc_id(1, Time.get_ticks_msec())


## Host only; the round count comes from the lobby setting (room.round_count).
## `config` (MatchController keys: "rounds", "seed", "playlist", timing
## overrides) is for test harnesses and is ignored unless the server runs
## with --debug-rpcs.
func request_start_match(config: Dictionary = {}) -> void:
	_rpc_start_match.rpc_id(1, config)


## Per-frame gameplay intent for the minigame in progress; shape is defined by
## each minigame's handle_input.
func send_match_input(data: Dictionary) -> void:
	_rpc_match_input.rpc_id(1, data)


## Vote to skip the current round intro card; the round starts early once
## every connected player in the room has voted (SPEC $4 "ready-skip").
func request_skip_intro() -> void:
	_rpc_skip_intro.rpc_id(1)


## Broadcast a quick emote (Emotes index) to the room; the server enforces
## a per-player token-bucket rate limit (#592).
func request_send_emote(emote: int) -> void:
	_rpc_send_emote.rpc_id(1, emote)


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


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_ready(ready: bool) -> void:
	if not is_server:
		return
	var room: Room = room_manager.room_of_peer(multiplayer.get_remote_sender_id())
	if room == null or room.state != Room.State.LOBBY:
		return
	var member := room.find_by_peer(multiplayer.get_remote_sender_id())
	if member == null:
		return
	member.ready = ready
	_broadcast_room_state(room)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_kick(slot: int) -> void:
	if not is_server:
		return
	var room := _room_of_host_sender()
	if room == null or room.state != Room.State.LOBBY:
		return
	var target := room.find_by_slot(slot)
	if target == null or target.peer_id == multiplayer.get_remote_sender_id():
		return
	var target_peer := target.peer_id
	room_manager.leave_room(target_peer, Time.get_ticks_msec())
	if target.connected and target_peer > 0:
		_rpc_kicked.rpc_id(target_peer)
	_broadcast_room_state(room)
	peer_left_room.emit(room)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_character(character_id: StringName) -> void:
	if not is_server:
		return
	var room: Room = room_manager.room_of_peer(multiplayer.get_remote_sender_id())
	if room == null or room.state != Room.State.LOBBY or not CharacterRoster.is_valid(character_id):
		return
	var member := room.find_by_peer(multiplayer.get_remote_sender_id())
	if member == null:
		return
	member.character_id = character_id
	_broadcast_room_state(room)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_round_count(count: int) -> void:
	if not is_server:
		return
	var room := _room_of_host_sender()
	if room == null:
		return
	if room.set_round_count(count):
		_broadcast_room_state(room)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_series_length(length: int) -> void:
	if not is_server:
		return
	var room := _room_of_host_sender()
	if room == null:
		return
	if room.set_series_length(length):
		_broadcast_room_state(room)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_mutator_pool(pool: Array) -> void:
	if not is_server:
		return
	var room := _room_of_host_sender()
	if room == null:
		return
	MutatorCatalog.register_builtins()
	if room.set_mutator_pool(pool):
		_broadcast_room_state(room)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_excluded_games(ids: Array) -> void:
	if not is_server:
		return
	var room := _room_of_host_sender()
	if room == null:
		return
	MinigameCatalog.register_builtins()
	if room.set_excluded_game_ids(ids):
		_broadcast_room_state(room)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_start_match(config: Dictionary) -> void:
	if not is_server:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var room := _room_of_host_sender()
	if room == null:
		_rpc_match_start_failed.rpc_id(peer_id, "not_host")
		return
	if not debug_rpcs_enabled:
		config = {}
	if not config.has("rounds"):
		config["rounds"] = room.round_count
	MinigameCatalog.register_builtins()
	if config.has("playlist"):
		for id: StringName in config.playlist:
			if not MinigameCatalog.is_registered(id):
				_rpc_match_start_failed.rpc_id(peer_id, "unknown_minigame_%s" % id)
				return
	elif MinigameCatalog.eligible_ids(room.connected_count(), room.excluded_game_ids).is_empty():
		# With the 24-player room cap (ADR 003 / M15-01) ahead of the per-game
		# cap raises, a head count no game supports must refuse here — before
		# ready flags are consumed — instead of crashing the playlist builder.
		_rpc_match_start_failed.rpc_id(peer_id, "no_eligible_minigames")
		return
	# Consumes the ready flags and flips the room to IN_MATCH (M2-02 gating).
	# debug_force_start (test/dev harnesses only, requires --debug-rpcs) skips
	# the 2-player-minimum/ready gate for solo minigame iteration.
	var started := (
		room.force_start_match()
		if debug_rpcs_enabled and config.get("debug_force_start", false)
		else room.start_match()
	)
	if not started:
		_rpc_match_start_failed.rpc_id(peer_id, "not_ready")
		return
	_start_match(room, config)


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_ping(client_ms: int) -> void:
	if not is_server:
		return
	_rpc_pong.rpc_id(multiplayer.get_remote_sender_id(), client_ms)


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
func _rpc_skip_intro() -> void:
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
		controller.handle_skip(member.slot)


## True if `peer_id` may send an emote at `now_ms`, consuming a token if so
## (#592). `now_ms` is a parameter rather than read internally so the
## token-bucket math is directly unit-testable without live multiplayer
## transport or real delays.
func _emote_allowed(peer_id: int, now_ms: int) -> bool:
	var state: Dictionary = _emote_tokens.get(
		peer_id, {"tokens": EMOTE_BURST_MAX, "last_ms": now_ms}
	)
	var elapsed := now_ms - int(state.last_ms)
	var tokens: float = minf(EMOTE_BURST_MAX, float(state.tokens) + elapsed / EMOTE_REFILL_MS)
	if tokens < 1.0:
		_emote_tokens[peer_id] = {"tokens": tokens, "last_ms": now_ms}
		return false
	_emote_tokens[peer_id] = {"tokens": tokens - 1.0, "last_ms": now_ms}
	return true


@rpc("any_peer", "call_remote", "reliable")
func _rpc_send_emote(emote: int) -> void:
	if not is_server or not Emotes.is_valid(emote):
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var room: Room = room_manager.room_of_peer(peer_id)
	if room == null:
		return
	if not _emote_allowed(peer_id, Time.get_ticks_msec()):
		return
	var member := room.find_by_peer(peer_id)
	if member == null:
		return
	for target: RoomMember in room.members:
		if target.connected:
			_rpc_emote.rpc_id(target.peer_id, member.slot, emote)


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
	my_room_state = state
	DiagnosticsLog.event(&"room", &"joined", {"room": code, "slot": slot})
	joined_room.emit(code, slot, token)
	room_updated.emit(state)


@rpc("authority", "call_remote", "reliable")
func _rpc_join_failed(reason: int) -> void:
	# Covers version_mismatch as a reason value — no separate event needed.
	DiagnosticsLog.event(&"net", &"join_failed", {"reason": NetConfig.JoinResult.keys()[reason]})
	join_failed.emit(reason)


@rpc("authority", "call_remote", "reliable")
func _rpc_left_room() -> void:
	_reset_client_session()
	DiagnosticsLog.event(&"room", &"left", {})
	left_room.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_kicked() -> void:
	_reset_client_session()
	DiagnosticsLog.event(&"room", &"kicked", {})
	kicked.emit()
	left_room.emit()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_add_bot() -> void:
	if not is_server:
		return
	var room := _room_of_host_sender()
	if room == null or room.state != Room.State.LOBBY:
		return
	if room.add_bot() != null:
		_broadcast_room_state(room)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_remove_bot() -> void:
	if not is_server:
		return
	var room := _room_of_host_sender()
	if room == null or room.state != Room.State.LOBBY:
		return
	if room.remove_last_bot() != null:
		_broadcast_room_state(room)


@rpc("authority", "call_remote", "reliable")
func _rpc_room_state(state: Dictionary) -> void:
	my_room_state = state
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


@rpc("authority", "call_remote", "reliable")
func _rpc_emote(slot: int, emote: int) -> void:
	emote_received.emit(slot, emote)


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
	_drive_bots(delta)
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


## Feed each practice bot (#577) a random intent on the input cadence, exactly
## as a human client would RPC one. The controller drops intents outside
## PLAY/FINALE_PLAY, so pumping through intros/results is harmless. Drivers are
## seeded per (room, slot) for distinct-but-deterministic behavior.
func _drive_bots(delta: float) -> void:
	_bot_input_accum += delta
	if _bot_input_accum < BOT_INPUT_INTERVAL_SEC:
		return
	_bot_input_accum = 0.0
	for code: String in match_controllers:
		var controller: MatchController = match_controllers[code]
		if controller.room == null:
			continue
		for member: RoomMember in controller.room.members:
			if not member.is_bot:
				continue
			var key := "%s:%d" % [code, member.slot]
			var driver: BotInputDriver = _bot_drivers.get(key)
			if driver == null:
				driver = BotInputDriver.new(hash(key))
				_bot_drivers[key] = driver
			controller.handle_input(member.slot, driver.next_intent())


func _broadcast_snapshots() -> void:
	for room: Room in room_manager.rooms.values():
		var payload := {"tick": _server_tick, "server_ms": Time.get_ticks_msec()}
		var controller: MatchController = match_controllers.get(room.code)
		if controller != null:
			payload["match"] = controller.get_snapshot()
		for member: RoomMember in room.members:
			if not member.connected:
				continue
			# Hidden-role data is computed per recipient so a player's secret
			# role never reaches another player's client (#254). Games with no
			# private state send the shared payload unchanged.
			var private: Dictionary = (
				{} if controller == null else controller.private_snapshot_for(member.slot)
			)
			if private.is_empty():
				_rpc_snapshot.rpc_id(member.peer_id, payload)
			else:
				var personal: Dictionary = payload.duplicate()
				personal["private"] = private
				_rpc_snapshot.rpc_id(member.peer_id, personal)
		# Debug-only cost telemetry (M15-01): one line every ~10 s per room so
		# soak runs can verify the 30 Hz snapshot stays sane at 24 players.
		# Measures the shared payload; per-recipient "private" extras (#254)
		# add a few dozen bytes for at most the games that use them.
		if debug_rpcs_enabled and _server_tick % (NetConfig.SNAPSHOT_HZ * 10) == 0:
			var bytes := var_to_bytes(payload).size()
			print(
				(
					"[server] snapshot_cost room=%s members=%d bytes=%d"
					% [room.code, room.connected_count(), bytes]
				)
			)


func _start_match(room: Room, config: Dictionary) -> void:
	var controller := MatchController.new(room, config)
	match_controllers[room.code] = controller
	DiagnosticsLog.event(
		&"match",
		&"match_start",
		{"room": room.code, "players": room.connected_count(), "bots": room.bot_count()}
	)
	controller.event_emitted.connect(_relay_match_event.bind(room))
	# Room state goes out first so clients are on the match screen before the
	# match_started/round_intro events (all reliable, so order holds).
	_broadcast_room_state(room)
	controller.start()
	match_started.emit(room)


func _relay_match_event(event: Dictionary, room: Room) -> void:
	for member: RoomMember in room.members:
		if member.connected:
			_rpc_match_event.rpc_id(member.peer_id, event)


func _deliver_join_outcome(peer_id: int, outcome: Dictionary) -> void:
	if outcome.result != NetConfig.JoinResult.OK:
		_rpc_join_failed.rpc_id(peer_id, outcome.result)
		DiagnosticsLog.event(
			&"room",
			&"join_failed",
			{"peer": peer_id, "result": NetConfig.JoinResult.keys()[outcome.result]}
		)
		return
	var room: Room = outcome.room
	var member: RoomMember = outcome.member
	_rpc_room_joined.rpc_id(
		peer_id, room.code, member.slot, member.session_token, room.to_state_dict()
	)
	DiagnosticsLog.event(
		&"room",
		&"join",
		{"peer": peer_id, "room": room.code, "slot": member.slot, "members": room.members.size()}
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
		DiagnosticsLog.event(&"net", &"peer_connect", {"peer": peer_id})


func _on_peer_disconnected(peer_id: int) -> void:
	if not is_server:
		return
	print("[server] peer %d disconnected" % peer_id)
	DiagnosticsLog.event(&"net", &"peer_disconnect", {"peer": peer_id})
	var room: Room = room_manager.handle_disconnect(peer_id, Time.get_ticks_msec())
	if room != null and room_manager.rooms.has(room.code):
		_broadcast_room_state(room)
		peer_left_room.emit(room)


func _on_connected_to_server() -> void:
	DiagnosticsLog.event(&"net", &"connected", {})
	connected_to_server.emit()


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	DiagnosticsLog.event(&"net", &"connect_failed", {})
	connection_failed.emit()


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	_reset_client_session()
	DiagnosticsLog.event(&"net", &"disconnect", {})
	server_disconnected.emit()


# --- Helpers -----------------------------------------------------------------


func _drain_lag_queue() -> void:
	if _lag_queue.is_empty():
		return
	var now := Time.get_ticks_msec()
	while not _lag_queue.is_empty() and _lag_queue[0].deliver_at <= now:
		var entry: Dictionary = _lag_queue.pop_front()
		snapshot_received.emit(entry.snapshot)


## Returns the sender's room only when the sender is that room's host: the
## guard for host-only lobby controls (settings, start).
func _room_of_host_sender() -> Room:
	var peer_id := multiplayer.get_remote_sender_id()
	var room: Room = room_manager.room_of_peer(peer_id)
	if room == null:
		return null
	var host := room.host()
	if host == null or host.peer_id != peer_id:
		return null
	return room


func _reset_client_session() -> void:
	my_room_code = ""
	my_slot = -1
	my_session_token = ""
	my_room_state = {}


static func _arg_value(args: PackedStringArray, key: String, fallback: String) -> String:
	for arg in args:
		if arg.begins_with(key + "="):
			return arg.get_slice("=", 1)
	return fallback
