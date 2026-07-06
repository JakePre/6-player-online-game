class_name HurdleDashBrain
extends BotBrain
## Racer archetype (M19): hold run and jump as each hurdle comes up.
## Snapshot: {players: {slot: [progress, airborne, stun_left, done]},
## hurdles: [progress, ...], course_len} (HurdleDash). Input: {"mx": > 0.1}
## keeps running; {"jump": true} jumps (sim gates cooldown/stun/air itself).

## Jump when the next hurdle is within this much progress ahead.
const JUMP_LEAD := 1.4


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var state: Array = players.get(slot, [])
	if state.size() < 4 or bool(state[3]):
		return {}
	var progress := float(state[0])
	var airborne := int(state[1]) == 1
	if not airborne:
		for hurdle: Variant in game.get("hurdles", []):
			var ahead := float(hurdle) - progress
			if ahead > 0.0 and ahead < JUMP_LEAD:
				# The sim treats a jump intent as jump-only; keep running on
				# the next tick (0.25 s cadence keeps momentum fine).
				return {"jump": true}
	return {"mx": 1.0}
