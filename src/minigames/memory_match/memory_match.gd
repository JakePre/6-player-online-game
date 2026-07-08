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

## get_snapshot() wire shape (#708): named indices for the players positional
## array. Array SHAPE on the wire is unchanged — additive only.
const PS_X := 0
const PS_Y := 1

var positions := {}
var move_dirs := {}
var phase := Phase.SHOW
## Tile indices (row-major) that are safe this round.
var safe_tiles: Array = []
var round_number := 0
## Slots in down order; same-check failures share a tie group.
var down_order: Array = []

var _phase_left := SHOW_SEC


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"memory_match",
				"controls": "Move — WASD / left stick",
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
	_deal_pattern()


func _handle_input(slot: int, data: Dictionary) -> void:
	if not _is_in(slot):
		return
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)


func _tick(delta: float) -> void:
	if finished:
		return
	# Alive-set cache (cleanup #467): computed once, shared by the movement
	# loop and _advance_phase()'s loser check, which both run before this
	# tick's own downs are finalized. _check_end() still calls _in_slots()
	# fresh — it must see the roster *after* this tick's eliminations land.
	var alive := _in_slots()
	for slot: int in alive:
		var pos: Vector2 = positions[slot] + move_dirs[slot] * MOVE_SPEED * delta
		positions[slot] = pos.clamp(
			Vector2(-HALF_EXTENT, -HALF_EXTENT), Vector2(HALF_EXTENT, HALF_EXTENT)
		)
	_phase_left -= delta
	if _phase_left <= 0.0:
		_advance_phase(alive)
	_check_end()


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in _in_slots():
		var pos: Vector2 = positions[slot]
		players[slot] = [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)]
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
