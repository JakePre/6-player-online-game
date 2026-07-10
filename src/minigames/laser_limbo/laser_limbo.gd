class_name LaserLimbo
extends MinigameBase
## Laser Limbo (M10-06, PHASE2.md $4 #23): timed laser walls sweep the arena
## — jump the low ones, duck the high ones, slip through the gap in the full
## ones. A wall caught in the wrong stance costs a life. Last one standing
## wins; down order = placement.
## Server-side simulation only — the client renders get_snapshot().

enum WallKind { LOW, HIGH, GAP }

const ARENA_HALF := 9.0
const MOVE_SPEED := 6.0
## Ducking is safe but slow.
const DUCK_SPEED := 3.0
const PLAYER_RADIUS := 0.45
const LIVES := 3
const JUMP_SEC := 0.5
const JUMP_COOLDOWN_SEC := 0.3
## One wall can never double-hit through the crossing tick.
const HIT_INVULN_SEC := 0.8
const GAP_HALF_WIDTH := 1.8
const WALL_SPEED_START := 5.0
const WALL_SPEED_MAX := 9.0
const WALL_INTERVAL_START := 2.2
const WALL_INTERVAL_MIN := 1.0

## get_snapshot() wire shapes (#708): named indices for the positional arrays
## the view and brain read. Array SHAPE on the wire is unchanged — additive.
const PS_X := 0
const PS_Y := 1
const PS_LIVES := 2
const PS_AIRBORNE := 3
const PS_DUCKING := 4
const PS_COUNT := 5

const WL_X := 0
const WL_DIR := 1
const WL_KIND := 2
const WL_GAP_Y := 3

var positions := {}
var move_dirs := {}
var lives := {}
var airborne := {}
var ducking := {}
var invuln := {}
## Sweeping walls: {x, dir (+1/-1), kind, gap_y, speed}.
var walls: Array = []
## Slots in down order; same-tick knockouts share a tie group.
var down_order: Array = []

var _jump_cooldown := {}
var _spawn_left := WALL_INTERVAL_START
var _pending_downs: Array = []

## Play area, gap, and wall speed scale with the lobby size (M15, ADR 003).
## The gap scales *with the arena* so the safe fraction — and thus the
## difficulty of slipping through — stays constant; wall speed scales so a
## wall still crosses the wider arena in the same time (cadence holds). At
## <=6 players all three equal the consts above, so the game is unchanged.
var _play_half := ARENA_HALF
var _gap_half := GAP_HALF_WIDTH
var _speed_scale := 1.0


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"laser_limbo",
				"controls": "Move — WASD / stick · Jump — SPACE / pad A · Duck — hold E / pad X",
				# Device-aware (#608): the buttons read as what the player holds.
				"control_hints":
				[
					"Move — WASD / stick · Jump — ",
					{"action": &"action_primary"},
					" · Duck — hold ",
					{"action": &"action_secondary"},
				],
				# Structured spec (#832): the move + action + hold template shape.
				"control_spec":
				[
					{"verb": "Move", "input": InputGlyphs.CLUSTER_MOVE},
					{"verb": "Jump", "input": &"action_primary"},
					{"verb": "Duck", "input": &"action_secondary", "hold": true},
				],
				"name": "Laser Limbo",
				"category": MinigameMeta.Category.SKILL,
				"min_players": 2,
				"max_players": 24,
				"duration_sec": 60.0,
				"rules": "Jump the low lasers, duck the high ones, slip through the gaps. 3 lives.",
			}
		)
	)


func _setup() -> void:
	_play_half = MinigameScaling.arena_half(ARENA_HALF, slots.size())
	# Keep the gap the same fraction of the arena, and let walls cross the wider
	# arena in the same time — difficulty and cadence hold as the lobby grows.
	var scale := _play_half / ARENA_HALF
	_gap_half = GAP_HALF_WIDTH * scale
	_speed_scale = scale
	var spawns := SpawnLayout.ring_positions(slots.size(), _play_half * 0.5)
	for i in slots.size():
		positions[slots[i]] = spawns[i]
		move_dirs[slots[i]] = Vector2.ZERO
		lives[slots[i]] = LIVES
		airborne[slots[i]] = 0.0
		ducking[slots[i]] = false
		invuln[slots[i]] = 0.0
		_jump_cooldown[slots[i]] = 0.0


func _handle_input(slot: int, data: Dictionary) -> void:
	if not _is_in(slot):
		return
	if data.has("mx"):
		var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
		move_dirs[slot] = dir.limit_length(1.0)
	if data.get("jump", false) and _jump_cooldown[slot] <= 0.0 and not ducking[slot]:
		airborne[slot] = JUMP_SEC
		_jump_cooldown[slot] = JUMP_SEC + JUMP_COOLDOWN_SEC
	if data.has("duck"):
		ducking[slot] = bool(data.duck) and airborne[slot] <= 0.0


func _tick(delta: float) -> void:
	if finished:
		return
	# Alive-set cache (cleanup #467): computed once, shared by the movement
	# loop and _sweep_walls(), which both run before this tick's own downs
	# are finalized. _check_end() still calls _in_slots() fresh — it must
	# see the roster *after* _flush_downs() applies this tick's eliminations.
	var alive := _in_slots()
	for slot: int in alive:
		airborne[slot] = maxf(airborne[slot] - delta, 0.0)
		invuln[slot] = maxf(invuln[slot] - delta, 0.0)
		_jump_cooldown[slot] = maxf(_jump_cooldown[slot] - delta, 0.0)
		var speed := DUCK_SPEED if ducking[slot] else MOVE_SPEED
		var pos: Vector2 = positions[slot] + move_dirs[slot] * speed * delta
		positions[slot] = pos.limit_length(_play_half)
	_sweep_walls(delta, alive)
	_spawn_walls(delta)
	_flush_downs()
	_check_end()


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in _in_slots():
		var pos: Vector2 = positions[slot]
		players[slot] = [
			snappedf(pos.x, 0.01),
			snappedf(pos.y, 0.01),
			lives[slot],
			1 if airborne[slot] > 0.0 else 0,
			1 if ducking[slot] else 0,
		]
	var wall_list: Array = []
	for wall: Dictionary in walls:
		wall_list.append([snappedf(wall.x, 0.01), wall.dir, wall.kind, snappedf(wall.gap_y, 0.01)])
	return {"players": players, "walls": wall_list, "fallen": down_order}


## Timeout: survivors rank by lives left (ties share), then the fallen.
func _rank_players() -> Array:
	var by_lives := {}
	for slot: int in _in_slots():
		var count: int = lives[slot]
		if not by_lives.has(count):
			by_lives[count] = []
		by_lives[count].append(slot)
	var counts := by_lives.keys()
	counts.sort()
	counts.reverse()
	var placements: Array = []
	for count: int in counts:
		placements.append(by_lives[count])
	return placements + _out_placements()


## A wall hits when it crosses a player's x this tick in the wrong stance:
## LOW needs airtime, HIGH needs ducking, GAP needs standing in the opening.
func _sweep_walls(delta: float, alive: Array) -> void:
	var remaining: Array = []
	for wall: Dictionary in walls:
		var before: float = wall.x
		wall.x += wall.dir * wall.speed * delta
		for slot: int in alive:
			if invuln[slot] > 0.0:
				continue
			var px: float = positions[slot].x
			if not _crossed(before, wall.x, px):
				continue
			if not _survives(slot, wall):
				lives[slot] -= 1
				invuln[slot] = HIT_INVULN_SEC
				if lives[slot] <= 0:
					_pending_downs.append(slot)
		if absf(wall.x) <= _play_half + 1.0:
			remaining.append(wall)
	walls = remaining


func _crossed(before: float, after: float, px: float) -> bool:
	return (before - px) * (after - px) <= 0.0


func _survives(slot: int, wall: Dictionary) -> bool:
	match int(wall.kind):
		WallKind.LOW:
			return airborne[slot] > 0.0
		WallKind.HIGH:
			return ducking[slot]
		_:
			return absf(positions[slot].y - float(wall.gap_y)) <= _gap_half


func _spawn_walls(delta: float) -> void:
	_spawn_left -= delta
	if _spawn_left > 0.0:
		return
	var t := clampf(elapsed / effective_duration(), 0.0, 1.0)
	_spawn_left = lerpf(WALL_INTERVAL_START, WALL_INTERVAL_MIN, t)
	var dir := 1 if rng.randf() < 0.5 else -1
	(
		walls
		. append(
			{
				"x": -dir * (_play_half + 0.5),
				"dir": dir,
				"kind": rng.randi_range(0, WallKind.size() - 1),
				"gap_y": rng.randf_range(-_play_half * 0.7, _play_half * 0.7),
				"speed": lerpf(WALL_SPEED_START, WALL_SPEED_MAX, t) * _speed_scale,
			}
		)
	)


func _flush_downs() -> void:
	if _pending_downs.is_empty():
		return
	var group: Array = []
	for slot: int in _pending_downs:
		if slot not in group:
			group.append(slot)
	down_order.append(group)
	_pending_downs.clear()


func _check_end() -> void:
	if finished:
		return
	var survivors := _in_slots()
	if survivors.size() > 1:
		return
	var placements: Array = []
	if not survivors.is_empty():
		placements.append(survivors)
	finish(placements + _out_placements())


func _is_in(slot: int) -> bool:
	if slot not in slots:
		return false
	for group: Array in down_order:
		if slot in group:
			return false
	return slot not in _pending_downs


func _in_slots() -> Array:
	return slots.filter(_is_in)


func _out_placements() -> Array:
	var placements := down_order.duplicate(true)
	placements.reverse()
	return placements
