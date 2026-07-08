class_name ShredSessionBrain
extends BotBrain
## Rhythm-lane archetype (M19-02, #686): the chart is fully visible ahead of
## time (LOOKAHEAD_SEC), so this brain just presses a note's lane once it's
## inside the GOOD window, remembering which notes it already tried so it
## never re-presses a lane it already cleared and whiffs into empty air.
##
## Snapshot: {elapsed, notes: [[time, lane], ...] (upcoming, not filtered per
## player), players: {...}}. Input: {"lane": 0..LANES-1} only. Indices named
## via ShredSession.NT_* (#708).

## Notes ("time:lane" keys) this bot has already pressed, so a note that
## lingers in the upcoming list after we've hit it is never pressed twice.
var _attempted := {}


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var elapsed := float(game.get("elapsed", 0.0))
	var best_lane := -1
	var best_key := ""
	var best_dt := ShredSession.GOOD_SEC + 1.0
	for note: Array in game.get("notes", []):
		var time := float(note[ShredSession.NT_TIME])
		var dt := absf(time - elapsed)
		if dt > ShredSession.GOOD_SEC:
			continue
		var key := "%.2f:%d" % [time, int(note[ShredSession.NT_LANE])]
		if _attempted.has(key):
			continue
		if dt < best_dt:
			best_dt = dt
			best_lane = int(note[ShredSession.NT_LANE])
			best_key = key
	if best_lane == -1:
		return {}
	# Marked only once we've committed to this note, not while merely scanning
	# — a candidate that loses out to a closer one must stay pressable.
	_attempted[best_key] = true
	return {"lane": best_lane}
