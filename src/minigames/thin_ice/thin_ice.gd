class_name ThinIce
extends MinigameBase
## Thin Ice (M4-03, SPEC $7 #4): everyone roams a shared tile grid. Stepping
## onto a tile damages it: intact -> cracked, and stepping onto a cracked
## tile starts a visible, escapable collapse (BREAKING) before it drops
## (#138 — the instant crack->gone kill read as random). Standing on a gone
## tile drops you. Last player standing wins; fall order = placement.
## Server-side simulation only — the client renders get_snapshot().

enum TileState { INTACT, CRACKED, BREAKING, GONE }

## How long a BREAKING tile holds before it gives way — the escape window.
const COLLAPSE_SEC := 0.8
## Camping is not safe (#167): standing on the same tile this long applies
## one damage step, and keeps applying while you stay.
const STAND_DAMAGE_SEC := 1.5

## Grid size at the 6-player baseline; scales with lobby size (M15) so
## tiles-per-player density stays ~constant (the destruction rate keeps
## feeling the same at 12 as it does at 6). Unchanged at <=6 players.
##
## #961 round-length fix: raised 7 -> 12 (≈3x the tiles-per-player, the owner's
## "more ice" lever). At 7 the floor cleared in ~6-8s with brains — far under the
## #933 ≥18s bar — because a 7x7 grid packs movers close enough that tiles take
## their second (breaking) hit almost immediately. More ice spreads them out;
## bot-driven round probe medians land ~20s at 6-8p (4p ~19s, 12p ~30s), all
## clearing the bar with no timeout stalemates.
const GRID_SIZE := 12
const TILE_SIZE := 2.0
const MOVE_SPEED := 5.0
const PLAYER_RADIUS := 0.4

## get_snapshot() wire shape (#708): named indices for the players positional
## array. Array SHAPE on the wire is unchanged — additive only.
const PS_X := 0
const PS_Y := 1
const PS_COUNT := 2
## #946 wire-shape tripwire: the declared type of each slot in a `players`
## snapshot row. Validated by test_snapshot_schema against get_snapshot().
const PLAYER_SCHEMA := [TYPE_FLOAT, TYPE_FLOAT]

var positions := {}
var move_dirs := {}
## Row-major _grid_size * _grid_size array of TileState.
var tiles: Array = []
## Last tile coordinate (Vector2i) each player was resolved onto.
var last_tile := {}
## Slots in fall order; same-tick falls share a tie group.
var fall_order: Array = []
## This match's grid dimension and half-extent, derived from player count
## in _setup(); equal GRID_SIZE/HALF_EXTENT at <=6 players.
var _grid_size := GRID_SIZE
var _half_extent := GRID_SIZE * TILE_SIZE / 2.0

var _pending_falls: Array = []
## Collapse countdowns for BREAKING tiles, {tile index: seconds left}.
var _collapse_left := {}
## Continuous time each player has spent on their current tile.
var _stand_time := {}


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"thin_ice",
				"controls": "Move — WASD / left stick",
				# Structured spec (#832/#844): the bare-movement template shape.
				"control_spec": [{"verb": "Move", "input": InputGlyphs.CLUSTER_MOVE}],
				"name": "Thin Ice",
				"category": MinigameMeta.Category.FFA,
				"min_players": 2,
				"max_players": 12,
				"duration_sec": 45.0,
				"rules":
				"The ice cracks underfoot — even standing still! Flashing ice is about to drop. Keep moving!",
			}
		)
	)


func _setup() -> void:
	# Grid area scales with player count the same way MinigameScaling scales
	# arena area, so tiles-per-player density holds steady.
	_grid_size = roundi(GRID_SIZE * sqrt(MinigameScaling.growth(slots.size())))
	_half_extent = _grid_size * TILE_SIZE / 2.0
	tiles.resize(_grid_size * _grid_size)
	tiles.fill(TileState.INTACT)
	for i in slots.size():
		var angle := TAU * i / slots.size()
		var pos := Vector2(cos(angle), sin(angle)) * _half_extent * 0.6
		positions[slots[i]] = pos
		move_dirs[slots[i]] = Vector2.ZERO
		last_tile[slots[i]] = _tile_of(pos)


func _handle_input(slot: int, data: Dictionary) -> void:
	if not _is_in(slot):
		return
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)


func _tick(delta: float) -> void:
	# Alive-set cache (cleanup #467): computed once, shared by the movement
	# loop, _resolve_tile_entries(), _tick_standing(), and _check_falls() —
	# none of these touch fall_order before this point in the tick, so they
	# all see the same pre-elimination roster. _check_end() still calls
	# _in_slots() fresh — it must see the roster *after* _flush_falls()
	# applies this tick's eliminations.
	var alive := _in_slots()
	for slot: int in alive:
		var pos: Vector2 = positions[slot] + move_dirs[slot] * MOVE_SPEED * delta
		positions[slot] = pos.clamp(
			Vector2(-_half_extent, -_half_extent), Vector2(_half_extent, _half_extent)
		)
	_resolve_tile_entries(alive)
	_tick_standing(delta, alive)
	_tick_collapses(delta)
	_check_falls(alive)
	_flush_falls()
	_check_end()


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		if not _is_in(slot):
			continue
		var pos: Vector2 = positions[slot]
		players[slot] = [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)]
	return {
		"grid_size": _grid_size,
		"tile_size": TILE_SIZE,
		"tiles": tiles.duplicate(),
		"players": players,
		"fallen": fall_order,
	}


## Timeout: everyone still standing ties ahead of the fallen.
func _rank_players() -> Array:
	var survivors := _in_slots()
	var placements: Array = []
	if not survivors.is_empty():
		placements.append(survivors)
	return placements + _out_placements()


func _resolve_tile_entries(alive: Array) -> void:
	for slot: int in alive:
		var tile: Vector2i = _tile_of(positions[slot])
		if tile != last_tile[slot]:
			last_tile[slot] = tile
			_stand_time[slot] = 0.0
			_damage_tile(tile)


## Standing still cracks the ice under you too (#167).
func _tick_standing(delta: float, alive: Array) -> void:
	for slot: int in alive:
		_stand_time[slot] = float(_stand_time.get(slot, 0.0)) + delta
		if _stand_time[slot] >= STAND_DAMAGE_SEC:
			_stand_time[slot] = 0.0
			_damage_tile(last_tile[slot])


func _damage_tile(tile: Vector2i) -> void:
	var idx := _tile_index(tile)
	match int(tiles[idx]):
		TileState.INTACT:
			tiles[idx] = TileState.CRACKED
		TileState.CRACKED:
			tiles[idx] = TileState.BREAKING
			_collapse_left[idx] = COLLAPSE_SEC


func _tick_collapses(delta: float) -> void:
	for idx: int in _collapse_left.keys():
		_collapse_left[idx] -= delta
		if _collapse_left[idx] <= 0.0:
			_collapse_left.erase(idx)
			tiles[idx] = TileState.GONE


func _check_falls(alive: Array) -> void:
	for slot: int in alive:
		var idx := _tile_index(last_tile[slot])
		if tiles[idx] == TileState.GONE:
			_pending_falls.append(slot)


func _flush_falls() -> void:
	if not _pending_falls.is_empty():
		fall_order.append(_pending_falls.duplicate())
		_pending_falls.clear()


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


func _tile_of(pos: Vector2) -> Vector2i:
	var tx := clampi(int(floor((pos.x + _half_extent) / TILE_SIZE)), 0, _grid_size - 1)
	var ty := clampi(int(floor((pos.y + _half_extent) / TILE_SIZE)), 0, _grid_size - 1)
	return Vector2i(tx, ty)


func _tile_index(tile: Vector2i) -> int:
	return tile.y * _grid_size + tile.x
