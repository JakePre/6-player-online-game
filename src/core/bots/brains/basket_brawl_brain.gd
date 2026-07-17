class_name BasketBrawlBrain
extends BotBrain
## Team ball-sport archetype (M19-02, #686; #1037 2K offense): carry toward
## the enemy hoop, drive the dunk when the lane is short, otherwise pull up —
## start the wind-up, hold into the sweet window, release. Off the ball:
## chase a loose ball, hound an enemy carrier (shove only in range — a whiff
## staggers, #1037), run support while a teammate carries. Snapshot: {players:
## {slot: [x, y, has_ball, charge]}, ball: [x, y, holder, shot], teams, hoops}.
## Input: {mx, my} + {"act": true} + {"shoot": true/false} press/release.
## Indices named via BasketBrawl.PS_*/BALL_*/HP_* (#708).

## Pull up only inside this range with no defender contesting; from beyond
## the arc the made shot pays 3, so range shooting beats a long drive.
const PULL_UP_DIST := BasketBrawl.SHOT_FAR_DIST


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var state: Array = players.get(slot, [])
	if state.size() < BasketBrawl.PS_COUNT:
		return {}
	var me := Vector2(float(state[BasketBrawl.PS_X]), float(state[BasketBrawl.PS_Y]))
	var teams: Array = game.get("teams", [])
	var team_index := _team_of(teams)
	if team_index == -1:
		return {}
	if int(state[BasketBrawl.PS_HAS_BALL]) == 1:
		return _run_the_offense(game, state, me, team_index)
	return _react_to_the_ball(game, players, teams, team_index, me)


## The 2K possession (#1037): mid-wind-up the carrier is rooted anyway, so
## just watch the replicated charge and release inside the sweet window (the
## ~4Hz think cadence steps the fraction ~0.28 per look — it lands). Off the
## wind-up: drive point-blank for the dunk, pull up when in range and open.
func _run_the_offense(game: Dictionary, state: Array, me: Vector2, team_index: int) -> Dictionary:
	var charge := float(state[BasketBrawl.PS_CHARGE])
	if charge > 0.0:
		if charge >= BasketBrawl.PERFECT_LO:
			return {"shoot": false}
		return {"shoot": true}
	var hoop := _attack_hoop(game, team_index)
	var dist := me.distance_to(hoop)
	var intent := move_toward_point(me, hoop, BasketBrawl.HOOP_RADIUS * 0.5)
	if dist <= BasketBrawl.HOOP_RADIUS * 1.5:
		return intent
	if dist <= PULL_UP_DIST and not _contested(game, me, team_index):
		intent["shoot"] = true
	return intent


## A defender inside CONTEST_RADIUS halves the make odds (#1037) — the brain
## keeps driving instead of hoisting a contested brick.
func _contested(game: Dictionary, me: Vector2, team_index: int) -> bool:
	var players: Dictionary = game.get("players", {})
	var teams: Array = game.get("teams", [])
	for other: int in players:
		if other == slot or other in (teams[team_index] as Array):
			continue
		var other_state: Array = players[other]
		var pos := Vector2(
			float(other_state[BasketBrawl.PS_X]), float(other_state[BasketBrawl.PS_Y])
		)
		if me.distance_to(pos) <= BasketBrawl.CONTEST_RADIUS:
			return true
	return false


## Nobody's carrying: chase the loose ball. A teammate carries: run support
## toward the attack hoop. An enemy carries: hound them, shoving in range.
func _react_to_the_ball(
	game: Dictionary, players: Dictionary, teams: Array, team_index: int, me: Vector2
) -> Dictionary:
	var ball: Array = game.get("ball", [0.0, 0.0, -1])
	var holder := int(ball[BasketBrawl.BALL_HOLDER])
	if holder == -1:
		return move_toward_point(
			me, Vector2(float(ball[BasketBrawl.BALL_X]), float(ball[BasketBrawl.BALL_Y])), 0.0
		)
	if holder in (teams[team_index] as Array):
		return move_toward_point(me, _attack_hoop(game, team_index), 0.3)
	var carrier_state: Array = players.get(holder, [])
	if carrier_state.size() <= BasketBrawl.PS_Y:
		return {}
	var carrier_pos := Vector2(
		float(carrier_state[BasketBrawl.PS_X]), float(carrier_state[BasketBrawl.PS_Y])
	)
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
	return Vector2(float(enemy_hoop[BasketBrawl.HP_X]), float(enemy_hoop[BasketBrawl.HP_Y]))
