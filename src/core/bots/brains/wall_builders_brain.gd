class_name WallBuildersBrain
extends BotBrain
## Team-economy archetype (M19-02, #686): carry blocks home, prioritized —
## deliver whatever we're already carrying, else grab the nearest floor block,
## else pry a block off the enemy wall (continuous contact does the stealing;
## no button needed), else hold when there's nothing productive to do.
##
## Snapshot: {players: {slot: [x, y, carrying]}, blocks: [[x, y], ...],
## walls: [team0_height, team1_height], wall_x, teams: [[slot, ...],
## [slot, ...]]} (WallBuilders). Input: {mx, my}.


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var me_state: Array = players.get(slot, [])
	if me_state.size() < 3:
		return {}
	var me := Vector2(float(me_state[0]), float(me_state[1]))
	var teams: Array = game.get("teams", [])
	var my_team := _team_of(slot, teams)
	if my_team == -1:
		return {}
	if int(me_state[2]) == 1:
		return move_toward_point(me, _wall_pos(my_team, game), 0.4)
	var block := nearest_point(me, game.get("blocks", []))
	if block != Vector2.INF:
		return move_toward_point(me, block, 0.0)
	var enemy := 1 - my_team
	var walls: Array = game.get("walls", [0, 0])
	if enemy < walls.size() and int(walls[enemy]) > 0:
		return move_toward_point(me, _wall_pos(enemy, game), 0.0)
	return {}  # nothing to grab and nothing worth stealing yet


## 0/1 for the team roster containing `target_slot`, or -1 if in neither.
func _team_of(target_slot: int, teams: Array) -> int:
	for i in teams.size():
		if target_slot in teams[i]:
			return i
	return -1


func _wall_pos(team_index: int, game: Dictionary) -> Vector2:
	var wall_x := float(game.get("wall_x", WallBuilders.WALL_X))
	return Vector2(-wall_x if team_index == 0 else wall_x, 0.0)
