class_name ShockTagBrain
extends BotBrain
## Shock Tag archetype (M19-02, #686): flee the zapped player to keep banking
## clean coins; when zapped, chase whoever's carrying the most coins — passing
## the zap onto a fat target drains the most value. Snapshot: {players:
## {slot: [x, y, coins]}, zapped}. Input: {mx, my} only. Indices named via
## ShockTag.PS_* (#708).


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
	return move_away_from_point(me, zapped_pos)


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
