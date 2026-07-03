extends MinigameView3D
## Color Clash client view (M8-10): renders the replicated paint grid in the
## shared 2.5D iso-arena (M8-01, MinigameView3D) — one flat quad per tile via
## a MultiMesh with per-instance faction colors, players as CharacterRig
## instances. Presentation-tier swap only: state storage and the render
## contract are unchanged from the 2D pass (M4-13).

const UNPAINTED_COLOR := Color(0.22, 0.23, 0.26)
const PAINT_LIFT := 0.02
const PAINT_DARKEN := 0.15

## Latest replicated state, straight from ColorClash.get_snapshot().
var players := {}
var grid: Array = []
var teams: Array = []

var _tiles: MultiMeshInstance3D
## Script-side copy of per-tile colors: the MultiMesh color buffer lives in
## the RenderingServer and reads back empty under the headless test runner.
var _tile_colors: Array = []


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
	_update_tiles()
	_update_players()


func _update_tiles() -> void:
	var multimesh := _tiles.multimesh
	for i in mini(grid.size(), multimesh.instance_count):
		var color := _faction_color(int(grid[i]))
		_tile_colors[i] = color
		multimesh.set_instance_color(i, color)


func tile_color(index: int) -> Color:
	return _tile_colors[index] if index < _tile_colors.size() else UNPAINTED_COLOR


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
