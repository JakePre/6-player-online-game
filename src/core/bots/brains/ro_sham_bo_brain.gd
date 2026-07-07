class_name RoShamBoBrain
extends BotBrain
## Rock-paper-scissors archetype (M19-02, #686): rival throws are secret until
## REVEAL (anti-peek), so a normal round has no signal to pick a shape by — the
## brain picks once at random and commits, same blind choice a human makes.
## Sudden death is different: `target_shape` IS revealed, so the brain always
## walks the deterministic counter pad. Eliminated players vote once for a
## random still-alive rival (no more read on the outcome than that).
##
## Snapshot: {phase, players: {slot: [x, y, alive, thrown]}, sudden_death,
## target_shape}. Input: {mx, my} to walk a pad, or {"vote": slot} once out.

var _chosen_shape := -1
var _prev_thrown := false


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var state: Array = players.get(slot, [])
	if state.size() < 4:
		return {}
	var me := Vector2(float(state[0]), float(state[1]))
	if int(state[2]) == 0:
		return _vote(players)
	var thrown := int(state[3]) == 1
	if thrown:
		_prev_thrown = true
		return {}
	if _prev_thrown:
		_chosen_shape = -1  # a fresh round just started: this pick is stale
	_prev_thrown = false
	var target_shape := int(game.get("target_shape", -1))
	var shape: int
	if bool(game.get("sudden_death", false)) and target_shape != -1:
		shape = _counter(target_shape)
	else:
		if _chosen_shape == -1:
			_chosen_shape = rng.randi_range(RoShamBo.Shape.ROCK, RoShamBo.Shape.SCISSORS)
		shape = _chosen_shape
	return move_toward_point(me, RoShamBo.pad_position(shape), 0.0)


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
		if state.size() >= 3 and int(state[2]) == 1:
			alive.append(other)
	if alive.is_empty():
		return {}
	return {"vote": alive[rng.randi_range(0, alive.size() - 1)]}
