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

## Latest replicated state, straight from ColorClash.get_snapshot().
var players := {}
var grid: Array = []
var teams: Array = []

var _tiles: MultiMeshInstance3D
## Script-side copy of per-tile colors: the MultiMesh color buffer lives in
## the RenderingServer and reads back empty under the headless test runner.
var _tile_colors: Array = []
# M13-21 FX state: last-seen tile owners for splat diffing, tile counts for
# the leading-faction shimmer, snapshot counter for the pulse.
var _grid_seen: Array = []
var _counts := {}
var _pulse_ticks := 0


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _arena_half() -> float:
	return ColorClash.ARENA_HALF + 1.0


func _setup_3d() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(ColorClash.TILE_WORLD, ColorClash.TILE_WORLD) * 0.94
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	mesh.material = material

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = ColorClash.GRID_SIZE * ColorClash.GRID_SIZE
	var start := -ColorClash.ARENA_HALF + ColorClash.TILE_WORLD * 0.5
	for i in multimesh.instance_count:
		var row := i / ColorClash.GRID_SIZE
		var col := i % ColorClash.GRID_SIZE
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


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	grid = game.get("grid", [])
	teams = game.get("teams", [])
	_counts = game.get("counts", {})
	_pulse_ticks += 1
	_update_tiles()
	_update_players()


func _update_tiles() -> void:
	var multimesh := _tiles.multimesh
	# Splat diffing only once a same-shaped grid has been seen: the first
	# sighting (and any size change) seeds silently instead of erupting.
	var seeded := _grid_seen.size() == grid.size()
	var splats := 0
	var leading := leading_faction()
	var boost := shimmer_boost()
	for i in mini(grid.size(), multimesh.instance_count):
		var faction := int(grid[i])
		var color := _faction_color(faction)
		_tile_colors[i] = color
		# Fresh paint splashes in the new owner's color (M13-21).
		if seeded and splats < MAX_SPLATS_PER_SNAPSHOT:
			if faction != int(_grid_seen[i]) and faction != ColorClash.UNPAINTED:
				ArenaFX.splash(arena, to_arena(_tile_world_pos(i), PAINT_LIFT + 0.05), color)
				splats += 1
		# Coverage shimmer (M13-21): the leading faction's tiles breathe.
		# (leading == UNPAINTED means "no leader", never "unpainted shimmers".)
		var is_leading := faction == leading and leading != ColorClash.UNPAINTED
		var shown := color.lightened(boost) if is_leading else color
		multimesh.set_instance_color(i, shown)
	_grid_seen = grid.duplicate()


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
	var start := -ColorClash.ARENA_HALF + ColorClash.TILE_WORLD * 0.5
	var row := index / ColorClash.GRID_SIZE
	var col := index % ColorClash.GRID_SIZE
	return Vector2(start + col * ColorClash.TILE_WORLD, start + row * ColorClash.TILE_WORLD)


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		update_rig(slot, Vector2(state[0], state[1]))


func _faction_color(faction: int) -> Color:
	if faction == ColorClash.UNPAINTED:
		return UNPAINTED_COLOR
	if faction < teams.size() and not teams[faction].is_empty():
		return player_color(int(teams[faction][0])).darkened(PAINT_DARKEN)
	return player_color(faction).darkened(PAINT_DARKEN)
