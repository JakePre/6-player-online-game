class_name MemoryMatchBrain
extends BotBrain
## Memory archetype (M19-02, #686): the safe tiles are shown only during the
## SHOW phase and blank out in the DARK, so the whole game is remembering the
## pattern. The brain caches the safe set every tick it is visible and, once it
## has one, walks to the centre of the nearest remembered-safe tile and settles
## there — the nearest safe tile to a spot already on one is itself, so it holds
## put through the dark check instead of drifting off.
##
## Snapshot: {players: {slot: [x, y, act_seq, shove_cd]}, phase (0 SHOW, 1 DARK),
## safe_tiles: [tile_index, ...] (only while SHOW), grid_size, round, fallen}
## (MemoryMatch). Input: {mx, my, shove}.

## Cached row-major safe-tile indices from the most recent SHOW phase.
var _known_safe: Array = []


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var state: Array = players.get(slot, [])
	if state.size() <= MemoryMatch.PS_Y:
		return {}  # eliminated or not yet in the snapshot
	var me := Vector2(float(state[MemoryMatch.PS_X]), float(state[MemoryMatch.PS_Y]))
	# Memorise the pattern whenever it is on show; it blanks out in the dark.
	var shown: Array = game.get("safe_tiles", [])
	if not shown.is_empty():
		_known_safe = shown.duplicate()
	if _known_safe.is_empty():
		return {}  # first frame before any pattern has been shown
	var grid := int(game.get("grid_size", MemoryMatch.GRID_SIZE))
	var intent := move_toward_point(me, _nearest_safe_center(me, grid), 0.25)
	# Jostle for tiles in the dark: shove a rival crowding into reach when the
	# cooldown is up (#784). Pairs naturally with #818's later imperfection knob.
	if int(game.get("phase", MemoryMatch.Phase.SHOW)) == MemoryMatch.Phase.DARK:
		var cd := (
			float(state[MemoryMatch.PS_SHOVE_CD]) if state.size() > MemoryMatch.PS_SHOVE_CD else 0.0
		)
		if cd <= 0.0 and _rival_in_reach(players, me):
			intent["shove"] = true
	return intent


## True when a standing rival is within shove range — the cue to swing.
func _rival_in_reach(players: Dictionary, me: Vector2) -> bool:
	for other: int in players:
		if other == slot:
			continue
		var state: Array = players[other]
		if state.size() <= MemoryMatch.PS_Y:
			continue
		var pos := Vector2(float(state[MemoryMatch.PS_X]), float(state[MemoryMatch.PS_Y]))
		if me.distance_to(pos) <= MemoryMatch.SHOVE_RADIUS:
			return true
	return false


## The centre of the remembered-safe tile closest to `from`.
func _nearest_safe_center(from: Vector2, grid: int) -> Vector2:
	var best := Vector2.ZERO
	var best_distance := INF
	for tile: int in _known_safe:
		var center := _tile_center(tile, grid)
		var distance := from.distance_squared_to(center)
		if distance < best_distance:
			best_distance = distance
			best = center
	return best


## World centre of a row-major tile index — mirrors MemoryMatch.tile_of so we
## land squarely inside the tile, not on a seam the floor check rounds the wrong
## way.
func _tile_center(tile: int, grid: int) -> Vector2:
	var col := tile % grid
	var row := tile / grid
	var half := grid * MemoryMatch.TILE_SIZE / 2.0
	return Vector2(
		col * MemoryMatch.TILE_SIZE - half + MemoryMatch.TILE_SIZE / 2.0,
		row * MemoryMatch.TILE_SIZE - half + MemoryMatch.TILE_SIZE / 2.0
	)
