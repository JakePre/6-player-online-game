extends MinigameView3D
## Blast Grid client view (M14-06): renders the Bomberman grid in the shared
## iso-arena — indestructible pillars, destructible soft walls (which puff and
## vanish when blasted), bombs with a fuse pulse, the blast-cross flames,
## floating power-ups, and the players. Renders get_snapshot() only.

## Brighter, higher-contrast blocks (#786): the old muted grey/brown pair
## read as flat and dark, especially against the light #589 floor tint.
const PILLAR_COLOR := Color(0.58, 0.6, 0.68)
const SOFT_COLOR := Color(0.85, 0.62, 0.4)
const BOMB_COLOR := Color(0.15, 0.15, 0.18)
const FLAME_COLOR := Color(1.0, 0.55, 0.15)
const RANGE_COLOR := Color(1.0, 0.5, 0.35)
const BOMB_POWER_COLOR := Color(0.45, 0.75, 1.0)
const BLOCK_HEIGHT := 1.1
## Soft walls are the landed MDL-018 wooden crate (#817) — the real model this
## grid was the named consumer for, replacing the crate-face-textured BoxMesh
## (#929). Pillars stay flat-colored — they're structural, not a crate.
const CRATE_SCENE := preload("res://assets/generated/models/wooden-crate.glb")
## The crate GLB is 1 x 0.728 x 1 with its pivot at base center.
const CRATE_GLB_HEIGHT := 0.728
## Powerups read as billboard icons (#929) instead of plain colored blobs —
## the same glyphs the nameplate already uses for range/bomb count.
const RANGE_ICON := "🔥"
const BOMB_ICON := "💣"
## Cursed Skull pickup (#949): the landed MDL-016 skull-token model, wobbling
## in place so its 50/50 gamble reads as "risky" next to the plain powerups.
const SKULL_SCENE := preload("res://assets/generated/models/skull-token.glb")
const SKULL_WOBBLE_DEG := 14.0
const SKULL_BOB := 0.12
## A cursed player wears this on the nameplate so rivals can hunt them (#949).
const CURSED_ICON := "💀"
## Border-revenge riders (#949): eliminated players ghost-tinted on the border.
const GHOST_COLOR := Color(0.55, 0.6, 0.7)

var players := {}
var grid: Array = []

var _blocks := {}  # cell (int) -> Node3D (SOLID pillar boxes + SOFT crate scenes)
# Pooled (#709): reused across snapshots, hiding surplus instead of freeing, so
# a dense grid (bombs+flames+powerups at 24 players) stops churning
# MeshInstance3D/StandardMaterial3D allocations every render.
var _bomb_nodes: Array[MeshInstance3D] = []
var _bomb_materials: Array[StandardMaterial3D] = []
var _bombs: Array = []
var _flame_mesh: BoxMesh
var _flame_nodes: Array[MeshInstance3D] = []
var _flame_cells: Array = []
var _power_nodes: Array[Label3D] = []
var _powerups: Array = []
## Skulls render as the wobbling MDL-016 model, in their own pool (#949).
var _skull_nodes: Array[Node3D] = []
var _skulls: Array = []
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
	_update_revenge(game.get("revenge", []))


## Blocks are kept in sync with the grid: pillars persist, soft walls puff and
## free the moment a blast turns their cell to EMPTY.
func _update_blocks() -> void:
	for cell in mini(grid.size(), BlastGrid.GRID * BlastGrid.GRID):
		var kind := int(grid[cell])
		var node: Node3D = _blocks.get(cell)
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


func _make_block(cell: int, solid: bool) -> Node3D:
	if not solid:
		# The real crate model, stretched to the cell footprint and the grid's
		# BLOCK_HEIGHT so spacing/occlusion are unchanged (base pivot -> y 0).
		var crate := CRATE_SCENE.instantiate() as Node3D
		crate.name = "Block%d" % cell
		var footprint := BlastGrid.CELL_SIZE * 0.92
		crate.scale = Vector3(footprint, BLOCK_HEIGHT / CRATE_GLB_HEIGHT, footprint)
		crate.position = to_arena(_cell_pos(cell), 0.0)
		arena.add_child(crate)
		return crate
	var mesh := BoxMesh.new()
	mesh.size = Vector3(BlastGrid.CELL_SIZE * 0.92, BLOCK_HEIGHT, BlastGrid.CELL_SIZE * 0.92)
	var material := StandardMaterial3D.new()
	material.albedo_color = PILLAR_COLOR
	# Metallic/roughness + a modest emission (#786) give the pillar a real
	# specular highlight and lift it clear of ambient shadow, instead of
	# reading as a flat, dark silhouette (the coin_scramble/treasure_divers
	# convention, toned down since these are structural, not glowing pickups).
	material.metallic = 0.3
	material.roughness = 0.5
	material.emission_enabled = true
	material.emission = PILLAR_COLOR
	material.emission_energy_multiplier = 0.25
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
	var urgency := clampf(1.0 - float(bomb[BlastGrid.BM_FUSE]) / BlastGrid.BOMB_FUSE, 0.0, 1.0)
	var beat := 0.5 + 0.5 * sin(_ticks * (0.3 + urgency))
	_bomb_materials[index].emission = FLAME_COLOR
	_bomb_materials[index].emission_energy_multiplier = beat * (0.4 + urgency)
	# Continuous position (#949) so a kicked bomb reads as a smooth slide;
	# falls back to the cell center for older snapshots without x,y.
	var world := (
		Vector2(float(bomb[BlastGrid.BM_X]), float(bomb[BlastGrid.BM_Y]))
		if bomb.size() > BlastGrid.BM_Y
		else _cell_pos(int(bomb[BlastGrid.BM_CELL]))
	)
	node.position = to_arena(world, BlastGrid.CELL_SIZE * 0.32)


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
	# Skulls (#949) render as the wobbling MDL-016 model; range/bomb stay
	# billboard glyphs. Split the list so each drives its own pool.
	_powerups = []
	_skulls = []
	for entry_v: Variant in power_list:
		var entry: Array = entry_v
		if int(entry[BlastGrid.PW_KIND]) == BlastGrid.Power.SKULL:
			_skulls.append(entry)
		else:
			_powerups.append(entry)
	sync_pool(_power_nodes, _powerups.size(), _make_powerup, _place_powerup)
	sync_pool(_skull_nodes, _skulls.size(), _make_skull, _place_skull)


func _make_skull() -> Node3D:
	return SKULL_SCENE.instantiate() as Node3D


## Bob + wobble so the gamble reads as "risky" beside the plain powerups.
func _place_skull(node: Node3D, index: int) -> void:
	var cell := int((_skulls[index] as Array)[BlastGrid.PW_CELL])
	var bob := SKULL_BOB * sin(_ticks * 0.25 + cell)
	node.position = to_arena(_cell_pos(cell), 0.45 + bob)
	node.rotation.y = deg_to_rad(SKULL_WOBBLE_DEG) * sin(_ticks * 0.2 + cell)


## Billboard icon (#929) — readable at iso distance, unlike a plain color blob.
func _make_powerup() -> Node3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.002
	label.font_size = 44
	label.outline_size = 12
	return label


func _place_powerup(node: Node3D, index: int) -> void:
	var entry: Array = _powerups[index]
	var label := node as Label3D
	var is_range := int(entry[BlastGrid.PW_KIND]) == BlastGrid.Power.RANGE
	label.text = RANGE_ICON if is_range else BOMB_ICON
	label.modulate = RANGE_COLOR if is_range else BOMB_POWER_COLOR
	label.position = to_arena(_cell_pos(int(entry[BlastGrid.PW_CELL])), 0.4)


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
		update_rig(slot, Vector2(state[BlastGrid.PS_X], state[BlastGrid.PS_Y]))
		# A cursed player (#949) wears the skull so rivals can hunt them; a
		# living player's color is restored in case they were a ghost rider.
		rig.player_color = player_color(slot)
		var cursed := state.size() > BlastGrid.PS_CURSED and int(state[BlastGrid.PS_CURSED]) == 1
		var curse_tag := "  %s" % CURSED_ICON if cursed else ""
		rig.display_name = (
			"%s  ✚%d 💣%d%s"
			% [
				player_name(slot),
				int(state[BlastGrid.PS_RANGE]),
				int(state[BlastGrid.PS_MAX_BOMBS]),
				curse_tag,
			]
		)


## Border revenge (#949): eliminated players ride the border as ghost-tinted
## rigs (their lobbed bombs come through the normal bomb list). Runs after
## _update_players, which hides non-living rigs — this re-shows the riders.
func _update_revenge(riders: Array) -> void:
	for rider_v: Variant in riders:
		var rider: Array = rider_v
		var slot := int(rider[BlastGrid.RV_SLOT])
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		reveal_rig(slot)
		rig.visible = true
		rig.player_color = GHOST_COLOR
		rig.display_name = "%s  👻" % player_name(slot)
		rig.position = to_arena(
			Vector2(float(rider[BlastGrid.RV_X]), float(rider[BlastGrid.RV_Y])), 0.0
		)


func _cell_pos(cell: int) -> Vector2:
	var half := (BlastGrid.GRID - 1) / 2.0
	@warning_ignore("integer_division")
	var r := cell / BlastGrid.GRID
	var c := cell % BlastGrid.GRID
	return Vector2((c - half) * BlastGrid.CELL_SIZE, (r - half) * BlastGrid.CELL_SIZE)
