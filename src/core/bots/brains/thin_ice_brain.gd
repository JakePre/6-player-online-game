class_name ThinIceBrain
extends BotBrain
## Surface-avoider archetype (M19): get off BREAKING/CRACKED ice and walk to
## the safest (most intact) nearby tile. Snapshot: {grid_size, tile_size,
## tiles: flat row-major TileState array, players: {slot: [x, y]}, fallen}
## (ThinIce). TileState: 0 INTACT, 1 CRACKED, 2 BREAKING, 3 GONE.


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var me := my_position(game.get("players", {}))
	if me == Vector2.INF:
		return {}
	var tiles: Array = game.get("tiles", [])
	var grid_size := int(game.get("grid_size", 0))
	var tile_size := float(game.get("tile_size", 2.0))
	if tiles.is_empty() or grid_size <= 0:
		return {}
	var half := grid_size * tile_size / 2.0
	var my_col := clampi(int(floorf((me.x + half) / tile_size)), 0, grid_size - 1)
	var my_row := clampi(int(floorf((me.y + half) / tile_size)), 0, grid_size - 1)
	# Score nearby tiles: intact best, then cracked; never step onto
	# breaking/gone. Prefer close tiles so bots don't sprint across the map.
	var best := Vector2.INF
	var best_score := -INF
	for row in grid_size:
		for col in grid_size:
			var state := int(tiles[row * grid_size + col])
			if state >= 2:  # BREAKING or GONE
				continue
			var hops := absi(col - my_col) + absi(row - my_row)
			if hops > 3:
				continue
			var score := (2.0 if state == 0 else 0.5) - hops * 0.6
			# Standing still cracks ice (#167): the current tile scores worst
			# of its state class so the bot keeps rotating.
			if hops == 0:
				score -= 1.0
			if score > best_score:
				best_score = score
				best = Vector2(-half + (col + 0.5) * tile_size, -half + (row + 0.5) * tile_size)
	if best == Vector2.INF:
		return {}
	return move_toward_point(me, best, 0.15)
