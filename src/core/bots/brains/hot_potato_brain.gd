class_name HotPotatoBrain
extends BotBrain
## Hot Potato archetype (M19-02, #686): flee the carrier when someone else
## has the bomb; when you're holding it, hunt the nearest rival to pass it off
## before the fuse blows. Snapshot: {players: {slot: [x, y]}, carrier, fuse,
## alive: [slot, ...], holds: {slot: seconds}}. Input: {mx, my} only. Indices
## named via HotPotato.PS_* (#708).
##
## Wall-aware fleeing (#715): fleeing used to aim straight away from the
## carrier with no regard for the arena edge, so a bot already near the
## boundary — chased by a carrier 10% faster (CARRIER_SPEED_MULT) — could get
## pinned in a corner with no escape vector. _flee_dir zeroes whichever axis
## would drive further into a wall already at the boundary, so the bot slides
## along it instead of pushing uselessly into it.

## How close to the boundary counts as "against the wall".
const WALL_MARGIN := 0.6


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var alive: Array = game.get("alive", [])
	if slot not in alive:
		return {}
	var players: Dictionary = game.get("players", {})
	var me := my_position(players)
	if me == Vector2.INF:
		return {}
	var carrier := int(game.get("carrier", -1))
	if carrier == slot:
		return _hunt(players, me, alive)
	if carrier == -1:
		return {}
	var carrier_pos := _pos_of(players, carrier)
	if carrier_pos == Vector2.INF:
		return {}
	var dir := _flee_dir(me, carrier_pos)
	return {"mx": dir.x, "my": dir.y}


## Direction away from the carrier, with wall-hugging axes zeroed so a bot
## already pinned against the boundary slides along it instead of freezing
## into the corner (#715).
func _flee_dir(me: Vector2, carrier_pos: Vector2) -> Vector2:
	var away := me - carrier_pos
	var dir := Vector2.RIGHT if away.length() < 0.001 else away.normalized()
	var bound := HotPotato.ARENA_HALF - WALL_MARGIN
	if (dir.x > 0.0 and me.x >= bound) or (dir.x < 0.0 and me.x <= -bound):
		dir.x = 0.0
	if (dir.y > 0.0 and me.y >= bound) or (dir.y < 0.0 and me.y <= -bound):
		dir.y = 0.0
	if dir.length() < 0.001:
		# Cornered on both axes: run perpendicular to the carrier bearing
		# rather than freezing at (0, 0).
		dir = Vector2(-away.y, away.x)
		if dir.length() < 0.001:
			dir = Vector2.RIGHT
	return dir.normalized()


## Head straight for whoever's nearest — the carrier moves faster (#hot_potato
## CARRIER_SPEED_MULT) so closing on a fleeing rival needs a beeline, not a
## cautious approach.
func _hunt(players: Dictionary, me: Vector2, alive: Array) -> Dictionary:
	var best := Vector2.INF
	var best_dist := INF
	for other: int in alive:
		if other == slot:
			continue
		var pos := _pos_of(players, other)
		if pos == Vector2.INF:
			continue
		var dist := me.distance_squared_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = pos
	if best == Vector2.INF:
		return {"mx": 0.0, "my": 0.0}
	return move_toward_point(me, best, 0.0)


func _pos_of(players: Dictionary, other: int) -> Vector2:
	var state: Array = players.get(other, [])
	if state.size() < HotPotato.PS_COUNT:
		return Vector2.INF
	return Vector2(float(state[HotPotato.PS_X]), float(state[HotPotato.PS_Y]))
