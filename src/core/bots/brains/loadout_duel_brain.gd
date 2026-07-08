class_name LoadoutDuelBrain
extends BotBrain
## Arena-weapon archetype (M19-02, #686): grab a weapon from the nearest armed
## dais when empty-handed, then face a level rival and fire — one hit KOs.
## Navigates the platform tiers (jump toward an elevated dais/target) and
## dodges an incoming shot.
##
## Snapshot: {players: {slot: [x, y, facing, flags, held]}, shots: [[x, y,
## kind], ...], daises: [[x, y, kind], ...]} (LoadoutDuel). flags bit0 alive.
## held: 0 NONE. Input: {mx} (sets facing), {jump}, {fire}, {throw}. Indices
## named via LoadoutDuel.PS_*/SH_*/DS_* (#708).

## Fire when a rival is within this vertical band (shots fly ~horizontally).
const LEVEL_BAND := 1.0
## Dodge a shot inside this radius that's roughly at our height.
const DODGE_RADIUS := 2.2
## Jump toward a target/dais this much higher than us when grounded.
const CLIMB_LEAD := 1.2


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var me: Array = players.get(slot, [])
	if me.size() < LoadoutDuel.PS_COUNT or (int(me[LoadoutDuel.PS_FLAGS]) & 1) == 0:
		return {}
	var my_pos := Vector2(float(me[LoadoutDuel.PS_X]), float(me[LoadoutDuel.PS_Y]))
	# Dodge an incoming shot at our height before anything else.
	var dodge := _dodge(game.get("shots", []), my_pos)
	if not dodge.is_empty():
		return dodge
	# Empty-handed: go arm up at the nearest live dais.
	if int(me[LoadoutDuel.PS_HELD]) == LoadoutDuel.Kind.NONE:
		return _seek(_nearest_dais(game.get("daises", []), my_pos), my_pos)
	# Armed: line up a level rival and fire.
	var rival := _nearest_rival(players, my_pos)
	if rival.is_empty():
		return {}
	var rival_pos := Vector2(float(rival[LoadoutDuel.PS_X]), float(rival[LoadoutDuel.PS_Y]))
	if absf(rival_pos.y - my_pos.y) <= LEVEL_BAND:
		var facing_dir := signf(rival_pos.x - my_pos.x)
		var intent := {"mx": (facing_dir if absf(facing_dir) > 0.0 else 1.0) * 0.4}
		intent["fire"] = true
		return intent
	# Rival is on another tier: move under/onto their level.
	return _seek(rival_pos, my_pos)


## Move toward a world point, jumping when it sits above us and we're grounded
## enough (approximated: only jump when clearly higher — the sim buffers it).
func _seek(target: Vector2, from: Vector2) -> Dictionary:
	if target == Vector2.INF:
		return {}
	var intent := {"mx": signf(target.x - from.x)}
	if target.y - from.y > CLIMB_LEAD:
		intent["jump"] = true
	return intent


func _dodge(shots: Array, from: Vector2) -> Dictionary:
	for shot: Array in shots:
		if shot.size() <= LoadoutDuel.SH_Y:
			continue
		var pos := Vector2(float(shot[LoadoutDuel.SH_X]), float(shot[LoadoutDuel.SH_Y]))
		if from.distance_to(pos) <= DODGE_RADIUS and absf(pos.y - from.y) <= LEVEL_BAND:
			# Sidestep away from the shot and hop.
			return {"mx": signf(from.x - pos.x), "jump": true}
	return {}


func _nearest_dais(daises: Array, from: Vector2) -> Vector2:
	var live: Array = []
	for dais: Array in daises:
		if dais.size() >= 3 and int(dais[LoadoutDuel.DS_KIND]) != LoadoutDuel.Kind.NONE:
			live.append([dais[LoadoutDuel.DS_X], dais[LoadoutDuel.DS_Y]])
	return nearest_point(from, live)


func _nearest_rival(players: Dictionary, from: Vector2) -> Array:
	var best: Array = []
	var best_distance := INF
	for other: int in players:
		if other == slot:
			continue
		var state: Array = players[other]
		if state.size() < LoadoutDuel.PS_COUNT or (int(state[LoadoutDuel.PS_FLAGS]) & 1) == 0:
			continue
		var distance := from.distance_squared_to(
			Vector2(float(state[LoadoutDuel.PS_X]), float(state[LoadoutDuel.PS_Y]))
		)
		if distance < best_distance:
			best_distance = distance
			best = state
	return best
