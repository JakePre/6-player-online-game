extends Node
## Headless soak-test bot (M1-05), launched by boot.gd via `-- --bot`.
## Connects, creates or joins a room, verifies a steady snapshot stream and
## ping round-trips, optionally exercises the disconnect->rejoin flow, then
## exits 0 (pass) or 1 (fail). Machine-readable output lines:
##   ROOM_CODE=ABCDEF        (creator only)
##   BOT_RESULT PASS|FAIL name=<name> ...
##
## User args: --address=127.0.0.1 --port=7777 --name=Bot1 --duration=15
##            --create | --code=ABCDEF   [--rejoin-test]

enum Phase {
	CONNECTING,
	JOINING,
	IN_ROOM,
	REJOIN_OFFLINE,
	REJOINING,
	DONE,
}

const PHASE_TIMEOUT_SEC := 15.0
const REJOIN_OFFLINE_SEC := 2.0

var _address := "127.0.0.1"
var _port := NetConfig.DEFAULT_PORT
var _bot_name := "Bot"
var _duration_sec := 15.0
var _create := false
var _join_code := ""
var _rejoin_test := false

var _phase := Phase.CONNECTING
var _phase_started_ms := 0
var _run_started_ms := 0
var _snapshots := 0
var _pongs := 0
var _ping_accum := 0.0
var _joined_slot := -1
var _rejoined_slot := -1
var _room_code := ""
var _token := ""
var _did_rejoin := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_address = NetManager._arg_value(args, "--address", _address)
	_port = int(NetManager._arg_value(args, "--port", str(_port)))
	_bot_name = NetManager._arg_value(args, "--name", _bot_name)
	_duration_sec = float(NetManager._arg_value(args, "--duration", str(_duration_sec)))
	_join_code = NetManager._arg_value(args, "--code", "")
	_create = args.has("--create")
	_rejoin_test = args.has("--rejoin-test")

	NetManager.connected_to_server.connect(_on_connected)
	NetManager.connection_failed.connect(func() -> void: _fail("connection_failed"))
	NetManager.joined_room.connect(_on_joined_room)
	NetManager.join_failed.connect(
		func(reason: int) -> void: _fail("join_failed_" + NetConfig.join_result_name(reason))
	)
	NetManager.snapshot_received.connect(func(_snapshot: Dictionary) -> void: _snapshots += 1)
	NetManager.pong_received.connect(func(_rtt_ms: int) -> void: _pongs += 1)

	_run_started_ms = Time.get_ticks_msec()
	_enter_phase(Phase.CONNECTING)
	if NetManager.connect_to_server(_address, _port) != OK:
		_fail("connect_call_failed")


func _process(delta: float) -> void:
	if _phase == Phase.DONE:
		return
	var now := Time.get_ticks_msec()
	if _phase != Phase.IN_ROOM and now - _phase_started_ms > PHASE_TIMEOUT_SEC * 1000.0:
		_fail("timeout_in_phase_%d" % _phase)
		return
	match _phase:
		Phase.IN_ROOM:
			_ping_accum += delta
			if _ping_accum >= 1.0:
				_ping_accum = 0.0
				NetManager.send_ping()
			var elapsed := (now - _run_started_ms) / 1000.0
			if _rejoin_test and not _did_rejoin and elapsed >= _duration_sec * 0.5:
				_did_rejoin = true
				NetManager.disconnect_from_server()
				_enter_phase(Phase.REJOIN_OFFLINE)
			elif elapsed >= _duration_sec:
				_finish()
		Phase.REJOIN_OFFLINE:
			if now - _phase_started_ms >= REJOIN_OFFLINE_SEC * 1000.0:
				_enter_phase(Phase.REJOINING)
				if NetManager.connect_to_server(_address, _port) != OK:
					_fail("reconnect_call_failed")


func _on_connected() -> void:
	if _phase == Phase.REJOINING:
		NetManager.request_rejoin_room(_room_code, _token)
		return
	_enter_phase(Phase.JOINING)
	if _create:
		NetManager.request_create_room(_bot_name)
	else:
		NetManager.request_join_room(_join_code, _bot_name)


func _on_joined_room(code: String, slot: int, token: String) -> void:
	_room_code = code
	_token = token
	if _phase == Phase.REJOINING:
		_rejoined_slot = slot
	else:
		_joined_slot = slot
		if _create:
			print("ROOM_CODE=%s" % code)
		if _rejoin_test:
			# Rejoin only exists for in-match rooms (lobby disconnects free the
			# slot), so flip the room state via the server's debug RPC.
			NetManager.request_debug_set_match_state(true)
	_enter_phase(Phase.IN_ROOM)


func _finish() -> void:
	# With fake loss/lag active the stream thins out, and the rejoin bot is
	# offline for part of the run, so require half the nominal rate.
	var required := int(_duration_sec * NetConfig.SNAPSHOT_HZ * 0.5)
	if _rejoin_test:
		required /= 2
	if _snapshots < required:
		_fail("too_few_snapshots_%d_of_%d" % [_snapshots, required])
		return
	if _pongs == 0:
		_fail("no_pongs")
		return
	if _rejoin_test and _rejoined_slot != _joined_slot:
		_fail("rejoin_slot_mismatch_%d_vs_%d" % [_rejoined_slot, _joined_slot])
		return
	print(
		(
			"BOT_RESULT PASS name=%s snapshots=%d pongs=%d rejoined=%s"
			% [_bot_name, _snapshots, _pongs, str(_did_rejoin)]
		)
	)
	_quit(0)


func _fail(reason: String) -> void:
	print("BOT_RESULT FAIL name=%s reason=%s" % [_bot_name, reason])
	_quit(1)


func _enter_phase(phase: Phase) -> void:
	_phase = phase
	_phase_started_ms = Time.get_ticks_msec()


func _quit(exit_code: int) -> void:
	_phase = Phase.DONE
	get_tree().quit(exit_code)
