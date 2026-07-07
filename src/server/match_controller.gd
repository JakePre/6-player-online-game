class_name MatchController
extends RefCounted
## Server-side match state machine (M3-01, SPEC $4):
## INTRO -> COUNTDOWN -> PLAY -> RESULTS -> (LEADERBOARD every 5 rounds) ->
## ... -> FINALE_SHOP -> FINALE_PLAY -> PODIUM (#554).
## Pure logic driven by tick(delta); emits `event_emitted` Dictionaries that
## NetManager relays to the room, and feeds get_snapshot() into the 30 Hz
## room snapshot (ADR 001). Coins live on RoomMember.score.

signal event_emitted(event: Dictionary)

enum State {
	INTRO,
	PLAY,
	RESULTS,
	LEADERBOARD,
	PODIUM,
	DONE,
	# Appended after DONE so the wire values of the original states stay
	# stable across client/server versions (#182). Same rule for the finale
	# states below (#554).
	COUNTDOWN,
	FINALE_SHOP,
	FINALE_PLAY,
}

const LEADERBOARD_EVERY := 5
## PHASE2.md $3: roughly this share of rounds draw a mutator from the host's
## enabled pool. Mutators roll per playlist round only — the finale clears
## `current_mutator` on entry, so "never the finale" holds structurally.
const MUTATOR_ROUND_CHANCE := 0.4
## 3-2-1 over the visible arena at 600 ms per digit (#182). The game is
## already instantiated during COUNTDOWN so clients render the starting
## positions, but it does not tick and takes no input until PLAY.
const COUNTDOWN_STEP_SEC := 0.6
const COUNTDOWN_STEPS := 3

var state := State.INTRO
var room: Room
var round_index := 0
var playlist: Array = []
var game: MinigameBase
## The finale buy-in shop (M5-01), live only during FINALE_SHOP; its post-shop
## balances feed the FINALE_PLAY loadouts and the final ranking's tiebreaks.
var shop: FinaleShop
## The mutator rolled for the current round, or null (M9-03). Knob effects
## are wired by the M9-04/05 packs; this controller rolls and announces.
var current_mutator: Mutator

var _intro_sec := 10.0
var _results_sec := 8.0
var _leaderboard_sec := 5.0
var _podium_sec := 8.0
var _shop_sec := FinaleShop.SHOP_SEC
var _duration_override := 0.0
var _countdown_step_sec := COUNTDOWN_STEP_SEC
## SPEC $4: real matches settle in the finale. Harnesses may disable it, and
## degenerate rooms (fewer than 2 connected, e.g. --debug-minigame solo) skip
## straight to the podium exactly as before #554.
var _finale_enabled := true
## Debug/render path (#685): skip the rounds entirely and open on the buy-in
## shop, with a seeded purse so loadouts actually feature. Config-gated like
## every other override — the server accepts it only under --debug-rpcs.
var _finale_only := false
var _finale_coins := 120
var _state_left := 0.0
var _rng := RandomNumberGenerator.new()
var _round_slots: Array[int] = []
var _skip_votes := {}


## config: rounds (int), seed (int), and for test harnesses only (server must
## run --debug-rpcs to accept them from clients): intro_sec, results_sec,
## leaderboard_sec, podium_sec, shop_sec, duration_override,
## countdown_step_sec, finale (bool).
func _init(match_room: Room, config: Dictionary) -> void:
	room = match_room
	_rng.seed = int(config.get("seed", randi()))
	_intro_sec = config.get("intro_sec", _intro_sec)
	_results_sec = config.get("results_sec", _results_sec)
	_leaderboard_sec = config.get("leaderboard_sec", _leaderboard_sec)
	_podium_sec = config.get("podium_sec", _podium_sec)
	_shop_sec = config.get("shop_sec", _shop_sec)
	_duration_override = config.get("duration_override", 0.0)
	_finale_enabled = config.get("finale", true)
	_finale_only = config.get("finale_only", false)
	_finale_coins = int(config.get("finale_coins", _finale_coins))
	# Compress the 3-2-1 gate for the playtest harness too, or a full match
	# overruns the bot's phase budget (#369).
	_countdown_step_sec = config.get("countdown_step_sec", _countdown_step_sec)
	MinigameCatalog.register_builtins()
	if config.has("playlist"):
		# GDScript evaluates Dictionary.get()'s default argument eagerly (no
		# short-circuiting), so build_playlist() must not sit in that position:
		# its player-count eligibility assert would fire even when an explicit
		# playlist is supplied, e.g. for a solo --debug-minigame session.
		playlist = config.playlist
	else:
		playlist = MinigameCatalog.build_playlist(
			_rng, int(config.get("rounds", 12)), room.connected_count(), room.excluded_game_ids
		)


func start() -> void:
	room.state = Room.State.IN_MATCH
	for member in room.members:
		member.score = 0
	event_emitted.emit({"type": "match_started", "rounds": playlist.size()})
	if _finale_only:
		# #685: straight to the finale for debug/render sessions — everyone
		# gets the seeded purse in place of round earnings.
		for member in room.members:
			member.score = _finale_coins
		_enter_finale_shop()
		return
	_enter_intro()


func tick(delta: float) -> void:
	if state == State.DONE:
		return
	if state == State.PLAY:
		# Overdrive (M9-04): the server scales the sim delta, so everything —
		# movement, timers, the round clock — runs faster together.
		if current_mutator != null:
			delta = current_mutator.scaled_tick_delta(delta)
		game.tick(delta)
		if game.finished:
			_enter_results()
		return
	if state == State.FINALE_SHOP:
		# The shop owns its own clock and closes early once everyone confirms.
		shop.tick(delta)
		if not shop.open:
			_enter_finale_play()
		return
	if state == State.FINALE_PLAY:
		game.tick(delta)
		if game.finished:
			_enter_podium_from_finale()
		return
	_state_left -= delta
	if _state_left > 0.0:
		return
	match state:
		State.INTRO:
			_enter_countdown()
		State.COUNTDOWN:
			_enter_play()
		State.RESULTS:
			_after_results()
		State.LEADERBOARD:
			_next_round()
		State.PODIUM:
			_finish_match()


func handle_input(slot: int, data: Dictionary) -> void:
	if slot not in _round_slots:
		return
	match state:
		State.PLAY:
			# Mirror Mode (M9-05): transformed server-side so it is fair and
			# cheat-proof.
			if current_mutator != null:
				data = current_mutator.transform_input(data)
			game.handle_input(slot, data)
		State.FINALE_PLAY:
			# No mutator transforms in the finale (never the finale, M9-03).
			game.handle_input(slot, data)
		State.FINALE_SHOP:
			if data.has("shop"):
				_handle_shop_input(slot, data.shop)


## Intro ready-skip (SPEC $4): the round starts early once every connected
## player has voted. Votes reset with each intro card.
func handle_skip(slot: int) -> void:
	if state != State.INTRO:
		return
	var voters := _connected_slots()
	if slot not in voters or _skip_votes.has(slot):
		return
	_skip_votes[slot] = true
	var votes := 0
	for voter in voters:
		if _skip_votes.has(voter):
			votes += 1
	event_emitted.emit({"type": "skip_votes", "votes": votes, "needed": voters.size()})
	if votes >= voters.size():
		_enter_countdown()


func is_done() -> bool:
	return state == State.DONE


func get_snapshot() -> Dictionary:
	var snapshot := {
		"state": state,
		"round": round_index,
		"rounds": playlist.size(),
		"time_left": maxf(_state_left, 0.0),
	}
	if state in [State.PLAY, State.FINALE_PLAY]:
		snapshot.time_left = maxf(game.effective_duration() - game.elapsed, 0.0)
	if state in [State.COUNTDOWN, State.PLAY]:
		# The id lets late arrivals (rejoin, missed events) mount the right
		# view; during COUNTDOWN it also shows the starting positions (#182).
		snapshot["minigame"] = String(playlist[round_index])
		snapshot["game"] = game.get_snapshot()
	if state == State.FINALE_PLAY:
		snapshot["minigame"] = "gauntlet"
		snapshot["game"] = game.get_snapshot()
	if state == State.FINALE_SHOP:
		# Authoritative shop state (#554): the client UI renders purely from
		# this, so a lost buy intent is visibly un-bought and re-clickable.
		snapshot.time_left = shop.time_left
		var players := {}
		for slot in _round_slots:
			players[slot] = {
				"coins": shop.coins_left(slot),
				"items": shop.loadout(slot),
				"confirmed": shop.is_confirmed(slot),
			}
		snapshot["shop"] = {"players": players}
	# Late arrivals also learn the round's mutator (M9-03).
	if current_mutator != null and state in [State.INTRO, State.COUNTDOWN, State.PLAY]:
		snapshot["mutator"] = current_mutator.to_dict()
	return snapshot


## Per-player secret state for `slot`, delivered only to that player's own
## client (#254). Non-empty only during an in-progress round whose minigame
## chooses to reveal something private (hidden roles); {} otherwise.
func private_snapshot_for(slot: int) -> Dictionary:
	if state != State.PLAY or game == null:
		return {}
	return game.get_private_snapshot(slot)


# --- State transitions -------------------------------------------------------


func _enter_intro() -> void:
	state = State.INTRO
	_state_left = _intro_sec
	_skip_votes.clear()
	current_mutator = _roll_mutator()
	var meta := MinigameCatalog.meta_of(playlist[round_index])
	var intro := {
		"type": "round_intro",
		"round": round_index + 1,
		"rounds": playlist.size(),
		"minigame": meta.to_dict(),
	}
	# Announced on the intro card — no hidden modifiers (PHASE2.md $3 rule 2).
	if current_mutator != null:
		intro["mutator"] = current_mutator.to_dict()
	event_emitted.emit(intro)


## ~MUTATOR_ROUND_CHANCE of rounds get one mutator from the room's enabled
## pool, never the same one twice in a row. Deterministic from the match seed.
func _roll_mutator() -> Mutator:
	var previous := current_mutator
	if room.mutator_pool.is_empty() or _rng.randf() >= MUTATOR_ROUND_CHANCE:
		return null
	var pool := room.mutator_pool.filter(
		func(id: StringName) -> bool: return previous == null or id != previous.id
	)
	if pool.is_empty():
		return null
	return MutatorCatalog.mutator_of(pool[_rng.randi_range(0, pool.size() - 1)])


## The game is built and set up here — before PLAY — so countdown snapshots
## carry the arena and starting positions while everyone reads the 3-2-1.
func _enter_countdown() -> void:
	state = State.COUNTDOWN
	_state_left = _countdown_step_sec * COUNTDOWN_STEPS
	# Members who joined the room by round start play; rejoiners who arrive
	# mid-round sit out until the next one (SPEC $9).
	_round_slots = _connected_slots()
	game = MinigameCatalog.instantiate(playlist[round_index])
	game.duration_override = _duration_override
	# Short Fuse (M9-04): scale whatever duration would otherwise apply.
	if current_mutator != null and not is_equal_approx(current_mutator.duration_scale, 1.0):
		var base := (
			_duration_override
			if _duration_override > 0.0
			else MinigameCatalog.meta_of(playlist[round_index]).duration_sec
		)
		game.duration_override = current_mutator.scaled_duration(base)
	game.setup(_round_slots, _rng.randi())
	event_emitted.emit({"type": "round_countdown", "round": round_index + 1})


func _enter_play() -> void:
	state = State.PLAY
	event_emitted.emit({"type": "round_started", "round": round_index + 1})
	(
		DiagnosticsLog
		. event(
			&"match",
			&"round_start",
			{
				"room": room.code,
				"round": round_index + 1,
				"game": String(game.meta.id),
				"slots": _round_slots,
			}
		)
	)


func _enter_results() -> void:
	state = State.RESULTS
	_state_left = _results_sec
	var results := game.get_results()
	# Mutator economy knobs (M9-04): Golden Round scales the pickup cap,
	# Double Coins multiplies the combined award.
	var cap := Economy.PICKUP_CAP
	if current_mutator != null:
		cap = current_mutator.scaled_pickup_cap(Economy.PICKUP_CAP)
	var awards := (
		Economy.total_team_round_award(results.placements, results.pickup_coins, cap)
		if results.get("team_mode", false)
		else Economy.total_round_award(results.placements, results.pickup_coins, cap)
	)
	if current_mutator != null:
		awards = current_mutator.apply_award_multiplier(awards)
	for member in room.members:
		member.score += int(awards.get(member.slot, 0))
	# Robin Hood (M9-05): the transfer moves standing coins after the round's
	# awards land, so the broadcast totals already reflect it.
	if current_mutator != null and current_mutator.end_transfer_amount > 0:
		var adjusted := current_mutator.apply_end_transfer(_totals(), results.placements)
		for member in room.members:
			member.score = int(adjusted.get(member.slot, member.score))
	(
		DiagnosticsLog
		. event(
			&"match",
			&"round_end",
			{
				"room": room.code,
				"round": round_index + 1,
				"game": String(game.meta.id),
				"placements": results.placements,
				"awards": awards,
				"totals": _totals(),
			}
		)
	)
	(
		event_emitted
		. emit(
			{
				"type": "round_results",
				"round": round_index + 1,
				"placements": results.placements,
				"awards": awards,
				"totals": _totals(),
			}
		)
	)
	game = null


func _after_results() -> void:
	var played := round_index + 1
	if played < playlist.size() and played % LEADERBOARD_EVERY == 0:
		state = State.LEADERBOARD
		_state_left = _leaderboard_sec
		event_emitted.emit({"type": "leaderboard", "totals": _totals()})
	else:
		_next_round()


func _next_round() -> void:
	round_index += 1
	if round_index < playlist.size():
		_enter_intro()
	elif _finale_enabled and _connected_slots().size() >= 2:
		_enter_finale_shop()
	else:
		_enter_podium(_standings())


func _enter_podium(standings: Array) -> void:
	state = State.PODIUM
	_state_left = _podium_sec
	# Best-of-N accumulation (M11-01): the room's tracker carries points
	# and the coin tiebreak across matches; idle at series length 1.
	room.series.record_match(standings)
	event_emitted.emit(
		{"type": "match_ended", "standings": standings, "series": room.series.to_dict()}
	)


# --- Finale (SPEC $6, #554) ---------------------------------------------------


## The 30 s buy-in shop opens once the playlist is exhausted. Purchases arrive
## as {"shop": {...}} intents on the normal match-input channel; the snapshot
## carries the authoritative shop state back.
func _enter_finale_shop() -> void:
	state = State.FINALE_SHOP
	current_mutator = null
	_round_slots = _connected_slots()
	var coins := {}
	for slot in _round_slots:
		var member := room.find_by_slot(slot)
		coins[slot] = 0 if member == null else member.score
	shop = FinaleShop.new(coins, _shop_sec)
	event_emitted.emit({"type": "finale_shop", "time": _shop_sec, "totals": _totals()})


func _handle_shop_input(slot: int, action: Dictionary) -> void:
	var item := StringName(String(action.get("item", "")))
	match String(action.get("action", "")):
		"buy":
			shop.buy(slot, item)
		"refund":
			shop.refund(slot, item)
		"confirm":
			shop.confirm(slot)


## The Gauntlet is entered directly — never via the catalog/playlist — with
## each player's shop loadout applied on top of the base kit (M5-02).
func _enter_finale_play() -> void:
	state = State.FINALE_PLAY
	game = Gauntlet.new()
	game.meta = Gauntlet.make_meta()
	game.duration_override = _duration_override
	game.setup(_round_slots, _rng.randi())
	(game as Gauntlet).apply_loadouts(shop.loadouts())
	event_emitted.emit({"type": "finale_started", "minigame": game.meta.to_dict()})


## Elimination order decides final placement; FinaleRanking splits ties by
## leftover coins, then coins earned (M5-03). Members who never entered the
## finale (disconnected before the shop) rank below every participant.
func _enter_podium_from_finale() -> void:
	var coins_left := {}
	for slot in _round_slots:
		coins_left[slot] = shop.coins_left(slot)
	var results := game.get_results()
	var ranked: Array = FinaleRanking.rank(results.placements, coins_left, _totals())
	var standings: Array = []
	var placement := 1
	for group: Array in ranked:
		for slot: int in group:
			standings.append(_standing_row(slot, placement))
		placement += group.size()
	for row: Dictionary in _absentee_rows(placement):
		standings.append(row)
	# Balance telemetry (#706): the finale never emits round_results (it skips
	# straight to the podium), so this is its own event — KO-cause breakdown
	# answers the #584 weapons-vs-hazards tuning question once bots (#705)
	# start feeding real balance data.
	if results.has("ko_causes"):
		(
			event_emitted
			. emit(
				{
					"type": "finale_results",
					"placements": results.placements,
					"ko_causes": results.ko_causes,
					"axe_kills": results.axe_kills,
				}
			)
		)
	game = null
	_enter_podium(standings)


func _standing_row(slot: int, placement: int) -> Dictionary:
	var member := room.find_by_slot(slot)
	return {
		"slot": slot,
		"name": "" if member == null else member.display_name,
		"score": 0 if member == null else member.score,
		"placement": placement,
	}


## Rows for members who sat the finale out entirely, ordered by score with
## exact ties sharing a placement, numbered after the last finale placement.
func _absentee_rows(next_placement: int) -> Array:
	var absent: Array = []
	for member in room.members:
		if member.slot not in _round_slots:
			absent.append(member)
	absent.sort_custom(func(a: RoomMember, b: RoomMember) -> bool: return a.score > b.score)
	var rows: Array = []
	var placement := next_placement
	for i in absent.size():
		if i > 0 and absent[i].score != absent[i - 1].score:
			placement = next_placement + i
		rows.append(_standing_row(absent[i].slot, placement))
	return rows


func _finish_match() -> void:
	state = State.DONE
	room.state = Room.State.LOBBY
	DiagnosticsLog.event(
		&"match", &"match_end", {"room": room.code, "totals": _totals(), "rounds": round_index + 1}
	)


func _connected_slots() -> Array[int]:
	var slots: Array[int] = []
	for member in room.members:
		if member.connected:
			slots.append(member.slot)
	return slots


func _totals() -> Dictionary:
	var totals := {}
	for member in room.members:
		totals[member.slot] = member.score
	return totals


func _standings() -> Array:
	var members := room.members.duplicate()
	members.sort_custom(func(a: RoomMember, b: RoomMember) -> bool: return a.score > b.score)
	var standings: Array = []
	for member: RoomMember in members:
		standings.append({"slot": member.slot, "name": member.display_name, "score": member.score})
	return standings
