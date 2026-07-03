class_name ThinIce
extends MinigameBase
## Thin Ice (M4-03, SPEC $7 #4): everyone roams a shared tile grid. Stepping
## onto a tile damages it (intact -> cracked -> gone); standing on a gone
## tile drops you. Last player standing wins; fall order = placement.
## Server-side simulation only — the client renders get_snapshot().

enum TileState { INTACT, CRACKED, GONE }

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
				"rules": "The ice cracks where you step. Don't be there when it gives way.",
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
			_damage_tile(tile)


func _damage_tile(tile: Vector2i) -> void:
	var idx := _tile_index(tile)
	var state: int = tiles[idx]
	if state != TileState.GONE:
		tiles[idx] = state + 1


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
