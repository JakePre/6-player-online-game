class_name ShredSessionBrain
extends BotBrain
## Rhythm-lane archetype (M19-02, #686): the chart is fully visible ahead of
## time (LOOKAHEAD_SEC), so this brain just presses a note's lane once it's
## inside the GOOD window, remembering which notes it already tried so it
## never re-presses a lane it already cleared and whiffs into empty air.
##
## Snapshot: {elapsed, notes: [[time, lane], ...] (upcoming, not filtered per
## player), players: {slot: [...star_meter, star_active]}}. Input: {"lane":
## 0..LANES-1} or {"star": true}. Indices named via ShredSession.NT_*/PS_* (#708).

## Star Power spend heuristic (#957): cash a full meter in when at least this
## many notes cross within the next window — a denser-than-average stretch worth
## the 2x (the chart runs ~4-5 notes / 3s on average, ramping up late).
const STAR_DENSITY_SEC := 3.0
const STAR_SPEND_NOTES := 5

## Notes ("time:lane" keys) this bot has already pressed, so a note that
## lingers in the upcoming list after we've hit it is never pressed twice.
var _attempted := {}


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var elapsed := float(game.get("elapsed", 0.0))
	# Star Power (#957): a full meter, not already burning, cashed in when a dense
	# stretch is coming. The upstream imperfection knob still delays/drops this
	# like any other input. Own meter reads off this bot's snapshot row.
	var me: Array = (game.get("players", {}) as Dictionary).get(slot, [])
	if (
		me.size() > ShredSession.PS_STAR_ACTIVE
		and int(me[ShredSession.PS_STAR_METER]) >= ShredSession.STAR_PERFECTS
		and int(me[ShredSession.PS_STAR_ACTIVE]) == 0
		and _upcoming_note_count(game, elapsed) >= STAR_SPEND_NOTES
	):
		return {"star": true}
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


## Notes crossing within the next STAR_DENSITY_SEC — the density read the Star
## Power spend decision keys off. The snapshot advertises LOOKAHEAD_SEC (4s)
## ahead, enough to see the 3s stretch coming.
func _upcoming_note_count(game: Dictionary, elapsed: float) -> int:
	var count := 0
	for note: Array in game.get("notes", []):
		var dt := float(note[ShredSession.NT_TIME]) - elapsed
		if dt >= 0.0 and dt <= STAR_DENSITY_SEC:
			count += 1
	return count
