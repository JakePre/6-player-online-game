class_name FishFrenzyBrain
extends BotBrain
## Rhythm-lane archetype (M19-02, #686): stand in the lane of the
## soonest-arriving fish. Snapshot: {players: {slot: [lane, caught, streak]},
## fish: [[lane, seconds_to_arrival], ...], swim_sec}. Input: {"lane": 0..2}.
## Indices named via FishFrenzy.PS_*/FL_* (#708).


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var fish: Array = game.get("fish", [])
	if fish.is_empty():
		return {}
	var soonest_lane := -1
	var soonest_time := INF
	for entry: Array in fish:
		var arrival := float(entry[FishFrenzy.FL_ARRIVES])
		if arrival < soonest_time:
			soonest_time = arrival
			soonest_lane = int(entry[FishFrenzy.FL_LANE])
	if soonest_lane == -1:
		return {}
	return {"lane": soonest_lane}
