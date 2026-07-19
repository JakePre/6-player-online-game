class_name ShockTagBrain
extends BotBrain
## Shock Tag archetype (M19-02, #686): flee the zapped player to keep banking
## clean coins; when zapped, chase whoever's carrying the most coins — passing
## the zap onto a fat target drains the most value. Snapshot: {players:
## {slot: [x, y, coins]}, zapped}. Input: {mx, my} only. Indices named via
## ShockTag.PS_* (#708).
##
## Fleeing is spread and rim-aware (#926): fleers repel each other so the pack
## doesn't smear into one spot, and near the circular boundary the flee curves
## along the rim instead of pressing uselessly into it (the old straight
## move_away_from_point pinned bots against the edge).

## How close to the circular boundary counts as "against the rim".
const WALL_MARGIN := 0.6
## Anti-stacking + rim-orbit weights (#926), matching the hot_potato pattern.
const SEPARATION_RADIUS := 3.0
const SEPARATION_WEIGHT := 1.1
const ORBIT_WEIGHT := 0.9


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var me := my_position(players)
	if me == Vector2.INF:
		return {}
	var zapped := int(game.get("zapped", -1))
	if zapped == slot:
		return _chase_richest(players, me)
	var zapped_pos := _pos_of(players, zapped)
	if zapped_pos == Vector2.INF:
		return {"mx": 0.0, "my": 0.0}
	var dir := _flee_dir(me, zapped_pos, players, zapped)
	return {"mx": dir.x, "my": dir.y}


## Flee the zapped player, spread from other fleers and curved along the rim.
## Pure radial in the open; near the circular boundary it gains a tangential
## orbit push and drops the outward radial component so it slides along the edge
## rather than pinning into it (#926).
func _flee_dir(me: Vector2, threat_pos: Vector2, players: Dictionary, threat_slot: int) -> Vector2:
	var away_vec := me - threat_pos
	var away := Vector2.RIGHT if away_vec.length() < 0.001 else away_vec.normalized()
	var dir := away + _separation(me, players, threat_slot) * SEPARATION_WEIGHT
	if me.length() > ShockTag.ARENA_HALF - WALL_MARGIN:
		var radial := me.normalized()
		var tangent := Vector2(-away.y, away.x)
		if tangent.dot(-radial) < 0.0:
			tangent = -tangent
		dir += tangent * ORBIT_WEIGHT
		var outward := dir.dot(radial)
		if outward > 0.0:
			dir -= radial * outward  # slide along the rim, not into it
	if dir.length() < 0.001:
		dir = Vector2(-away_vec.y, away_vec.x)
		if dir.length() < 0.001:
			dir = Vector2.RIGHT
	return dir.normalized()


## Summed push away from other fleers (everyone but self and the zapped chaser)
## within SEPARATION_RADIUS, falling off linearly — the anti-stacking term (#926).
func _separation(me: Vector2, players: Dictionary, threat_slot: int) -> Vector2:
	var push := Vector2.ZERO
	for other: int in players:
		if other == slot or other == threat_slot:
			continue
		var pos := _pos_of(players, other)
		if pos == Vector2.INF:
			continue
		var offset := me - pos
		var dist := offset.length()
		if dist > 0.001 and dist < SEPARATION_RADIUS:
			push += offset.normalized() * (1.0 - dist / SEPARATION_RADIUS)
	return push


## Whoever's holding the most coins is the most valuable tag — go beeline for
## them rather than the nearest rival.
func _chase_richest(players: Dictionary, me: Vector2) -> Dictionary:
	var best := Vector2.INF
	var best_coins := -1
	for other: int in players:
		if other == slot:
			continue
		var state: Array = players[other]
		if state.size() < ShockTag.PS_COUNT:
			continue
		var coins := int(state[ShockTag.PS_COINS])
		if coins > best_coins:
			best_coins = coins
			best = Vector2(float(state[ShockTag.PS_X]), float(state[ShockTag.PS_Y]))
	if best == Vector2.INF:
		return {"mx": 0.0, "my": 0.0}
	return move_toward_point(me, best, 0.0)


func _pos_of(players: Dictionary, other: int) -> Vector2:
	var state: Array = players.get(other, [])
	if state.size() <= ShockTag.PS_Y:
		return Vector2.INF
	return Vector2(float(state[ShockTag.PS_X]), float(state[ShockTag.PS_Y]))
