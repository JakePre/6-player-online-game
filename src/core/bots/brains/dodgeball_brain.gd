class_name DodgeballBrain
extends BotBrain
## Dodgeball archetype (#791): grab a loose ball, aim at the nearest hostile
## (leading their motion a touch so throws connect), and hurl. Empty-handed and
## with a hostile ball incoming, it flees — and *sometimes* attempts a catch,
## the tunable imperfection knob (#715/#818): a perfect always-catch bot would
## make throwing pointless, so a bot only tries when it's already the target and
## rolls under CATCH_CHANCE.
##
## Snapshot: {players: {slot: [x, y, fx, fy, holding, team]}, balls: [[x, y,
## state, holder]], team_mode}. Input: {mx, my} to steer, {act: true} to
## grab/throw/catch. Indices via Dodgeball.PS_*/BL_*.

## How often the bot attempts a catch when a hostile ball is bearing down —
## low on purpose so catches stay a highlight, not the default outcome.
const CATCH_CHANCE := 0.35
## A hostile flying ball closer than this (world units) is "incoming".
const INCOMING_RANGE := 4.5
## Lead the target's aim by this fraction of the distance along their facing.
const LEAD_FACTOR := 0.25


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var state: Array = players.get(slot, [])
	if state.size() < Dodgeball.PS_COUNT:
		return {}  # eliminated or not in this round
	var me := Vector2(float(state[Dodgeball.PS_X]), float(state[Dodgeball.PS_Y]))
	var team_mode := bool(game.get("team_mode", false))
	var my_team := int(state[Dodgeball.PS_TEAM])
	var balls: Array = game.get("balls", [])

	if int(state[Dodgeball.PS_HOLDING]) == 1:
		return _aim_and_throw(me, players, team_mode, my_team)

	var incoming := _incoming_ball(me, balls)
	if incoming != Vector2.INF:
		# Under threat: try a catch sometimes, otherwise dodge sideways.
		if rng.randf() < CATCH_CHANCE:
			return {"act": true}
		return _dodge(me, incoming)

	var loose := _nearest_loose_ball(me, balls)
	if loose != Vector2.INF:
		var intent := move_toward_point(me, loose, 0.5)
		intent["act"] = true  # grab on contact; harmless while still approaching
		return intent
	return {}


## Face the nearest hostile (led along their facing) and throw. The sim reads
## facing from movement, so steer toward the aim point and fire the same tick.
func _aim_and_throw(me: Vector2, players: Dictionary, team_mode: bool, my_team: int) -> Dictionary:
	var target := _nearest_hostile(me, players, team_mode, my_team)
	if target == Vector2.INF:
		return {"act": true}  # no one to aim at — just lob it downrange
	var aim := (target - me).normalized()
	return {"mx": aim.x, "my": aim.y, "act": true}


func _nearest_hostile(me: Vector2, players: Dictionary, team_mode: bool, my_team: int) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	for other: int in players:
		if other == slot:
			continue
		var os: Array = players[other]
		if os.size() < Dodgeball.PS_COUNT:
			continue
		if team_mode and int(os[Dodgeball.PS_TEAM]) == my_team:
			continue
		var pos := Vector2(float(os[Dodgeball.PS_X]), float(os[Dodgeball.PS_Y]))
		var facing := Vector2(float(os[Dodgeball.PS_FACING_X]), float(os[Dodgeball.PS_FACING_Y]))
		var d := me.distance_to(pos)
		if d < best_d:
			best_d = d
			best = pos + facing * (d * LEAD_FACTOR)
	return best


func _nearest_loose_ball(me: Vector2, balls: Array) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	for ball: Array in balls:
		if int(ball[Dodgeball.BL_STATE]) != Dodgeball.BallState.LOOSE:
			continue
		var pos := Vector2(float(ball[Dodgeball.BL_X]), float(ball[Dodgeball.BL_Y]))
		var d := me.distance_to(pos)
		if d < best_d:
			best_d = d
			best = pos
	return best


## The nearest flying ball within INCOMING_RANGE, or INF. A ball's thrower/team
## isn't in the snapshot once it's airborne, so every flying ball in range is
## treated as a threat — a teammate's ball whizzing past just makes the bot flinch,
## which reads fine.
func _incoming_ball(me: Vector2, balls: Array) -> Vector2:
	for ball: Array in balls:
		if int(ball[Dodgeball.BL_STATE]) != Dodgeball.BallState.FLYING:
			continue
		var pos := Vector2(float(ball[Dodgeball.BL_X]), float(ball[Dodgeball.BL_Y]))
		if me.distance_to(pos) <= INCOMING_RANGE:
			return pos
	return Vector2.INF


## Sidestep perpendicular to the incoming ball's line, away from where it's
## heading — a real dodge, not a straight retreat it can't win.
func _dodge(me: Vector2, ball_pos: Vector2) -> Dictionary:
	var toward := ball_pos - me
	if toward.length() < 0.01:
		return move_away_from_point(me, ball_pos)
	var perp := Vector2(-toward.y, toward.x).normalized()
	# Pick the perpendicular that also carries away from the ball.
	if (me + perp - ball_pos).length() < (me - perp - ball_pos).length():
		perp = -perp
	return {"mx": perp.x, "my": perp.y}
