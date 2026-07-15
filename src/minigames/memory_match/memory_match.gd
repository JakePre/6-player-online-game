class_name MemoryMatch
extends MinigameBase
## Memory Match (M10-05, PHASE2.md $4 #22): the floor flashes a pattern of
## safe tiles, then goes dark — get to a safe tile before the check, because
## everything else gives way. Fewer safe tiles every round. Last one standing
## wins; down order = placement.
## Server-side simulation only — the client renders get_snapshot().

enum Phase { SHOW, DARK }

const GRID_SIZE := 6
const TILE_SIZE := 2.0
const HALF_EXTENT := GRID_SIZE * TILE_SIZE / 2.0
const MOVE_SPEED := 6.0
const PLAYER_RADIUS := 0.45
const SHOW_SEC := 2.5
const DARK_SEC := 3.5
## Fraction of the grid that starts safe, shrinking each round.
const SAFE_START_FRACTION := 0.5
const SAFE_SHRINK := 0.75
const SAFE_MIN := 3

## Shove (#784, owner-approved Option B): action_primary radial shove on a
## cooldown, plus soft body separation so players can never stack on one tile.
## Tuned so a shove is recoverable with >½s left in the dark window (~2.5u of
## travel ≈ 1.25 tiles, and MOVE_SPEED walks it back in ~0.4s) but lethal at
## the buzzer — timing, not spam (the cooldown caps it at ~2 per dark phase).
const SHOVE_RADIUS := 1.2
const SHOVE_COOLDOWN_SEC := 1.5
const SHOVE_KNOCK := 5.5
const KNOCK_DECAY := 6.0

## get_snapshot() wire shape (#708): named indices for the players positional
## array. Array SHAPE on the wire is append-only — PS_ACT_SEQ/PS_SHOVE_CD were
## added for the shove (#784), keeping x/y at the same indices.
const PS_X := 0
const PS_Y := 1
## Monotonic per-slot shove counter — the view plays the swing once when it
## ticks (#808 act_seq convention).
const PS_ACT_SEQ := 2
## Seconds of shove cooldown left, for the view's cooldown ring (#792/#808).
const PS_SHOVE_CD := 3
## #946 wire-shape tripwire: the declared type of each slot in a `players`
## snapshot row. Validated by test_snapshot_schema against get_snapshot().
const PLAYER_SCHEMA := [TYPE_FLOAT, TYPE_FLOAT, TYPE_INT, TYPE_FLOAT]

var positions := {}
var move_dirs := {}
var phase := Phase.SHOW
## Tile indices (row-major) that are safe this round.
var safe_tiles: Array = []
var round_number := 0
## Slots in down order; same-check failures share a tie group.
var down_order: Array = []

## Shove state (#784): active knockback velocity, cooldown-left, and the
## play-once swing counter, per slot.
var knocks := {}
var shove_cd := {}
var act_seq := {}

var _phase_left := SHOW_SEC


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"memory_match",
				"controls": "Move — WASD / left stick",
				"control_hints":
				["Move — WASD / left stick · Shove — ", {"action": &"action_primary"}],
				# Structured spec (#832/#844): the move + action template shape.
				"control_spec":
				[
					{"verb": "Move", "input": InputGlyphs.CLUSTER_MOVE},
					{"verb": "Shove", "input": &"action_primary"},
				],
				"name": "Memory Match",
				"category": MinigameMeta.Category.SKILL,
				"min_players": 2,
				"max_players": 24,
				"duration_sec": 75.0,
				"rules":
				(
					"The floor flashes the GREEN safe tiles, then goes dark — be standing on"
					+ " one when it does, or you drop into the pit! Fewer safe tiles each round."
				),
			}
		)
	)


func _setup() -> void:
	for i in slots.size():
		var angle := TAU * i / slots.size()
		positions[slots[i]] = Vector2(cos(angle), sin(angle)) * HALF_EXTENT * 0.5
		move_dirs[slots[i]] = Vector2.ZERO
		knocks[slots[i]] = Vector2.ZERO
		shove_cd[slots[i]] = 0.0
		act_seq[slots[i]] = 0
	_deal_pattern()


func _handle_input(slot: int, data: Dictionary) -> void:
	if not _is_in(slot):
		return
	# Move is gated on mx/my being present so a shove-only message (no axes)
	# doesn't zero the player's heading for that tick.
	if data.has("mx") or data.has("my"):
		var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
		move_dirs[slot] = dir.limit_length(1.0)
	if data.get("shove", false):
		_shove(slot)


func _tick(delta: float) -> void:
	if finished:
		return
	# Alive-set cache (cleanup #467): computed once, shared by the movement
	# loop and _advance_phase()'s loser check, which both run before this
	# tick's own downs are finalized. _check_end() still calls _in_slots()
	# fresh — it must see the roster *after* this tick's eliminations land.
	var alive := _in_slots()
	for slot: int in alive:
		shove_cd[slot] = maxf(float(shove_cd[slot]) - delta, 0.0)
		var knock: Vector2 = knocks[slot]
		var pos: Vector2 = positions[slot] + (move_dirs[slot] * MOVE_SPEED + knock) * delta
		positions[slot] = pos.clamp(
			Vector2(-HALF_EXTENT, -HALF_EXTENT), Vector2(HALF_EXTENT, HALF_EXTENT)
		)
		knocks[slot] = knock.move_toward(Vector2.ZERO, KNOCK_DECAY * delta)
	_resolve_separation(alive)
	_phase_left -= delta
	if _phase_left <= 0.0:
		_advance_phase(alive)
	_check_end()


## Radial shove (#784): every other standing player within SHOVE_RADIUS gets
## knocked away, and the swing plays once (act_seq) whether or not it connects.
## No-op while on cooldown.
func _shove(slot: int) -> void:
	if float(shove_cd[slot]) > 0.0:
		return
	shove_cd[slot] = SHOVE_COOLDOWN_SEC
	act_seq[slot] = int(act_seq[slot]) + 1
	for other: int in _in_slots():
		if other == slot:
			continue
		var away: Vector2 = positions[other] - positions[slot]
		if away.length() > SHOVE_RADIUS:
			continue
		var dir := away.normalized() if away.length() > 0.001 else Vector2.UP
		knocks[other] = dir * SHOVE_KNOCK


## Soft body separation (#784): overlapping players are pushed apart so a crowd
## can never stack invisibly on one safe tile. Position-based (each moves half
## the overlap), so it always resolves in one pass without adding momentum.
func _resolve_separation(active: Array) -> void:
	var min_gap := PLAYER_RADIUS * 2.0
	var lo := Vector2(-HALF_EXTENT, -HALF_EXTENT)
	var hi := Vector2(HALF_EXTENT, HALF_EXTENT)
	for i in active.size():
		for j in range(i + 1, active.size()):
			var a: int = active[i]
			var b: int = active[j]
			# Position-based soft separation — shared math (#945).
			var push := SimGeometry.separation_push(positions[a], positions[b], min_gap)
			if push == Vector2.ZERO:
				continue
			positions[a] = (positions[a] - push).clamp(lo, hi)
			positions[b] = (positions[b] + push).clamp(lo, hi)


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in _in_slots():
		var pos: Vector2 = positions[slot]
		players[slot] = [
			snappedf(pos.x, 0.01),
			snappedf(pos.y, 0.01),
			int(act_seq[slot]),
			snappedf(shove_cd[slot], 0.01),
		]
	return {
		"players": players,
		"phase": phase,
		# Only replicated while showing — dark-phase clients can't peek.
		"safe_tiles": safe_tiles.duplicate() if phase == Phase.SHOW else [],
		"grid_size": GRID_SIZE,
		"round": round_number,
		"fallen": down_order,
	}


## Timeout: everyone still standing ties ahead of the fallen.
func _rank_players() -> Array:
	var survivors := _in_slots()
	var placements: Array = []
	if not survivors.is_empty():
		placements.append(survivors)
	return placements + _out_placements()


func tile_of(pos: Vector2) -> int:
	var col := clampi(int(floorf((pos.x + HALF_EXTENT) / TILE_SIZE)), 0, GRID_SIZE - 1)
	var row := clampi(int(floorf((pos.y + HALF_EXTENT) / TILE_SIZE)), 0, GRID_SIZE - 1)
	return row * GRID_SIZE + col


func _advance_phase(alive: Array) -> void:
	if phase == Phase.SHOW:
		phase = Phase.DARK
		_phase_left = DARK_SEC
		return
	# Dark window closed: everyone off the pattern goes down together.
	var losers: Array = []
	for slot: int in alive:
		if tile_of(positions[slot]) not in safe_tiles:
			losers.append(slot)
	if not losers.is_empty():
		down_order.append(losers)
	round_number += 1
	_deal_pattern()
	phase = Phase.SHOW
	_phase_left = SHOW_SEC


func _deal_pattern() -> void:
	var total := GRID_SIZE * GRID_SIZE
	var count := maxi(
		int(roundf(total * SAFE_START_FRACTION * pow(SAFE_SHRINK, round_number))), SAFE_MIN
	)
	var indices: Array = range(total)
	safe_tiles = []
	for _i in count:
		safe_tiles.append(indices.pop_at(rng.randi_range(0, indices.size() - 1)))


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
	return true


func _in_slots() -> Array:
	return slots.filter(_is_in)


func _out_placements() -> Array:
	var placements := down_order.duplicate(true)
	placements.reverse()
	return placements
