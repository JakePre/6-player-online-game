class_name KnockOffBrain
extends BotBrain
## Platform-brawler archetype (M19-02, #686): approach the nearest rival on the
## small floating stage, jab to build their percent and smash to launch them
## off once it's high — while never chasing off the edge into the void, and
## recovering back toward center if knocked out over it.
##
## Snapshot: {players: {slot: [x, y, facing, alive, percent, attack]}, phase,
## phase_left} (KnockOff). Phase: 0 COUNTDOWN, 1 FIGHT, 2 DONE. Input:
## {mx} (also sets facing), {jump}, {jab}, {smash}. Stage geometry is static.

## Stay this far inside the platform edge so a nudge never walks us off.
const EDGE_MARGIN := 0.8
## Smash (big launch, slow) once a rival's percent can actually KO; jab (fast,
## builds percent) below it.
const SMASH_PERCENT := 55.0
## Recover if we've fallen this far below the platform surface (top ≈ 0).
const FELL_BELOW := -1.2


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	if int(game.get("phase", KnockOff.Phase.COUNTDOWN)) != KnockOff.Phase.FIGHT:
		return {}
	var players: Dictionary = game.get("players", {})
	var me: Array = players.get(slot, [])
	if me.size() < 5 or int(me[3]) == 0:
		return {}
	var my_pos := Vector2(float(me[0]), float(me[1]))
	var edge := KnockOff.STAGE_HALF_WIDTH - EDGE_MARGIN
	# Recovery: knocked off the side or falling below — get back over center.
	if absf(my_pos.x) > KnockOff.STAGE_HALF_WIDTH or my_pos.y < FELL_BELOW:
		var toward := -signf(my_pos.x)
		return {"mx": toward, "jump": true}
	var rival := _nearest_rival(players, my_pos)
	if rival.is_empty():
		return {"mx": -signf(my_pos.x) * 0.3}  # ease toward center, keep safe
	var rival_pos := Vector2(float(rival[0]), float(rival[1]))
	var dx := rival_pos.x - my_pos.x
	var dy := rival_pos.y - my_pos.y
	var facing_dir := signf(dx) if absf(dx) > 0.01 else 1.0
	# In striking range and roughly level: face the rival and attack.
	if absf(dx) <= KnockOff.ATTACK_RANGE and absf(dy) <= KnockOff.ATTACK_HALF_HEIGHT:
		var intent := {"mx": facing_dir * 0.4}  # nudge to set facing, hold ground
		if int(rival[4]) >= int(SMASH_PERCENT):
			intent["smash"] = true
		else:
			intent["jab"] = true
		return intent
	# Approach — but clamp the target inside the stage so we never pursue a
	# rival out over the void.
	var target_x := clampf(rival_pos.x, -edge, edge)
	var intent := {"mx": signf(target_x - my_pos.x)}
	if dy > 1.0:
		intent["jump"] = true  # rival is up on the high platform
	return intent


func _nearest_rival(players: Dictionary, from: Vector2) -> Array:
	var best: Array = []
	var best_distance := INF
	for other: int in players:
		if other == slot:
			continue
		var state: Array = players[other]
		if state.size() < 5 or int(state[3]) == 0:
			continue
		var distance := from.distance_squared_to(Vector2(float(state[0]), float(state[1])))
		if distance < best_distance:
			best_distance = distance
			best = state
	return best
