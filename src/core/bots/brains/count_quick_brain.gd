class_name CountQuickBrain
extends BotBrain
## Counting archetype (M19-02, #686): count the swarm while it's visible
## (FLASH — the swarm array IS the on-screen dots, so reading its size is the
## bot equivalent of counting what a human sees, not a sim-state peek), then
## run to the matching pad (ANSWER) and stay on it. Snapshot: {phase, players:
## {slot: [x, y, score, answer]}, swarm: [[x,y],...] (FLASH only), pads:
## [[x,y,value],...] (ANSWER only)}. Input: {mx, my} only — your pad at the
## buzzer is your answer (no lock-in, #799). Indices named via CountQuick.PS_*/
## PD_* (#708).

var _remembered_count := -1


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var state: Array = players.get(slot, [])
	if state.size() < CountQuick.PS_COUNT:
		return {}
	var phase := int(game.get("phase", CountQuick.Phase.FLASH))
	if phase == CountQuick.Phase.FLASH:
		var swarm: Array = game.get("swarm", [])
		if not swarm.is_empty():
			_remembered_count = swarm.size()
		return {}
	var me := Vector2(float(state[CountQuick.PS_X]), float(state[CountQuick.PS_Y]))
	for pad: Array in game.get("pads", []):
		if int(pad[CountQuick.PD_VALUE]) == _remembered_count:
			# Arrive within the pad and stop: move_toward_point emits an explicit
			# zero once inside PAD_RADIUS, which parks the bot on its answer. With
			# no lock-in an empty intent would instead leave it drifting off.
			return move_toward_point(
				me,
				Vector2(float(pad[CountQuick.PD_X]), float(pad[CountQuick.PD_Y])),
				CountQuick.PAD_RADIUS
			)
	return {}
