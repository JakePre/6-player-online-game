class_name SumoSmashBrain
extends BotBrain
## Sumo Smash archetype (M19-02, #686): the Gauntlet's shove-and-ring-out idiom
## in miniature. Stay clear of the platform edge; when safely inside it, hunt
## the nearest rival and dash into them once close and off cooldown — a dash
## shove is 3x stronger (DASH_SHOVE_MULT) and is the only way to ring someone
## out from mid-platform. Snapshot: {radius, players: {slot: [x, y, cooldown,
## dashing]}}. Input: {mx, my} + {dash: true}.

## Distance from the rim at which self-preservation overrides the hunt.
const EDGE_MARGIN := 1.5
## Range at which a dash actually connects before the rival can juke away.
const DASH_RANGE := 2.2


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var state: Array = players.get(slot, [])
	if state.size() < 4:
		return {}
	var me := Vector2(float(state[0]), float(state[1]))
	var radius := float(game.get("radius", SumoSmash.PLATFORM_RADIUS))
	if me.length() > radius - EDGE_MARGIN:
		# Too close to the rim: retreat toward center outranks the hunt.
		return move_toward_point(me, Vector2.ZERO, 0.0)
	var rival := _nearest_rival(players, me)
	if rival == Vector2.INF:
		return {"mx": 0.0, "my": 0.0}
	var cooldown := float(state[2])
	var intent := move_toward_point(me, rival, 0.0)
	if cooldown <= 0.0 and me.distance_to(rival) <= DASH_RANGE:
		intent["dash"] = true
	return intent


func _nearest_rival(players: Dictionary, me: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_dist := INF
	for other: int in players:
		if other == slot:
			continue
		var state: Array = players[other]
		if state.size() < 2:
			continue
		var pos := Vector2(float(state[0]), float(state[1]))
		var dist := me.distance_squared_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = pos
	return best
