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
## SKULL is the #949 cursed-skull gamble (50/50 mega/curse on grab).
enum Power { RANGE, BOMB, SKULL }

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
## Of the power-ups that drop, this fraction are the #949 cursed skull.
const SKULL_CHANCE := 0.22
## Bomb Kick (#949): a bomb you walk into slides this many tiles/sec in your
## facing direction until it hits a wall, crate, bomb, or player, then stops
## (its fuse keeps running). The classic corridor-kick outplay.
const BOMB_SLIDE_TILES_PER_SEC := 3.0
## Cursed Skull (#949): a bad grab reverses your movement for this long.
const CURSE_SEC := 5.0
## Mega grab adds this much range for the round.
const SKULL_MEGA_RANGE := 3
## Border revenge (#949): each eliminated player lobs one 2-tile bomb onto the
## field on this cooldown — nobody sits out. Revenge KOs credit nothing.
const REVENGE_COOLDOWN := 8.0
const REVENGE_RANGE := 2
## Owner sentinel for revenge bombs: not a real slot, so they never count
## against anyone's bomb cap and their KOs credit no one.
const REVENGE_OWNER := -1

## get_snapshot() wire shapes (#708): named indices for the positional arrays
## the view and brain read. Array SHAPE on the wire is unchanged — additive.
const PS_X := 0
const PS_Y := 1
const PS_RANGE := 2
const PS_MAX_BOMBS := 3
## 1 while the #949 curse (reversed movement) is active, else 0 — drives the
## nameplate skull so rivals can hunt the cursed player.
const PS_CURSED := 4
const PS_COUNT := 5
## #946 wire-shape tripwire: the declared type of each slot in a `players`
## snapshot row. test_snapshot_schema validates every row against this — length
## and per-slot kind — so a reinterpreted or added/removed slot fails loudly
## instead of surfacing later as a cross-version desync.
const PLAYER_SCHEMA := [TYPE_FLOAT, TYPE_FLOAT, TYPE_INT, TYPE_INT, TYPE_INT]

## Bombs carry a continuous x,y now (#949) so a kicked bomb reads as a smooth
## slide, not a cell-to-cell hop; BM_CELL stays the authoritative gameplay cell.
const BM_CELL := 0
const BM_FUSE := 1
const BM_X := 2
const BM_Y := 3
## Owner slot, or REVENGE_OWNER for a border-revenge lob — lets a bot spot its
## own resting bombs to kick (#949). Not secret; every client already sees them.
const BM_OWNER := 4

const PW_CELL := 0
const PW_KIND := 1

## Border-revenge rider row (#949): world x, y on the border + the slot.
const RV_X := 0
const RV_Y := 1
const RV_SLOT := 2

var grid: Array[int] = []
var positions := {}
var move_dirs := {}
var ranges := {}
var max_bombs := {}
## Live bombs: {cell:int, fuse:float, range:int, owner:int, pos:Vector2,
## slide:Vector2i}. slide == ZERO means resting; non-zero is a kicked bomb (#949).
var bombs: Array = []
## cell (int) -> flame time_left (float).
var flames := {}
## cell (int) -> Power.
var powerups := {}
## Slots eliminated, in KO order; same-tick KOs share a tie group.
var down_order: Array = []
## #949 curse: slot -> seconds of reversed movement remaining.
var curses := {}
## #949 border revenge: eliminated slot -> seconds until its next lob.
var _revenge_cd := {}

var _pending_downs: Array = []
var _prev_cell := {}


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
				# Structured spec (#832): the move + action template shape.
				"control_spec":
				[
					{"verb": "Move", "input": InputGlyphs.CLUSTER_MOVE},
					{"verb": "Bomb", "input": &"action_primary"},
				],
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
		curses[slot] = 0.0
		_prev_cell[slot] = cell


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
	_tick_curses(delta)
	_move_players(delta)
	_slide_bombs(delta)
	_tick_bombs(delta)
	_tick_flames(delta)
	_collect_powerups()
	_tick_revenge(delta)
	_flush_downs()
	_check_end()


## #949 curse: reversed-movement timer bleeds down each tick.
func _tick_curses(delta: float) -> void:
	for slot: int in curses:
		if float(curses[slot]) > 0.0:
			curses[slot] = maxf(0.0, float(curses[slot]) - delta)


func get_snapshot() -> Dictionary:
	var player_states := {}
	for slot: int in _in_slots():
		var pos: Vector2 = positions[slot]
		player_states[slot] = [
			snappedf(pos.x, 0.01),
			snappedf(pos.y, 0.01),
			int(ranges[slot]),
			int(max_bombs[slot]),
			1 if float(curses[slot]) > 0.0 else 0,
		]
	var bomb_list: Array = []
	for bomb: Dictionary in bombs:
		var bpos: Vector2 = bomb.pos
		(
			bomb_list
			. append(
				[
					int(bomb.cell),
					snappedf(bomb.fuse, 0.05),
					snappedf(bpos.x, 0.01),
					snappedf(bpos.y, 0.01),
					int(bomb.owner),
				]
			)
		)
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
		# #949 border-revenge riders (ghost rigs on the border); [] until someone
		# is out.
		"revenge": _revenge_riders(),
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
## only if it is EMPTY (pillars and soft walls block; bombs do not). While
## cursed (#949) the input direction is reversed. Stepping onto your own
## resting bomb kicks it (#949).
func _move_players(delta: float) -> void:
	for slot: int in _in_slots():
		var dir: Vector2 = move_dirs[slot]
		if float(curses[slot]) > 0.0:
			dir = -dir
		var cur: Vector2 = positions[slot]
		var want: Vector2 = cur + dir * MOVE_SPEED * delta
		if _walkable(Vector2(want.x, cur.y)):
			cur.x = want.x
		if _walkable(Vector2(cur.x, want.y)):
			cur.y = want.y
		positions[slot] = cur
		_try_kick(slot, dir)
		_prev_cell[slot] = _cell_at(cur)


## Bomb Kick (#949): if this move stepped the player onto a resting bomb they
## own, and they're pushing a direction, the bomb slides that cardinal way —
## but only if the cell it would slide into is clear (else it just sits).
func _try_kick(slot: int, dir: Vector2) -> void:
	if dir == Vector2.ZERO:
		return
	var cell := _cell_at(positions[slot])
	if cell == int(_prev_cell[slot]):
		return  # only a fresh step onto the bomb kicks it
	var bomb := _bomb_at(cell)
	if bomb.is_empty() or int(bomb.owner) != slot or (bomb.slide as Vector2i) != Vector2i.ZERO:
		return
	var card := _cardinal(dir)
	if _bomb_can_enter(_step_cell(cell, card), slot):
		bomb.slide = card


func _bomb_at(cell: int) -> Dictionary:
	for bomb: Dictionary in bombs:
		if int(bomb.cell) == cell:
			return bomb
	return {}


## Dominant-axis cardinal of a movement vector.
func _cardinal(dir: Vector2) -> Vector2i:
	if absf(dir.x) >= absf(dir.y):
		return Vector2i(1 if dir.x > 0.0 else -1, 0)
	return Vector2i(0, 1 if dir.y > 0.0 else -1)


func _walkable(pos: Vector2) -> bool:
	return grid[_cell_at(pos)] == Cell.EMPTY


func _try_drop_bomb(slot: int) -> void:
	var cell := _cell_at(positions[slot])
	if _active_bombs(slot) >= int(max_bombs[slot]):
		return
	for bomb: Dictionary in bombs:
		if int(bomb.cell) == cell:
			return
	_spawn_bomb(cell, BOMB_FUSE, int(ranges[slot]), slot)


func _spawn_bomb(cell: int, fuse: float, blast_range: int, owner: int) -> void:
	(
		bombs
		. append(
			{
				"cell": cell,
				"fuse": fuse,
				"range": blast_range,
				"owner": owner,
				"pos": _cell_center(cell),
				"slide": Vector2i.ZERO,
			}
		)
	)


## Kicked bombs (#949) glide cell-to-cell at BOMB_SLIDE_TILES_PER_SEC. A bomb
## re-centers as it crosses into each new cell and stops the moment the next
## cell is blocked (wall, crate, another bomb, or a player) — it never rolls
## over anything, matching the classic corridor kick.
func _slide_bombs(delta: float) -> void:
	var step := BOMB_SLIDE_TILES_PER_SEC * CELL_SIZE * delta
	for bomb: Dictionary in bombs:
		var slide: Vector2i = bomb.slide
		if slide == Vector2i.ZERO:
			continue
		# Re-check the cell ahead every tick, so a bomb stops the instant a
		# player/crate/bomb blocks it — it never rolls onto anything.
		var next := _step_cell(int(bomb.cell), slide)
		if not _bomb_can_enter(next, int(bomb.owner)):
			bomb.pos = _cell_center(int(bomb.cell))
			bomb.slide = Vector2i.ZERO
			continue
		var target := _cell_center(next)
		var to_target := target - (bomb.pos as Vector2)
		if to_target.length() <= step:
			bomb.pos = target
			bomb.cell = next  # commit the new cell only on arrival at its center
		else:
			bomb.pos = (bomb.pos as Vector2) + to_target.normalized() * step


## Can a sliding bomb move into `cell`? Blocked by non-empty grid, another bomb,
## or any living player standing there (owner passed only for symmetry).
func _bomb_can_enter(cell: int, _owner: int) -> bool:
	if cell < 0 or cell >= grid.size() or grid[cell] != Cell.EMPTY:
		return false
	if not _bomb_at(cell).is_empty():
		return false
	for slot: int in _in_slots():
		if _cell_at(positions[slot]) == cell:
			return false
	return true


func _step_cell(cell: int, dir: Vector2i) -> int:
	var r := cell / GRID + dir.y
	var c := cell % GRID + dir.x
	if r < 0 or c < 0 or r >= GRID or c >= GRID:
		return -1
	return r * GRID + c


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
	if rng.randf() >= POWERUP_CHANCE:
		return
	# A slice of drops are the #949 cursed skull; the rest split range/bomb.
	if rng.randf() < SKULL_CHANCE:
		powerups[cell] = Power.SKULL
	else:
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
			Power.SKULL:
				_grab_skull(slot)
		powerups.erase(cell)


## #949 cursed skull, 50/50 on grab: MEGA (+3 range this round) or CURSED
## (reversed movement for CURSE_SEC). Deterministic from the sim rng.
func _grab_skull(slot: int) -> void:
	if rng.randf() < 0.5:
		ranges[slot] = mini(int(ranges[slot]) + SKULL_MEGA_RANGE, MAX_RANGE)
	else:
		curses[slot] = CURSE_SEC


func _flush_downs() -> void:
	if _pending_downs.is_empty():
		return
	var group: Array = []
	for slot: int in _pending_downs:
		if slot not in group:
			group.append(slot)
	down_order.append(group)
	# Newly eliminated players join the border-revenge rotation (#949) with a
	# full cooldown, so the first lob comes REVENGE_COOLDOWN after they're out.
	for slot: int in group:
		_revenge_cd[slot] = REVENGE_COOLDOWN
	_pending_downs.clear()


## #949 border revenge: each eliminated rider lobs one REVENGE_RANGE bomb at a
## living rival's cell every REVENGE_COOLDOWN — nobody just sits out. Owner is
## the sentinel REVENGE_OWNER so KOs credit nothing and no bomb cap applies.
func _tick_revenge(delta: float) -> void:
	var living := _in_slots()
	if living.is_empty():
		return
	for slot: int in _revenge_cd:
		_revenge_cd[slot] = float(_revenge_cd[slot]) - delta
		if float(_revenge_cd[slot]) > 0.0:
			continue
		_revenge_cd[slot] = REVENGE_COOLDOWN
		var target := _revenge_target(_border_position(slot), living)
		if target != -1 and _bomb_at(target).is_empty():
			_spawn_bomb(target, BOMB_FUSE, REVENGE_RANGE, REVENGE_OWNER)


## Nearest living rival's cell if it's an empty drop spot, else the closest
## empty interior cell to it — a revenge bomb still has to land on open ground.
func _revenge_target(from: Vector2, living: Array) -> int:
	var best_cell := -1
	var best_dist := INF
	for slot: int in living:
		var d := from.distance_squared_to(positions[slot])
		if d < best_dist:
			best_dist = d
			best_cell = _cell_at(positions[slot])
	if best_cell == -1:
		return -1
	if grid[best_cell] == Cell.EMPTY:
		return best_cell
	for n: int in [best_cell - 1, best_cell + 1, best_cell - GRID, best_cell + GRID]:
		if n >= 0 and n < grid.size() and grid[n] == Cell.EMPTY:
			return n
	return -1


## A rider's fixed spot on the border ring, spread by KO order so riders don't
## stack. Purely cosmetic (drives the ghost rig); lobs originate from here.
func _border_position(slot: int) -> Vector2:
	var order := 0
	var index := 0
	for group: Array in down_order:
		for s: int in group:
			if s == slot:
				order = index
			index += 1
	var count := maxi(index, 1)
	var angle := TAU * order / count
	return Vector2(cos(angle), sin(angle)) * (ARENA_HALF + 0.6)


func _revenge_riders() -> Array:
	var riders: Array = []
	for group: Array in down_order:
		for slot: int in group:
			var pos := _border_position(slot)
			riders.append([snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), slot])
	return riders


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
