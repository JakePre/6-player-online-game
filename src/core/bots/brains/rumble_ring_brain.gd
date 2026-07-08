class_name RumbleRingBrain
extends BotBrain
## Brawler archetype (M19-02, #686): hunt the nearest rival, swing once in
## range and off cooldown. Cooldowns aren't exposed in the snapshot, so this
## mirrors RumbleRing.SWING_COOLDOWN_SEC locally (#715) instead of firing
## "attack" on every poll it's in range: rumble_ring.gd's _handle_input is a
## mutually-exclusive if/return chain, so an "attack" input — even one the
## sim silently no-ops mid-cooldown — drops that tick's movement/facing
## update. At a 0.6s cooldown against a 0.25s poll, spamming attack meant the
## bot stood still with stale facing for most of every chase, right when it
## was closest to landing a hit. Tracking the rival on cooldown polls keeps
## facing (the 180° frontal arc check) current for when the swing fires.
## Snapshot: {players: {slot: [x, y, hp, points, guarding, invuln, facing_x,
## facing_y]}, coins, events}. Input: {mx, my} or {"attack": true}. Indices
## named via RumbleRing.PS_* (#708).

var _swing_cd := 0.0


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	_swing_cd = maxf(_swing_cd - NetManager.BOT_INPUT_INTERVAL_SEC, 0.0)
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var me := my_position(players)
	if me == Vector2.INF:
		return {}
	var rival := _nearest_rival(players, me)
	if rival == Vector2.INF:
		return {}
	if _swing_cd <= 0.0 and me.distance_to(rival) <= RumbleRing.SWING_RANGE:
		_swing_cd = RumbleRing.SWING_COOLDOWN_SEC
		return {"attack": true}
	return move_toward_point(me, rival, 0.0)


func _nearest_rival(players: Dictionary, me: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_dist := INF
	for other: int in players:
		if other == slot:
			continue
		var state: Array = players[other]
		if state.size() <= RumbleRing.PS_Y:
			continue
		var pos := Vector2(float(state[RumbleRing.PS_X]), float(state[RumbleRing.PS_Y]))
		var dist := me.distance_squared_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = pos
	return best
