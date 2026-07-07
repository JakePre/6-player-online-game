class_name SimonStompBrain
extends BotBrain
## Simon-says archetype (M19-02, #686): memorize the pad sequence while it's
## flashing (SHOW), then stomp it back in order (INPUT) — the sequence is
## withheld from the snapshot once SHOW ends (fair information).
##
## Unlike Beat Bounce, there's no beat-timing window to hit: INPUT just wants
## the pads in order, and the server's own `progress` count tells the brain
## exactly which step is next, so it can't get out of sync with itself.
##
## Snapshot: {phase, sequence (SHOW only), alive, progress, round_cleared,
## round_failed}. Input: {"pad": 0..PAD_COUNT-1} only during INPUT.

var _remembered: Array = []


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	if not bool((game.get("alive", {}) as Dictionary).get(slot, false)):
		return {}
	var phase := int(game.get("phase", SimonStomp.Phase.SHOW))
	if phase == SimonStomp.Phase.SHOW:
		var sequence: Array = game.get("sequence", [])
		if not sequence.is_empty():
			_remembered = sequence.duplicate()
		return {}
	return _play_back(game)


## During INPUT, press the next remembered pad — unless we've already
## resolved this round (cleared or busted) or run out of memorized steps.
func _play_back(game: Dictionary) -> Dictionary:
	if int(game.get("phase", SimonStomp.Phase.SHOW)) != SimonStomp.Phase.INPUT:
		return {}
	if bool((game.get("round_cleared", {}) as Dictionary).get(slot, false)):
		return {}
	if bool((game.get("round_failed", {}) as Dictionary).get(slot, false)):
		return {}
	var index := int((game.get("progress", {}) as Dictionary).get(slot, 0))
	if index < 0 or index >= _remembered.size():
		return {}
	return {"pad": int(_remembered[index])}
