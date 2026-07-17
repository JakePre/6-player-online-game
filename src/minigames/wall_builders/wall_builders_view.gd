extends MinigameView3D
## Wall Builders client view (M10-10): stacked wall rows at each end, floor
## blocks in the contested middle, carriers glow with a block overhead.

const WALL_COLORS: Array[Color] = [Color(0.85, 0.45, 0.3), Color(0.35, 0.55, 0.85)]
const BLOCK_SIZE := 0.7
## Blocks are the landed MDL-018 wooden crate (#817 — Wall Builders is a named
## consumer): natural pine on the floor, tinted to the team color in walls.
## The GLB is 1 x 0.728 x 1 with a base pivot — stretched to a BLOCK_SIZE cube.
const CRATE_SCENE := preload("res://assets/generated/models/wooden-crate.glb")
const CRATE_GLB_HEIGHT := 0.728
const WALL_WIDTH := 4.0
const ROW_BLOCKS := 5
## Home-zone marker (#807): a floor decal the size of the actual delivery
## radius, plus a beacon tall enough to stay visible over a near-full wall —
## an empty wall (height 0) is otherwise invisible, so nothing shows a
## first-time player where to haul blocks.
const BEACON_HEIGHT := 6.0
const BEACON_RADIUS := 0.1

## Latest replicated state, straight from WallBuilders.get_snapshot().
var players := {}
var blocks: Array = []
var walls: Array = [0, 0]
var teams: Array = []

var _floor_pool: Array[Node3D] = []
var _wall_pools := {}
var _carry_markers := {}
var _carrying_seen := {}
var _walls_seen: Array = [0, 0]


func _physics_process(_delta: float) -> void:
	send_move_intent()


## Warm construction-wood floor (#589).
func _floor_tint() -> Color:
	return Color(1.0, 0.92, 0.78)


func _arena_half() -> float:
	return WallBuilders.ARENA_HALF + 1.0


func _setup_3d() -> void:
	for i in WallBuilders.MAX_FLOOR_BLOCKS + 4:
		var node := _make_crate(Color.WHITE)
		node.visible = false
		arena.add_child(node)
		_floor_pool.append(node)
	for team_index in 2:
		var side := -1.0 if team_index == 0 else 1.0
		_build_home_marker(team_index, side)
		var pool: Array[Node3D] = []
		# Pool tall enough for this lobby's scaled target (#961), plus headroom
		# for blocks pried above it — the win target now scales with team size.
		var pool_size := WallBuilders.WIN_PER_BUILDER * maxi(1, names.size() / 2) + 4
		for i in pool_size:
			var node := _make_crate(WALL_COLORS[team_index])
			node.visible = false
			var row := i / ROW_BLOCKS
			var col := i % ROW_BLOCKS
			# Base pivot: rows stack from the floor.
			node.position = Vector3(
				side * WallBuilders.WALL_X,
				row * BLOCK_SIZE,
				(col - ROW_BLOCKS / 2.0) * BLOCK_SIZE * 1.05
			)
			arena.add_child(node)
			pool.append(node)
		_wall_pools[team_index] = pool
	for slot: int in names:
		var marker := _make_crate(Color.WHITE)
		marker.scale *= 0.7
		marker.visible = false
		arena.add_child(marker)
		_carry_markers[slot] = marker


## A crate instance stretched to a BLOCK_SIZE cube; tint multiplies the pine
## albedo (team walls stay team-readable, Color.WHITE keeps it natural).
func _make_crate(tint: Color) -> Node3D:
	var crate := CRATE_SCENE.instantiate() as Node3D
	crate.scale = Vector3(BLOCK_SIZE, BLOCK_SIZE / CRATE_GLB_HEIGHT, BLOCK_SIZE)
	if tint != Color.WHITE:
		for found in crate.find_children("*", "MeshInstance3D", true, false):
			var mesh_node := found as MeshInstance3D
			for surface in mesh_node.mesh.get_surface_count():
				var mat := mesh_node.get_active_material(surface)
				if mat is StandardMaterial3D:
					var tinted: StandardMaterial3D = mat.duplicate()
					tinted.albedo_color = tint
					mesh_node.set_surface_override_material(surface, tinted)
	return crate


## A team-colored floor decal at the actual delivery radius, plus a beacon
## tall enough to read over a near-full wall (#807) — an empty wall gives no
## clue where home is otherwise.
func _build_home_marker(team_index: int, side: float) -> void:
	var pos := Vector2(side * WallBuilders.WALL_X, 0.0)
	var color := WALL_COLORS[team_index]

	var decal_mesh := CylinderMesh.new()
	decal_mesh.top_radius = WallBuilders.WALL_REACH
	decal_mesh.bottom_radius = WallBuilders.WALL_REACH
	decal_mesh.height = 0.08
	var decal_material := StandardMaterial3D.new()
	decal_material.albedo_color = color
	decal_material.emission_enabled = true
	decal_material.emission = color
	decal_material.emission_energy_multiplier = 0.4
	decal_mesh.material = decal_material
	var decal := MeshInstance3D.new()
	decal.name = "HomeZone%d" % team_index
	decal.mesh = decal_mesh
	decal.position = to_arena(pos, 0.04)
	arena.add_child(decal)

	var beacon_mesh := CylinderMesh.new()
	beacon_mesh.top_radius = BEACON_RADIUS
	beacon_mesh.bottom_radius = BEACON_RADIUS * 1.5
	beacon_mesh.height = BEACON_HEIGHT
	var beacon_material := StandardMaterial3D.new()
	beacon_material.albedo_color = color
	beacon_material.emission_enabled = true
	beacon_material.emission = color
	beacon_material.emission_energy_multiplier = 0.7
	beacon_mesh.material = beacon_material
	var beacon := MeshInstance3D.new()
	beacon.name = "HomeBeacon%d" % team_index
	beacon.mesh = beacon_mesh
	beacon.position = to_arena(pos, BEACON_HEIGHT / 2.0)
	arena.add_child(beacon)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	blocks = game.get("blocks", [])
	walls = game.get("walls", [0, 0])
	teams = game.get("teams", [])
	for i in _floor_pool.size():
		var node := _floor_pool[i]
		if i < blocks.size():
			var block: Array = blocks[i]
			node.position = to_arena(
				Vector2(float(block[WallBuilders.BL_X]), float(block[WallBuilders.BL_Y])),
				0.0  # crate pivot is at its base
			)
			node.visible = true
		else:
			node.visible = false
	for team_index in 2:
		var pool: Array = _wall_pools[team_index]
		var height := int(walls[team_index]) if walls.size() > team_index else 0
		for i in pool.size():
			(pool[i] as Node3D).visible = i < height
		# Your own team's wall rising a row pays off (M12-02).
		if height > int(_walls_seen[team_index]) and team_index < teams.size():
			if my_slot in (teams[team_index] as Array):
				# The delivery cue (#728, docs/AUDIO_GUIDE.md — Team objects).
				play_sfx(&"bell")
		_walls_seen[team_index] = height
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		update_rig(slot, Vector2(state[WallBuilders.PS_X], state[WallBuilders.PS_Y]))
		var carrying := int(state[WallBuilders.PS_CARRYING]) == 1
		var marker: Node3D = _carry_markers.get(slot)
		if marker != null:
			marker.visible = carrying
			if carrying:
				marker.position = to_arena(
					Vector2(state[WallBuilders.PS_X], state[WallBuilders.PS_Y]), 2.4
				)
		rig.display_name = player_name(slot) + ("  🧱" if carrying else "")
		if slot == my_slot and carrying and not bool(_carrying_seen.get(slot, false)):
			# Picking up a floor block isn't currency (#728).
			play_sfx(&"pop")
		_carrying_seen[slot] = carrying
