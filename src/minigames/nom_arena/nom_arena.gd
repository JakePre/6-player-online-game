class_name NomArena
extends MinigameBase
## Nom Arena (M14-10, PHASE2.md §8): an agar.io homage, kept QUICK per owner
## directive — a 60 s scramble where you eat dense dots to grow, lunge to catch
## smaller blobs and swallow them, and dodge bigger ones, while idle mass decays
## and the arena closes in for the finish. Biggest blob at the buzzer wins.
## Split is distilled to a short forward lunge (no multi-blob state) — a
## deliberate homage simplification. Server-side simulation only.

const ARENA_HALF := 12.0
const START_MASS := 8.0
const MIN_MASS := 5.0
const DOT_MASS := 0.6
const DOT_COUNT := 42
## radius = sqrt(mass) * K (area grows with mass); speed drops as you fatten.
const RADIUS_K := 0.28
const BASE_SPEED := 7.5
const SLOW_K := 0.045
## You must be this much bigger than a blob to swallow it.
const EAT_RATIO := 1.15
## Proportional idle decay — big blobs melt faster, so you must keep eating.
const DECAY_RATE := 0.02
## Lunge (the "split"): a short dash on a cooldown, paid for in mass, that
## closes distance to prey but leaves you briefly smaller/vulnerable.
const LUNGE_SPEED := 17.0
const LUNGE_SEC := 0.22
const LUNGE_COOLDOWN_SEC := 1.3
const LUNGE_MASS_COST := 1.2
## The closing ring: starts shrinking with this long left, down to the final
## radius; blobs caught outside bleed mass fast — that's the QUICK endgame.
const SHRINK_LAST_SEC := 20.0
const SHRINK_END_RADIUS := 5.0
const OUT_DAMAGE := 9.0

## get_snapshot() wire shapes (#708): named indices for the positional arrays
## the view and brain read. Array SHAPE on the wire is unchanged — additive.
const PS_X := 0
const PS_Y := 1
const PS_MASS := 2
const PS_LUNGING := 3
const PS_COUNT := 4

const DT_X := 0
const DT_Y := 1

var positions := {}
var move_dirs := {}
var masses := {}
var boundary := ARENA_HALF
var dots: Array[Vector2] = []

var _lunge_left := {}
var _lunge_cd := {}
var _lunge_dir := {}


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"nom_arena",
				"name": "Nom Arena",
				"category": MinigameMeta.Category.FFA,
				"min_players": 2,
				"max_players": 8,
				"duration_sec": 60.0,
				"rules":
				(
					"Eat dots to grow, LUNGE to swallow smaller blobs, flee the bigger ones —"
					+ " biggest blob when the ring closes wins!"
				),
				"controls": "Move — WASD / left stick · Lunge — SPACE / pad A",
				# Device-aware (#608): the button reads as what the player holds.
				"control_hints":
				["Move — WASD / left stick · Lunge — ", {"action": &"action_primary"}],
			}
		)
	)


func _setup() -> void:
	for i in slots.size():
		var slot: int = slots[i]
		var angle := TAU * i / slots.size()
		positions[slot] = Vector2(cos(angle), sin(angle)) * ARENA_HALF * 0.5
		move_dirs[slot] = Vector2.ZERO
		masses[slot] = START_MASS
		_lunge_left[slot] = 0.0
		_lunge_cd[slot] = 0.0
		_lunge_dir[slot] = Vector2.ZERO
	for _i in DOT_COUNT:
		dots.append(_random_point(ARENA_HALF - 0.5))


func _handle_input(slot: int, data: Dictionary) -> void:
	# Only touch the move direction when the packet actually carries one (#783):
	# a lunge-only packet used to zero move_dir here, stalling movement AND
	# leaving the lunge with no direction to aim along.
	if data.has("mx") or data.has("my"):
		var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
		move_dirs[slot] = dir.limit_length(1.0)
	if data.get("lunge", false) and float(_lunge_cd[slot]) <= 0.0:
		# Aim along the current heading (#783): the bug was reading the packet's
		# own dir, which a separate lunge packet lacks, so every lunge defaulted
		# to straight up. The persisted move_dir is the true current heading.
		var move: Vector2 = move_dirs[slot]
		var aim := move if move.length() > 0.1 else Vector2(0.0, -1.0)
		_lunge_dir[slot] = aim.normalized()
		_lunge_left[slot] = LUNGE_SEC
		_lunge_cd[slot] = LUNGE_COOLDOWN_SEC
		masses[slot] = maxf(MIN_MASS, float(masses[slot]) - LUNGE_MASS_COST)


func _tick(delta: float) -> void:
	boundary = _boundary_radius()
	for slot: int in slots:
		_lunge_cd[slot] = maxf(0.0, float(_lunge_cd[slot]) - delta)
		var velocity: Vector2 = (move_dirs[slot] as Vector2) * _speed(slot)
		if float(_lunge_left[slot]) > 0.0:
			_lunge_left[slot] = maxf(0.0, float(_lunge_left[slot]) - delta)
			velocity = (_lunge_dir[slot] as Vector2) * LUNGE_SPEED
		var pos: Vector2 = positions[slot] + velocity * delta
		positions[slot] = pos.limit_length(ARENA_HALF)
		# Idle decay, and heavy bleed if caught outside the closing ring.
		var mass := float(masses[slot]) * (1.0 - DECAY_RATE * delta)
		if positions[slot].length() > boundary:
			mass -= OUT_DAMAGE * delta
		masses[slot] = maxf(MIN_MASS, mass)
	_eat_dots()
	_eat_players()


func get_snapshot() -> Dictionary:
	var player_states := {}
	for slot: int in slots:
		var pos: Vector2 = positions[slot]
		player_states[slot] = [
			snappedf(pos.x, 0.01),
			snappedf(pos.y, 0.01),
			snappedf(float(masses[slot]), 0.05),
			1 if float(_lunge_left[slot]) > 0.0 else 0,
		]
	var dot_list: Array = []
	for dot in dots:
		dot_list.append([snappedf(dot.x, 0.01), snappedf(dot.y, 0.01)])
	return {"players": player_states, "dots": dot_list, "boundary": snappedf(boundary, 0.01)}


## Biggest blob wins; equal masses (rare) share the rank.
func _rank_players() -> Array:
	var by_mass := {}
	for slot: int in slots:
		var key := roundi(float(masses[slot]) * 10.0)
		if not by_mass.has(key):
			by_mass[key] = []
		by_mass[key].append(slot)
	var keys := by_mass.keys()
	keys.sort()
	keys.reverse()
	var placements: Array = []
	for key: int in keys:
		placements.append(by_mass[key])
	return placements


func radius_of(slot: int) -> float:
	return sqrt(float(masses[slot])) * RADIUS_K


func _speed(slot: int) -> float:
	return BASE_SPEED / (1.0 + float(masses[slot]) * SLOW_K)


func _boundary_radius() -> float:
	var t := clampf(
		(elapsed - (effective_duration() - SHRINK_LAST_SEC)) / SHRINK_LAST_SEC, 0.0, 1.0
	)
	return lerpf(ARENA_HALF, SHRINK_END_RADIUS, t)


func _eat_dots() -> void:
	for i in dots.size():
		for slot: int in slots:
			if positions[slot].distance_to(dots[i]) <= radius_of(slot):
				masses[slot] = float(masses[slot]) + DOT_MASS
				dots[i] = _random_point(maxf(boundary - 0.5, 2.0))
				break


## Bigger blobs swallow smaller ones they cover; the eaten respawn small and
## keep playing. One pass with an eaten-guard so nobody is consumed twice or
## eats after being consumed.
func _eat_players() -> void:
	var eaten := {}
	for a: int in slots:
		if eaten.has(a):
			continue
		for b: int in slots:
			if a == b or eaten.has(b):
				continue
			if (
				float(masses[a]) > float(masses[b]) * EAT_RATIO
				and positions[a].distance_to(positions[b]) <= radius_of(a)
			):
				masses[a] = float(masses[a]) + float(masses[b])
				eaten[b] = true
				_respawn(b)


func _respawn(slot: int) -> void:
	masses[slot] = MIN_MASS
	positions[slot] = _random_point(maxf(boundary - 1.0, 2.0))
	move_dirs[slot] = Vector2.ZERO
	_lunge_left[slot] = 0.0


func _random_point(radius: float) -> Vector2:
	var angle := rng.randf_range(0.0, TAU)
	var dist := sqrt(rng.randf()) * radius
	return Vector2(cos(angle), sin(angle)) * dist
