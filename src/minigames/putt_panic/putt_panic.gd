class_name PuttPanic
extends MinigameBase
## Putt Panic (M14-08, PHASE2.md §8; #1071 course pool): a mini-golf homage —
## everyone putts on one shared green toward a single cup, simultaneously,
## fewest strokes wins. Aim + charge + release; the ball rolls with friction,
## bounces off the walls, static blocks and an orbiting guard bar, and drops if
## it reaches the cup slowly enough. A 30 s shot clock auto-putts idlers. Each
## round seeds one course from a pool of archetypes, all built rotationally
## symmetric around a near-centre cup with every tee on the same circle — so
## every seat has the same distance and the same hole-in-one potential.
## Server-side simulation only — the client renders get_snapshot().

## The course archetypes in the #1071 pool; one is seeded per round.
enum Course { OPEN_GREEN, WINDMILL, PILLAR_RING, BUMPER_FIELD }

const ARENA_HALF := 9.0
const BALL_RADIUS := 0.3
const CUP_RADIUS := 0.55
const MAX_POWER := 14.0
## Speed lost per second (rolling friction), and the speed below which the
## ball is considered at rest and ready for the next putt.
const FRICTION := 7.0
const STOP_SPEED := 0.4
## A ball only drops if it reaches the cup no faster than this (else it rolls
## over the lip); wall/obstacle bounces keep this much of their speed.
const SINK_MAX_SPEED := 7.0
const RESTITUTION := 0.7
const SHOT_CLOCK_SEC := 30.0
const AUTO_PUTT_POWER := 0.35

## Course pool (#1071, supersedes the #793 single archetype): each round seeds
## one archetype. Every course is rotationally symmetric around the cup — the
## cup sits near centre (± CUP_JITTER), obstacles form seeded-rotation rings
## around it, the guard bar ORBITS it, and all tees share one circle of radius
## TEE_RADIUS around it. The old bottom-row tees gave the centre seat the only
## straight line (owner playtest wave 4); the tee ring makes every seat's putt
## the same length against the same geometry.
const CUP_JITTER := 0.8
const TEE_RADIUS := 6.5
## Pillar Ring: pillars evenly around the cup; the gaps between them are the
## lanes (circumference ~18.2 against 6 × ~1.1 of pillar ≈ 1.9 per gap).
const PILLAR_COUNT := 6
const PILLAR_RING_RADIUS := 2.9
const PILLAR_HALF := 0.55
## Bumper Field: four fat bumpers on the diagonals-ish (seeded rotation).
const BUMPER_COUNT := 4
const BUMPER_RING_RADIUS := 4.4
const BUMPER_HALF := 0.8
## Guard-bar orbits per course: the Windmill hugs the cup and spins fast (time
## the arm!), the others patrol wider and slower. Orbit minus bar half always
## clears the cup by more than a ball.
const OPEN_ORBIT_RADIUS := 4.2
const WINDMILL_ORBIT_RADIUS := 2.4
const OUTER_ORBIT_RADIUS := 4.6
const BUMPER_ORBIT_RADIUS := 3.2

## get_snapshot() wire shape (#708): named indices for the players positional
## array. Array SHAPE on the wire is unchanged — additive only.
const PS_X := 0
const PS_Y := 1
const PS_STROKES := 2
const PS_SUNK := 3
const PS_AIM_X := 4
const PS_AIM_Y := 5
const PS_AT_REST := 6
const PS_COUNT := 7
## #946 wire-shape tripwire: the declared type of each slot in a `players`
## snapshot row. Validated by test_snapshot_schema against get_snapshot().
const PLAYER_SCHEMA := [
	TYPE_FLOAT, TYPE_FLOAT, TYPE_INT, TYPE_INT, TYPE_FLOAT, TYPE_FLOAT, TYPE_INT
]

var positions := {}
var velocities := {}
var aims := {}
var strokes := {}
var sunk := {}
var rest_time := {}
## The seeded course (#793/#1071): archetype, cup, static blocks ({pos, half})
## and the orbiting bar's geometry — set once in _setup() and replicated so
## every peer and the view agree on the same layout.
var course := Course.OPEN_GREEN
var cup_pos := Vector2.ZERO
var blocks: Array = []
var bar_half := Vector2(1.5, 0.5)
## bar_range is the bar's ORBIT RADIUS around the cup (#1071); bar_x/bar_y are
## its centre this tick (replicated so the view need not recompute).
var bar_range := OPEN_ORBIT_RADIUS
var bar_speed := 0.6
var bar_phase := 0.0
var bar_x := 0.0
var bar_y := 0.0


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"putt_panic",
				"name": "Putt Panic",
				"category": MinigameMeta.Category.SKILL,
				"min_players": 2,
				"max_players": 8,
				"duration_sec": 90.0,
				"rules":
				"Aim, charge, and putt into the cup — fewest strokes wins. Mind the moving bar!",
				"controls": "Aim — WASD / stick / mouse · Charge + putt — hold & release SPACE / Ⓐ",
				# Device-aware (#608): the button reads as what the player holds.
				"control_hints":
				[
					"Aim — WASD / stick / mouse · Charge + putt — hold & release ",
					{"action": &"action_primary"},
				],
				# Structured spec (#832/#844): aim + hold-release action template shape.
				"control_spec":
				[
					{"verb": "Aim", "input": InputGlyphs.CLUSTER_MOVE, "alt": "or mouse"},
					{
						"verb": "Charge + putt",
						"input": &"action_primary",
						"modifier": "hold & release"
					},
				],
			}
		)
	)


func _setup() -> void:
	_generate_course()
	# Tees on one circle around the cup (#1071): every seat the same distance,
	# the whole ring rotated by a seeded turn so no seat owns a fixed angle.
	var first_tee := rng.randf_range(0.0, TAU)
	for i in slots.size():
		var slot: int = slots[i]
		var angle := first_tee + TAU * float(i) / float(slots.size())
		positions[slot] = cup_pos + Vector2.RIGHT.rotated(angle) * TEE_RADIUS
		velocities[slot] = Vector2.ZERO
		aims[slot] = (cup_pos - positions[slot]).normalized()
		strokes[slot] = 0
		sunk[slot] = false
		rest_time[slot] = 0.0


## Draw one archetype from the pool (#1071) and dress it from the round seed.
## Every layout is rotationally symmetric around the cup, so combined with the
## tee ring no seat gets a privileged line — only the look, the seeded ring
## rotation, and the bar's orbit change between plays of the same archetype.
func _generate_course() -> void:
	course = rng.randi_range(0, Course.size() - 1) as Course
	cup_pos = Vector2(
		rng.randf_range(-CUP_JITTER, CUP_JITTER), rng.randf_range(-CUP_JITTER, CUP_JITTER)
	)
	blocks = []
	var ring_turn := rng.randf_range(0.0, TAU)
	match course:
		Course.OPEN_GREEN:
			_set_orbit(OPEN_ORBIT_RADIUS, Vector2(1.5, 0.5), 0.5, 0.8)
		Course.WINDMILL:
			_set_orbit(WINDMILL_ORBIT_RADIUS, Vector2(1.1, 0.4), 1.1, 1.5)
		Course.PILLAR_RING:
			_ring_blocks(
				PILLAR_COUNT, PILLAR_RING_RADIUS, Vector2(PILLAR_HALF, PILLAR_HALF), ring_turn
			)
			_set_orbit(OUTER_ORBIT_RADIUS, Vector2(1.2, 0.4), 0.4, 0.6)
		Course.BUMPER_FIELD:
			_ring_blocks(
				BUMPER_COUNT, BUMPER_RING_RADIUS, Vector2(BUMPER_HALF, BUMPER_HALF), ring_turn
			)
			_set_orbit(BUMPER_ORBIT_RADIUS, Vector2(1.0, 0.4), 0.6, 0.9)
	bar_phase = rng.randf_range(0.0, TAU)


func _set_orbit(radius: float, half: Vector2, speed_min: float, speed_max: float) -> void:
	bar_range = radius
	bar_half = half
	bar_speed = rng.randf_range(speed_min, speed_max)


## `count` blocks evenly spaced on a circle around the cup, rotated by `turn`.
func _ring_blocks(count: int, radius: float, half: Vector2, turn: float) -> void:
	for i in count:
		var angle := turn + TAU * float(i) / float(count)
		blocks.append({"pos": cup_pos + Vector2.RIGHT.rotated(angle) * radius, "half": half})


func _handle_input(slot: int, data: Dictionary) -> void:
	if bool(sunk[slot]):
		return
	var aim := Vector2(float(data.get("ax", 0.0)), float(data.get("ay", 0.0)))
	if aim.length() > 0.1:
		aims[slot] = aim.normalized()
	if data.get("putt", false) and _at_rest(slot):
		_putt(slot, clampf(float(data.get("power", 0.0)), 0.0, 1.0))


func _tick(delta: float) -> void:
	# The guard bar orbits the cup (#1071) — radially fair: it threatens every
	# approach angle equally over time.
	var theta := elapsed * bar_speed + bar_phase
	bar_x = cup_pos.x + cos(theta) * bar_range
	bar_y = cup_pos.y + sin(theta) * bar_range
	for slot: int in slots:
		if bool(sunk[slot]):
			continue
		if _at_rest(slot):
			rest_time[slot] = float(rest_time[slot]) + delta
			if float(rest_time[slot]) >= SHOT_CLOCK_SEC:
				_putt(slot, AUTO_PUTT_POWER)
			continue
		_roll(slot, delta)
	_check_end()


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		var pos: Vector2 = positions[slot]
		var aim: Vector2 = aims[slot]
		players[slot] = [
			snappedf(pos.x, 0.01),
			snappedf(pos.y, 0.01),
			int(strokes[slot]),
			1 if bool(sunk[slot]) else 0,
			snappedf(aim.x, 0.01),
			snappedf(aim.y, 0.01),
			1 if _at_rest(slot) else 0,
		]
	var block_list: Array = []
	for block: Dictionary in blocks:
		var half: Vector2 = block.half
		block_list.append(
			[snappedf(block.pos.x, 0.01), snappedf(block.pos.y, 0.01), half.x, half.y]
		)
	return {
		"players": players,
		"course": course,
		"cup": [snappedf(cup_pos.x, 0.01), snappedf(cup_pos.y, 0.01)],
		# Bar carries its geometry now (#793): [x, y, half_x, half_y].
		"bar": [snappedf(bar_x, 0.01), snappedf(bar_y, 0.01), bar_half.x, bar_half.y],
		"blocks": block_list,
		"shot_clock": SHOT_CLOCK_SEC,
	}


## Sunk players rank by strokes (fewer first, ties grouped); everyone who
## didn't hole out ranks after, nearest-the-cup first.
func _rank_players() -> Array:
	var by_strokes := {}
	var unsunk: Array = []
	for slot: int in slots:
		if bool(sunk[slot]):
			var s: int = strokes[slot]
			if not by_strokes.has(s):
				by_strokes[s] = []
			by_strokes[s].append(slot)
		else:
			unsunk.append(slot)
	var stroke_values := by_strokes.keys()
	stroke_values.sort()
	var placements: Array = []
	for value: int in stroke_values:
		placements.append(by_strokes[value])
	unsunk.sort_custom(
		func(a: int, b: int) -> bool:
			return positions[a].distance_to(cup_pos) < positions[b].distance_to(cup_pos)
	)
	for slot: int in unsunk:
		placements.append([slot])
	return placements


func _at_rest(slot: int) -> bool:
	return (velocities[slot] as Vector2).length() <= STOP_SPEED


func _putt(slot: int, power: float) -> void:
	velocities[slot] = (aims[slot] as Vector2) * MAX_POWER * power
	strokes[slot] = int(strokes[slot]) + 1
	rest_time[slot] = 0.0


func _roll(slot: int, delta: float) -> void:
	var pos: Vector2 = positions[slot] + (velocities[slot] as Vector2) * delta
	var vel: Vector2 = velocities[slot]
	# Outer walls.
	var limit := ARENA_HALF - BALL_RADIUS
	if absf(pos.x) > limit:
		pos.x = clampf(pos.x, -limit, limit)
		vel.x = -vel.x * RESTITUTION
	if absf(pos.y) > limit:
		pos.y = clampf(pos.y, -limit, limit)
		vel.y = -vel.y * RESTITUTION
	positions[slot] = pos
	velocities[slot] = vel
	# Obstacles.
	for block: Dictionary in blocks:
		_bounce_box(slot, block.pos, block.half)
	_bounce_box(slot, Vector2(bar_x, bar_y), bar_half)
	# Friction.
	var speed := (velocities[slot] as Vector2).length()
	speed = maxf(0.0, speed - FRICTION * delta)
	if speed <= STOP_SPEED:
		velocities[slot] = Vector2.ZERO
	else:
		velocities[slot] = (velocities[slot] as Vector2).normalized() * speed
	# Sink check.
	if (
		(positions[slot] as Vector2).distance_to(cup_pos) <= CUP_RADIUS
		and (velocities[slot] as Vector2).length() <= SINK_MAX_SPEED
	):
		sunk[slot] = true
		positions[slot] = cup_pos
		velocities[slot] = Vector2.ZERO


## Circle-vs-AABB: if the ball overlaps the block, push it to the surface and
## reflect the incoming velocity component.
func _bounce_box(slot: int, center: Vector2, half: Vector2) -> void:
	# Circle-vs-AABB bounce with penetration ejection — shared math (#945).
	var result := SimGeometry.bounce_circle_box(
		positions[slot], velocities[slot], center, half, BALL_RADIUS, RESTITUTION
	)
	positions[slot] = result.pos
	velocities[slot] = result.vel


func _check_end() -> void:
	if finished:
		return
	for slot: int in slots:
		if not bool(sunk[slot]):
			return
	finish(_rank_players())
