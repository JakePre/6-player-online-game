class_name CartPushBrain
extends BotBrain
## Payload Race archetype (#932, reworked from the shared-cart tug M19-02): each
## bot mans its own lane's cart. Most teammates park at the cart and alternate
## ◀▶ to push it home; one designated saboteur per team peels off to the enemy
## lane and shoves their pushers off rhythm. Team assignment (`teams`) is public
## in the snapshot, same as color_clash/snake_chain's team_mode games.
##
## Snapshot: {players: {slot: [x, y, flags]} (bit0 staggered, bit1 windup, bit2
## pushing), carts: [prog0, prog1], teams: [[slot,...], [slot,...]]}. Input:
## {mx, my} + {"push": 0/1} (only alternations count) + {"shove": true}. Indices
## named via CartPush.PS_*/FLAG_* (#708).

## Alternate this each tick we're at the cart, so the sim sees a fresh ◀▶ flip.
var _phase := 0


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var state: Array = players.get(slot, [])
	if state.size() < CartPush.PS_COUNT:
		return {}
	if int(state[CartPush.PS_FLAGS]) & CartPush.FLAG_STAGGERED:
		return {}
	var me := Vector2(float(state[CartPush.PS_X]), float(state[CartPush.PS_Y]))
	var teams: Array = game.get("teams", [])
	var team_index := _team_of(teams)
	if team_index == -1:
		return {}
	if _is_saboteur(teams, team_index):
		return _sabotage(game, players, teams, team_index, me)
	return _push(game, team_index, me)


## Park at our own cart and alternate the push phase to advance it.
func _push(game: Dictionary, team_index: int, me: Vector2) -> Dictionary:
	var cart := _cart_pos(game, team_index)
	if me.distance_to(cart) > CartPush.CART_REACH * 0.75:
		return move_toward_point(me, cart, CartPush.CART_REACH * 0.5)
	_phase = 1 - _phase
	return {"mx": 0.0, "my": 0.0, "push": _phase}


## Peel off to the enemy lane and shove their nearest pusher when close enough.
func _sabotage(
	game: Dictionary, players: Dictionary, teams: Array, team_index: int, me: Vector2
) -> Dictionary:
	var target := _cart_pos(game, 1 - team_index)
	var intent := move_toward_point(me, target, 0.4)
	var rival := _nearest_on_team(players, teams[1 - team_index], me)
	if rival != Vector2.INF and me.distance_to(rival) <= CartPush.SHOVE_RANGE:
		intent["shove"] = true
	return intent


## Exactly one saboteur per team — the highest-numbered slot — but only once the
## team is big enough (3+) that it can spare a body from the mash.
func _is_saboteur(teams: Array, team_index: int) -> bool:
	var team: Array = teams[team_index]
	if team.size() < 3:
		return false
	return slot == team.max()


func _cart_pos(game: Dictionary, team_index: int) -> Vector2:
	var carts: Array = game.get("carts", [0.0, 0.0])
	var prog := float(carts[team_index]) if team_index < carts.size() else 0.0
	var lane := -CartPush.LANE_Y if team_index == 0 else CartPush.LANE_Y
	return Vector2(-CartPush.TRACK_HALF + prog, lane)


func _team_of(teams: Array) -> int:
	for i in teams.size():
		if slot in (teams[i] as Array):
			return i
	return -1


func _nearest_on_team(players: Dictionary, team: Array, me: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_dist := INF
	for other: int in team:
		var state: Array = players.get(other, [])
		if state.size() <= CartPush.PS_Y:
			continue
		var pos := Vector2(float(state[CartPush.PS_X]), float(state[CartPush.PS_Y]))
		var dist := me.distance_squared_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = pos
	return best
