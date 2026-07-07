class_name CartPushBrain
extends BotBrain
## Team tug-of-war archetype (M19-02, #686): push from our own side of the
## shared cart, detour for a close ore to bank a permanent bonus pusher,
## deliver a carried ore to our own depot, and shove an opposing pusher when
## one's in range. Team assignment (`teams`) is public in the snapshot, same
## as color_clash/snake_chain's team_mode games.
##
## Snapshot: {players: {slot: [x, y, flags]} (bit0 carrying, bit1 staggered,
## bit2 shove-windup), cart, teams: [[slot,...], [slot,...]], ores: [[id,x,y],
## ...]}. Input: {mx, my} + {"shove": true}.

const FLAG_CARRYING := 1
const FLAG_STAGGERED := 2
## How close a loose ore has to be before it's worth detouring for over
## staying on the cart.
const ORE_ATTRACT_RANGE := 4.0


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var state: Array = players.get(slot, [])
	if state.size() < 3:
		return {}
	var flags := int(state[2])
	if flags & FLAG_STAGGERED:
		return {}
	var me := Vector2(float(state[0]), float(state[1]))
	var teams: Array = game.get("teams", [])
	var team_index := _team_of(teams)
	if team_index == -1:
		return {}
	if flags & FLAG_CARRYING:
		var depot := Vector2(-CartPush.TRACK_END if team_index == 0 else CartPush.TRACK_END, 0.0)
		return move_toward_point(me, depot, CartPush.DEPOT_RADIUS * 0.5)
	var ore := _nearest_ore(game.get("ores", []), me)
	if ore != Vector2.INF and me.distance_to(ore) <= ORE_ATTRACT_RANGE:
		return move_toward_point(me, ore, CartPush.ORE_PICKUP_RADIUS * 0.5)
	return _push(game, players, teams, team_index, me)


## Park within reach of the cart on our own pushing side, shoving an opposing
## pusher the instant one's close enough.
func _push(
	game: Dictionary, players: Dictionary, teams: Array, team_index: int, me: Vector2
) -> Dictionary:
	var side := -1.0 if team_index == 0 else 1.0
	var cart_pos := Vector2(float(game.get("cart", 0.0)), 0.0)
	var push_spot := cart_pos + Vector2(side * CartPush.CART_REACH * 0.5, 0.0)
	var intent := move_toward_point(me, push_spot, 0.3)
	var rival := _nearest_on_team(players, teams[1 - team_index], me)
	if rival != Vector2.INF and me.distance_to(rival) <= CartPush.SHOVE_RANGE:
		intent["shove"] = true
	return intent


func _team_of(teams: Array) -> int:
	for i in teams.size():
		if slot in (teams[i] as Array):
			return i
	return -1


func _nearest_ore(ores: Array, me: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_dist := INF
	for ore: Array in ores:
		var pos := Vector2(float(ore[1]), float(ore[2]))
		var dist := me.distance_squared_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = pos
	return best


func _nearest_on_team(players: Dictionary, team: Array, me: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_dist := INF
	for other: int in team:
		var state: Array = players.get(other, [])
		if state.size() < 2:
			continue
		var pos := Vector2(float(state[0]), float(state[1]))
		var dist := me.distance_squared_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = pos
	return best
