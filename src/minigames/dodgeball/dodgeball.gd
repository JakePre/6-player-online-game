class_name Dodgeball
extends MinigameBase
## Dodgeball (#791, retires ro_sham_bo): the party sport the roster lacked —
## the only game where you throw at other *players*. Grab a ball by walking
## over it, aim with your movement facing, action_primary throws. A hit
## eliminates the target — UNLESS they catch it (action_primary timed as the
## ball arrives, a tight window), which eliminates the thrower instead. Last
## side standing wins; elimination order is placement (Thin Ice rules). Two
## teams split at the center line at 4+ players (Fort Siege clamp keeps each
## side home), free-for-all at 2-3. Server-side simulation only — the client
## renders get_snapshot().

enum BallState { LOOSE, HELD, FLYING }

## Court half-extent at the 6-player baseline; grows with the lobby (M15) so
## per-player floor area holds. Split along x: team 0 owns -x, team 1 owns +x.
const ARENA_HALF := 9.0
const MOVE_SPEED := 5.5
const PLAYER_RADIUS := 0.4
## Neutral strip at the center line (team mode): nobody stands on the line, so
## the split reads and point-blank throws across it aren't free. Must stay
## well under PICKUP_RADIUS: center-spawned balls sit at x=0.0, so the gap is
## also the closest either team can ever get to one (#1035 — at 0.7 == the old
## PICKUP_RADIUS, that distance was only reachable with perfect y-alignment,
## making every centered ball practically unpickupable in team mode).
const CENTER_GAP := 0.3

## Thrown-ball flight and the two resolution radii. CATCH_RADIUS is larger than
## HIT_RADIUS so an approaching ball crosses the catch band first: a buffered
## press there catches; without one it carries on into the hit band.
const THROW_SPEED := 15.0
const BALL_RADIUS := 0.3
const HIT_RADIUS := 0.75
const CATCH_RADIUS := 1.15
## Walking over a loose ball this close picks it up.
const PICKUP_RADIUS := 0.7
## Pressing action_primary while empty-handed buffers a catch attempt this long
## (Quick Draw's input-timing feel) — the ball must reach the catch band while
## the buffer is live.
const CATCH_WINDOW := 0.3

## Balls seeded on the center line at setup (~one per two players), plus one
## more every EXTRA_BALL_SEC so an end-game with cautious survivors can't stall,
## capped so dense lobbies don't drown in balls.
const EXTRA_BALL_SEC := 8.0
const MAX_BALLS := 8

## Snapshot player-array indices (#708 named-index convention).
const PS_X := 0
const PS_Y := 1
const PS_FACING_X := 2
const PS_FACING_Y := 3
const PS_HOLDING := 4  # 1 while carrying a ball
const PS_TEAM := 5  # team index, or -1 in FFA
const PS_COUNT := 6
## #946 wire-shape tripwire: the declared type of each slot in a `players`
## snapshot row. Validated by test_snapshot_schema against get_snapshot().
const PLAYER_SCHEMA := [TYPE_FLOAT, TYPE_FLOAT, TYPE_FLOAT, TYPE_FLOAT, TYPE_INT, TYPE_INT]

## Snapshot ball-array indices.
const BL_X := 0
const BL_Y := 1
const BL_STATE := 2
const BL_HOLDER := 3  # holder slot when HELD/FLYING-owner, else -1
const BL_COUNT := 4

var positions := {}
var move_dirs := {}
## Aim direction per slot: last non-zero move, seeded toward the enemy side.
var facings := {}
## elapsed time until which a slot's buffered catch attempt stays live.
var catch_until := {}
## Teams as arrays of slots; empty in FFA. team_of(slot) reads this.
var teams: Array = []
## Ball dicts: {pos: Vector2, vel: Vector2, state: int, holder: int, thrower: int}.
var balls: Array = []
## Slots in elimination order; same-tick KOs share a tie group (Thin Ice).
var fall_order: Array = []

var _half := ARENA_HALF
var _pending_falls: Array = []
var _next_ball_at := EXTRA_BALL_SEC


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"dodgeball",
				"name": "Dodgeball",
				"category": MinigameMeta.Category.FFA,
				"min_players": 2,
				"max_players": 12,
				"duration_sec": 60.0,
				"rules":
				(
					"Grab a ball and peg your rivals out! A hit eliminates —"
					+ " unless they catch it, and then YOU'RE out. Last standing wins."
				),
				"controls": "Move — WASD / left stick · Grab / Throw / Catch — SPACE / pad A",
				# Device-aware structured spec (#832): move + one context verb.
				"control_spec":
				[
					{"verb": "Move", "input": InputGlyphs.CLUSTER_MOVE},
					{
						"verb": "Grab / Throw / Catch",
						"input": &"action_primary",
						"note": "catch a throw to reflect it!"
					},
				],
			}
		)
	)


func _setup() -> void:
	_half = MinigameScaling.arena_half(ARENA_HALF, slots.size())
	# Classic team dodgeball at 4+; below that a court split leaves 1-per-side,
	# which isn't a game — so 2-3 players run free-for-all.
	if slots.size() >= 4:
		_setup_teams()
	else:
		_setup_ffa()
	_spawn_center_balls(maxi(1, slots.size() / 2))


func _setup_teams() -> void:
	team_mode = true
	team_count = 2
	var shuffled := slots.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: int = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp
	teams = [shuffled.slice(0, shuffled.size() / 2), shuffled.slice(shuffled.size() / 2)]
	for team_index in teams.size():
		var side := -1.0 if team_index == 0 else 1.0
		var group: Array = teams[team_index]
		for i in group.size():
			var slot: int = group[i]
			var spread := (float(i) - (group.size() - 1) / 2.0) * 2.2
			_init_player(slot, Vector2(side * _half * 0.55, clampf(spread, -_half, _half)))
			facings[slot] = Vector2(-side, 0.0)  # face across the line


func _setup_ffa() -> void:
	team_mode = false
	teams = []
	for i in slots.size():
		var angle := TAU * i / slots.size()
		var pos := Vector2(cos(angle), sin(angle)) * _half * 0.6
		_init_player(slots[i], pos)
		facings[slots[i]] = (-pos).normalized() if pos.length() > 0.01 else Vector2.RIGHT


func _init_player(slot: int, pos: Vector2) -> void:
	positions[slot] = pos
	move_dirs[slot] = Vector2.ZERO
	catch_until[slot] = -1.0


func _spawn_center_balls(count: int) -> void:
	for i in mini(count, MAX_BALLS):
		var y := 0.0 if count == 1 else lerpf(-_half * 0.6, _half * 0.6, float(i) / (count - 1))
		balls.append(_loose_ball(Vector2(0.0, y)))


func _loose_ball(pos: Vector2) -> Dictionary:
	return {"pos": pos, "vel": Vector2.ZERO, "state": BallState.LOOSE, "holder": -1, "thrower": -1}


func _handle_input(slot: int, data: Dictionary) -> void:
	if not _is_in(slot):
		return
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)
	if not bool(data.get("act", false)):
		return
	var held: Variant = _ball_held_by(slot)
	if held != null:
		_throw(slot, held)
	else:
		# Empty-handed press buffers a catch (beats the hit check on arrival).
		catch_until[slot] = elapsed + CATCH_WINDOW


func _tick(delta: float) -> void:
	var alive := _in_slots()
	for slot: int in alive:
		var dir: Vector2 = move_dirs[slot]
		if dir.length() > 0.01:
			facings[slot] = dir.normalized()
		positions[slot] = _clamp_to_court(slot, positions[slot] + dir * MOVE_SPEED * delta)
	_resolve_pickups(alive)
	_carry_held_balls(alive)
	_tick_flying(delta, alive)
	_tick_ball_spawn()
	_flush_falls()
	_check_end()


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		if not _is_in(slot):
			continue
		var pos: Vector2 = positions[slot]
		var facing: Vector2 = facings.get(slot, Vector2.RIGHT)
		players[slot] = [
			snappedf(pos.x, 0.01),
			snappedf(pos.y, 0.01),
			snappedf(facing.x, 0.01),
			snappedf(facing.y, 0.01),
			1 if _ball_held_by(slot) != null else 0,
			_team_of(slot),
		]
	var ball_list: Array = []
	for ball: Dictionary in balls:
		var pos: Vector2 = ball.pos
		ball_list.append(
			[snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), int(ball.state), int(ball.holder)]
		)
	return {
		"players": players,
		"balls": ball_list,
		"teams": teams.duplicate(true),
		"team_mode": team_mode,
		"half": snappedf(_half, 0.01),
		"center_gap": CENTER_GAP,
		"fallen": fall_order,
	}


## Timeout ranking. Team mode: the side with more survivors wins (tie = full
## tie), matching the SPEC $5 team tables. FFA: survivors tie ahead of the
## fallen, in reverse elimination order (Thin Ice).
func _rank_players() -> Array:
	if team_mode:
		return _team_placements()
	var survivors := _in_slots()
	var placements: Array = []
	if not survivors.is_empty():
		placements.append(survivors)
	return placements + _out_placements()


# --- Throwing, catching, hitting ---------------------------------------------


func _throw(slot: int, ball: Dictionary) -> void:
	var facing: Vector2 = facings.get(slot, Vector2.RIGHT)
	if facing.length() < 0.01:
		facing = Vector2.RIGHT
	ball.state = BallState.FLYING
	ball.holder = slot
	ball.thrower = slot
	ball.vel = facing.normalized() * THROW_SPEED
	# Launch a hair ahead of the thrower so it clears their own body radius.
	ball.pos = (positions[slot] as Vector2) + facing.normalized() * (PLAYER_RADIUS + BALL_RADIUS)


func _tick_flying(delta: float, alive: Array) -> void:
	for ball: Dictionary in balls:
		if int(ball.state) != BallState.FLYING:
			continue
		ball.pos = (ball.pos as Vector2) + (ball.vel as Vector2) * delta
		if _out_of_bounds(ball.pos):
			ball.state = BallState.LOOSE
			ball.vel = Vector2.ZERO
			ball.holder = -1
			ball.pos = (ball.pos as Vector2).clamp(Vector2(-_half, -_half), Vector2(_half, _half))
			continue
		_resolve_flying_ball(ball, alive)


## Resolve the nearest eligible target for one flying ball: a live catch buffer
## inside the catch band reflects it (thrower out, catcher holds); otherwise the
## hit band eliminates the target. The thrower is never their own victim.
func _resolve_flying_ball(ball: Dictionary, alive: Array) -> void:
	var thrower := int(ball.thrower)
	var nearest := -1
	var nearest_d := INF
	for slot: int in alive:
		if slot == thrower or not _is_hostile(thrower, slot):
			continue
		var d: float = (ball.pos as Vector2).distance_to(positions[slot])
		if d < nearest_d:
			nearest_d = d
			nearest = slot
	if nearest == -1:
		return
	if nearest_d <= CATCH_RADIUS and _catch_active(nearest):
		_eliminate(thrower)
		ball.state = BallState.HELD
		ball.holder = nearest
		ball.thrower = -1
		catch_until[nearest] = -1.0
	elif nearest_d <= HIT_RADIUS:
		_eliminate(nearest)
		ball.state = BallState.LOOSE
		ball.holder = -1
		ball.thrower = -1
		ball.vel = Vector2.ZERO


func _resolve_pickups(alive: Array) -> void:
	for slot: int in alive:
		if _ball_held_by(slot) != null:
			continue
		for ball: Dictionary in balls:
			if int(ball.state) != BallState.LOOSE:
				continue
			if (positions[slot] as Vector2).distance_to(ball.pos) <= PICKUP_RADIUS:
				ball.state = BallState.HELD
				ball.holder = slot
				break


func _carry_held_balls(alive: Array) -> void:
	for ball: Dictionary in balls:
		if int(ball.state) == BallState.HELD and int(ball.holder) in alive:
			ball.pos = positions[int(ball.holder)]


func _tick_ball_spawn() -> void:
	if balls.size() >= MAX_BALLS:
		return
	if elapsed < _next_ball_at:
		return
	_next_ball_at += EXTRA_BALL_SEC
	balls.append(_loose_ball(Vector2(0.0, rng.randf_range(-_half * 0.6, _half * 0.6))))


# --- Eliminations & endgame --------------------------------------------------


func _eliminate(slot: int) -> void:
	if slot in _pending_falls or not _is_in(slot):
		return
	_pending_falls.append(slot)
	# A ball the eliminated player was carrying drops loose where they stood.
	var held: Variant = _ball_held_by(slot)
	if held != null:
		held.state = BallState.LOOSE
		held.holder = -1
		held.pos = positions[slot]


func _flush_falls() -> void:
	if not _pending_falls.is_empty():
		fall_order.append(_pending_falls.duplicate())
		_pending_falls.clear()


func _check_end() -> void:
	if finished:
		return
	if team_mode:
		var live_teams := 0
		for team: Array in teams:
			if team.any(_is_in):
				live_teams += 1
		if live_teams <= 1:
			finish(_team_placements())
		return
	var survivors := _in_slots()
	if survivors.size() > 1:
		return
	var placements: Array = []
	if not survivors.is_empty():
		placements.append(survivors)
	finish(placements + _out_placements())


## Team-level placement: the side with more survivors first (whole teams as tie
## groups, per the SPEC $5 team tables); an equal count is a full tie.
func _team_placements() -> Array:
	var a := _alive_count(0)
	var b := _alive_count(1)
	if a == b:
		return [slots.duplicate()]
	var order := [teams[0], teams[1]] if a > b else [teams[1], teams[0]]
	return [order[0].duplicate(), order[1].duplicate()]


func _alive_count(team_index: int) -> int:
	var count := 0
	for slot: int in teams[team_index]:
		if _is_in(slot):
			count += 1
	return count


# --- Helpers -----------------------------------------------------------------


func _clamp_to_court(slot: int, pos: Vector2) -> Vector2:
	var min_x := -_half
	var max_x := _half
	if team_mode:
		# Each side is clamped home with a neutral strip at the line (#808 clamp).
		if _team_of(slot) == 0:
			max_x = -CENTER_GAP
		else:
			min_x = CENTER_GAP
	return Vector2(clampf(pos.x, min_x, max_x), clampf(pos.y, -_half, _half))


func _out_of_bounds(pos: Vector2) -> bool:
	return absf(pos.x) > _half or absf(pos.y) > _half


## In FFA everyone but the thrower is a target; in team mode only the enemy is.
func _is_hostile(thrower: int, slot: int) -> bool:
	if not team_mode:
		return true
	return _team_of(thrower) != _team_of(slot)


func _team_of(slot: int) -> int:
	for i in teams.size():
		if slot in teams[i]:
			return i
	return -1


func _catch_active(slot: int) -> bool:
	return elapsed <= float(catch_until.get(slot, -1.0))


## The ball this slot is carrying (HELD with holder == slot), or null.
func _ball_held_by(slot: int) -> Variant:
	for ball: Dictionary in balls:
		if int(ball.state) == BallState.HELD and int(ball.holder) == slot:
			return ball
	return null


func _is_in(slot: int) -> bool:
	if slot not in slots:
		return false
	for group: Array in fall_order:
		if slot in group:
			return false
	return slot not in _pending_falls


func _in_slots() -> Array:
	return slots.filter(_is_in)


func _out_placements() -> Array:
	var placements := fall_order.duplicate(true)
	placements.reverse()
	return placements
