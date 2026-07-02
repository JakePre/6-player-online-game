class_name MatchController
extends RefCounted
## Server-side match state machine (M3-01, SPEC $4):
## INTRO -> PLAY -> RESULTS -> (LEADERBOARD every 5 rounds) -> ... -> PODIUM.
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
}

const LEADERBOARD_EVERY := 5

var state := State.INTRO
var room: Room
var round_index := 0
var playlist: Array = []
var game: MinigameBase

var _intro_sec := 10.0
var _results_sec := 8.0
var _leaderboard_sec := 5.0
var _podium_sec := 8.0
var _duration_override := 0.0
var _state_left := 0.0
var _rng := RandomNumberGenerator.new()
var _round_slots: Array[int] = []
var _skip_votes := {}


## config: rounds (int), seed (int), and for test harnesses only (server must
## run --debug-rpcs to accept them from clients): intro_sec, results_sec,
## leaderboard_sec, podium_sec, duration_override.
func _init(match_room: Room, config: Dictionary) -> void:
	room = match_room
	_rng.seed = int(config.get("seed", randi()))
	_intro_sec = config.get("intro_sec", _intro_sec)
	_results_sec = config.get("results_sec", _results_sec)
	_leaderboard_sec = config.get("leaderboard_sec", _leaderboard_sec)
	_podium_sec = config.get("podium_sec", _podium_sec)
	_duration_override = config.get("duration_override", 0.0)
	MinigameCatalog.register_builtins()
	playlist = config.get(
		"playlist",
		MinigameCatalog.build_playlist(_rng, int(config.get("rounds", 12)), room.connected_count())
	)


func start() -> void:
	room.state = Room.State.IN_MATCH
	for member in room.members:
		member.score = 0
	event_emitted.emit({"type": "match_started", "rounds": playlist.size()})
	_enter_intro()


func tick(delta: float) -> void:
	if state == State.DONE:
		return
	if state == State.PLAY:
		game.tick(delta)
		if game.finished:
			_enter_results()
		return
	_state_left -= delta
	if _state_left > 0.0:
		return
	match state:
		State.INTRO:
			_enter_play()
		State.RESULTS:
			_after_results()
		State.LEADERBOARD:
			_next_round()
		State.PODIUM:
			_finish_match()


func handle_input(slot: int, data: Dictionary) -> void:
	if state == State.PLAY and slot in _round_slots:
		game.handle_input(slot, data)


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
		_enter_play()


func is_done() -> bool:
	return state == State.DONE


func get_snapshot() -> Dictionary:
	var snapshot := {
		"state": state,
		"round": round_index,
		"rounds": playlist.size(),
		"time_left": maxf(_state_left, 0.0),
	}
	if state == State.PLAY:
		snapshot.time_left = maxf(game.effective_duration() - game.elapsed, 0.0)
		snapshot["game"] = game.get_snapshot()
	return snapshot


# --- State transitions -------------------------------------------------------


func _enter_intro() -> void:
	state = State.INTRO
	_state_left = _intro_sec
	_skip_votes.clear()
	var meta := MinigameCatalog.meta_of(playlist[round_index])
	(
		event_emitted
		. emit(
			{
				"type": "round_intro",
				"round": round_index + 1,
				"rounds": playlist.size(),
				"minigame": meta.to_dict(),
			}
		)
	)


func _enter_play() -> void:
	state = State.PLAY
	# Members who joined the room by round start play; rejoiners who arrive
	# mid-round sit out until the next one (SPEC $9).
	_round_slots = _connected_slots()
	game = MinigameCatalog.instantiate(playlist[round_index])
	game.duration_override = _duration_override
	game.setup(_round_slots, _rng.randi())
	event_emitted.emit({"type": "round_started", "round": round_index + 1})


func _enter_results() -> void:
	state = State.RESULTS
	_state_left = _results_sec
	var results := game.get_results()
	var awards := Economy.total_round_award(results.placements, results.pickup_coins)
	for member in room.members:
		member.score += int(awards.get(member.slot, 0))
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
	else:
		state = State.PODIUM
		_state_left = _podium_sec
		event_emitted.emit({"type": "match_ended", "standings": _standings()})


func _finish_match() -> void:
	state = State.DONE
	room.state = Room.State.LOBBY


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
