class_name BotBrain
extends RefCounted
## Base class for goal-seeking bot AI (M19, #684). A brain receives exactly
## what a human player's client sees — the room's match snapshot plus its own
## private snapshot (#254) — and returns one gameplay intent, the same shape
## a client would send over match_input. Brains never touch the sim directly:
## fair information (hidden roles stay hidden from other bots' brains) and
## zero risk of a bot mutating authoritative state.
##
## Subclasses override think(). The registry (BotBrains) picks a brain per
## minigame id and falls back to RandomBrain for games without one yet.
##
## think() itself stays a pure, deterministic decision — every per-brain unit
## test calls it directly and is unaffected by the below. Human-like
## imperfection (#818) lives one layer up in think_with_error(), which the
## live server pump and practice-bot driver call instead: it occasionally
## replaces a fresh decision with a slip (a stale/delayed response, a dropped
## input, or jittered aim) so bots stop reading as mechanically perfect —
## simon_stomp never missing a sequence, memory_match never whiffing a match,
## sumo_smash mass-suiciding into the center, races that never DNF a bot.

## Per-tick probability of a slip when driven via think_with_error(). 0
## disables it entirely.
const DEFAULT_ERROR_RATE := 0.08
## Within an erroneous tick, the odds split between slip flavors: replaying
## the last intent (delayed reaction), dropping input this tick (distracted
## miss), or rotating any aim/movement direction (imperfect aim / wrong
## lane). The remainder after ERROR_DELAY_SHARE + ERROR_MISS_SHARE goes to aim
## jitter.
const ERROR_DELAY_SHARE := 0.35
const ERROR_MISS_SHARE := 0.25
## Max random rotation applied to a jittered direction, in radians.
const ERROR_AIM_JITTER_RAD := 0.6

var slot := -1
var rng := RandomNumberGenerator.new()
## Tunable per instance; defaults to DEFAULT_ERROR_RATE so drivers get
## human-like play with zero extra wiring.
var error_rate := DEFAULT_ERROR_RATE

## Independent stream from `rng` so toggling error_rate never perturbs a
## brain's own decision-making draws (aim rolls, tie-breaks, etc).
var _error_rng := RandomNumberGenerator.new()
var _error_last_intent := {}


func _init(bot_slot: int, seed_value: int) -> void:
	slot = bot_slot
	rng.seed = seed_value
	_error_rng.seed = seed_value ^ 0x5BD1E995


## `match_state` is MatchController.get_snapshot() (state/minigame/game/shop),
## `private` is private_snapshot_for(slot) — this bot's own secrets only.
## Returns a match_input intent Dictionary ({} = do nothing this tick).
func think(_match_state: Dictionary, _private: Dictionary) -> Dictionary:
	return {}


## What live drivers actually pump (#818): think()'s fresh decision, with an
## error_rate chance of a human-like slip substituted in its place.
func think_with_error(match_state: Dictionary, private: Dictionary) -> Dictionary:
	var intent := think(match_state, private)
	if error_rate <= 0.0 or _error_rng.randf() >= error_rate:
		_error_last_intent = intent
		return intent
	var roll := _error_rng.randf()
	if roll < ERROR_DELAY_SHARE:
		return _error_last_intent.duplicate()  # still reacting to last tick
	if roll < ERROR_DELAY_SHARE + ERROR_MISS_SHARE:
		_error_last_intent = intent
		return {}  # distracted — no input lands this tick
	var jittered := _jitter_aim(intent)
	_error_last_intent = jittered
	return jittered


## Rotates any aim/movement direction pair (mx/my, ax/ay) by a random offset
## — the "swung wide" flavor of imperfection. Every other intent field
## (button presses, choices, ids) passes through untouched.
func _jitter_aim(intent: Dictionary) -> Dictionary:
	var noisy := intent.duplicate()
	for pair in [["mx", "my"], ["ax", "ay"]]:
		if not (noisy.has(pair[0]) and noisy.has(pair[1])):
			continue
		var dir := Vector2(float(noisy[pair[0]]), float(noisy[pair[1]]))
		if dir.length() <= 0.001:
			continue
		dir = dir.rotated(_error_rng.randf_range(-ERROR_AIM_JITTER_RAD, ERROR_AIM_JITTER_RAD))
		noisy[pair[0]] = dir.x
		noisy[pair[1]] = dir.y
	return noisy


# --- Shared steering helpers ---------------------------------------------------


## Unit-ish movement intent from `from` toward `to`; stops dead inside
## `arrive_radius` so bots don't jitter on top of their target.
static func move_toward_point(from: Vector2, to: Vector2, arrive_radius := 0.2) -> Dictionary:
	var delta := to - from
	if delta.length() <= arrive_radius:
		return {"mx": 0.0, "my": 0.0}
	var dir := delta.normalized()
	return {"mx": dir.x, "my": dir.y}


## Movement intent fleeing straight away from `threat`.
static func move_away_from_point(from: Vector2, threat: Vector2) -> Dictionary:
	var delta := from - threat
	var dir := Vector2.RIGHT if delta.length() < 0.001 else delta.normalized()
	return {"mx": dir.x, "my": dir.y}


## This bot's [x, y] from a players snapshot map, or Vector2.INF when absent
## (eliminated / not in the round).
func my_position(players: Dictionary) -> Vector2:
	var state: Array = players.get(slot, [])
	if state.size() < 2:
		return Vector2.INF
	return Vector2(float(state[0]), float(state[1]))


## Nearest [x, y, ...] entry of `points` to `from`, or Vector2.INF when empty.
static func nearest_point(from: Vector2, points: Array) -> Vector2:
	var best := Vector2.INF
	var best_distance := INF
	for entry: Array in points:
		if entry.size() < 2:
			continue
		var point := Vector2(float(entry[0]), float(entry[1]))
		var distance := from.distance_squared_to(point)
		if distance < best_distance:
			best_distance = distance
			best = point
	return best
