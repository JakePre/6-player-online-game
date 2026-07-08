class_name ColorClashBrain
extends BotBrain
## Painter archetype (M19-02, #686): walk onto the nearest tile that isn't
## already this bot's own faction color — repainting your own tiles is a
## wasted step, since walking only flips ownership when it changes.
##
## The grid is delta-replicated (#479: a full "grid" keyframe every 30 ticks,
## "grid_changes" [[index, owner], ...] between them) exactly like a human
## client's view, so the brain folds it the same way (mirrors
## color_clash_view.gd's _adopt_snapshot_dim / grid fold) — it holds no more
## information than a real client ever sees.
##
## Snapshot: {players: {slot: [x, y, faction]}, dim, half, grid?,
## grid_changes?}. Input: {mx, my} only (painting is walking, no button).
## Indices named via ColorClash.PS_*/GC_* (#708).

var _grid: Array = []
var _dim := 0


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var state: Array = players.get(slot, [])
	if state.size() < ColorClash.PS_COUNT:
		return {}
	var me := Vector2(float(state[ColorClash.PS_X]), float(state[ColorClash.PS_Y]))
	var faction := int(state[ColorClash.PS_FACTION])
	var dim := int(game.get("dim", 0))
	var half := float(game.get("half", 0.0))
	if dim != _dim:
		_grid = []  # a resize invalidates any delta baseline (#479, #662)
		_dim = dim
	if game.has("grid"):
		_grid = (game["grid"] as Array).duplicate()
	elif game.has("grid_changes") and not _grid.is_empty():
		for change: Array in game["grid_changes"]:
			var index := int(change[ColorClash.GC_INDEX])
			if index >= 0 and index < _grid.size():
				_grid[index] = int(change[ColorClash.GC_OWNER])
	if _grid.is_empty() or dim <= 0:
		# No keyframe folded yet: wander so we're not a statue while waiting.
		return move_toward_point(
			me, Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half))
		)
	var target := _nearest_unowned_tile(me, faction, dim, half)
	if target == Vector2.INF:
		return {"mx": 0.0, "my": 0.0}  # the whole floor is already ours
	return move_toward_point(me, target, ColorClash.TILE_WORLD * 0.3)


## World position of the nearest tile whose owner isn't `faction`, or INF if
## every tile already reads ours.
func _nearest_unowned_tile(me: Vector2, faction: int, dim: int, half: float) -> Vector2:
	var best := Vector2.INF
	var best_dist := INF
	for index in _grid.size():
		if int(_grid[index]) == faction:
			continue
		var col := index % dim
		var row := index / dim
		var pos := Vector2(
			-half + (col + 0.5) * ColorClash.TILE_WORLD, -half + (row + 0.5) * ColorClash.TILE_WORLD
		)
		var dist := me.distance_squared_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = pos
	return best
