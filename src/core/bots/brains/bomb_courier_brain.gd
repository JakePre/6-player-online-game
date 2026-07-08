class_name BombCourierBrain
extends BotBrain
## Delivery-scramble archetype (M19-02, #686): grab a loose package, rush it to
## the depot — unless the fuse is critically low, in which case defuse for a
## safe partial score, or dash-dump it onto a nearby rival if one's in reach
## (the sim's own "everyone can play saboteur" mechanic, #252 — not a hidden
## role). Snapshot: {players: {slot: [x, y, score, fuse, staggered]}, pile:
## [[id, x, y, fuse], ...]}. Input: {mx, my} + {dash: true}. Indices named via
## BombCourier.PS_*/PL_* (#708).

## Below this much fuse left, a carried package is worth dumping on a rival
## rather than risking the walk to depot.
const DUMP_THRESHOLD := 1.5
## Below this, cut losses and defuse for the guaranteed scrap point instead
## of gambling on reaching the depot.
const DEFUSE_THRESHOLD := 1.0
## How close a rival needs to be for a dash-dump to be worth aiming at.
const DASH_REACT_RANGE := 3.0


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var state: Array = players.get(slot, [])
	if state.size() < BombCourier.PS_COUNT:
		return {}
	var me := Vector2(float(state[BombCourier.PS_X]), float(state[BombCourier.PS_Y]))
	var fuse := float(state[BombCourier.PS_FUSE])
	if fuse < 0.0:
		return _find_package(game, me)
	return _deliver(players, me, fuse)


## Carrying a package: dump it on a close rival if it's about to blow,
## otherwise race for the depot (or the defuse zone once it's nearly spent).
func _deliver(players: Dictionary, me: Vector2, fuse: float) -> Dictionary:
	if fuse < DUMP_THRESHOLD:
		var rival := _nearest_rival(players, me)
		if (
			rival != Vector2.INF
			and me.distance_squared_to(rival) <= DASH_REACT_RANGE * DASH_REACT_RANGE
		):
			var intent := move_toward_point(me, rival, 0.0)
			intent["dash"] = true
			return intent
	if fuse < DEFUSE_THRESHOLD:
		return move_toward_point(me, BombCourier.DEFUSE_POS, BombCourier.ZONE_RADIUS * 0.5)
	return move_toward_point(me, BombCourier.DEPOT_POS, BombCourier.ZONE_RADIUS * 0.5)


## Empty-handed: head for the nearest loose package. Pile entries are
## [id, x, y, fuse] — id leads, so nearest_point's [x, y, ...] assumption
## doesn't fit and this walks the list itself.
func _find_package(game: Dictionary, me: Vector2) -> Dictionary:
	var best := Vector2.INF
	var best_dist := INF
	for entry: Array in game.get("pile", []):
		var pos := Vector2(float(entry[BombCourier.PL_X]), float(entry[BombCourier.PL_Y]))
		var dist := me.distance_squared_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = pos
	if best == Vector2.INF:
		return {}
	return move_toward_point(me, best, BombCourier.PICKUP_RADIUS * 0.5)


func _nearest_rival(players: Dictionary, me: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_dist := INF
	for other: int in players:
		if other == slot:
			continue
		var state: Array = players[other]
		if state.size() <= BombCourier.PS_Y:
			continue
		var pos := Vector2(float(state[BombCourier.PS_X]), float(state[BombCourier.PS_Y]))
		var dist := me.distance_squared_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = pos
	return best
