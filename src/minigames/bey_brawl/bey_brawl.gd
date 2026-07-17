class_name BeyBrawl
extends MinigameBase
## Bey Brawl (#1034, owner-designed): a beyblade battle that replaces Sumo
## Smash. Everyone spins permanently (axe out, whirlwind) inside a concave
## BOWL whose slope pulls every body toward the center — collisions are
## inevitable, so the corner-camp/stalemate degeneracies the flat dohyo bred
## (#926) can't exist. Movement is pure momentum: input STEERS (thrust), it
## never sets position, so you build speed and carve arcs. Spin is both HP
## and power: it drains slowly with time and sharply when you LOSE a clash
## (the faster, spin-heavier body wins one). Two ways out, like a real
## stadium: topple at zero spin, or get launched over the bowl lip faster
## than the escape speed (slower, and the slope just slides you back in).
## Last one spinning wins; a timeout ranks by remaining spin.
## Server-side simulation only — the client renders get_snapshot().

## Bowl geometry. Fixed size on purpose, like the dohyo it replaces (ADR
## 003 precedent): a bigger bowl would dilute the guaranteed-collision core.
const BOWL_RADIUS := 8.0
const PLAYER_RADIUS := 0.5
## Inward acceleration at the lip; scales linearly to zero at the center
## (a smooth concave slope, not a cliff).
const BOWL_PULL := 5.0
## Crossing the lip slower than this slides you back in; faster flies out.
const LIP_ESCAPE_SPEED := 6.5

## Momentum steering: thrust from input, gentle decel, and a speed cap.
## FRICTION is deliberately far below STEER_ACCEL — momentum IS the game.
const STEER_ACCEL := 8.0
const FRICTION := 1.6
const MAX_SPEED := 10.0

## Spin (0..1): the meter that is both HP and clash power.
const START_SPIN := 1.0
## ~0.008/s alone would never topple anyone in 60s; clashes are the real
## drain. Time drain exists so hiding at the rim still loses slowly.
const SPIN_DRAIN_PER_SEC := 0.008
const CLASH_SPIN_COST_LOSER := 0.16
const CLASH_SPIN_COST_WINNER := 0.05

## Clash resolution. Power = speed * (0.5 + 0.5*spin): a fast, healthy top
## beats a slow or drained one. The loser is launched along the collision
## axis BENT toward the winner's current steer (AIM_BIAS) — the owner's
## "slight aiming of where you collide". A per-pair cooldown makes each
## clash one impulse, not a per-tick pile-up (#927's dash-shove lesson).
const CLASH_IMPULSE_LOSER := 9.0
const CLASH_IMPULSE_WINNER := 4.0
const AIM_BIAS := 0.35
const CLASH_COOLDOWN_SEC := 0.4

## get_snapshot() wire shape (#708): named indices for the players positional
## array. clash_seq bumps on every clash a body is part of, so the view can
## edge-detect impact FX (#941 EdgeTracker idiom).
const PS_X := 0
const PS_Y := 1
const PS_SPIN := 2
const PS_CLASH_SEQ := 3
const PS_COUNT := 4
## #946 wire-shape tripwire: the declared type of each slot in a `players`
## snapshot row. Validated by test_snapshot_schema against get_snapshot().
const PLAYER_SCHEMA := [TYPE_FLOAT, TYPE_FLOAT, TYPE_FLOAT, TYPE_INT]

var positions := {}
var velocities := {}
var steers := {}
var spins := {}
var clash_seq := {}
## Elimination + placement bookkeeping (#940): same-tick outs share a tie
## group, placements rank in reverse out order.
var _elim := EliminationTracker.new()
## "a|b" (a<b) -> elapsed time until that pair may clash again.
var _pair_cooldown := {}


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"bey_brawl",
				"controls": "Steer — WASD / left stick (momentum!)",
				# Structured spec (#832/#844): the bare-movement template shape.
				"control_spec": [{"verb": "Steer", "input": InputGlyphs.CLUSTER_MOVE}],
				"name": "Bey Brawl",
				"category": MinigameMeta.Category.FFA,
				"min_players": 2,
				# 8 by design, like the dohyo before it: the bowl stays one tight
				# pit so the slope keeps everyone colliding.
				"max_players": 8,
				"duration_sec": 60.0,
				"rules":
				(
					"Everyone spins — steer your momentum and win the clashes!"
					+ " Losing one drains your spin: hit zero and you topple,"
					+ " or get launched clean over the lip. Last one spinning wins!"
				),
			}
		)
	)


func _setup() -> void:
	for i in slots.size():
		var angle := TAU * i / slots.size()
		positions[slots[i]] = Vector2(cos(angle), sin(angle)) * BOWL_RADIUS * 0.6
		velocities[slots[i]] = Vector2.ZERO
		steers[slots[i]] = Vector2.ZERO
		spins[slots[i]] = START_SPIN
		clash_seq[slots[i]] = 0


func _handle_input(slot: int, data: Dictionary) -> void:
	if not _elim.is_in(slot, slots):
		return
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	steers[slot] = dir.limit_length(1.0)


func _tick(delta: float) -> void:
	# Alive-set cache (#467): shared by every helper below; _check_end still
	# reads the roster fresh after _elim.flush() applies this tick's outs.
	var alive := _elim.in_slots(slots)
	for slot: int in alive:
		spins[slot] = maxf(0.0, float(spins[slot]) - SPIN_DRAIN_PER_SEC * delta)
		if float(spins[slot]) <= 0.0:
			_elim.mark(slot)  # toppled — out of spin
			continue
		var vel: Vector2 = velocities[slot]
		vel += (steers[slot] as Vector2) * STEER_ACCEL * delta
		vel += _bowl_pull(positions[slot]) * delta
		vel = vel.move_toward(Vector2.ZERO, FRICTION * delta).limit_length(MAX_SPEED)
		velocities[slot] = vel
		positions[slot] = (positions[slot] as Vector2) + vel * delta
		_resolve_lip(slot)
	_resolve_clashes(alive)
	_elim.flush()
	_check_end()


## The concave slope: inward acceleration growing linearly from zero at the
## center to BOWL_PULL at the lip. Everyone drifts toward the middle.
func _bowl_pull(pos: Vector2) -> Vector2:
	var dist := pos.length()
	if dist < 0.001:
		return Vector2.ZERO
	return -pos / dist * BOWL_PULL * (dist / BOWL_RADIUS)


## The lip: crossing it faster than LIP_ESCAPE_SPEED (outward) is a ring-out;
## anything slower is caught — position clamps to the rim and the outward
## velocity component is removed, so the body slides along the lip and the
## slope pulls it back into play.
func _resolve_lip(slot: int) -> void:
	var pos: Vector2 = positions[slot]
	if pos.length() <= BOWL_RADIUS:
		return
	var outward := pos.normalized()
	var vel: Vector2 = velocities[slot]
	if vel.dot(outward) > LIP_ESCAPE_SPEED:
		_elim.mark(slot)  # launched clean over the lip
		return
	positions[slot] = outward * BOWL_RADIUS
	velocities[slot] = vel - outward * maxf(0.0, vel.dot(outward))


func _resolve_clashes(alive: Array) -> void:
	for i in alive.size():
		for j in range(i + 1, alive.size()):
			var a: int = alive[i]
			var b: int = alive[j]
			var apart: Vector2 = positions[b] - positions[a]
			if apart.length() > PLAYER_RADIUS * 2.0:
				continue
			# Bodies never stack, cooling down or not (#945 shared math).
			var push := SimGeometry.separation_push(positions[a], positions[b], PLAYER_RADIUS * 2.0)
			positions[a] = (positions[a] as Vector2) - push
			positions[b] = (positions[b] as Vector2) + push
			var key := "%d|%d" % [mini(a, b), maxi(a, b)]
			if elapsed < float(_pair_cooldown.get(key, 0.0)):
				continue
			_pair_cooldown[key] = elapsed + CLASH_COOLDOWN_SEC
			_clash(a, b, apart)


## One clash: the body with more power (speed weighted by spin health) wins.
## The loser is launched hard along the collision axis, bent toward the
## winner's steer; the winner takes light recoil and a small spin cost.
func _clash(a: int, b: int, apart: Vector2) -> void:
	var axis := apart.normalized() if apart.length() > 0.001 else Vector2.RIGHT
	var winner := a if _clash_power(a) >= _clash_power(b) else b
	var loser := b if winner == a else a
	# `axis` points a->b; the loser is launched away from the winner.
	var away := axis if loser == b else -axis
	var aimed := (away + (steers[winner] as Vector2) * AIM_BIAS).normalized()
	velocities[loser] = (velocities[loser] as Vector2) + aimed * CLASH_IMPULSE_LOSER
	velocities[winner] = (velocities[winner] as Vector2) - away * CLASH_IMPULSE_WINNER
	spins[loser] = maxf(0.0, float(spins[loser]) - CLASH_SPIN_COST_LOSER)
	spins[winner] = maxf(0.0, float(spins[winner]) - CLASH_SPIN_COST_WINNER)
	clash_seq[a] = int(clash_seq[a]) + 1
	clash_seq[b] = int(clash_seq[b]) + 1


func _clash_power(slot: int) -> float:
	return (velocities[slot] as Vector2).length() * (0.5 + 0.5 * float(spins[slot]))


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		if not _elim.is_in(slot, slots):
			continue
		var pos: Vector2 = positions[slot]
		players[slot] = [
			snappedf(pos.x, 0.01),
			snappedf(pos.y, 0.01),
			snappedf(float(spins[slot]), 0.01),
			int(clash_seq[slot]),
		]
	return {"radius": BOWL_RADIUS, "players": players, "out": _elim.order}


## Timeout: survivors rank by remaining spin (snapped so near-equal meters
## tie), then the out groups in reverse elimination order.
func _rank_players() -> Array:
	var by_spin := {}
	for slot: int in _elim.in_slots(slots):
		var key := roundi(float(spins[slot]) * 20.0)
		if not by_spin.has(key):
			by_spin[key] = []
		by_spin[key].append(slot)
	var keys := by_spin.keys()
	keys.sort()
	keys.reverse()
	var placements: Array = []
	for key: int in keys:
		placements.append(by_spin[key])
	return placements + _elim.out_placements()


func _check_end() -> void:
	if finished:
		return
	var survivors := _elim.in_slots(slots)
	if survivors.size() > 1:
		return
	var placements: Array = []
	if not survivors.is_empty():
		placements.append(survivors)
	finish(placements + _elim.out_placements())
