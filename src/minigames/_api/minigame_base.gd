class_name MinigameBase
extends RefCounted
## Server-side base class of the Minigame Contract (plan $4). Minigames are
## pure simulations: the framework calls setup/tick/handle_input, reads
## get_snapshot() for replication, and consumes results when `finished`.
## Minigames never touch RPCs (ADR 001).
##
## Results shape: placements is an array of rank groups (arrays of slots,
## best first, ties grouped); pickup_coins is {slot: int}.

var meta: MinigameMeta
var slots: Array[int] = []
var rng := RandomNumberGenerator.new()
var elapsed := 0.0
var finished := false
## True when the round ended *before* its clock ran out — an elimination, a
## race won, an objective met: a decisive moment worth a finisher beat (#1045).
## A plain timeout end leaves this false (nothing dramatic to punctuate). Set in
## finish() from whether the duration had elapsed; the match flow reads it to
## decide whether to hold a beat before results so the loser's KO renders.
var finished_early := false
## Team minigames set this so the framework awards the SPEC $5 team tables
## instead of FFA placements. An explicit flag (not the meta category)
## because e.g. Color Clash plays FFA below 4 players.
var team_mode := false
## True number of teams in a team_mode game (#811). Multi-team sims (3+
## teams) set it in _setup() so tied teams — merged into one placements
## group — still award from the right table; 0 keeps the pre-#811 "one team
## per placements group" reading, exact for 2-team games.
var team_count := 0
## Test-harness hook: when > 0, replaces meta.duration_sec for this instance.
var duration_override := 0.0
## Server-owned bot slots among `slots` (#819) — the match controller passes
## these at setup so a "wait for everyone" gate (lock-ins, votes) can skip
## waiting on a bot that will never explicitly act, via `_human_slots()`.
## Minigames otherwise stay bot-blind by design.
var bot_slots: Array[int] = []

var _placements: Array = []
var _pickup_coins := {}


func setup(player_slots: Array[int], seed_value: int, bots: Array[int] = []) -> void:
	slots = player_slots.duplicate()
	bot_slots = bots.duplicate()
	rng.seed = seed_value
	_setup()


## The subset of `slots` a "wait for everyone" gate should require action
## from — see BotGate.humans_or_everyone() (#819).
func _human_slots() -> Array[int]:
	return BotGate.humans_or_everyone(slots, bot_slots)


func tick(delta: float) -> void:
	if finished:
		return
	elapsed += delta
	_tick(delta)
	if elapsed >= effective_duration() and not finished:
		finish(_rank_players())


func effective_duration() -> float:
	return duration_override if duration_override > 0.0 else meta.duration_sec


## `data` comes straight off the wire — validate everything.
func handle_input(slot: int, data: Dictionary) -> void:
	if not finished and slot in slots:
		_handle_input(slot, data)


func get_results() -> Dictionary:
	return {
		"placements": _placements,
		"pickup_coins": _pickup_coins,
		"team_mode": team_mode,
		"team_count": team_count,
	}


func get_snapshot() -> Dictionary:
	return {}


## Per-player secret state, delivered only to `slot`'s own client (#254).
## Hidden-role games (saboteur, mole, disguised guard) override this to
## reveal a role to exactly one player; the shared get_snapshot() stays
## anonymous. Default: nothing secret.
func get_private_snapshot(_slot: int) -> Dictionary:
	return {}


func finish(placements: Array) -> void:
	_placements = placements
	finished = true
	# Ended before the clock expired = a decisive end (#1045). The base tick()
	# only calls finish() once elapsed has reached the duration, so a still-short
	# clock here means the game itself ended the round early.
	finished_early = elapsed < effective_duration()


# --- Overridables ------------------------------------------------------------


func _setup() -> void:
	pass


func _tick(_delta: float) -> void:
	pass


func _handle_input(_slot: int, _data: Dictionary) -> void:
	pass


## Ranking used when time runs out. Default: everyone tied.
func _rank_players() -> Array:
	return [slots.duplicate()]
