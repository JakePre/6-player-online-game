extends Node
## Headless playtest bot (M7-03), launched by boot.gd via `-- --playtest`.
## Unlike the M1-05 soak bot (which only exercises the connection), this bot
## plays a full match to completion: join/ready-up, the creator starts the
## match with a `--debug-rpcs` timing override so all `--rounds` rounds finish
## in seconds, then every bot verifies the round count, event sequence, and
## final standings before the room returns to LOBBY. Exit 0 (pass) or 1 (fail).
## Machine-readable output lines:
##   ROOM_CODE=ABCDEF        (creator only)
##   BOT_RESULT PASS|FAIL name=<name> ...
##
## User args: --address=127.0.0.1 --port=7777 --name=Bot1 --rounds=12
##            --create | --code=ABCDEF

enum Phase {
	CONNECTING,
	JOINING,
	LOBBY_WAIT,
	IN_MATCH,
	AWAIT_LOBBY,
	DONE,
}

const PHASE_TIMEOUT_SEC := 30.0
## Debug timing override (server must run --debug-rpcs to honour it) so a
## full match finishes in seconds instead of ~15 minutes.
const DEBUG_CONFIG := {
	"intro_sec": 0.2,
	"results_sec": 0.2,
	"leaderboard_sec": 0.2,
	"podium_sec": 0.2,
	"duration_override": 0.4,
}
const LEADERBOARD_EVERY := 5
## Seed for the --mutators variant (M9-06): the per-round roll is seed-driven,
## so this keeps the ">=1 mutated round" pass criterion deterministic.
const MUTATOR_SOAK_SEED := 20260703

var _address := "127.0.0.1"
var _port := NetConfig.DEFAULT_PORT
var _bot_name := "Bot"
var _rounds := 12
var _create := false
var _with_mutators := false
var _join_code := ""
var _expected_members := 0

var _phase := Phase.CONNECTING
var _phase_started_ms := 0
var _room_code := ""

var _rounds_started := 0
var _rounds_resulted := 0
var _mutated_intros := 0
var _leaderboards := 0
var _match_ended_standings: Array = []
var _got_match_ended := false
var _room_is_lobby := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_address = NetManager._arg_value(args, "--address", _address)
	_port = int(NetManager._arg_value(args, "--port", str(_port)))
	_bot_name = NetManager._arg_value(args, "--name", _bot_name)
	_rounds = int(NetManager._arg_value(args, "--rounds", str(_rounds)))
	_expected_members = int(NetManager._arg_value(args, "--players", "6"))
	_join_code = NetManager._arg_value(args, "--code", "")
	_create = args.has("--create")
	_with_mutators = args.has("--mutators")

	NetManager.connected_to_server.connect(_on_connected)
	NetManager.connection_failed.connect(func() -> void: _fail("connection_failed"))
	NetManager.joined_room.connect(_on_joined_room)
	NetManager.join_failed.connect(
		func(reason: int) -> void: _fail("join_failed_" + NetConfig.join_result_name(reason))
	)
	NetManager.room_updated.connect(_on_room_updated)
	NetManager.match_event_received.connect(_on_match_event)
	NetManager.match_start_failed.connect(
		func(reason: String) -> void: _fail("start_failed_" + reason)
	)

	_enter_phase(Phase.CONNECTING)
	if NetManager.connect_to_server(_address, _port) != OK:
		_fail("connect_call_failed")


func _process(_delta: float) -> void:
	if _phase == Phase.DONE:
		return
	var now := Time.get_ticks_msec()
	if now - _phase_started_ms > PHASE_TIMEOUT_SEC * 1000.0:
		_fail("timeout_in_phase_%d" % _phase)


func _on_connected() -> void:
	_enter_phase(Phase.JOINING)
	if _create:
		NetManager.request_create_room(_bot_name)
	else:
		NetManager.request_join_room(_join_code, _bot_name)


func _on_joined_room(code: String, _slot: int, _token: String) -> void:
	_room_code = code
	if _create:
		print("ROOM_CODE=%s" % code)
		# Mutator soak variant (M9-06): the host enables the full pool so the
		# per-round roll exercises every knob path during the match.
		if _with_mutators:
			MutatorCatalog.register_builtins()
			var pool: Array = []
			for id: StringName in MutatorCatalog.registered_ids():
				pool.append(String(id))
			NetManager.request_set_mutator_pool(pool)
	_enter_phase(Phase.LOBBY_WAIT)
	NetManager.request_set_ready(true)


func _on_room_updated(state: Dictionary) -> void:
	var room_state: int = state.get("state", Room.State.LOBBY)
	if _phase == Phase.AWAIT_LOBBY:
		if room_state == Room.State.LOBBY:
			_room_is_lobby = true
			_check_awaiting_lobby()
		return
	if _phase != Phase.LOBBY_WAIT:
		return
	if room_state != Room.State.LOBBY:
		return
	var members: Array = state.get("members", [])
	if members.size() < _expected_members:
		return
	for member: Dictionary in members:
		if not member.get("ready", false):
			return
	# Everyone present and ready: the host (lowest join_order, i.e. the room
	# creator here) kicks off the match with the fast debug timing.
	if _create:
		var config := DEBUG_CONFIG.duplicate()
		config["rounds"] = _rounds
		# Fixed seed for the mutator variant: the roll is seed-driven, so the
		# ">=1 mutated round" pass criterion stays deterministic.
		if _with_mutators:
			config["seed"] = MUTATOR_SOAK_SEED
		NetManager.request_start_match(config)
	_enter_phase(Phase.IN_MATCH)


func _on_match_event(event: Dictionary) -> void:
	if _phase != Phase.IN_MATCH:
		return
	match event.get("type", ""):
		"round_intro":
			if event.has("mutator"):
				_mutated_intros += 1
		"round_started":
			_rounds_started += 1
		"round_results":
			_rounds_resulted += 1
		"leaderboard":
			_leaderboards += 1
		"match_ended":
			_got_match_ended = true
			_match_ended_standings = event.get("standings", [])
			_enter_phase(Phase.AWAIT_LOBBY)
			_check_awaiting_lobby()


func _check_awaiting_lobby() -> void:
	# room_updated for the LOBBY transition can arrive before or after
	# match_ended (both are reliable RPCs but on separate channels), so check
	# from both handlers once we have both pieces.
	if _phase == Phase.AWAIT_LOBBY and _room_is_lobby:
		_finish()


func _finish() -> void:
	if _rounds_started != _rounds:
		_fail("rounds_started_%d_of_%d" % [_rounds_started, _rounds])
		return
	if _rounds_resulted != _rounds:
		_fail("rounds_resulted_%d_of_%d" % [_rounds_resulted, _rounds])
		return
	if not _got_match_ended:
		_fail("no_match_ended_event")
		return
	if _match_ended_standings.size() != _expected_members:
		_fail("standings_size_%d_of_%d" % [_match_ended_standings.size(), _expected_members])
		return
	var expected_leaderboards := 0
	var k := LEADERBOARD_EVERY
	while k < _rounds:
		expected_leaderboards += 1
		k += LEADERBOARD_EVERY
	if _leaderboards != expected_leaderboards:
		_fail("leaderboards_%d_of_%d" % [_leaderboards, expected_leaderboards])
		return
	if _with_mutators and _mutated_intros == 0:
		_fail("no_mutated_rounds")
		return
	print(
		(
			"BOT_RESULT PASS name=%s rounds=%d leaderboards=%d standings=%d mutated=%d"
			% [
				_bot_name,
				_rounds_started,
				_leaderboards,
				_match_ended_standings.size(),
				_mutated_intros,
			]
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
