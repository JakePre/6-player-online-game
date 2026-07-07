class_name BeatBounceBrain
extends BotBrain
## Simon-says archetype (M19-02, #686): memorize the pad sequence while it's
## shown (WATCH), then play it back on the beat (REPEAT) — the sequence is
## withheld from the snapshot during REPEAT (fair information: a bot that
## didn't watch has to guess, exactly like a human who looked away).
##
## Snapshot: {phase, step, sequence (WATCH only), next_in, interval, alive}.
## Input: {"pad": 0..PAD_COUNT-1} only during REPEAT, near a beat.

## Sequence as last seen during WATCH — the sim never resends it during
## REPEAT, so this is the brain's only memory of what to play back.
var _remembered: Array = []


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	if not bool((game.get("alive", {}) as Dictionary).get(slot, false)):
		return {}
	var phase := int(game.get("phase", BeatBounce.Phase.WATCH))
	var sequence: Array = game.get("sequence", [])
	if phase == BeatBounce.Phase.WATCH:
		if not sequence.is_empty():
			_remembered = sequence.duplicate()
		return {}
	return _press_near_the_beat(game)


## The hit window opens for HIT_WINDOW_SEC right after a beat (the currently
## flagged `step`) and again for HIT_WINDOW_SEC right before the next one (an
## early press for `step + 1`, the sim's own allowance). `next_in` counts down
## to the next beat, so `interval - next_in` is time since the last one.
func _press_near_the_beat(game: Dictionary) -> Dictionary:
	var step := int(game.get("step", -1))
	var interval := float(game.get("interval", BeatBounce.START_INTERVAL_SEC))
	var next_in := float(game.get("next_in", interval))
	var since_last_beat := interval - next_in
	var target_step := -1
	if since_last_beat <= BeatBounce.HIT_WINDOW_SEC and step >= 0:
		target_step = step
	elif next_in <= BeatBounce.HIT_WINDOW_SEC:
		target_step = step + 1
	if target_step < 0 or target_step >= _remembered.size():
		return {}
	return {"pad": int(_remembered[target_step])}
