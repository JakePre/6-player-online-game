class_name NomArenaBrain
extends BotBrain
## Agar-io archetype (M19-02, #686): flee anything big enough to eat us, stay
## inside the closing ring, lunge at anything small enough to swallow, else
## graze the nearest dot. Priorities in that order — survival first, growth
## second. Snapshot: {players: {slot: [x, y, mass, lunging]}, dots: [[x,y],
## ...], boundary}. Input: {mx, my} + {lunge: true}. Indices named via
## NomArena.PS_*/DT_* (#708).

## How far out a threat/prey is worth reacting to, scaled by the mass gap so
## a much bigger rival is noticed sooner than a marginal one.
const REACT_RANGE := 6.0
const BOUNDARY_MARGIN := 1.0


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var state: Array = players.get(slot, [])
	if state.size() < NomArena.PS_COUNT:
		return {}
	var me := Vector2(float(state[NomArena.PS_X]), float(state[NomArena.PS_Y]))
	var mass := float(state[NomArena.PS_MASS])
	var threat := _nearest_by_size(players, me, mass, true)
	if threat != Vector2.INF:
		return move_away_from_point(me, threat)
	var boundary := float(game.get("boundary", NomArena.ARENA_HALF))
	if me.length() > boundary - BOUNDARY_MARGIN:
		return move_toward_point(me, Vector2.ZERO, 0.0)
	var prey := _nearest_by_size(players, me, mass, false)
	if prey != Vector2.INF:
		var intent := move_toward_point(me, prey, 0.0)
		intent["lunge"] = true
		return intent
	var dot := nearest_point(me, game.get("dots", []))
	if dot == Vector2.INF:
		return {}
	return move_toward_point(me, dot, 0.0)


## Nearest rival within REACT_RANGE that's either a threat (bigger than us by
## EAT_RATIO, `want_threat=true`) or prey (smaller than us by EAT_RATIO,
## `want_threat=false`) — the same ratio the sim itself uses to eat.
func _nearest_by_size(players: Dictionary, me: Vector2, mass: float, want_threat: bool) -> Vector2:
	var best := Vector2.INF
	var best_dist := INF
	for other: int in players:
		if other == slot:
			continue
		var state: Array = players[other]
		if state.size() <= NomArena.PS_MASS:
			continue
		var other_mass := float(state[NomArena.PS_MASS])
		var qualifies := (
			other_mass > mass * NomArena.EAT_RATIO
			if want_threat
			else mass > other_mass * NomArena.EAT_RATIO
		)
		if not qualifies:
			continue
		var pos := Vector2(float(state[NomArena.PS_X]), float(state[NomArena.PS_Y]))
		var dist := me.distance_squared_to(pos)
		if dist <= REACT_RANGE * REACT_RANGE and dist < best_dist:
			best_dist = dist
			best = pos
	return best
