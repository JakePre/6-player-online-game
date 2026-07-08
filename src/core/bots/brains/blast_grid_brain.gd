class_name BlastGridBrain
extends BotBrain
## Bomberman archetype (M19-02, #686): survive the blast grid first — never
## stand on a flame or a cell a live bomb's cross will reach — then break soft
## walls and pressure rivals, dropping a bomb only when a safe escape step
## exists. The grid, bombs, and flames are all in the snapshot; a bomb's range
## isn't, so danger is modeled conservatively (MAX_RANGE, truncated by walls).
##
## Snapshot: {grid: [Cell...], players: {slot: [x, y, range, max_bombs]},
## bombs: [[cell, fuse], ...], flames: [cell, ...], powerups, fallen}
## (BlastGrid). Cell: 0 EMPTY, 1 SOLID, 2 SOFT. Input: {mx, my, bomb}.
## Indices named via BlastGrid.PS_*/BM_* (#708).

const GRID := BlastGrid.GRID
const CELL := BlastGrid.CELL_SIZE


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var me: Array = players.get(slot, [])
	var grid: Array = game.get("grid", [])
	if me.size() < BlastGrid.PS_COUNT or grid.size() < GRID * GRID:
		return {}
	return _act(game, players, me, grid)


## Survival first, then a well-escaped bomb, then advance toward a target.
func _act(game: Dictionary, players: Dictionary, me: Array, grid: Array) -> Dictionary:
	var my_pos := Vector2(float(me[BlastGrid.PS_X]), float(me[BlastGrid.PS_Y]))
	var my_cell := _cell_at(my_pos)
	var danger := _danger_cells(game, grid)
	# 1. Survival: if our cell is deadly, step to the safest neighbor (or hold
	# and hope a wall shielded us when boxed in).
	if danger.has(my_cell):
		var escape := _safest_neighbor(my_cell, grid, danger)
		return _move_to_cell(my_pos, escape) if escape != -1 else {}
	# 2. Offense: bomb a soft wall / rival in reach, but only with an escape.
	if (
		_worth_bombing(my_cell, grid, players)
		and _has_escape(my_cell, int(me[BlastGrid.PS_RANGE]), grid, danger)
	):
		return {"bomb": true, "mx": 0.0, "my": 0.0}
	# 3. Seek: advance toward the nearest soft wall or rival.
	var target := _nearest_target(my_pos, my_cell, grid, players)
	return _step_toward_safely(my_cell, target, grid, danger, my_pos) if target != -1 else {}


func _cell_at(pos: Vector2) -> int:
	var half := (GRID - 1) / 2.0
	var c := clampi(roundi(pos.x / CELL + half), 0, GRID - 1)
	var r := clampi(roundi(pos.y / CELL + half), 0, GRID - 1)
	return r * GRID + c


func _cell_center(cell: int) -> Vector2:
	var half := (GRID - 1) / 2.0
	return Vector2((cell % GRID - half) * CELL, (cell / GRID - half) * CELL)


## Flame cells plus every live bomb's blast cross (conservative range,
## truncated by SOLID/SOFT walls exactly as the sim's _blast_cells does).
func _danger_cells(game: Dictionary, grid: Array) -> Dictionary:
	var danger := {}
	for cell: Variant in game.get("flames", []):
		danger[int(cell)] = true
	for bomb: Array in game.get("bombs", []):
		if bomb.size() <= BlastGrid.BM_FUSE:
			continue
		for cell: int in _blast_cross(int(bomb[BlastGrid.BM_CELL]), BlastGrid.MAX_RANGE, grid):
			danger[cell] = true
	return danger


## The cross a bomb at `center` covers: outward each direction until a SOLID
## wall (stops before) or a SOFT wall (stops after) — mirrors the sim.
func _blast_cross(center: int, blast_range: int, grid: Array) -> Array:
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
			if int(grid[index]) == BlastGrid.Cell.SOLID:
				break
			cells.append(index)
			if int(grid[index]) == BlastGrid.Cell.SOFT:
				break
	return cells


## Walkable = in bounds and empty (not solid/soft). Used for stepping.
func _walkable(cell: int, grid: Array) -> bool:
	return cell >= 0 and cell < grid.size() and int(grid[cell]) == BlastGrid.Cell.EMPTY


func _neighbors(cell: int) -> Array:
	var r := cell / GRID
	var c := cell % GRID
	var out: Array = []
	if r > 0:
		out.append(cell - GRID)
	if r < GRID - 1:
		out.append(cell + GRID)
	if c > 0:
		out.append(cell - 1)
	if c < GRID - 1:
		out.append(cell + 1)
	return out


## The adjacent walkable cell that is out of danger; -1 if none.
func _safest_neighbor(cell: int, grid: Array, danger: Dictionary) -> int:
	for n: int in _neighbors(cell):
		if _walkable(n, grid) and not danger.has(n):
			return n
	return -1


## Would a bomb here reach a rival or a soft wall?
func _worth_bombing(cell: int, grid: Array, players: Dictionary) -> bool:
	for n: int in _neighbors(cell):
		if n >= 0 and n < grid.size() and int(grid[n]) == BlastGrid.Cell.SOFT:
			return true
	# A rival within a two-cell cross line.
	var cross := _blast_cross(cell, 2, grid)
	for other: int in players:
		if other == slot:
			continue
		var state: Array = players[other]
		if (
			state.size() > BlastGrid.PS_Y
			and cross.has(
				_cell_at(Vector2(float(state[BlastGrid.PS_X]), float(state[BlastGrid.PS_Y])))
			)
		):
			return true
	return false


## True only if we could get clear of our own blast after dropping a bomb here.
## A bomb's cross covers every orthogonal neighbor, so there is never a one-step
## escape — the way out is a corner: step to a safe neighbor, then step
## perpendicular to a cell the cross doesn't reach (classic Bomberman escape).
func _has_escape(cell: int, blast_range: int, grid: Array, danger: Dictionary) -> bool:
	var own_blast := {}
	for c: int in _blast_cross(cell, blast_range, grid):
		own_blast[c] = true
	for n: int in _neighbors(cell):
		if not _walkable(n, grid) or danger.has(n):
			continue
		for m: int in _neighbors(n):
			if m != cell and _walkable(m, grid) and not own_blast.has(m) and not danger.has(m):
				return true
	return false


func _nearest_target(from_pos: Vector2, from_cell: int, grid: Array, players: Dictionary) -> int:
	var best := -1
	var best_distance := INF
	# Soft walls to break, and rivals to hunt, both count as targets.
	for cell in grid.size():
		if int(grid[cell]) != BlastGrid.Cell.SOFT:
			continue
		var distance := from_pos.distance_squared_to(_cell_center(cell))
		if distance < best_distance:
			best_distance = distance
			best = cell
	for other: int in players:
		if other == slot:
			continue
		var state: Array = players[other]
		if state.size() <= BlastGrid.PS_Y:
			continue
		var pos := Vector2(float(state[BlastGrid.PS_X]), float(state[BlastGrid.PS_Y]))
		var distance := from_pos.distance_squared_to(pos)
		if distance < best_distance:
			best_distance = distance
			best = _cell_at(pos)
	return best if best != from_cell else -1


## Step toward `target_cell` via a walkable, non-dangerous neighbor; if the
## greedy step is blocked or unsafe, hold.
func _step_toward_safely(
	from_cell: int, target_cell: int, grid: Array, danger: Dictionary, from_pos: Vector2
) -> Dictionary:
	var target_pos := _cell_center(target_cell)
	var best := -1
	var best_distance := INF
	for n: int in _neighbors(from_cell):
		if not _walkable(n, grid) or danger.has(n):
			continue
		var distance := _cell_center(n).distance_squared_to(target_pos)
		if distance < best_distance:
			best_distance = distance
			best = n
	if best == -1:
		return {}
	return _move_to_cell(from_pos, best)


func _move_to_cell(from_pos: Vector2, cell: int) -> Dictionary:
	var dir := _cell_center(cell) - from_pos
	if dir.length() < 0.001:
		return {}
	dir = dir.normalized()
	return {"mx": dir.x, "my": dir.y}
