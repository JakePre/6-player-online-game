class_name PickpocketPlazaBrain
extends BotBrain
## Hidden-role archetype (M19-02, #686): one slot is the GUARD, told only via
## the private snapshot which crowd body it secretly puppets (#254, the same
## hook The Mole uses). The brain branches on that role.
##
## GUARD: hunt the nearest arrestable SUSPECT (a thief still inside its
## post-lift window) with the puppeted body and fire the arrest once in range;
## with no suspect, shadow the nearest thief so we're on them the instant they
## lift. THIEF: stand on the nearest villager to lift a coin, but the moment we
## become a SUSPECT any body could be the guard — break away from the nearest
## one until the window passes, then get back to work.
##
## Snapshot: {crowd: [[x, y], ...], thieves: {slot: [x, y, stunned, suspect]},
## guard (slot), scores, alarm, time_left} (PickpocketPlaza). Guard private:
## {role: "guard", body: <crowd index>}. Input: {mx, my, act}. Indices named
## via PickpocketPlaza.CR_*/TH_* (#708).

const ARREST_RANGE := PickpocketPlaza.ARREST_RADIUS


func think(match_state: Dictionary, private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	if private.get("role", "") == "guard":
		return _guard(game, int(private.get("body", -1)))
	return _thief(game)


func _guard(game: Dictionary, body: int) -> Dictionary:
	var crowd: Array = game.get("crowd", [])
	if body < 0 or body >= crowd.size():
		return {}
	var me := Vector2(
		float(crowd[body][PickpocketPlaza.CR_X]), float(crowd[body][PickpocketPlaza.CR_Y])
	)
	var thieves: Dictionary = game.get("thieves", {})
	# Close on the nearest arrestable suspect; trip the arrest once in range.
	var suspect := _nearest_suspect(thieves, me)
	if suspect != Vector2.INF:
		var intent := move_toward_point(me, suspect, 0.0)
		intent["act"] = me.distance_to(suspect) <= ARREST_RANGE
		return intent
	# Nobody arrestable yet: hover on the nearest thief, ready for their lift.
	var mark := _nearest_thief(thieves, me)
	return move_toward_point(me, mark, 0.6) if mark != Vector2.INF else {}


func _thief(game: Dictionary) -> Dictionary:
	var thieves: Dictionary = game.get("thieves", {})
	var me_state: Array = thieves.get(slot, [])
	if me_state.size() < PickpocketPlaza.TH_COUNT:
		return {}
	if int(me_state[PickpocketPlaza.TH_STUN]) == 1:
		return {}  # stunned — frozen, nothing to do
	var me := Vector2(float(me_state[PickpocketPlaza.TH_X]), float(me_state[PickpocketPlaza.TH_Y]))
	var crowd: Array = game.get("crowd", [])
	if int(me_state[PickpocketPlaza.TH_SUSPECT]) == 1:
		# Arrestable: any body could be the guard, so break away from the
		# nearest one and let the suspect window burn down.
		var threat := _nearest_body(crowd, me)
		return move_away_from_point(me, threat) if threat != Vector2.INF else {}
	# Clear to work: stand on the nearest villager and lift.
	var mark := _nearest_body(crowd, me)
	return move_toward_point(me, mark, 0.4) if mark != Vector2.INF else {}


## Nearest thief that's currently a suspect and not already stunned.
func _nearest_suspect(thieves: Dictionary, from: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_distance := INF
	for other: int in thieves:
		var state: Array = thieves[other]
		if (
			state.size() < PickpocketPlaza.TH_COUNT
			or int(state[PickpocketPlaza.TH_STUN]) == 1
			or int(state[PickpocketPlaza.TH_SUSPECT]) == 0
		):
			continue
		var pos := Vector2(float(state[PickpocketPlaza.TH_X]), float(state[PickpocketPlaza.TH_Y]))
		var distance := from.distance_squared_to(pos)
		if distance < best_distance:
			best_distance = distance
			best = pos
	return best


## Nearest thief that can still move (skip the stunned — they're going nowhere).
func _nearest_thief(thieves: Dictionary, from: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_distance := INF
	for other: int in thieves:
		var state: Array = thieves[other]
		if state.size() <= PickpocketPlaza.TH_STUN or int(state[PickpocketPlaza.TH_STUN]) == 1:
			continue
		var pos := Vector2(float(state[PickpocketPlaza.TH_X]), float(state[PickpocketPlaza.TH_Y]))
		var distance := from.distance_squared_to(pos)
		if distance < best_distance:
			best_distance = distance
			best = pos
	return best


func _nearest_body(crowd: Array, from: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_distance := INF
	for body: Array in crowd:
		if body.size() <= PickpocketPlaza.CR_Y:
			continue
		var pos := Vector2(float(body[PickpocketPlaza.CR_X]), float(body[PickpocketPlaza.CR_Y]))
		var distance := from.distance_squared_to(pos)
		if distance < best_distance:
			best_distance = distance
			best = pos
	return best
