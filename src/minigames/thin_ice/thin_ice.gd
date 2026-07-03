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

const GRID_SIZE := 7
const TILE_SIZE := 2.0
const HALF_EXTENT := GRID_SIZE * TILE_SIZE / 2.0
const MOVE_SPEED := 5.0
const PLAYER_RADIUS := 0.4

var positions := {}
var move_dirs := {}
## Row-major GRID_SIZE * GRID_SIZE array of TileState.
var tiles: Array = []
## Last tile coordinate (Vector2i) each player was resolved onto.
var last_tile := {}
## Slots in fall order; same-tick falls share a tie group.
var fall_order: Array = []

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
				"name": "Thin Ice",
				"category": MinigameMeta.Category.FFA,
				"min_players": 2,
				"max_players": 6,
				"duration_sec": 45.0,
				"rules":
				"The ice cracks underfoot — even standing still! Flashing ice is about to drop. Keep moving!",
			}
		)
	)


func _setup() -> void:
	tiles.resize(GRID_SIZE * GRID_SIZE)
	tiles.fill(TileState.INTACT)
	for i in slots.size():
		var angle := TAU * i / slots.size()
		var pos := Vector2(cos(angle), sin(angle)) * HALF_EXTENT * 0.6
		positions[slots[i]] = pos
		move_dirs[slots[i]] = Vector2.ZERO
		last_tile[slots[i]] = _tile_of(pos)


func _handle_input(slot: int, data: Dictionary) -> void:
	if not _is_in(slot):
		return
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)


func _tick(delta: float) -> void:
	for slot: int in _in_slots():
		var pos: Vector2 = positions[slot] + move_dirs[slot] * MOVE_SPEED * delta
		positions[slot] = pos.clamp(
			Vector2(-HALF_EXTENT, -HALF_EXTENT), Vector2(HALF_EXTENT, HALF_EXTENT)
		)
	_resolve_tile_entries()
	_tick_standing(delta)
	_tick_collapses(delta)
	_check_falls()
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
		"grid_size": GRID_SIZE,
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


func _resolve_tile_entries() -> void:
	for slot: int in _in_slots():
		var tile: Vector2i = _tile_of(positions[slot])
		if tile != last_tile[slot]:
			last_tile[slot] = tile
			_stand_time[slot] = 0.0
			_damage_tile(tile)


## Standing still cracks the ice under you too (#167).
func _tick_standing(delta: float) -> void:
	for slot: int in _in_slots():
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


func _check_falls() -> void:
	for slot: int in _in_slots():
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
	var tx := clampi(int(floor((pos.x + HALF_EXTENT) / TILE_SIZE)), 0, GRID_SIZE - 1)
	var ty := clampi(int(floor((pos.y + HALF_EXTENT) / TILE_SIZE)), 0, GRID_SIZE - 1)
	return Vector2i(tx, ty)


func _tile_index(tile: Vector2i) -> int:
	return tile.y * GRID_SIZE + tile.x
