class_name HotPotatoBrain
extends BotBrain
## Hot Potato archetype (M19-02, #686): flee the carrier when someone else
## has the bomb; when you're holding it, hunt the nearest rival to pass it off
## before the fuse blows. Snapshot: {players: {slot: [x, y]}, carrier, fuse,
## alive: [slot, ...], holds: {slot: seconds}}. Input: {mx, my} only.


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
	return move_away_from_point(me, carrier_pos)


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
	if state.size() < 2:
		return Vector2.INF
	return Vector2(float(state[0]), float(state[1]))
