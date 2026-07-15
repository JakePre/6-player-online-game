class_name PuttPanicBrain
extends BotBrain
## Physics-aim archetype (M19-02, #686): aim at the cup and pick a power that
## carries the ball roughly the remaining distance without overshooting so
## fast it can't sink (the cup only accepts a slow ball). Only putts when at
## rest; the sim auto-putts a weak shot if we dawdle, so a deliberate aimed
## stroke is a clear improvement.
##
## Aim/power noise (#715, classified in #759): every bot instance computed
## an identical, deterministic aim+power from remaining distance, so a whole
## bot lobby's putts converged near-optimally and simultaneously — reading
## as fast, heavily-tied rounds in the M12-01 telemetry. Not a sim bug (a
## human's stroke has real variance); a small per-shot wobble, seeded per bot
## like everything else here, spreads outcomes out instead.
##
## Snapshot: {players: {slot: [x, y, strokes, sunk, aim_x, aim_y, at_rest]},
## cup: [x, y], bar, shot_clock} (PuttPanic). Input: {ax, ay} to aim,
## {putt: true, power: 0..1} to strike. Indices named via PuttPanic.PS_* (#708).

## MAX_POWER (14) * power sets launch speed; friction eats it. This factor
## converts remaining distance into a launch power that lands near the cup and
## arrives slow enough to sink (undershoot beats a rimmed-out rocket).
const POWER_PER_UNIT := 0.052
const POWER_MIN := 0.18
const POWER_MAX := 0.75
## Per-shot wobble (#715). CUP_RADIUS (0.55) still swallows a small miss on
## short putts, so this mainly spreads out longer ones rather than making the
## bot incompetent up close.
const AIM_JITTER_RAD := 0.1
const POWER_JITTER := 0.05
## Putt pacing (#961). The bot keeps lining up every tick but only strikes on a
## random ready beat, not the instant the ball rests — a human takes a moment to
## read the line and charge. Without this the bots machine-gunned a putt every
## time they came to rest (~0.45s), grinding a whole round out in ~6s of a 90s
## hole; the readiness beat paces strokes to a human cadence and desyncs the
## field so the shots (and their stroke totals) stop landing in lockstep ties.
## Seeded via `rng` like the rest of the bot's noise; ~1/PUTT_READINESS ticks
## between strokes on average (at the sim's fixed 30 Hz, ~2.5s).
const PUTT_READINESS := 0.011


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var state: Array = players.get(slot, [])
	if state.size() < PuttPanic.PS_COUNT or int(state[PuttPanic.PS_SUNK]) == 1:
		return {}  # not in the round, or already sunk
	var me := Vector2(float(state[PuttPanic.PS_X]), float(state[PuttPanic.PS_Y]))
	var cup_arr: Array = game.get("cup", [0.0, 6.5])
	var cup := Vector2(float(cup_arr[0]), float(cup_arr[1]))
	var to_cup := cup - me
	var aim := to_cup.normalized().rotated(rng.randf_range(-AIM_JITTER_RAD, AIM_JITTER_RAD))
	var intent := {"ax": aim.x, "ay": aim.y}
	# Strike only when at rest AND on a random ready beat (#961 pacing), so the
	# bot lines up for a human moment instead of machine-gunning the instant it
	# stops rolling.
	if int(state[PuttPanic.PS_AT_REST]) == 1 and rng.randf() < PUTT_READINESS:
		var power := clampf(
			to_cup.length() * POWER_PER_UNIT + rng.randf_range(-POWER_JITTER, POWER_JITTER),
			POWER_MIN,
			POWER_MAX
		)
		intent["putt"] = true
		intent["power"] = power
	return intent
