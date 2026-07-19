extends MinigameView3D
## Color Clash client view (M8-10): renders the replicated paint grid in the
## shared 2.5D iso-arena (M8-01, MinigameView3D) — one flat quad per tile via
## a MultiMesh with per-instance faction colors, players as CharacterRig
## instances. Presentation-tier swap only: state storage and the render
## contract are unchanged from the 2D pass (M4-13).
## M13-21 FX pass: tiles changing owner splash paint, and the faction holding
## the most tiles shimmers so the current leader reads at a glance.

const UNPAINTED_COLOR := Color(0.22, 0.23, 0.26)
const PAINT_LIFT := 0.02
const PAINT_DARKEN := 0.15
## Ceiling on paint splashes per snapshot: a mass repaint (late join, big
## desync catch-up) must not spawn a particle storm.
const MAX_SPLATS_PER_SNAPSHOT := 8
const SHIMMER_PERIOD_TICKS := 16
const SHIMMER_STRENGTH := 0.12
## Home-turf surf FX (#955): a subtle dust streak in your own color when a rig
## is boosted — moving into a tile its faction owns (the sim's +25% highway).
## Throttled and staggered per slot so it stays a hint, not a haze; ArenaFX
## already emits nothing under reduced motion (design: reduced-motion = none).
const SURF_FX_EVERY := 4
const MIN_SURF_MOVE := 0.12

## Latest replicated state, straight from ColorClash.get_snapshot().
var players := {}
var grid: Array = []
var teams: Array = []

var _tiles: MultiMeshInstance3D
## Script-side copy of per-tile colors: the MultiMesh color buffer lives in
## the RenderingServer and reads back empty under the headless test runner.
var _tile_colors: Array = []
## This match's scaled grid dimension / arena size (M15 → 24). Derived from the
## head count with the sim's own helpers, so the tile mesh matches the grid
## the server paints without threading the size through the snapshot.
var _dim := ColorClash.GRID_SIZE
var _half := ColorClash.ARENA_HALF
# M13-21 FX state: last-seen tile owners for splat diffing, tile counts for
# the leading-faction shimmer, snapshot counter for the pulse.
var _grid_seen: Array = []
var _counts := {}
var _pulse_ticks := 0
## Last-seen leading faction, for the take-the-lead cue (#728).
var _leading_seen := ColorClash.UNPAINTED
## Last-snapshot positions per slot, for the surf-FX movement/boost check (#955).
var _prev_player_pos := {}


func _physics_process(_delta: float) -> void:
	send_move_intent()


## Cool neutral floor so the paint tiles do the talking (#589).
func _floor_tint() -> Color:
	return Color(0.92, 0.94, 0.98)


func _arena_half() -> float:
	return ColorClash.arena_half_for(names.size()) + 1.0


func _setup_3d() -> void:
	# Best-effort size from the head count; the snapshot's authoritative dim
	# corrects it on the first render if a held-but-disconnected member skewed
	# the estimate across a grid_dim_for boundary (#662).
	_build_tile_grid(ColorClash.grid_dim_for(names.size()), ColorClash.arena_half_for(names.size()))


## Builds (or rebuilds) the `dim`x`dim` paint-tile MultiMesh over an arena of
## half-extent `half`, freeing any prior grid first so a rebuild is clean.
func _build_tile_grid(dim: int, half: float) -> void:
	_dim = dim
	_half = half
	if _tiles != null:
		# Remove from the tree immediately (not just queue_free, which defers to
		# frame end) so the name "PaintTiles" is free for the replacement and no
		# stale node lingers alongside it.
		arena.remove_child(_tiles)
		_tiles.queue_free()
	_tile_colors.clear()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(ColorClash.TILE_WORLD, ColorClash.TILE_WORLD) * 0.94
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	mesh.material = material

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = _dim * _dim
	var start := -_half + ColorClash.TILE_WORLD * 0.5
	for i in multimesh.instance_count:
		var row := i / _dim
		var col := i % _dim
		var pos := Vector3(
			start + col * ColorClash.TILE_WORLD, PAINT_LIFT, start + row * ColorClash.TILE_WORLD
		)
		multimesh.set_instance_transform(i, Transform3D(Basis(), pos))
		multimesh.set_instance_color(i, UNPAINTED_COLOR)
		_tile_colors.append(UNPAINTED_COLOR)

	_tiles = MultiMeshInstance3D.new()
	_tiles.name = "PaintTiles"
	_tiles.multimesh = multimesh
	arena.add_child(_tiles)


## The setup-time estimate over-counts disconnected-but-held members, so at a
## grid_dim_for boundary the view built a wrong-width tile grid and the sim's
## flat `grid` mapped onto the wrong nodes — scrambled paint (#662, sibling of
## Thin Ice #578). When the snapshot's authoritative dim disagrees, rebuild to
## match and drop the delta-fold baseline: a `grid_changes` computed against the
## old width must never be folded onto the fresh grid, so it waits for the
## keyframe the sim always sends on a resize (#479).
func _adopt_snapshot_dim(dim: int, half: float) -> void:
	if dim == _dim:
		return
	_build_tile_grid(dim, half)
	_grid_seen = []  # no splat storm on the rebuilt board
	grid = []  # await a fresh keyframe; never apply a stale-width delta
	if _camera_rig != null:
		_camera_rig.ortho_size = (half + 1.0) * 2.4  # re-fit like _arena_half() + 1


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	# Honor the sim's authoritative grid dimension before folding paint (#662).
	if game.has("dim"):
		_adopt_snapshot_dim(int(game["dim"]), float(game.get("half", _half)))
	# Grid replication (#479): a keyframe carries the full "grid" — an
	# authoritative reset that mounts a fresh view and heals any dropped delta.
	# Between keyframes "grid_changes" carries only the tiles that flipped, which
	# we fold into the grid we already hold. A delta arriving before the first
	# keyframe has nothing to build on, so it waits for the keyframe to arrive.
	if game.has("grid"):
		grid = (game["grid"] as Array).duplicate()
	elif game.has("grid_changes") and not grid.is_empty():
		for change: Array in game["grid_changes"]:
			var index := int(change[ColorClash.GC_INDEX])
			if index >= 0 and index < grid.size():
				grid[index] = int(change[ColorClash.GC_OWNER])
	teams = game.get("teams", [])
	_counts = game.get("counts", {})
	_pulse_ticks += 1
	_update_tiles()
	_update_players()
	_update_surf_fx()
	# Signature cue (#728, docs/AUDIO_GUIDE.md — Tiles & ice): taking the lead
	# is a positive checkpoint, same spirit as musical_platforms' claim bell.
	var leading := leading_faction()
	if leading != _leading_seen and leading != ColorClash.UNPAINTED and leading == _my_faction():
		play_sfx(&"bell")
	_leading_seen = leading


func _update_tiles() -> void:
	var multimesh := _tiles.multimesh
	# Splat diffing only once a same-shaped grid has been seen: the first
	# sighting (and any size change) seeds silently instead of erupting.
	var seeded := _grid_seen.size() == grid.size()
	var splats := 0
	var leading := leading_faction()
	var boost := shimmer_boost()
	var my_faction := _my_faction()
	var my_faction_painted := false
	for i in mini(grid.size(), multimesh.instance_count):
		var faction := int(grid[i])
		var color := _faction_color(faction)
		_tile_colors[i] = color
		# Fresh paint splashes in the new owner's color (M13-21).
		if seeded and splats < MAX_SPLATS_PER_SNAPSHOT:
			if faction != int(_grid_seen[i]) and faction != ColorClash.UNPAINTED:
				ArenaFX.splash(arena, to_arena(_tile_world_pos(i), PAINT_LIFT + 0.05), color)
				splats += 1
				if faction == my_faction:
					my_faction_painted = true
		# Coverage shimmer (M13-21): the leading faction's tiles breathe.
		# (leading == UNPAINTED means "no leader", never "unpainted shimmers".)
		var is_leading := faction == leading and leading != ColorClash.UNPAINTED
		var shown := color.lightened(boost) if is_leading else color
		multimesh.set_instance_color(i, shown)
	_grid_seen = grid.duplicate()
	# One ping per snapshot, not per tile, so a mass repaint isn't a chord
	# (M12-02). `pop` (#728, docs/AUDIO_GUIDE.md) — a tile claim isn't currency,
	# so this no longer repurposes the shared `coin` meaning (rule 1).
	if my_faction_painted:
		play_sfx(&"pop")


## This client's own faction index, or -1 before teams are known.
func _my_faction() -> int:
	for faction in teams.size():
		if my_slot in (teams[faction] as Array):
			return faction
	return -1


func tile_color(index: int) -> Color:
	return _tile_colors[index] if index < _tile_colors.size() else UNPAINTED_COLOR


## Faction currently holding the most tiles; UNPAINTED on a tie or an
## unpainted board (nobody shimmers then).
func leading_faction() -> int:
	var best := ColorClash.UNPAINTED
	var best_count := 0
	var tied := false
	for faction: int in _counts:
		var count := int(_counts[faction])
		if count > best_count:
			best = faction
			best_count = count
			tied = false
		elif count == best_count:
			tied = true
	return ColorClash.UNPAINTED if tied or best_count == 0 else best


## Brightness boost applied to the leading faction's tiles this snapshot,
## breathing on snapshot cadence (the M13-03 zone-throb pattern).
func shimmer_boost() -> float:
	return SHIMMER_STRENGTH * (0.5 + 0.5 * sin(_pulse_ticks * TAU / SHIMMER_PERIOD_TICKS))


func _tile_world_pos(index: int) -> Vector2:
	var start := -_half + ColorClash.TILE_WORLD * 0.5
	var row := index / _dim
	var col := index % _dim
	return Vector2(start + col * ColorClash.TILE_WORLD, start + row * ColorClash.TILE_WORLD)


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		update_rig(slot, Vector2(state[ColorClash.PS_X], state[ColorClash.PS_Y]))


## Surf streaks (#955): for each rig that moved far enough this snapshot and is
## boosted (entering a tile its faction owns — the same probe the sim uses to
## apply +25%, so the streak and the speedup never disagree, #971), emit one
## subtle own-color dust puff. Grid may be empty mid-resize (awaiting a keyframe)
## — skip FX then but still refresh the position baseline so the next real
## snapshot measures a true step, not a resize jump.
func _update_surf_fx() -> void:
	if not grid.is_empty():
		for slot: int in players:
			var state: Array = players[slot]
			if state.size() < ColorClash.PS_COUNT:
				continue
			var pos := Vector2(state[ColorClash.PS_X], state[ColorClash.PS_Y])
			var prev: Vector2 = _prev_player_pos.get(slot, pos)
			var step := pos - prev
			if step.length() < MIN_SURF_MOVE or (_pulse_ticks + slot) % SURF_FX_EVERY != 0:
				continue
			var faction := int(state[ColorClash.PS_FACTION])
			# Same full-tile-ahead probe the sim uses to apply the +25% (#955), so
			# the streak and the speedup never disagree (#971 desync class).
			var probe := pos + step.normalized() * ColorClash.TILE_WORLD
			var owner := int(grid[ColorClash.tile_index_at(probe, _dim, _half)])
			if ColorClash.speed_mult(owner, faction) <= ColorClash.NEUTRAL_SPEED:
				continue  # neutral or enemy paint: no highway, no streak
			ArenaFX.dust(
				arena, to_arena(pos, PAINT_LIFT + 0.03), _faction_color(faction).lightened(0.25)
			)
	_prev_player_pos = _snapshot_positions()


## {slot: Vector2} of this snapshot's rig positions, for next tick's step check.
func _snapshot_positions() -> Dictionary:
	var out := {}
	for slot: int in players:
		var state: Array = players[slot]
		if state.size() >= ColorClash.PS_COUNT:
			out[slot] = Vector2(state[ColorClash.PS_X], state[ColorClash.PS_Y])
	return out


func _faction_color(faction: int) -> Color:
	if faction == ColorClash.UNPAINTED:
		return UNPAINTED_COLOR
	if faction < teams.size() and not teams[faction].is_empty():
		return player_color(int(teams[faction][0])).darkened(PAINT_DARKEN)
	return player_color(faction).darkened(PAINT_DARKEN)
