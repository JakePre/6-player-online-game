class_name NomArenaBrain
extends BotBrain
## Agar-io archetype (M19-02, #686): flee anything big enough to eat us, stay
## inside the closing ring, lunge at anything small enough to swallow, else
## graze the nearest dot. Priorities in that order — survival first, growth
## second. Snapshot: {players: {slot: [x, y, mass, lunging]}, dots: [[x,y],
## ...], boundary}. Input: {mx, my} + {lunge: true}. Indices named via
## NomArena.PS_*/DT_* (#708).
##
## Cost-aware lunging (#715): nom_arena.gd eats on plain proximity contact —
## the lunge is only a speed burst, and it costs LUNGE_MASS_COST the instant
## it's accepted regardless of whether it connects. This used to fire the
## moment prey entered REACT_RANGE (6.0u), but the burst only travels
## LUNGE_SPEED * LUNGE_SEC (~3.7u), so most lunges were paid for well before
## they could land — and since cooldowns aren't in the snapshot either, a
## whiffed early lunge burned the one chance a truly close shot would have
## had. Now the lunge is range-gated to its actual reach with a local
## cooldown mirror.

## How far out a threat/prey is worth reacting to, scaled by the mass gap so
## a much bigger rival is noticed sooner than a marginal one.
const REACT_RANGE := 6.0
const BOUNDARY_MARGIN := 1.0
## Real lunge reach — firing from farther than this pays LUNGE_MASS_COST
## before the burst can possibly connect.
const LUNGE_REACH := NomArena.LUNGE_SPEED * NomArena.LUNGE_SEC

var _lunge_cd := 0.0


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	_lunge_cd = maxf(_lunge_cd - NetManager.BOT_INPUT_INTERVAL_SEC, 0.0)
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var state: Array = players.get(slot, [])
	if state.size() < NomArena.PS_LUNGING + 1:
		return {}
	var me := Vector2(float(state[NomArena.PS_X]), float(state[NomArena.PS_Y]))
	var mass := float(state[NomArena.PS_MASS])
	# Frenzied (#954): every rival is a meal — our own frenzy overrides the
	# usual size-based caution and hunts the nearest blob.
	if _frenzy_of(state) > 0.0:
		return _frenzied_intent(players, me)
	# Flee a threat: a frenzied rival at ANY size (#954), else a bigger blob.
	var threat := _flee_target(players, me, mass)
	if threat != Vector2.INF:
		return move_away_from_point(me, threat)
	var boundary := float(game.get("boundary", NomArena.ARENA_HALF))
	if me.length() > boundary - BOUNDARY_MARGIN:
		return move_toward_point(me, Vector2.ZERO, 0.0)
	# Growth: contest the pellet if closest (#954), else hunt prey, else graze.
	return _growth_intent(game, players, me, mass)


## Frenzied: chase the nearest rival regardless of size and bite when in reach
## (#954). No rival visible → idle (a solo frenzy has nothing to hunt).
func _frenzied_intent(players: Dictionary, me: Vector2) -> Dictionary:
	var meal := _nearest_rival(players, me)
	if meal == Vector2.INF:
		return {}
	var chase := move_toward_point(me, meal, 0.0)
	if _lunge_cd <= 0.0 and me.distance_to(meal) <= LUNGE_REACH:
		chase["lunge"] = true
		_lunge_cd = NomArena.LUNGE_COOLDOWN_SEC
	return chase


## The point to flee from, or Vector2.INF: a frenzied rival first (fear is
## mutual with the view's frightened tint), then the nearest bigger blob.
func _flee_target(players: Dictionary, me: Vector2, mass: float) -> Vector2:
	var frenzied := _nearest_frenzied(players, me)
	if frenzied != Vector2.INF:
		return frenzied
	return _nearest_by_size(players, me, mass, true)


## Growth priorities: contest the power pellet when we're strictly closest,
## then lunge at prey in reach, else graze the nearest dot.
func _growth_intent(game: Dictionary, players: Dictionary, me: Vector2, mass: float) -> Dictionary:
	var pellet: Array = game.get("pellet", [])
	if pellet.size() == 2:
		var pellet_pos := Vector2(float(pellet[0]), float(pellet[1]))
		if _closest_to(players, me, pellet_pos):
			return move_toward_point(me, pellet_pos, 0.0)
	var prey := _nearest_by_size(players, me, mass, false)
	if prey != Vector2.INF:
		var intent := move_toward_point(me, prey, 0.0)
		if _lunge_cd <= 0.0 and me.distance_to(prey) <= LUNGE_REACH:
			intent["lunge"] = true
			_lunge_cd = NomArena.LUNGE_COOLDOWN_SEC
		return intent
	var dot := nearest_point(me, game.get("dots", []))
	if dot == Vector2.INF:
		return {}
	return move_toward_point(me, dot, 0.0)


## Guarded read (#954): rows without the frenzy slot mean "not frenzied".
func _frenzy_of(state: Array) -> float:
	if state.size() <= NomArena.PS_FRENZY:
		return 0.0
	return float(state[NomArena.PS_FRENZY])


## Nearest frenzied rival within REACT_RANGE (#954).
func _nearest_frenzied(players: Dictionary, me: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_dist := INF
	for other: int in players:
		if other == slot:
			continue
		var state: Array = players[other]
		if _frenzy_of(state) <= 0.0:
			continue
		var pos := Vector2(float(state[NomArena.PS_X]), float(state[NomArena.PS_Y]))
		var dist := me.distance_squared_to(pos)
		if dist <= REACT_RANGE * REACT_RANGE and dist < best_dist:
			best_dist = dist
			best = pos
	return best


func _nearest_rival(players: Dictionary, me: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_dist := INF
	for other: int in players:
		if other == slot:
			continue
		var state: Array = players[other]
		if state.size() <= NomArena.PS_Y:
			continue
		var pos := Vector2(float(state[NomArena.PS_X]), float(state[NomArena.PS_Y]))
		var dist := me.distance_squared_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = pos
	return best


## True when no rival is nearer to `target` than we are — the pellet mind
## game: contest only spawns we'd actually win.
func _closest_to(players: Dictionary, me: Vector2, target: Vector2) -> bool:
	var my_dist := me.distance_squared_to(target)
	for other: int in players:
		if other == slot:
			continue
		var state: Array = players[other]
		if state.size() <= NomArena.PS_Y:
			continue
		var pos := Vector2(float(state[NomArena.PS_X]), float(state[NomArena.PS_Y]))
		if pos.distance_squared_to(target) < my_dist:
			return false
	return true


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
