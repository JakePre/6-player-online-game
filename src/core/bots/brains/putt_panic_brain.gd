class_name PuttPanicBrain
extends BotBrain
## Physics-aim archetype (M19-02, #686): aim straight at the cup and pick a
## power that carries the ball roughly the remaining distance without
## overshooting so fast it can't sink (the cup only accepts a slow ball).
## Only putts when at rest; the sim auto-putts a weak shot if we dawdle, so a
## deliberate aimed stroke is a clear improvement.
##
## Snapshot: {players: {slot: [x, y, strokes, sunk, aim_x, aim_y, at_rest]},
## cup: [x, y], bar, shot_clock} (PuttPanic). Input: {ax, ay} to aim,
## {putt: true, power: 0..1} to strike.

## MAX_POWER (14) * power sets launch speed; friction eats it. This factor
## converts remaining distance into a launch power that lands near the cup and
## arrives slow enough to sink (undershoot beats a rimmed-out rocket).
const POWER_PER_UNIT := 0.052
const POWER_MIN := 0.18
const POWER_MAX := 0.75


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var state: Array = players.get(slot, [])
	if state.size() < 7 or int(state[3]) == 1:
		return {}  # not in the round, or already sunk
	var me := Vector2(float(state[0]), float(state[1]))
	var cup_arr: Array = game.get("cup", [0.0, 6.5])
	var cup := Vector2(float(cup_arr[0]), float(cup_arr[1]))
	var to_cup := cup - me
	var aim := to_cup.normalized()
	var intent := {"ax": aim.x, "ay": aim.y}
	# Strike only when at rest; power scales with the distance left to the cup.
	if int(state[6]) == 1:
		var power := clampf(to_cup.length() * POWER_PER_UNIT, POWER_MIN, POWER_MAX)
		intent["putt"] = true
		intent["power"] = power
	return intent
