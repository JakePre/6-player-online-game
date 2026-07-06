class_name BlastGrid
extends MinigameBase
## Blast Grid (M14-06, PHASE2.md §8): a Bomberman homage — a single
## last-player-standing round on a grid of indestructible pillars and
## destructible soft walls. Drop bombs on a short fuse; they blast a cross of
## cells (stopped by pillars, eating one layer of soft wall), chain-detonate
## other bombs, and KO anyone caught. Destroyed soft walls sometimes drop a
## +range or +bomb power-up. Down order = placement. Server-side simulation
## only — the client renders get_snapshot().

enum Cell { EMPTY, SOLID, SOFT }
enum Power { RANGE, BOMB }

## Odd so the classic checkerboard of pillars leaves the corners open.
const GRID := 11
const CELL_SIZE := 1.4
const ARENA_HALF := GRID * CELL_SIZE / 2.0
const MOVE_SPEED := 5.0
const BOMB_FUSE := 2.5
## Flame lingers this long after a blast — kills late walkers, drives the view.
const FLAME_SEC := 0.5
const START_RANGE := 2
const START_BOMBS := 1
const MAX_RANGE := 6
const MAX_BOMBS := 5
## Fraction of open interior cells (outside spawn pockets) seeded with soft
## walls, and the chance a destroyed one drops a power-up.
const SOFT_DENSITY := 0.55
const POWERUP_CHANCE := 0.4

var grid: Array[int] = []
var positions := {}
var move_dirs := {}
var ranges := {}
var max_bombs := {}
## Live bombs: {cell:int, fuse:float, range:int, owner:int}.
var bombs: Array = []
## cell (int) -> flame time_left (float).
var flames := {}
## cell (int) -> Power.
var powerups := {}
## Slots eliminated, in KO order; same-tick KOs share a tie group.
var down_order: Array = []

var _pending_downs: Array = []


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"blast_grid",
				"name": "Blast Grid",
				"category": MinigameMeta.Category.FFA,
				"min_players": 2,
				"max_players": 8,
				"duration_sec": 75.0,
				"rules":
				(
					"Drop bombs, blast the soft walls and each other — grab power-ups,"
					+ " dodge the cross, be the last one standing!"
				),
				"controls": "Move — WASD / left stick · Bomb — SPACE / pad A",
				# Device-aware (#608): the button reads as what the player holds.
				"control_hints":
				["Move — WASD / left stick · Bomb — ", {"action": &"action_primary"}],
			}
		)
	)


func _setup() -> void:
	_build_grid()
	var spawn_cells := _spawn_cells()
	for i in slots.size():
		var slot: int = slots[i]
		var cell: int = spawn_cells[i]
		positions[slot] = _cell_center(cell)
		move_dirs[slot] = Vector2.ZERO
		ranges[slot] = START_RANGE
		max_bombs[slot] = START_BOMBS


func _handle_input(slot: int, data: Dictionary) -> void:
	if not _is_in(slot):
		return
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)
	if data.get("bomb", false):
		_try_drop_bomb(slot)


func _tick(delta: float) -> void:
	if finished:
		return
	_move_players(delta)
	_tick_bombs(delta)
	_tick_flames(delta)
	_collect_powerups()
	_flush_downs()
	_check_end()


func get_snapshot() -> Dictionary:
	var player_states := {}
	for slot: int in _in_slots():
		var pos: Vector2 = positions[slot]
		player_states[slot] = [
			snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), int(ranges[slot]), int(max_bombs[slot])
		]
	var bomb_list: Array = []
	for bomb: Dictionary in bombs:
		bomb_list.append([int(bomb.cell), snappedf(bomb.fuse, 0.05)])
	var flame_list: Array = flames.keys()
	var power_list: Array = []
	for cell: int in powerups:
		power_list.append([cell, int(powerups[cell])])
	return {
		"grid": grid.duplicate(),
		"players": player_states,
		"bombs": bomb_list,
		"flames": flame_list,
		"powerups": power_list,
		"fallen": down_order,
	}


## Timeout: everyone still standing ties ahead of the fallen (reverse KO order).
func _rank_players() -> Array:
	var survivors := _in_slots()
	var placements: Array = []
	if not survivors.is_empty():
		placements.append(survivors)
	return placements + _out_placements()


# --- Grid construction --------------------------------------------------------


func _build_grid() -> void:
	grid.resize(GRID * GRID)
	for r in GRID:
		for c in GRID:
			grid[r * GRID + c] = _base_cell(r, c)
	# Clear spawn pockets, then scatter soft walls on the remaining open cells.
	var protected := {}
	for cell: int in _spawn_cells():
		for pocket: int in _pocket(cell):
			protected[pocket] = true
	for r in GRID:
		for c in GRID:
			var index := r * GRID + c
			if grid[index] != Cell.EMPTY or protected.has(index):
				continue
			if rng.randf() < SOFT_DENSITY:
				grid[index] = Cell.SOFT


## Border is solid; interior pillars sit on even/even cells, leaving the
## odd/odd corners (the spawns) and all corridors open.
func _base_cell(r: int, c: int) -> int:
	if r == 0 or c == 0 or r == GRID - 1 or c == GRID - 1:
		return Cell.SOLID
	if r % 2 == 0 and c % 2 == 0:
		return Cell.SOLID
	return Cell.EMPTY


## Up to 8 spawn corners/edge-mids, all odd/odd so they land on open cells.
func _spawn_cells() -> Array:
	var lo := 1
	var hi := GRID - 2
	var mid := GRID / 2
	var order := [
		_index(lo, lo),
		_index(hi, hi),
		_index(lo, hi),
		_index(hi, lo),
		_index(lo, mid),
		_index(hi, mid),
		_index(mid, lo),
		_index(mid, hi),
	]
	return order.slice(0, slots.size())


## The spawn cell plus its two inward corridor neighbours — kept clear of soft
## walls so a player is never boxed in at the start.
func _pocket(cell: int) -> Array:
	var r := cell / GRID
	var c := cell % GRID
	var toward_r := 1 if r < GRID / 2 else -1
	var toward_c := 1 if c < GRID / 2 else -1
	return [cell, _index(r + toward_r, c), _index(r, c + toward_c)]


# --- Simulation ---------------------------------------------------------------


## Axis-separated movement so players slide along walls; a cell is walkable
## only if it is EMPTY (pillars and soft walls block; bombs do not).
func _move_players(delta: float) -> void:
	for slot: int in _in_slots():
		var cur: Vector2 = positions[slot]
		var want: Vector2 = cur + (move_dirs[slot] as Vector2) * MOVE_SPEED * delta
		if _walkable(Vector2(want.x, cur.y)):
			cur.x = want.x
		if _walkable(Vector2(cur.x, want.y)):
			cur.y = want.y
		positions[slot] = cur


func _walkable(pos: Vector2) -> bool:
	return grid[_cell_at(pos)] == Cell.EMPTY


func _try_drop_bomb(slot: int) -> void:
	var cell := _cell_at(positions[slot])
	if _active_bombs(slot) >= int(max_bombs[slot]):
		return
	for bomb: Dictionary in bombs:
		if int(bomb.cell) == cell:
			return
	bombs.append({"cell": cell, "fuse": BOMB_FUSE, "range": int(ranges[slot]), "owner": slot})


func _tick_bombs(delta: float) -> void:
	var detonate: Array = []
	for bomb: Dictionary in bombs:
		bomb.fuse = float(bomb.fuse) - delta
		if float(bomb.fuse) <= 0.0:
			detonate.append(bomb)
	# Chain: a detonation catching another bomb sets it off in the same pass.
	while not detonate.is_empty():
		var bomb: Dictionary = detonate.pop_back()
		if bomb not in bombs:
			continue
		bombs.erase(bomb)
		for cell: int in _blast_cells(int(bomb.cell), int(bomb.range)):
			flames[cell] = FLAME_SEC
			if grid[cell] == Cell.SOFT:
				_destroy_soft(cell)
			for other: Dictionary in bombs:
				if int(other.cell) == cell and other not in detonate:
					detonate.append(other)


## A `+`-cross from the bomb: each arm runs up to `range`, stopped by a pillar,
## and eats exactly the first soft wall it hits (then stops).
func _blast_cells(center: int, blast_range: int) -> Array:
	var cells: Array = [center]
	var r := center / GRID
	var c := center % GRID
	for step_dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		for step in range(1, blast_range + 1):
			var nr := r + step_dir.x * step
			var nc := c + step_dir.y * step
			if nr < 0 or nc < 0 or nr >= GRID or nc >= GRID:
				break
			var index := nr * GRID + nc
			if grid[index] == Cell.SOLID:
				break
			cells.append(index)
			if grid[index] == Cell.SOFT:
				break
	return cells


func _destroy_soft(cell: int) -> void:
	grid[cell] = Cell.EMPTY
	if rng.randf() < POWERUP_CHANCE:
		powerups[cell] = Power.RANGE if rng.randf() < 0.5 else Power.BOMB


func _tick_flames(delta: float) -> void:
	for cell: int in flames.keys():
		flames[cell] = float(flames[cell]) - delta
		if float(flames[cell]) <= 0.0:
			flames.erase(cell)
	# Anyone standing in a live flame this tick is knocked out (one life).
	for slot: int in _in_slots():
		if flames.has(_cell_at(positions[slot])):
			_pending_downs.append(slot)


func _collect_powerups() -> void:
	for slot: int in _in_slots():
		var cell := _cell_at(positions[slot])
		if not powerups.has(cell):
			continue
		match int(powerups[cell]):
			Power.RANGE:
				ranges[slot] = mini(int(ranges[slot]) + 1, MAX_RANGE)
			Power.BOMB:
				max_bombs[slot] = mini(int(max_bombs[slot]) + 1, MAX_BOMBS)
		powerups.erase(cell)


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


func _active_bombs(slot: int) -> int:
	var count := 0
	for bomb: Dictionary in bombs:
		if int(bomb.owner) == slot:
			count += 1
	return count


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


# --- Grid <-> world helpers ---------------------------------------------------


func _index(r: int, c: int) -> int:
	return r * GRID + c


func _cell_center(cell: int) -> Vector2:
	var r := cell / GRID
	var c := cell % GRID
	var half := (GRID - 1) / 2.0
	return Vector2((c - half) * CELL_SIZE, (r - half) * CELL_SIZE)


func _cell_at(pos: Vector2) -> int:
	var half := (GRID - 1) / 2.0
	var c := clampi(roundi(pos.x / CELL_SIZE + half), 0, GRID - 1)
	var r := clampi(roundi(pos.y / CELL_SIZE + half), 0, GRID - 1)
	return r * GRID + c
