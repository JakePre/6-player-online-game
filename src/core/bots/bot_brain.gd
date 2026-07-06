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

var slot := -1
var rng := RandomNumberGenerator.new()


func _init(bot_slot: int, seed_value: int) -> void:
	slot = bot_slot
	rng.seed = seed_value


## `match_state` is MatchController.get_snapshot() (state/minigame/game/shop),
## `private` is private_snapshot_for(slot) — this bot's own secrets only.
## Returns a match_input intent Dictionary ({} = do nothing this tick).
func think(_match_state: Dictionary, _private: Dictionary) -> Dictionary:
	return {}


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
