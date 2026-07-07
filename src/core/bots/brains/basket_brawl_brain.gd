class_name BasketBrawlBrain
extends BotBrain
## Team ball-sport archetype (M19-02, #686): carry to the enemy hoop, chase a
## loose ball, hound an enemy carrier (shove in range), or run support toward
## the attack hoop while a teammate carries. Snapshot: {players: {slot: [x, y,
## has_ball]}, ball: [x, y, holder], teams: [[slot,...],[slot,...]], hoops:
## [[x,y],[x,y]]}. Input: {mx, my} + {"act": true} (shove near an enemy
## carrier; passing while carrying is left to chance — a straight run is the
## simpler, steadier play for a bot).


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var state: Array = players.get(slot, [])
	if state.size() < 3:
		return {}
	var me := Vector2(float(state[0]), float(state[1]))
	var teams: Array = game.get("teams", [])
	var team_index := _team_of(teams)
	if team_index == -1:
		return {}
	if int(state[2]) == 1:
		return move_toward_point(me, _attack_hoop(game, team_index), BasketBrawl.HOOP_RADIUS * 0.5)
	return _react_to_the_ball(game, players, teams, team_index, me)


## Nobody's carrying: chase the loose ball. A teammate carries: run support
## toward the attack hoop. An enemy carries: hound them, shoving in range.
func _react_to_the_ball(
	game: Dictionary, players: Dictionary, teams: Array, team_index: int, me: Vector2
) -> Dictionary:
	var ball: Array = game.get("ball", [0.0, 0.0, -1])
	var holder := int(ball[2])
	if holder == -1:
		return move_toward_point(me, Vector2(float(ball[0]), float(ball[1])), 0.0)
	if holder in (teams[team_index] as Array):
		return move_toward_point(me, _attack_hoop(game, team_index), 0.3)
	var carrier_state: Array = players.get(holder, [])
	if carrier_state.size() < 2:
		return {}
	var carrier_pos := Vector2(float(carrier_state[0]), float(carrier_state[1]))
	var intent := move_toward_point(me, carrier_pos, 0.0)
	if me.distance_to(carrier_pos) <= BasketBrawl.SHOVE_RADIUS:
		intent["act"] = true
	return intent


func _team_of(teams: Array) -> int:
	for i in teams.size():
		if slot in (teams[i] as Array):
			return i
	return -1


func _attack_hoop(game: Dictionary, team_index: int) -> Vector2:
	var hoops: Array = game.get("hoops", [[0.0, 0.0], [0.0, 0.0]])
	var enemy_hoop: Array = hoops[1 - team_index]
	return Vector2(float(enemy_hoop[0]), float(enemy_hoop[1]))
