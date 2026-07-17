class_name TumbleRun
extends MinigameBase
## Tumble Run (M14-09, PHASE2.md §8, owner-approved design on #545): a
## one-screen vertical climb on the M14-00 side-view bones. The framework
## has no camera scrolling, so the gauntlet is a fixed tall stage — ladder
## the zigzag ledges to the summit while falling boulders and crumbling
## ledges knock you back down. No elimination: a knocked-down duck just
## loses height and climbs again (the comedy of the tumble). Placement is
## summit order, then highest reached when the clock runs out.
##
## Hazards are game-side timed entities (positions + timers applying
## sim.apply_impulse on contact), never framework changes — precedent:
## Meteor Shower's server-side hazards.

enum Phase { COUNTDOWN, CLIMB, DONE }

const COUNTDOWN_SEC := 1.5
const ROUND_CAP_SEC := 75.0
## #1065 (owner playtest): reaching the top has to END things. The first
## summit shrinks the remaining clock to at most this, so stragglers race a
## visible countdown instead of the round idling out the full cap.
const FINISH_WINDOW_SEC := 20.0

const GOAL_HEIGHT := 30.0
const LEDGE_COUNT := 9
const LEDGE_RISE := 3.1
const LEDGE_WIDTH := 4.0
const LEDGE_THICKNESS := 0.4
const LEDGE_X := 4.2
## The climb is the whole game, so it needs a jump that actually clears a
## zigzag ledge (#778): the shared default (apex ~2.6 u) can't reach the 3.1 u
## rise, let alone while crossing sideways to the alternating ledge. This lifts
## the apex to ~4.3 u so a well-timed diagonal jump lands the next ledge.
const JUMP_VELOCITY := 18.0

## Crumbling ledges cycle solid → gone → back, staggered by index so the
## whole climb never vanishes at once.
const CRUMBLE_SOLID_SEC := 3.0
const CRUMBLE_GONE_SEC := 1.6

const BOULDER_INTERVAL := 1.4
const BOULDER_SPEED := 7.0
const BOULDER_RADIUS := 0.6
const BOULDER_HIT_RADIUS := 0.9

## A hazard hit pops the duck off its perch (sideways + up) so it tumbles,
## and briefly stuns so the fall is committed.
const KNOCKDOWN := Vector2(5.0, 4.0)
const STUN_SEC := 0.5

## get_snapshot() wire shapes (#708): named indices for the positional arrays
## the view and brain read. Array SHAPE on the wire is unchanged — additive.
## players[0..2] (x, y, facing) match SideScrollView's shared render_side_scroll()
## contract; PS_FLAGS is this game's own addition (bit0 stun, bit1 summit,
## bit2 grounded).
const PS_X := 0
const PS_Y := 1
const PS_FACING := 2
const PS_FLAGS := 3
const PS_COUNT := 4

const BL_X := 0
const BL_Y := 1

var sim: SideScrollSim
var phase: Phase = Phase.COUNTDOWN
var phase_left := COUNTDOWN_SEC
## slot -> {height, summit, summit_at, stun}
var climbers := {}
## Each {pos, vel, life}.
var boulders: Array[Dictionary] = []
## Parallel to _crumble_ledges(): true while that ledge is solid.
var crumble_state: Array[bool] = []
var summit_order: Array = []

var _boulder_accum := 0.0
var _crumble_clock := 0.0


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"tumble_run",
				"controls": "Move — A/D / stick · Jump — W / stick up",
				# Structured spec (#832/#844): the side-scroll template shape
				# (lr-cluster move + move_up jump, no action button here).
				"control_spec":
				[
					{"verb": "Move", "input": InputGlyphs.CLUSTER_MOVE_LR},
					{"verb": "Jump", "input": &"move_up"},
				],
				"name": "Tumble Run",
				"category": MinigameMeta.Category.FFA,
				"min_players": 2,
				"max_players": 8,
				"duration_sec": COUNTDOWN_SEC + ROUND_CAP_SEC + 3.0,
				"rules":
				(
					"Climb to the top! Dodge boulders and crumbling ledges — first up "
					+ "wins, and the first finisher starts the final countdown."
				),
			}
		)
	)


static func stage_bounds() -> Rect2:
	return Rect2(-9.0, -4.0, 18.0, GOAL_HEIGHT + 10.0)


## Wide ground floor plus the summit platform — always solid.
static func solid_platforms() -> Array[Rect2]:
	return (
		[
			Rect2(-8.0, -1.0, 16.0, 1.0),
			Rect2(-3.0, GOAL_HEIGHT, 6.0, 0.5),
		]
		as Array[Rect2]
	)


## The zigzag climbing ledges (one-way), alternating side to side. Static so
## the view draws the identical ladder.
static func ledges() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for i in LEDGE_COUNT:
		var side := 1.0 if i % 2 == 0 else -1.0
		var y := 2.0 + float(i) * LEDGE_RISE
		rects.append(Rect2(side * LEDGE_X - LEDGE_WIDTH / 2.0, y, LEDGE_WIDTH, LEDGE_THICKNESS))
	return rects


## Every third ledge crumbles; the rest are stable footing.
static func _crumble_indices() -> Array[int]:
	var out: Array[int] = []
	for i in LEDGE_COUNT:
		if i % 3 == 1:
			out.append(i)
	return out


func _setup() -> void:
	sim = SideScrollSim.new()
	sim.bounds = stage_bounds()
	sim.jump_velocity = JUMP_VELOCITY
	crumble_state.resize(LEDGE_COUNT)
	crumble_state.fill(true)
	_rebuild_platforms()
	phase = Phase.COUNTDOWN
	phase_left = COUNTDOWN_SEC
	var spawns := _spawn_points()
	for i in slots.size():
		sim.add_body(slots[i], spawns[i])
		climbers[slots[i]] = {"height": spawns[i].y, "summit": false, "summit_at": 0.0, "stun": 0.0}


## Solid floor + summit, plus every currently-solid crumble ledge and all
## stable ledges, pushed to the sim as one-way climbing platforms.
func _rebuild_platforms() -> void:
	sim.solids = solid_platforms()
	var one_way: Array[Rect2] = []
	var all := ledges()
	for i in all.size():
		if crumble_state[i]:
			one_way.append(all[i])
	sim.one_way = one_way


func _spawn_points() -> Array[Vector2]:
	var points: Array[Vector2] = []
	var count := slots.size()
	for i in count:
		var t := (float(i) + 0.5) / float(count)
		points.append(Vector2(lerpf(-6.0, 6.0, t), 0.7))
	return points


func _handle_input(slot: int, data: Dictionary) -> void:
	if phase != Phase.CLIMB:
		return
	var climber: Dictionary = climbers.get(slot, {})
	# A summited climber is FINISHED (#1065) — their rank is locked and their
	# duck stays parked on the platform instead of hopping back into the run.
	if climber.is_empty() or float(climber.stun) > 0.0 or bool(climber.summit):
		return
	if data.has("mx"):
		sim.set_move(slot, clampf(float(data.mx), -1.0, 1.0))
	if data.get("jump", false):
		sim.press_jump(slot)


func _tick(delta: float) -> void:
	for slot: int in climbers:
		climbers[slot].stun = maxf(0.0, float(climbers[slot].stun) - delta)
	phase_left -= delta
	match phase:
		Phase.COUNTDOWN:
			sim.step(delta)
			if phase_left <= 0.0:
				phase = Phase.CLIMB
				phase_left = ROUND_CAP_SEC
		Phase.CLIMB:
			_tick_climb(delta)


func _tick_climb(delta: float) -> void:
	_tick_crumble(delta)
	# Stunned climbers keep their move intent frozen so the tumble commits.
	for slot: int in climbers:
		if float(climbers[slot].stun) > 0.0:
			sim.set_move(slot, 0.0)
	sim.step(delta)
	_reset_fallen()
	_track_heights()
	_tick_boulders(delta)
	if _all_summited() or phase_left <= 0.0:
		phase = Phase.DONE
		finish(_rank_players())


## Falling off the stage drops you back to the base to climb again (#778, owner
## call): no elimination (the #545 design), just the lost height — a tumble into
## the pit costs you progress, it doesn't end your run. Keeps the best height
## already tracked, so a fall never lowers your standing, only stalls it.
func _reset_fallen() -> void:
	for slot: int in sim.out_slots():
		var climber: Dictionary = climbers.get(slot, {})
		if climber.is_empty() or bool(climber.summit):
			continue
		var fallen_x: float = (sim.body_of(slot).pos as Vector2).x
		sim.remove_body(slot)
		sim.add_body(slot, Vector2(clampf(fallen_x, -6.0, 6.0), 0.7))
		climber.stun = 0.0


func _tick_crumble(delta: float) -> void:
	_crumble_clock += delta
	var cycle := CRUMBLE_SOLID_SEC + CRUMBLE_GONE_SEC
	var changed := false
	var crumble := _crumble_indices()
	for offset in crumble.size():
		var index: int = crumble[offset]
		# Stagger each crumble ledge by a slice of the cycle.
		var phase_offset := float(offset) * cycle / maxf(1.0, float(crumble.size()))
		var t := fmod(_crumble_clock + phase_offset, cycle)
		var solid := t < CRUMBLE_SOLID_SEC
		if crumble_state[index] != solid:
			crumble_state[index] = solid
			changed = true
	if changed:
		_rebuild_platforms()


func _track_heights() -> void:
	for slot: int in climbers:
		var body := sim.body_of(slot)
		if body.is_empty():
			continue
		var climber: Dictionary = climbers[slot]
		var y: float = (body.pos as Vector2).y
		climber.height = maxf(float(climber.height), y)
		# LANDING on the summit platform finishes the run (#1065) — a stray
		# airborne arc past the goal line doesn't count until the feet do.
		if not bool(climber.summit) and y >= GOAL_HEIGHT and int(body.get("grounded", 0)) == 1:
			climber.summit = true
			climber.summit_at = elapsed
			summit_order.append(slot)
			sim.set_move(slot, 0.0)
			# The first finisher puts the rest of the field on the clock.
			if summit_order.size() == 1:
				phase_left = minf(phase_left, FINISH_WINDOW_SEC)


func _tick_boulders(delta: float) -> void:
	_boulder_accum += delta
	if _boulder_accum >= BOULDER_INTERVAL:
		_boulder_accum -= BOULDER_INTERVAL
		var x := rng.randf_range(-7.0, 7.0)
		boulders.append({"pos": Vector2(x, GOAL_HEIGHT + 4.0), "vel": Vector2(0.0, -BOULDER_SPEED)})
	var alive: Array[Dictionary] = []
	for boulder in boulders:
		boulder.pos = (boulder.pos as Vector2) + (boulder.vel as Vector2) * delta
		if (boulder.pos as Vector2).y < -2.0:
			continue
		_boulder_contacts(boulder.pos)
		alive.append(boulder)
	boulders = alive


func _boulder_contacts(center: Vector2) -> void:
	for slot: int in climbers:
		var climber: Dictionary = climbers[slot]
		if bool(climber.summit) or float(climber.stun) > 0.0:
			continue
		var body := sim.body_of(slot)
		if body.is_empty():
			continue
		if (body.pos as Vector2).distance_to(center) <= BOULDER_HIT_RADIUS:
			_knock_down(slot, climber, center)


func _knock_down(slot: int, climber: Dictionary, from_pos: Vector2) -> void:
	climber.stun = STUN_SEC
	var away := 1.0 if (sim.body_of(slot).pos as Vector2).x >= from_pos.x else -1.0
	sim.apply_impulse(slot, Vector2(away * KNOCKDOWN.x, KNOCKDOWN.y))


func _all_summited() -> bool:
	for slot: int in climbers:
		if not bool(climbers[slot].summit):
			return false
	return true


## Summiters first in the order they topped out, then the rest by highest
## point reached (ties grouped).
func _rank_players() -> Array:
	var placements: Array = []
	for slot: int in summit_order:
		placements.append([slot])
	var rest: Array = []
	for slot: int in slots:
		if not bool(climbers[slot].summit):
			rest.append(slot)
	rest.sort_custom(
		func(a: int, b: int) -> bool: return float(climbers[a].height) > float(climbers[b].height)
	)
	var group: Array = []
	for slot: int in rest:
		if (
			group.is_empty()
			or is_equal_approx(float(climbers[int(group[-1])].height), float(climbers[slot].height))
		):
			group.append(slot)
		else:
			placements.append(group)
			group = [slot]
	if not group.is_empty():
		placements.append(group)
	return placements


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in climbers:
		var climber: Dictionary = climbers[slot]
		var body := sim.body_of(slot)
		var pos: Vector2 = body.get("pos", Vector2.ZERO)
		var flags := 0
		if float(climber.stun) > 0.0:
			flags |= 1
		if bool(climber.summit):
			flags |= 2
		if int(body.get("grounded", 0)) == 1:
			flags |= 4
		players[slot] = [
			snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), int(body.get("facing", 1)), flags
		]
	var boulder_list: Array = []
	for boulder in boulders:
		var pos: Vector2 = boulder.pos
		boulder_list.append([snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)])
	return {
		"players": players,
		"boulders": boulder_list,
		"crumble": crumble_state.duplicate(),
		"phase": int(phase),
		# The climb clock (#1065): lets the view surface the finish-window
		# countdown once the first climber tops out.
		"clock": snappedf(maxf(phase_left, 0.0), 0.1),
		"standings": _standings(),
	}


## Live order: summiters (by finish), then everyone else by height.
func _standings() -> Array:
	var order: Array = summit_order.duplicate()
	var rest: Array = []
	for slot: int in climbers:
		if not bool(climbers[slot].summit):
			rest.append(slot)
	rest.sort_custom(
		func(a: int, b: int) -> bool: return float(climbers[a].height) > float(climbers[b].height)
	)
	order.append_array(rest)
	return order
