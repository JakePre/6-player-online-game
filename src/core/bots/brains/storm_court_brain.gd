class_name StormCourtBrain
extends GauntletBrain
## Storm Court finale archetype (#936): the shop phase is inherited unchanged
## from GauntletBrain (survivability-first buying, then confirm) — only the
## showdown thinking differs. Armed: close on the nearest rival and throw in
## range. Unarmed with a ball incoming: buffer a catch and back away (the
## two-life swing is the best play in the game). Otherwise: race the nearest
## loose ball. Snapshot: {radius, players: {slot: [x, y, fx, fy, lives,
## holding, invuln, hit_seq, catch_seq]}, balls: [[x, y, state, holder]],
## strikes} (StormCourt, #708 named indices).

## Throw when the nearest rival is inside this range — comfortably shorter
## than a THROW_SPEED ball's useful flight on the shrinking court.
const THROW_RANGE := 6.5
## A FLYING ball this close is worth a catch buffer + evasive drift.
const INCOMING_RANGE := 3.0


func _think_play(game: Dictionary) -> Dictionary:
	var players: Dictionary = game.get("players", {})
	var my_state: Array = players.get(slot, [])
	if my_state.size() < StormCourt.PS_COUNT:
		return {}  # eliminated — nothing to do in a royale
	var me := Vector2(float(my_state[StormCourt.PS_X]), float(my_state[StormCourt.PS_Y]))
	var balls: Array = game.get("balls", [])
	if int(my_state[StormCourt.PS_HOLDING]) == 1:
		return _hunt(players, me)
	var incoming := _nearest_flying(balls, me)
	if incoming != Vector2.INF and me.distance_to(incoming) <= INCOMING_RANGE:
		# Buffer the catch AND drift away — either outcome beats standing still.
		var intent := move_away_from_point(me, incoming)
		intent["act"] = true
		return intent
	var loose := _nearest_loose(balls, me)
	if loose != Vector2.INF:
		return move_toward_point(me, loose, 0.0)
	return {}


## Armed: chase the nearest living rival, throwing once they're in range —
## the sim throws along the move heading, so driving at them IS the aim.
func _hunt(players: Dictionary, me: Vector2) -> Dictionary:
	var best := Vector2.INF
	var best_dist := INF
	for other: int in players:
		if other == slot:
			continue
		var state: Array = players[other]
		var pos := Vector2(float(state[StormCourt.PS_X]), float(state[StormCourt.PS_Y]))
		var dist := me.distance_squared_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = pos
	if best == Vector2.INF:
		return {}
	var intent := move_toward_point(me, best, 0.0)
	if me.distance_to(best) <= THROW_RANGE:
		intent["act"] = true
	return intent


func _nearest_flying(balls: Array, me: Vector2) -> Vector2:
	return _nearest_ball(balls, me, StormCourt.BallState.FLYING)


func _nearest_loose(balls: Array, me: Vector2) -> Vector2:
	return _nearest_ball(balls, me, StormCourt.BallState.LOOSE)


func _nearest_ball(balls: Array, me: Vector2, wanted_state: int) -> Vector2:
	var best := Vector2.INF
	var best_dist := INF
	for ball: Array in balls:
		if int(ball[StormCourt.BL_STATE]) != wanted_state:
			continue
		var pos := Vector2(float(ball[StormCourt.BL_X]), float(ball[StormCourt.BL_Y]))
		var dist := me.distance_squared_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = pos
	return best
