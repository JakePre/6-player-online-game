class_name NomArena
extends MinigameBase
## Nom Arena (M14-10, PHASE2.md §8; #1069 ring removed, #1027 seeded walls,
## on top of #954's Power Pellet): an agar.io homage, kept QUICK per owner
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
## Seeded walls (#1027): WALLS_PER_QUADRANT rects rolled in one quadrant and
## mirrored across both axes (4-fold symmetry = fair from every spawn angle),
## sized/placed so lanes always stay wider than the fattest blob. They replace
## the shrinking ring (#1069, owner playtest) as the crowd-splitting pressure.
const WALLS_PER_QUADRANT := 2
const WALL_MIN_HALF := Vector2(0.4, 1.2)
const WALL_MAX_HALF := Vector2(0.7, 2.6)
const WALL_CENTER_MIN := 3.0
const WALL_CENTER_MAX := 8.0
## Power Pellet (#954, owner-approved #944 design): one oversized pellet at a
## time, spawning PELLET_INTERVAL_SEC after round start / after the last one
## was eaten, never within PELLET_CLEARANCE of any player. The eater gets
## FRENZY_SEC of frenzy: biting (lunging into) a rival steals FRENZY_STEAL of
## their mass, once per rival per lunge. Frenzy grants NO speed change — a
## positioning reversal, not a guaranteed feast.
const PELLET_INTERVAL_SEC := 20.0
const PELLET_CLEARANCE := 2.0
const PELLET_RADIUS := 0.3
const FRENZY_SEC := 4.0
const FRENZY_STEAL := 0.3

## get_snapshot() wire shapes (#708): named indices for the positional arrays
## the view and brain read. Array SHAPE on the wire is unchanged — additive.
const PS_X := 0
const PS_Y := 1
const PS_MASS := 2
const PS_LUNGING := 3
const PS_FRENZY := 4
const PS_COUNT := 5
## #946 wire-shape tripwire: the declared type of each slot in a `players`
## snapshot row. Validated by test_snapshot_schema against get_snapshot().
const PLAYER_SCHEMA := [TYPE_FLOAT, TYPE_FLOAT, TYPE_FLOAT, TYPE_INT, TYPE_FLOAT]

const DT_X := 0
const DT_Y := 1

var positions := {}
var move_dirs := {}
var masses := {}
## Seeded walls (#1027), each {pos, half} — set once in _setup, replicated.
var walls: Array[Dictionary] = []
var dots: Array[Vector2] = []
## Power pellet (#954): Vector2.INF = none on the field.
var pellet := Vector2.INF

var _lunge_left := {}
var _lunge_cd := {}
var _lunge_dir := {}
var _pellet_timer := PELLET_INTERVAL_SEC
var _frenzy_left := {}
## slot -> {victim: true} for the current lunge, so one bite can't drain a
## rival every tick the 0.22 s lunge overlaps them.
var _bitten := {}


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
					+ " grab the POWER PELLET to turn the tables and bite anyone for 4s."
					+ " Weave the walls. Biggest blob at the buzzer wins!"
				),
				"controls": "Move — WASD / left stick · Lunge — SPACE / pad A",
				# Device-aware (#608): the button reads as what the player holds.
				"control_hints":
				["Move — WASD / left stick · Lunge — ", {"action": &"action_primary"}],
				# Structured spec (#832/#844): the move + action template shape.
				"control_spec":
				[
					{"verb": "Move", "input": InputGlyphs.CLUSTER_MOVE},
					{"verb": "Lunge", "input": &"action_primary"},
				],
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
		_frenzy_left[slot] = 0.0
		_bitten[slot] = {}
	_generate_walls()
	for _i in DOT_COUNT:
		dots.append(_clear_point(ARENA_HALF - 0.5))


## WALLS_PER_QUADRANT seeded rects in the +x/+y quadrant, mirrored across both
## axes (#1027): every spawn angle faces the same maze, and the center stays
## open so the pellet and respawns always have room.
func _generate_walls() -> void:
	for _i in WALLS_PER_QUADRANT:
		var half := Vector2(
			rng.randf_range(WALL_MIN_HALF.x, WALL_MAX_HALF.x),
			rng.randf_range(WALL_MIN_HALF.y, WALL_MAX_HALF.y)
		)
		if rng.randf() < 0.5:
			half = Vector2(half.y, half.x)
		var center := Vector2(
			rng.randf_range(WALL_CENTER_MIN, WALL_CENTER_MAX),
			rng.randf_range(WALL_CENTER_MIN, WALL_CENTER_MAX)
		)
		for mirror: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			walls.append({"pos": center * mirror, "half": half})


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
		_bitten[slot] = {}  # a fresh lunge earns a fresh bite per rival (#954)
		masses[slot] = maxf(MIN_MASS, float(masses[slot]) - LUNGE_MASS_COST)


func _tick(delta: float) -> void:
	for slot: int in slots:
		_lunge_cd[slot] = maxf(0.0, float(_lunge_cd[slot]) - delta)
		var velocity: Vector2 = (move_dirs[slot] as Vector2) * _speed(slot)
		if float(_lunge_left[slot]) > 0.0:
			_lunge_left[slot] = maxf(0.0, float(_lunge_left[slot]) - delta)
			velocity = (_lunge_dir[slot] as Vector2) * LUNGE_SPEED
		var pos: Vector2 = positions[slot] + velocity * delta
		pos = _push_out_of_walls(pos, radius_of(slot))
		positions[slot] = pos.limit_length(ARENA_HALF)
		# Idle decay — big blobs melt, so you must keep eating (the ring is
		# gone, #1069: the walls and the pellet make the pressure instead).
		masses[slot] = maxf(MIN_MASS, float(masses[slot]) * (1.0 - DECAY_RATE * delta))
	_tick_pellet(delta)
	_tick_frenzy(delta)
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
			snappedf(float(_frenzy_left[slot]), 0.01),
		]
	var dot_list: Array = []
	for dot in dots:
		dot_list.append([snappedf(dot.x, 0.01), snappedf(dot.y, 0.01)])
	# `pellet` is an additive key (#954): [] while none is on the field.
	var pellet_list: Array = []
	if pellet != Vector2.INF:
		pellet_list = [snappedf(pellet.x, 0.01), snappedf(pellet.y, 0.01)]
	var wall_list: Array = []
	for wall: Dictionary in walls:
		var wall_pos: Vector2 = wall.pos
		var wall_half: Vector2 = wall.half
		wall_list.append(
			[snappedf(wall_pos.x, 0.01), snappedf(wall_pos.y, 0.01), wall_half.x, wall_half.y]
		)
	return {
		"players": player_states,
		"dots": dot_list,
		"pellet": pellet_list,
		"walls": wall_list,
	}


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


## #954: the pellet timer runs only while no pellet is on the field, so the
## next one lands PELLET_INTERVAL_SEC after the previous was eaten.
func _tick_pellet(delta: float) -> void:
	if pellet == Vector2.INF:
		_pellet_timer -= delta
		if _pellet_timer <= 0.0:
			pellet = _pellet_spawn_point()
		return
	for slot: int in slots:
		if positions[slot].distance_to(pellet) <= radius_of(slot) + PELLET_RADIUS:
			pellet = Vector2.INF
			_pellet_timer = PELLET_INTERVAL_SEC
			_frenzy_left[slot] = FRENZY_SEC
			break


## Random point inside the ring with PELLET_CLEARANCE from every player; if a
## crowded endgame ring makes that impossible, the farthest-from-players
## candidate wins — the spawn never stalls.
func _pellet_spawn_point() -> Vector2:
	var best := Vector2.ZERO
	var best_gap := -INF
	for _i in 12:
		var candidate := _random_point(ARENA_HALF - 2.0)
		if _inside_a_wall(candidate):
			continue  # never bury the pellet in the maze (#1027)
		var gap := INF
		for slot: int in slots:
			gap = minf(gap, positions[slot].distance_to(candidate))
		if gap >= PELLET_CLEARANCE:
			return candidate
		if gap > best_gap:
			best_gap = gap
			best = candidate
	return best


## #954: a frenzied, LUNGING blob that touches a rival bites FRENZY_STEAL of
## their mass off (the victim keeps at least MIN_MASS; the biter gains exactly
## what was taken). One bite per rival per lunge — see _bitten.
func _tick_frenzy(delta: float) -> void:
	for slot: int in slots:
		_frenzy_left[slot] = maxf(0.0, float(_frenzy_left[slot]) - delta)
	for a: int in slots:
		if float(_frenzy_left[a]) <= 0.0 or float(_lunge_left[a]) <= 0.0:
			continue
		for b: int in slots:
			if a == b or (_bitten[a] as Dictionary).has(b):
				continue
			if positions[a].distance_to(positions[b]) > radius_of(a) + radius_of(b):
				continue
			var taken := clampf(float(masses[b]) * FRENZY_STEAL, 0.0, float(masses[b]) - MIN_MASS)
			masses[b] = float(masses[b]) - taken
			masses[a] = float(masses[a]) + taken
			_bitten[a][b] = true


func _eat_dots() -> void:
	for i in dots.size():
		for slot: int in slots:
			if positions[slot].distance_to(dots[i]) <= radius_of(slot):
				masses[slot] = float(masses[slot]) + DOT_MASS
				dots[i] = _clear_point(ARENA_HALF - 0.5)
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
	positions[slot] = _clear_point(ARENA_HALF - 1.0)
	move_dirs[slot] = Vector2.ZERO
	_lunge_left[slot] = 0.0
	_frenzy_left[slot] = 0.0  # being swallowed ends a frenzy (#954)


## Solid maze walls (#1027): circle-vs-AABB ejection via the shared #945 math
## (restitution 0 — blobs slide along walls, they don't bounce).
func _push_out_of_walls(pos: Vector2, radius: float) -> Vector2:
	for wall: Dictionary in walls:
		var result := SimGeometry.bounce_circle_box(
			pos, Vector2.ZERO, wall.pos, wall.half, radius, 0.0
		)
		pos = result.pos
	return pos


## A seeded point guaranteed clear of every wall (#1027) — dots, respawns and
## the pellet must never land inside the maze geometry. Bounded retry; the
## walls cover a small fraction of the arena, so this converges immediately.
func _clear_point(radius: float) -> Vector2:
	for _attempt in 16:
		var point := _random_point(radius)
		if not _inside_a_wall(point):
			return point
	return Vector2.ZERO


func _inside_a_wall(point: Vector2) -> bool:
	for wall: Dictionary in walls:
		var wall_pos: Vector2 = wall.pos
		var wall_half: Vector2 = wall.half
		if (
			absf(point.x - wall_pos.x) <= wall_half.x + 0.6
			and absf(point.y - wall_pos.y) <= wall_half.y + 0.6
		):
			return true
	return false


func _random_point(radius: float) -> Vector2:
	var angle := rng.randf_range(0.0, TAU)
	var dist := sqrt(rng.randf()) * radius
	return Vector2(cos(angle), sin(angle)) * dist
