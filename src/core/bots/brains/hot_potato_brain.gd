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
## Anti-stacking (#926): fleers within this range push off each other so five
## bots don't smear into one corner; the orbit push curves a wall-bound flee
## along the boundary instead of pinning into it.
const SEPARATION_RADIUS := 3.0
const SEPARATION_WEIGHT := 1.1
const ORBIT_WEIGHT := 0.9


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
	var dir := _flee_dir(me, carrier_pos, players, alive, carrier)
	return {"mx": dir.x, "my": dir.y}


## Direction away from the carrier, spread from other fleers and curved along
## the boundary. Pure radial in the open (unchanged from #715); near a wall it
## gains a tangential orbit push, and crowded fleers repel each other so a whole
## pack doesn't smear into one corner (#926). Wall-hugging axes are still zeroed
## so a pinned bot slides along the edge instead of freezing into it (#715).
func _flee_dir(
	me: Vector2, carrier_pos: Vector2, players: Dictionary, alive: Array, carrier: int
) -> Vector2:
	var away_vec := me - carrier_pos
	var away := Vector2.RIGHT if away_vec.length() < 0.001 else away_vec.normalized()
	var dir := away + _separation(me, players, alive, carrier) * SEPARATION_WEIGHT
	if _near_wall(me):
		# Tangential to the carrier bearing, turned toward the open middle, so a
		# flee that would pin us to the wall curves along it instead.
		var tangent := Vector2(-away.y, away.x)
		if tangent.dot(-me) < 0.0:
			tangent = -tangent
		dir += tangent * ORBIT_WEIGHT
	var bound := HotPotato.ARENA_HALF - WALL_MARGIN
	if (dir.x > 0.0 and me.x >= bound) or (dir.x < 0.0 and me.x <= -bound):
		dir.x = 0.0
	if (dir.y > 0.0 and me.y >= bound) or (dir.y < 0.0 and me.y <= -bound):
		dir.y = 0.0
	if dir.length() < 0.001:
		# Cornered on both axes: run perpendicular to the carrier bearing
		# rather than freezing at (0, 0).
		dir = Vector2(-away_vec.y, away_vec.x)
		if dir.length() < 0.001:
			dir = Vector2.RIGHT
	return dir.normalized()


## True when within WALL_MARGIN of either square boundary.
func _near_wall(me: Vector2) -> bool:
	var edge := HotPotato.ARENA_HALF - WALL_MARGIN
	return absf(me.x) >= edge or absf(me.y) >= edge


## Summed push away from other live, non-carrier fleers within SEPARATION_RADIUS,
## falling off linearly with distance — the anti-corner-stacking term (#926).
func _separation(me: Vector2, players: Dictionary, alive: Array, carrier: int) -> Vector2:
	var push := Vector2.ZERO
	for other: int in alive:
		if other == slot or other == carrier:
			continue
		var pos := _pos_of(players, other)
		if pos == Vector2.INF:
			continue
		var offset := me - pos
		var dist := offset.length()
		if dist > 0.001 and dist < SEPARATION_RADIUS:
			push += offset.normalized() * (1.0 - dist / SEPARATION_RADIUS)
	return push


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
