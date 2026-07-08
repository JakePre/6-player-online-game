extends MinigameView3D
## Blast Grid client view (M14-06): renders the Bomberman grid in the shared
## iso-arena — indestructible pillars, destructible soft walls (which puff and
## vanish when blasted), bombs with a fuse pulse, the blast-cross flames,
## floating power-ups, and the players. Renders get_snapshot() only.

const PILLAR_COLOR := Color(0.32, 0.34, 0.4)
const SOFT_COLOR := Color(0.6, 0.44, 0.3)
const BOMB_COLOR := Color(0.15, 0.15, 0.18)
const FLAME_COLOR := Color(1.0, 0.55, 0.15)
const RANGE_COLOR := Color(1.0, 0.5, 0.35)
const BOMB_POWER_COLOR := Color(0.45, 0.75, 1.0)
const BLOCK_HEIGHT := 1.1

var players := {}
var grid: Array = []

var _blocks := {}  # cell (int) -> MeshInstance3D (SOLID pillars + SOFT walls)
# Pooled (#709): reused across snapshots, hiding surplus instead of freeing, so
# a dense grid (bombs+flames+powerups at 24 players) stops churning
# MeshInstance3D/StandardMaterial3D allocations every render.
var _bomb_nodes: Array[MeshInstance3D] = []
var _bomb_materials: Array[StandardMaterial3D] = []
var _bombs: Array = []
var _flame_mesh: BoxMesh
var _flame_nodes: Array[MeshInstance3D] = []
var _flame_cells: Array = []
var _power_nodes: Array[MeshInstance3D] = []
var _power_materials: Array[StandardMaterial3D] = []
var _powerups: Array = []
var _flames_seen := {}
## Snapshot counter drives the fuse pulse without a local clock.
var _ticks := 0
## slot -> was alive last render, for the KO edge (#728).
var _alive_seen := {}


func _setup_3d() -> void:
	_flame_mesh = BoxMesh.new()
	_flame_mesh.size = Vector3(BlastGrid.CELL_SIZE * 0.9, 0.1, BlastGrid.CELL_SIZE * 0.9)
	var material := StandardMaterial3D.new()
	material.albedo_color = FLAME_COLOR
	material.emission_enabled = true
	material.emission = FLAME_COLOR
	material.emission_energy_multiplier = 1.8
	_flame_mesh.material = material


func _physics_process(_delta: float) -> void:
	send_move_intent()
	if Input.is_action_just_pressed(&"action_primary"):
		NetManager.send_match_input({"bomb": true})


## Ashy warm floor under the crate grid (#589).
func _floor_tint() -> Color:
	return Color(0.95, 0.88, 0.82)


func _arena_half() -> float:
	return BlastGrid.ARENA_HALF + 1.0


func _render_3d(game: Dictionary) -> void:
	grid = game.get("grid", [])
	players = game.get("players", {})
	_ticks += 1
	_update_blocks()
	_update_bombs(game.get("bombs", []))
	_update_flames(game.get("flames", []))
	_update_powerups(game.get("powerups", []))
	_update_players()


## Blocks are kept in sync with the grid: pillars persist, soft walls puff and
## free the moment a blast turns their cell to EMPTY.
func _update_blocks() -> void:
	for cell in mini(grid.size(), BlastGrid.GRID * BlastGrid.GRID):
		var kind := int(grid[cell])
		var node: MeshInstance3D = _blocks.get(cell)
		if node != null and kind != BlastGrid.Cell.SOLID and kind != BlastGrid.Cell.SOFT:
			if kind == BlastGrid.Cell.EMPTY:
				ArenaFX.dust(arena, to_arena(_cell_pos(cell), 0.3), SOFT_COLOR)
				# Signature cue (#728, docs/AUDIO_GUIDE.md — Bombs & blasts): a
				# soft wall giving way to a blast.
				play_sfx(&"break_wood")
			node.queue_free()
			_blocks.erase(cell)
		elif node == null and (kind == BlastGrid.Cell.SOLID or kind == BlastGrid.Cell.SOFT):
			_blocks[cell] = _make_block(cell, kind == BlastGrid.Cell.SOLID)


func _make_block(cell: int, solid: bool) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(BlastGrid.CELL_SIZE * 0.92, BLOCK_HEIGHT, BlastGrid.CELL_SIZE * 0.92)
	var material := StandardMaterial3D.new()
	material.albedo_color = PILLAR_COLOR if solid else SOFT_COLOR
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = "Block%d" % cell
	node.mesh = mesh
	node.position = to_arena(_cell_pos(cell), BLOCK_HEIGHT * 0.5)
	arena.add_child(node)
	return node


func _update_bombs(bomb_list: Array) -> void:
	_bombs = bomb_list
	sync_pool(_bomb_nodes, bomb_list.size(), _make_bomb, _place_bomb)


func _make_bomb() -> Node3D:
	var mesh := SphereMesh.new()
	mesh.radius = BlastGrid.CELL_SIZE * 0.32
	mesh.height = mesh.radius * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = BOMB_COLOR
	material.emission_enabled = true
	mesh.material = material
	_bomb_materials.append(material)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	return node


func _place_bomb(node: Node3D, index: int) -> void:
	var bomb: Array = _bombs[index]
	# Pulses faster as the fuse shortens — the readable "about to blow" cue.
	var urgency := clampf(1.0 - float(bomb[1]) / BlastGrid.BOMB_FUSE, 0.0, 1.0)
	var beat := 0.5 + 0.5 * sin(_ticks * (0.3 + urgency))
	_bomb_materials[index].emission = FLAME_COLOR
	_bomb_materials[index].emission_energy_multiplier = beat * (0.4 + urgency)
	node.position = to_arena(_cell_pos(int(bomb[0])), BlastGrid.CELL_SIZE * 0.32)


## Flame cells glow; a cell newly on fire pops a burst + shake (the detonation).
func _update_flames(flame_cells: Array) -> void:
	var current := {}
	for cell_v: Variant in flame_cells:
		current[int(cell_v)] = true
	var fresh := false
	for cell: int in current:
		if not _flames_seen.has(cell):
			fx_burst(_cell_pos(cell), FLAME_COLOR, 0.6)
			fresh = true
	if current.size() > _flames_seen.size():
		request_shake(4.0)
	if fresh:
		# One explosion per snapshot however many cells lit together (a chain
		# detonation), matching the shared shake — avoids machine-gunning #728.
		play_sfx(&"explosion")
	_flames_seen = current
	_flame_cells = flame_cells
	sync_pool(_flame_nodes, flame_cells.size(), _make_flame, _place_flame)


func _make_flame() -> Node3D:
	var node := MeshInstance3D.new()
	node.mesh = _flame_mesh
	return node


func _place_flame(node: Node3D, index: int) -> void:
	node.position = to_arena(_cell_pos(int(_flame_cells[index])), 0.12)


func _update_powerups(power_list: Array) -> void:
	_powerups = power_list
	sync_pool(_power_nodes, power_list.size(), _make_powerup, _place_powerup)


func _make_powerup() -> Node3D:
	var mesh := SphereMesh.new()
	mesh.radius = BlastGrid.CELL_SIZE * 0.22
	mesh.height = mesh.radius * 2.0
	var material := StandardMaterial3D.new()
	material.emission_enabled = true
	material.emission_energy_multiplier = 0.8
	mesh.material = material
	_power_materials.append(material)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	return node


func _place_powerup(node: Node3D, index: int) -> void:
	var entry: Array = _powerups[index]
	var color := RANGE_COLOR if int(entry[1]) == BlastGrid.Power.RANGE else BOMB_POWER_COLOR
	_power_materials[index].albedo_color = color
	_power_materials[index].emission = color
	node.position = to_arena(_cell_pos(int(entry[0])), 0.4)


func _update_players() -> void:
	for slot: int in names:
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		var alive: bool = players.has(slot)
		rig.visible = alive
		# The shared elimination cue (#728) — down order = placement, terminal
		# for the round.
		if bool(_alive_seen.get(slot, true)) and not alive:
			play_sfx(&"ko")
		_alive_seen[slot] = alive
		if not alive:
			continue
		var state: Array = players[slot]
		update_rig(slot, Vector2(state[0], state[1]))
		rig.display_name = "%s  ✚%d 💣%d" % [player_name(slot), int(state[2]), int(state[3])]


func _cell_pos(cell: int) -> Vector2:
	var half := (BlastGrid.GRID - 1) / 2.0
	@warning_ignore("integer_division")
	var r := cell / BlastGrid.GRID
	var c := cell % BlastGrid.GRID
	return Vector2((c - half) * BlastGrid.CELL_SIZE, (r - half) * BlastGrid.CELL_SIZE)
