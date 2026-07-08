class_name RoShamBoBrain
extends BotBrain
## Rock-paper-scissors archetype (M19-02, #686): rival throws are secret until
## REVEAL (anti-peek), so a normal round has no signal to pick a shape by — the
## brain picks once at random and commits, same blind choice a human makes.
## Sudden death is different: `target_shape` IS revealed to both duelists, and
## the sim's own win rule is "exactly one" throw of the counter — a shared
## correct throw is still a tie (#715: always countering guaranteed an
## infinite mirror-tie loop against another counter-reading bot). So the
## brain commits to the counter only about half the time and blind-guesses
## otherwise, same as `2p(1-p)` win-chance math for a symmetric duel. Eliminated
## players vote once for a random still-alive rival (no more read on the
## outcome than that).
##
## Snapshot: {phase, players: {slot: [x, y, alive, thrown]}, sudden_death,
## target_shape}. Input: {mx, my} to walk a pad, or {"vote": slot} once out.
## Indices named via RoShamBo.PS_* (#708).

var _chosen_shape := -1
var _prev_thrown := false


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var state: Array = players.get(slot, [])
	if state.size() < RoShamBo.PS_COUNT:
		return {}
	var me := Vector2(float(state[RoShamBo.PS_X]), float(state[RoShamBo.PS_Y]))
	if int(state[RoShamBo.PS_ALIVE]) == 0:
		return _vote(players)
	var thrown := int(state[RoShamBo.PS_THROWN]) == 1
	if thrown:
		_prev_thrown = true
		return {}
	if _prev_thrown:
		_chosen_shape = -1  # a fresh round just started: this pick is stale
	_prev_thrown = false
	if _chosen_shape == -1:
		var target_shape := int(game.get("target_shape", -1))
		if bool(game.get("sudden_death", false)) and target_shape != -1:
			_chosen_shape = (
				_counter(target_shape)
				if rng.randf() < 0.5
				else rng.randi_range(RoShamBo.Shape.ROCK, RoShamBo.Shape.SCISSORS)
			)
		else:
			_chosen_shape = rng.randi_range(RoShamBo.Shape.ROCK, RoShamBo.Shape.SCISSORS)
	return move_toward_point(me, RoShamBo.pad_position(_chosen_shape), 0.0)


## RoShamBo._counter is an instance method (not static), so the tiny
## rock-paper-scissors lookup is duplicated here rather than reaching into a
## sim instance the brain doesn't have.
func _counter(shape: int) -> int:
	match shape:
		RoShamBo.Shape.ROCK:
			return RoShamBo.Shape.PAPER
		RoShamBo.Shape.PAPER:
			return RoShamBo.Shape.SCISSORS
		_:
			return RoShamBo.Shape.ROCK


func _vote(players: Dictionary) -> Dictionary:
	var alive: Array = []
	for other: int in players:
		if other == slot:
			continue
		var state: Array = players[other]
		if state.size() > RoShamBo.PS_ALIVE and int(state[RoShamBo.PS_ALIVE]) == 1:
			alive.append(other)
	if alive.is_empty():
		return {}
	return {"vote": alive[rng.randi_range(0, alive.size() - 1)]}
