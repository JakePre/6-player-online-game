class_name RumbleRingBrain
extends BotBrain
## Brawler archetype (M19-02, #686): hunt the nearest rival, swing once in
## range. Cooldowns aren't exposed in the snapshot, so it swings on every poll
## it's in range — the sim silently no-ops mid-cooldown, the same tolerance
## every other cooldown-blind brain (sumo_smash, nom_arena) relies on.
## Snapshot: {players: {slot: [x, y, hp, points, guarding, invuln, facing_x,
## facing_y]}, coins, events}. Input: {mx, my} or {"attack": true}.


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var me := my_position(players)
	if me == Vector2.INF:
		return {}
	var rival := _nearest_rival(players, me)
	if rival == Vector2.INF:
		return {}
	if me.distance_to(rival) <= RumbleRing.SWING_RANGE:
		return {"attack": true}
	return move_toward_point(me, rival, 0.0)


func _nearest_rival(players: Dictionary, me: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_dist := INF
	for other: int in players:
		if other == slot:
			continue
		var state: Array = players[other]
		if state.size() < 2:
			continue
		var pos := Vector2(float(state[0]), float(state[1]))
		var dist := me.distance_squared_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = pos
	return best
