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
##   PLAYTEST_TELEMETRY [...]   (creator only, on PASS — #548: one JSON object
##                               per round: game_id, player_count, placements,
##                               awards (this round's per-slot coins), and
##                               duration_ms, for the M12-01 balance pass to
##                               consume once enough nightly runs accumulate)
##
## User args: --address=127.0.0.1 --port=7777 --name=Bot1 --rounds=12
##            --create | --code=ABCDEF [--balance] [--phase-timeout=1800]
##            [--inputs=brains|random|idle]
##
## --inputs (M19-03, #705): `brains` (default) drives each round through its
## goal-seeking BotBrain so nightly balance telemetry reflects real play, not
## random noise; `random` restores the pre-M19 fuzz driver; `idle` sends no
## gameplay input (spectate-only smoke).

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
	# The 3-2-1 gate (#182) costs 1.8 s per round undebugged; compress it too or
	# a 12-round match overruns PHASE_TIMEOUT_SEC (#369).
	"countdown_step_sec": 0.05,
	# The finale buy-in (#554) is compressed the same way; bots also confirm,
	# which closes the shop early on the all-confirmed path.
	"shop_sec": 0.3,
}
## The --balance variant (#560): chrome stays compressed (intros and results
## screens carry no balance signal) but rounds run their REAL durations, so
## with bots actually playing the telemetry finally means something. No
## duration_override on purpose.
const BALANCE_CONFIG := {
	"intro_sec": 0.5,
	"results_sec": 0.3,
	"leaderboard_sec": 0.3,
	"podium_sec": 0.3,
	"countdown_step_sec": 0.2,
	"shop_sec": 5.0,
}
## Intent pump cadence while a round is live (#560).
const INPUT_INTERVAL_SEC := 0.25
## Snapshot states whose intents the sim accepts as gameplay — the only ones a
## brain drives. The finale shop is handled by the explicit finale_shop event
## path below, not the brain, so bots keep exercising the buy/confirm flow.
const BRAIN_STATES := [MatchController.State.PLAY, MatchController.State.FINALE_PLAY]
## Chance each pump also presses one action key on top of the movement stick.
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
var _balance := false
var _send_inputs := true
## Drive intents through goal-seeking brains (M19-03, #705) rather than the
## random fuzz driver; false only under --inputs=random.
var _use_brains := true
var _phase_timeout_sec := PHASE_TIMEOUT_SEC
var _join_code := ""
var _slot := -1
var _expected_members := 0
var _input_accum := 0.0
## Shared random-intent generator (#577 extracted BotInputDriver); seeded per
## seat in _on_joined so intents stay deterministic per bot.
var _input_driver: BotInputDriver = null
## Latest match snapshot RPC payload ({tick, server_ms, match, private?}); the
## brain reads `match` (this player's client view) and its own `private` (#254).
var _latest_snapshot: Dictionary = {}
## Rebuilt when the round's minigame changes, mirroring NetManager._drive_bots.
var _bot_brain: BotBrain = null
var _brain_id := &""

var _phase := Phase.CONNECTING
var _phase_started_ms := 0
var _room_code := ""

var _rounds_started := 0
var _rounds_resulted := 0
var _mutated_intros := 0
var _leaderboards := 0
var _match_ended_standings: Array = []
var _got_match_ended := false
var _got_finale_shop := false
var _got_finale_started := false
var _room_is_lobby := false

## Balance telemetry (#548), creator-only: one entry per round_results.
var _telemetry: Array = []
var _round_game_id := ""
var _round_started_ms := 0


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
	_balance = args.has("--balance")
	# Bots play by default (#560, #705) — brains drive real, goal-seeking play so
	# balance telemetry means something. --inputs=random restores the old fuzz
	# driver; --inputs=idle is spectate-only.
	var inputs_mode := NetManager._arg_value(args, "--inputs", "brains")
	_send_inputs = inputs_mode != "idle"
	_use_brains = inputs_mode == "brains"
	_phase_timeout_sec = float(
		NetManager._arg_value(args, "--phase-timeout", str(PHASE_TIMEOUT_SEC))
	)
	# Deterministic per seat, distinct across seats.
	_input_driver = BotInputDriver.new(hash(_bot_name))

	NetManager.connected_to_server.connect(_on_connected)
	NetManager.connection_failed.connect(func() -> void: _fail("connection_failed"))
	NetManager.joined_room.connect(_on_joined_room)
	NetManager.join_failed.connect(
		func(reason: int) -> void: _fail("join_failed_" + NetConfig.join_result_name(reason))
	)
	NetManager.room_updated.connect(_on_room_updated)
	NetManager.snapshot_received.connect(_on_snapshot)
	NetManager.match_event_received.connect(_on_match_event)
	NetManager.match_start_failed.connect(
		func(reason: String) -> void: _fail("start_failed_" + reason)
	)

	_enter_phase(Phase.CONNECTING)
	if NetManager.connect_to_server(_address, _port) != OK:
		_fail("connect_call_failed")


func _process(delta: float) -> void:
	if _phase == Phase.DONE:
		return
	var now := Time.get_ticks_msec()
	if now - _phase_started_ms > _phase_timeout_sec * 1000.0:
		_fail("timeout_in_phase_%d" % _phase)
		return
	if _send_inputs and _phase == Phase.IN_MATCH:
		_input_accum += delta
		if _input_accum >= INPUT_INTERVAL_SEC:
			# Carry the remainder rather than zeroing (#768): zeroing pinned the
			# poll to a fixed tick-multiple that phase-locks against game
			# constants like hurdle_dash STUN_SEC, trapping racer bots in a stun
			# loop that never sampled the recovery window. Same fix as the
			# server pump (NetManager._drive_bots).
			_input_accum -= INPUT_INTERVAL_SEC
			# The server drops intents outside PLAY/FINALE_PLAY, so pumping
			# through intros/results is harmless; an empty brain intent (nothing
			# worth doing this tick) is simply not sent.
			var intent := _next_intent()
			if not intent.is_empty():
				NetManager.send_match_input(intent)


func _on_snapshot(snapshot: Dictionary) -> void:
	_latest_snapshot = snapshot


## This tick's intent: a goal-seeking brain's, or the random driver's under
## --inputs=random.
func _next_intent() -> Dictionary:
	if not _use_brains:
		return _input_driver.next_intent()
	return _brain_intent()


## Feed our own client view (the match snapshot + our private payload) through
## the round's brain, exactly as NetManager._drive_bots does server-side.
## Rebuilds the brain when the minigame changes; only acts during live play
## (the finale shop is driven by the explicit finale_shop event handler).
func _brain_intent() -> Dictionary:
	var match_state: Dictionary = _latest_snapshot.get("match", {})
	if match_state.is_empty() or int(match_state.get("state", -1)) not in BRAIN_STATES:
		return {}
	var brain_id := BotBrains.brain_id_for(match_state)
	if _bot_brain == null or brain_id != _brain_id:
		_brain_id = brain_id
		_bot_brain = BotBrains.brain_for(brain_id, _slot, hash("%s:%d" % [_room_code, _slot]))
	return _bot_brain.think(match_state, _latest_snapshot.get("private", {}))


func _on_connected() -> void:
	_enter_phase(Phase.JOINING)
	if _create:
		NetManager.request_create_room(_bot_name)
	else:
		NetManager.request_join_room(_join_code, _bot_name)


func _on_joined_room(code: String, slot: int, _token: String) -> void:
	_room_code = code
	_slot = slot
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
		var config := (BALANCE_CONFIG if _balance else DEBUG_CONFIG).duplicate()
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
			_round_game_id = String(event.minigame.id)
		"round_started":
			_rounds_started += 1
			_round_started_ms = Time.get_ticks_msec()
		"round_results":
			_rounds_resulted += 1
			if _create:
				_record_telemetry(event)
		"leaderboard":
			_leaderboards += 1
		"finale_shop":
			# Exercise the shop (#554): one purchase attempt (may fail broke —
			# that's fine, the server validates) and a confirm; all bots
			# confirming closes the shop early via the all-confirmed path.
			_got_finale_shop = true
			NetManager.send_match_input({"shop": {"action": "buy", "item": "shield"}})
			NetManager.send_match_input({"shop": {"action": "confirm"}})
		"finale_started":
			_got_finale_started = true
		"finale_results":
			# #706: the finale skips round_results (straight to podium), so its
			# KO-cause breakdown rides its own event into the same telemetry
			# stream the balance job already collects.
			if _create:
				_record_finale_telemetry(event)
		"match_ended":
			_got_match_ended = true
			_match_ended_standings = event.get("standings", [])
			_enter_phase(Phase.AWAIT_LOBBY)
			_check_awaiting_lobby()


## One structured record per round (#548). Dictionary keys are stringified
## explicitly (`awards` arrives keyed by int slot) so JSON.stringify() always
## produces valid JSON regardless of key type.
func _record_telemetry(event: Dictionary) -> void:
	var awards: Dictionary = event.get("awards", {})
	var string_awards := {}
	for slot: Variant in awards:
		string_awards[str(slot)] = int(awards[slot])
	(
		_telemetry
		. append(
			{
				"game_id": _round_game_id,
				"player_count": _expected_members,
				"round": int(event.get("round", 0)),
				"placements": event.get("placements", []),
				"awards": string_awards,
				"duration_ms": Time.get_ticks_msec() - _round_started_ms,
			}
		)
	)


## The finale's own telemetry record (#706): no `round`/`awards` (the finale
## isn't a round-scored game), just the KO-cause breakdown that answers
## "hazards vs. rim vs. axes" once the balance pass reads these artifacts.
## `axe_kills` arrives keyed by int slot — stringified for the same
## JSON.stringify() reason as `awards` above.
func _record_finale_telemetry(event: Dictionary) -> void:
	var axe_kills: Dictionary = event.get("axe_kills", {})
	var string_axe_kills := {}
	for slot: Variant in axe_kills:
		string_axe_kills[str(slot)] = int(axe_kills[slot])
	(
		_telemetry
		. append(
			{
				"game_id": "gauntlet",
				"finale": true,
				"player_count": _expected_members,
				"placements": event.get("placements", []),
				"ko_causes": event.get("ko_causes", {}),
				"axe_kills": string_axe_kills,
			}
		)
	)


func _check_awaiting_lobby() -> void:
	# room_updated for the LOBBY transition can arrive before or after
	# match_ended (both are reliable RPCs but on separate channels), so check
	# from both handlers once we have both pieces.
	if _phase == Phase.AWAIT_LOBBY and _room_is_lobby:
		_finish()


func _finish() -> void:
	var reason := _failure_reason()
	if not reason.is_empty():
		_fail(reason)
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
	if _create:
		print("PLAYTEST_TELEMETRY " + JSON.stringify(_telemetry))
	_quit(0)


## Empty string = the match verified clean; otherwise the machine-readable
## failure tag for BOT_RESULT FAIL. Ordered [failed, reason] pairs — the
## finale checks (#554) assert The Gauntlet actually ran with placements.
func _failure_reason() -> String:
	var expected_leaderboards := 0
	var k := LEADERBOARD_EVERY
	while k < _rounds:
		expected_leaderboards += 1
		k += LEADERBOARD_EVERY
	var missing_placement := _match_ended_standings.any(
		func(row: Dictionary) -> bool: return not row.has("placement")
	)
	var checks: Array = [
		[_rounds_started != _rounds, "rounds_started_%d_of_%d" % [_rounds_started, _rounds]],
		[_rounds_resulted != _rounds, "rounds_resulted_%d_of_%d" % [_rounds_resulted, _rounds]],
		[not _got_match_ended, "no_match_ended_event"],
		[not _got_finale_shop, "no_finale_shop_event"],
		[not _got_finale_started, "no_finale_started_event"],
		[
			_match_ended_standings.size() != _expected_members,
			"standings_size_%d_of_%d" % [_match_ended_standings.size(), _expected_members],
		],
		[missing_placement, "standings_missing_placement"],
		[
			_leaderboards != expected_leaderboards,
			"leaderboards_%d_of_%d" % [_leaderboards, expected_leaderboards],
		],
		[_with_mutators and _mutated_intros == 0, "no_mutated_rounds"],
	]
	for check: Array in checks:
		if check[0]:
			return check[1]
	return ""


func _fail(reason: String) -> void:
	print("BOT_RESULT FAIL name=%s reason=%s" % [_bot_name, reason])
	_quit(1)


func _enter_phase(phase: Phase) -> void:
	_phase = phase
	_phase_started_ms = Time.get_ticks_msec()


func _quit(exit_code: int) -> void:
	_phase = Phase.DONE
	get_tree().quit(exit_code)
