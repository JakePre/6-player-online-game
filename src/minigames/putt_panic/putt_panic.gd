class_name PuttPanic
extends MinigameBase
## Putt Panic (M14-08, PHASE2.md §8): a mini-golf homage — everyone putts on
## one shared green toward a single cup, simultaneously, fewest strokes wins.
## Aim + charge + release; the ball rolls with friction, bounces off the walls,
## static blocks and a sliding bar, and drops if it reaches the cup slowly
## enough. A 30 s shot clock auto-putts idlers. Server-side simulation only —
## the client renders get_snapshot().

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

## Seeded course generation (#793): each round's cup, flanking gate blocks, and
## guard bar are drawn from the round seed within these fair bounds, so the
## layout is different every play but the challenge stays balanced — the cup is
## always up-field, the gate always leaves a clear central lane (its blocks sit
## at ±(gap + block-half), so the lane spans ±gap ≥ GATE_GAP_MIN), and the bar
## always sweeps across between the gate and the cup.
const CUP_X_RANGE := 2.5
const CUP_Y_MIN := 5.5
const CUP_Y_MAX := 7.5
const GATE_Y_MIN := -0.5
const GATE_Y_MAX := 2.5
const GATE_GAP_MIN := 2.2
const GATE_GAP_MAX := 3.4
const GATE_HALF_MIN := 0.8
const GATE_HALF_MAX := 1.3
const BAR_Y_MIN := 3.2
const BAR_Y_MAX := 4.6
const BAR_HALF_X_MIN := 1.3
const BAR_HALF_X_MAX := 1.9
const BAR_RANGE_MIN := 3.0
const BAR_RANGE_MAX := 4.5
const BAR_SPEED_MIN := 0.8
const BAR_SPEED_MAX := 1.35

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
## The seeded course (#793): cup, static gate blocks ({pos, half}), and the
## sliding bar's geometry — set once in _setup() and replicated so every peer
## and the view agree on the same layout.
var cup_pos := Vector2(0.0, 6.5)
var blocks: Array = []
var bar_half := Vector2(1.6, 0.5)
var bar_y := 3.6
var bar_range := 4.0
var bar_speed := 1.1
var bar_phase := 0.0
## Sliding bar centre this tick (replicated so the view need not recompute).
var bar_x := 0.0


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
	for i in slots.size():
		var slot: int = slots[i]
		var spread := (i - (slots.size() - 1) / 2.0) * 1.6
		positions[slot] = Vector2(spread, -7.0)
		velocities[slot] = Vector2.ZERO
		aims[slot] = (cup_pos - positions[slot]).normalized()
		strokes[slot] = 0
		sunk[slot] = false
		rest_time[slot] = 0.0


## Draw a fresh course from the round seed (#793). The two-block gate always
## leaves a clear central lane and the cup always sits up-field, so every seed
## is solvable and roughly equal in difficulty — only the look and the required
## line change from round to round.
func _generate_course() -> void:
	cup_pos = Vector2(
		rng.randf_range(-CUP_X_RANGE, CUP_X_RANGE), rng.randf_range(CUP_Y_MIN, CUP_Y_MAX)
	)
	var gate_y := rng.randf_range(GATE_Y_MIN, GATE_Y_MAX)
	var gap := rng.randf_range(GATE_GAP_MIN, GATE_GAP_MAX)
	var half := Vector2(rng.randf_range(GATE_HALF_MIN, GATE_HALF_MAX), rng.randf_range(0.5, 0.8))
	blocks = [
		{"pos": Vector2(-(gap + half.x), gate_y), "half": half},
		{"pos": Vector2(gap + half.x, gate_y), "half": half},
	]
	bar_half = Vector2(rng.randf_range(BAR_HALF_X_MIN, BAR_HALF_X_MAX), 0.5)
	bar_y = rng.randf_range(BAR_Y_MIN, BAR_Y_MAX)
	bar_range = rng.randf_range(BAR_RANGE_MIN, BAR_RANGE_MAX)
	bar_speed = rng.randf_range(BAR_SPEED_MIN, BAR_SPEED_MAX)
	bar_phase = rng.randf_range(0.0, TAU)


func _handle_input(slot: int, data: Dictionary) -> void:
	if bool(sunk[slot]):
		return
	var aim := Vector2(float(data.get("ax", 0.0)), float(data.get("ay", 0.0)))
	if aim.length() > 0.1:
		aims[slot] = aim.normalized()
	if data.get("putt", false) and _at_rest(slot):
		_putt(slot, clampf(float(data.get("power", 0.0)), 0.0, 1.0))


func _tick(delta: float) -> void:
	bar_x = bar_range * sin(elapsed * bar_speed + bar_phase)
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
	var pos: Vector2 = positions[slot]
	var closest := Vector2(
		clampf(pos.x, center.x - half.x, center.x + half.x),
		clampf(pos.y, center.y - half.y, center.y + half.y)
	)
	var to_ball := pos - closest
	var dist := to_ball.length()
	if dist >= BALL_RADIUS:
		return
	var normal: Vector2
	if dist > 0.0001:
		normal = to_ball / dist
	else:
		# Centre inside the box: eject along the axis of least penetration.
		var px := half.x - absf(pos.x - center.x)
		var py := half.y - absf(pos.y - center.y)
		normal = (
			Vector2(signf(pos.x - center.x), 0.0)
			if px < py
			else Vector2(0.0, signf(pos.y - center.y))
		)
	positions[slot] = closest + normal * BALL_RADIUS
	var vel: Vector2 = velocities[slot]
	if vel.dot(normal) < 0.0:
		velocities[slot] = (vel - 2.0 * vel.dot(normal) * normal) * RESTITUTION


func _check_end() -> void:
	if finished:
		return
	for slot: int in slots:
		if not bool(sunk[slot]):
			return
	finish(_rank_players())
