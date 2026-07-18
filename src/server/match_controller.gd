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
	# Playtest mode (#1070): the match idles here after every round while the
	# host hand-picks the next game from the eligible catalog.
	PICK,
}

const LEADERBOARD_EVERY := 5
## The playtest picker's end-the-match choice (#1070) — not a catalog id, so it
## can never collide with a real game.
const PICK_END := "end"
## PHASE2.md $3: roughly this share of rounds draw a mutator from the host's
## enabled pool. Mutators roll per playlist round only — the finale clears
## `current_mutator` on entry, so "never the finale" holds structurally.
const MUTATOR_ROUND_CHANCE := 0.4
## 3-2-1 over the visible arena at 600 ms per digit (#182). The game is
## already instantiated during COUNTDOWN so clients render the starting
## positions, but it does not tick and takes no input until PLAY.
const COUNTDOWN_STEP_SEC := 0.6
const COUNTDOWN_STEPS := 3
## Beat held after a decisive round end before the results transition (#1045),
## so the loser's KO and the winner's moment render instead of the game cutting
## to the results panel the instant the win resolves. Only for early
## (elimination/objective/race) ends — a plain timeout goes straight to results.
const FINISHER_SEC := 1.2

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
## Finisher-beat countdown (#1045); >0 while holding the decided round in PLAY /
## FINALE_PLAY before the transition. _finisher_to_podium routes the finale beat
## to the podium instead of the round-results screen.
var _finisher_left := 0.0
## The finale arena for THIS match (#936): drawn from FinaleVariants at shop
## time (random per match, owner decision), overridable via config
## "finale_variant" for tests and render harnesses (#685).
var _finale_id: StringName = &"gauntlet"
var _finale_variant_override := ""
var _finisher_to_podium := false
var _rng := RandomNumberGenerator.new()
var _round_slots: Array[int] = []
var _skip_votes := {}
## Playtest mode (#1070): every game already played this match, in order —
## shown on the pick screen so the host can see roster coverage at a glance.
var _played_ids: Array = []


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
	_finale_variant_override = String(config.get("finale_variant", ""))
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
	elif room.playtest_mode:
		# #1070: no pre-built playlist — the host picks each round's game live,
		# and every pick appends here so round_index/snapshot code just works.
		playlist = []
	elif room.debug_all_games:
		# #812: the whole eligible roster once, in catalog order — no shuffle, no
		# repeats. Host exclusions are ignored on purpose; the point of the debug
		# run is to reach every game the current head count can support.
		playlist = MinigameCatalog.eligible_ids(room.connected_count(), [])
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
	if room.playtest_mode:
		_enter_pick()
		return
	_enter_intro()


func tick(delta: float) -> void:
	if state == State.DONE:
		return
	# The finisher beat (#1045) only holds during PLAY / FINALE_PLAY; checking it
	# once here (rather than inside each branch) keeps tick() under the return cap.
	if _tick_finisher(delta):
		return
	if state == State.PLAY:
		# Overdrive (M9-04): the server scales the sim delta, so everything —
		# movement, timers, the round clock — runs faster together.
		if current_mutator != null:
			delta = current_mutator.scaled_tick_delta(delta)
		game.tick(delta)
		if game.finished:
			_begin_finisher_or(false)
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
			_begin_finisher_or(true)
		return
	_state_left -= delta
	if _state_left > 0.0:
		return
	match state:
		State.PICK:
			# Host migration hands the pick to the next human; a room with no
			# connected humans at all would wedge here, so it self-picks.
			if room.host() == null:
				_auto_pick()
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


## A decisive early round end (elimination/objective/race) holds a finisher beat
## (#1045) so the loser's KO and the winner render before the transition; a plain
## timeout end has no dramatic moment, so it transitions immediately.
func _begin_finisher_or(to_podium: bool) -> void:
	if game.finished_early:
		_finisher_left = FINISHER_SEC
		_finisher_to_podium = to_podium
	elif to_podium:
		_enter_podium_from_finale()
	else:
		_enter_results()


## True while the finisher beat holds the decided round in PLAY / FINALE_PLAY
## (#1045). The game is already finished, so its tick() no-ops and the frozen
## final snapshot keeps streaming — the client renders the KO/celebration — until
## the beat elapses and the real transition runs.
func _tick_finisher(delta: float) -> bool:
	if _finisher_left <= 0.0:
		return false
	_finisher_left -= delta
	if _finisher_left <= 0.0:
		if _finisher_to_podium:
			_enter_podium_from_finale()
		else:
			_enter_results()
	return true


func handle_input(slot: int, data: Dictionary) -> void:
	# The pick screen (#1070) sits outside the round: _round_slots is stale (or
	# empty before round one), so the host gate below replaces that guard.
	if state == State.PICK:
		_handle_pick(slot, data)
		return
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
## HUMAN player has voted (#819) — a server-owned bot never presses the skip
## button, so it no longer counts toward "needed". Votes reset each intro card.
func handle_skip(slot: int) -> void:
	if state != State.INTRO:
		return
	var voters := _connected_slots()
	if slot not in voters or _skip_votes.has(slot):
		return
	_skip_votes[slot] = true
	var needed := _human_voters()
	var votes := 0
	for voter in needed:
		if _skip_votes.has(voter):
			votes += 1
	event_emitted.emit({"type": "skip_votes", "votes": votes, "needed": needed.size()})
	if votes >= needed.size():
		_enter_countdown()


## Connected slots that should be waited on for a "did everyone act" gate
## (#819) — see BotGate.humans_or_everyone().
func _human_voters() -> Array[int]:
	return BotGate.humans_or_everyone(_connected_slots(), _bot_slots())


func _bot_slots() -> Array[int]:
	var bots: Array[int] = []
	for member in room.members:
		if member.is_bot:
			bots.append(member.slot)
	return bots


## The playtest picker's input gate (#1070): only the current host may pick,
## and only ids the current head count can actually run. PICK_END finishes the
## match on demand (finale if enabled and populated, straight podium otherwise).
func _handle_pick(slot: int, data: Dictionary) -> void:
	var host := room.host()
	if host == null or host.slot != slot or not data.has("pick"):
		return
	var pick := String(data.pick)
	if pick == PICK_END:
		if _finale_enabled and _connected_slots().size() >= 2:
			_enter_finale_shop()
		else:
			_enter_podium(_standings())
		return
	var sid := StringName(pick)
	if sid not in MinigameCatalog.eligible_ids(room.connected_count(), []):
		return
	_start_picked(sid)


func _start_picked(id: StringName) -> void:
	playlist.append(id)
	round_index = playlist.size() - 1
	_enter_intro()


## Keeps a humanless room moving (bot harnesses, everyone-quit): a random
## eligible game, or straight to the podium if the head count supports none.
func _auto_pick() -> void:
	var eligible := MinigameCatalog.eligible_ids(room.connected_count(), [])
	if eligible.is_empty():
		_enter_podium(_standings())
		return
	_start_picked(eligible[_rng.randi_range(0, eligible.size() - 1)])


func _enter_pick() -> void:
	state = State.PICK
	# No clock: the picker waits on the host (tick()'s host-null branch is the
	# only escape hatch), so time_left renders as 0 on clients.
	_state_left = 0.0
	event_emitted.emit({"type": "pick_started", "played": _played_ids.duplicate()})


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
		snapshot["minigame"] = String(_finale_id)
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
	if state == State.PICK:
		# The pick screen renders purely from this (#1070): the live eligible
		# catalog (exclusions ignored on purpose — reaching the game under test
		# IS the point), plus everything already played this match.
		var eligible: Array = []
		for id in MinigameCatalog.eligible_ids(room.connected_count(), []):
			eligible.append(String(id))
		snapshot["pick"] = {"eligible": eligible, "played": _played_ids.duplicate()}
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
	# The debug run (#812) is a clean audit pass — never perturbed by mutators.
	# Playtest mode (#1070) is controlled-conditions testing — also unperturbed.
	if (
		room.debug_all_games
		or room.playtest_mode
		or room.mutator_pool.is_empty()
		or _rng.randf() >= MUTATOR_ROUND_CHANCE
	):
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
	game.setup(_round_slots, _rng.randi(), _bot_slots())
	event_emitted.emit({"type": "round_countdown", "round": round_index + 1})


func _enter_play() -> void:
	state = State.PLAY
	_finisher_left = 0.0
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
		Economy.total_team_round_award(
			results.placements, results.pickup_coins, cap, int(results.get("team_count", 0))
		)
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
	if room.playtest_mode:
		# #1070: back to the picker after every round — no leaderboard breaks,
		# no round cap; the host ends the match from the pick screen.
		_played_ids.append(String(playlist[round_index]))
		_enter_pick()
		return
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


## The finale is entered directly — never via the catalog/playlist — with
## each player's shop loadout applied on top of the base kit (M5-02). Which
## arena runs is drawn from the FinaleVariants pool (#936), random per match;
## every variant shares the apply_loadouts() interface.
func _enter_finale_play() -> void:
	state = State.FINALE_PLAY
	_finisher_left = 0.0
	_finale_id = (
		StringName(_finale_variant_override)
		if FinaleVariants.is_finale(StringName(_finale_variant_override))
		else FinaleVariants.pick(_rng)
	)
	game = FinaleVariants.instantiate(_finale_id)
	game.duration_override = _duration_override
	game.setup(_round_slots, _rng.randi(), _bot_slots())
	game.call(&"apply_loadouts", shop.loadouts())
	# Optional crowning hook (#936 Kingslayer): variants that care about the
	# match standings get the coin totals after loadouts land.
	if game.has_method(&"apply_match_totals"):
		game.call(&"apply_match_totals", _totals())
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
