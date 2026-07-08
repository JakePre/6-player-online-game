class_name TrapCorridorBrain
extends BotBrain
## Trap Corridor archetype (M19-02, #686): the role is public and rotates
## (snapshot.trapper), so the brain branches on it each sub-round. As trapper,
## spend the trap budget spread across the mid-corridor lanes; as runner, push
## to the finish, preferring already-sprung (revealed = safe) tiles since the
## live traps never leave the server.
##
## Snapshot: {phase, trapper, players: {slot: [x, y]} (excludes trapper +
## caught), revealed: [tile], caught: [slot], traps_left, corridor: [len,
## half_width]}. Input: {trap: [col, row]} (trapper, TRAPPING); {mx, my}
## (runner, RUNNING). Indices named via TrapCorridor.PS_* (#708); read here via
## the shared BotBrain.my_position() helper (every game's [x, y, ...] convention).

## Trap tiles placed this sub-round, [col, row]; reset when a fresh budget
## appears. Kept so placements spread instead of stacking on one tile.
var _placed: Array = []
var _target_row := -1


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var phase := int(game.get("phase", TrapCorridor.Phase.TRAPPING))
	var trapper := int(game.get("trapper", -1))
	if phase == TrapCorridor.Phase.TRAPPING:
		if slot == trapper:
			return _place_trap(game)
		return {}
	if slot == trapper:
		return {}
	var me := my_position(game.get("players", {}))
	if me == Vector2.INF:
		return {}
	return _run(game, me)


## One trap per tick, on a distinct interior tile, until the budget is spent.
func _place_trap(game: Dictionary) -> Dictionary:
	var traps_left := int(game.get("traps_left", 0))
	if traps_left >= TrapCorridor.TRAP_BUDGET:
		_placed.clear()  # a fresh sub-round: full budget, nothing placed yet
	if traps_left <= 0:
		return {}
	for _attempt in 12:
		var col := rng.randi_range(1, TrapCorridor.COLS - 2)
		var row := rng.randi_range(0, TrapCorridor.ROWS - 1)
		if [col, row] not in _placed:
			_placed.append([col, row])
			return {"trap": [col, row]}
	return {}


## Push toward the finish (+x), steering into a revealed-safe lane ahead when
## one is near, else holding a slot-seeded lane so runners don't bunch up.
func _run(game: Dictionary, me: Vector2) -> Dictionary:
	var my_col := _col_of(me.x)
	var safe_row := _nearest_safe_row_ahead(game.get("revealed", []), my_col)
	if safe_row != -1:
		_target_row = safe_row
	elif _target_row == -1:
		_target_row = _row_of(me.y)
	var target_y := _row_center(_target_row)
	var dy := clampf((target_y - me.y) * 0.8, -1.0, 1.0)
	return {"mx": 1.0, "my": dy}


## Row of the nearest revealed (already-sprung, therefore safe) tile within a
## few columns ahead, or -1 if none — those tiles are the only known-safe
## ground a runner ever sees.
func _nearest_safe_row_ahead(revealed: Array, my_col: int) -> int:
	var best_row := -1
	var best_col := TrapCorridor.COLS
	for tile: int in revealed:
		var col := int(tile) / TrapCorridor.ROWS
		if col <= my_col or col > my_col + 3:
			continue
		if col < best_col:
			best_col = col
			best_row = int(tile) % TrapCorridor.ROWS
	return best_row


func _col_of(x: float) -> int:
	return clampi(int(x / TrapCorridor.TILE_LEN), 0, TrapCorridor.COLS - 1)


func _row_of(y: float) -> int:
	var span := TrapCorridor.CORRIDOR_HALF_WIDTH
	return clampi(int((y + span) / TrapCorridor.TILE_WIDTH), 0, TrapCorridor.ROWS - 1)


func _row_center(row: int) -> float:
	return -TrapCorridor.CORRIDOR_HALF_WIDTH + (row + 0.5) * TrapCorridor.TILE_WIDTH
