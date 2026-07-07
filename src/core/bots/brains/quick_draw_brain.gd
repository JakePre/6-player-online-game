class_name QuickDrawBrain
extends BotBrain
## Reaction archetype (M19-02, #686): press the instant the round goes LIVE,
## never during WAITING (that forfeits the round). A tiny per-bot reaction
## delay after LIVE keeps bots from being inhumanly perfect and from tying on
## the very first LIVE tick.
##
## Snapshot: {phase, round, wins, false_started, winner} (QuickDraw). Phase:
## 0 WAITING, 1 LIVE, 2 ROUND_OVER. Input: {press: true} — the sim ignores
## repeats (one _acted latch per round), so pressing every LIVE tick is safe.

## Human-plausible reaction window (seconds) rolled once per LIVE onset, so
## bots don't all fire on the same tick and a human can still win.
const REACT_MIN := 0.12
const REACT_MAX := 0.32

var _reacting_since := -1.0
var _react_delay := 0.0
var _last_phase := -1


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var phase := int(game.get("phase", QuickDraw.Phase.WAITING))
	# Fresh reaction timer on each new LIVE onset; reset off LIVE.
	if phase != _last_phase:
		_last_phase = phase
		if phase == QuickDraw.Phase.LIVE:
			_reacting_since = 0.0
			_react_delay = rng.randf_range(REACT_MIN, REACT_MAX)
		else:
			_reacting_since = -1.0
	if phase != QuickDraw.Phase.LIVE or _reacting_since < 0.0:
		return {}
	# think() is pumped at BOT_INPUT_INTERVAL_SEC; count elapsed toward the
	# reaction delay, then commit the press (and keep pressing — sim latches).
	_reacting_since += NetManager.BOT_INPUT_INTERVAL_SEC
	if _reacting_since >= _react_delay:
		return {"press": true}
	return {}
