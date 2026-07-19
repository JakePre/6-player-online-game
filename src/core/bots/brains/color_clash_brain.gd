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

## Home-turf bias (#955): a target that touches our own paint is reached along
## our own color — a speed highway — so weight it as if it were nearer. Cheap
## 4-neighbour check, biasing the existing pick, not real pathfinding.
const OWN_EDGE_BIAS := 0.5

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


## World position of the nearest tile worth painting, or INF if every tile
## already reads ours. Distance is weighted by OWN_EDGE_BIAS for tiles touching
## our own paint so the bot grows its own edge (staying on its color highway,
## #955) rather than lunging across enemy turf for a marginally closer tile.
func _nearest_unowned_tile(me: Vector2, faction: int, dim: int, half: float) -> Vector2:
	var best := Vector2.INF
	var best_score := INF
	for index in _grid.size():
		if int(_grid[index]) == faction:
			continue
		var col := index % dim
		var row := index / dim
		var pos := Vector2(
			-half + (col + 0.5) * ColorClash.TILE_WORLD, -half + (row + 0.5) * ColorClash.TILE_WORLD
		)
		var score := me.distance_squared_to(pos)
		if _touches_faction(index, faction, dim):
			score *= OWN_EDGE_BIAS
		if score < best_score:
			best_score = score
			best = pos
	return best


## True if any orthogonal neighbour of tile `index` is owned by `faction` — i.e.
## the tile sits on the edge of our own territory.
func _touches_faction(index: int, faction: int, dim: int) -> bool:
	var col := index % dim
	var row := index / dim
	if col > 0 and int(_grid[index - 1]) == faction:
		return true
	if col < dim - 1 and int(_grid[index + 1]) == faction:
		return true
	if row > 0 and int(_grid[index - dim]) == faction:
		return true
	if row < dim - 1 and int(_grid[index + dim]) == faction:
		return true
	return false
