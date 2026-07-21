extends MinigameView3D
## Wall Builders client view (M10-10): stacked wall rows at each end, floor
## blocks in the contested middle, carriers glow with a block overhead.
##
## GFX enhancements (#1162): crate-face floor texture, construction-site
## scaffolding at corners, center crane, hard hats on carriers, blueprint
## tables, brick piles, rim props, and a warm construction mood.

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

# --- Construction-site dressing (#1162) ---------------------------------------

## Crate-face floor texture (IMG-059): tiled over the arena floor for a
## construction-site feel. Landed and named for Wall Builders.
const CRATE_FACE_TEXTURE := preload("res://assets/generated/textures/crate-face.png")
const FLOOR_TEXTURE_TILES := 4.0
## Scaffolding beam dimensions (BoxMesh).
const SCAFFOLD_POST_H := 4.0
const SCAFFOLD_POST_W := 0.15
const SCAFFOLD_BEAM_L := 3.0
const SCAFFOLD_BEAM_W := 0.12
## Center crane dimensions.
const CRANE_POLE_H := 5.0
const CRANE_POLE_RADIUS := 0.15
const CRANE_BOOM_L := 4.0
const CRANE_BOOM_W := 0.12
const CRANE_HOOK_H := 0.3
const CRANE_HOOK_RADIUS := 0.08
const CRANE_HOOK_RING_RADIUS := 0.2
const CRANE_HOOK_TUBE := 0.04
## Hard hat: a half-sphere on the head bone.
const HARD_HAT_RADIUS := 0.25
const HARD_HAT_HEIGHT := 0.2
## Blueprint table.
const TABLE_W := 1.2
const TABLE_D := 0.8
const TABLE_H := 0.7
const TABLE_LEG_W := 0.06
const BLUEPRINT_SIZE := Vector2(0.9, 0.6)
## Brick pile count and size.
const BRICK_W := 0.15
const BRICK_H := 0.06
const BRICK_D := 0.1
const BRICK_PILE_COUNT := 8
## Construction-theme rim props (#1162): barrels, crates, and ladders from the
## Kenney platformer kit, scattered around the arena perimeter.
const RIM_PROP_SCENES: Array[PackedScene] = [
	preload("res://assets/environment/kenney_platformer_kit/barrel.glb"),
	preload("res://assets/environment/kenney_platformer_kit/crate.glb"),
	preload("res://assets/environment/kenney_platformer_kit/crate-strong.glb"),
	preload("res://assets/environment/kenney_platformer_kit/ladder.glb"),
]
const RIM_PROP_COUNT := 14
const RIM_PROP_SEED := 0x1162

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

## Hard hat nodes per slot (#1162).
var _hard_hats := {}


func _physics_process(_delta: float) -> void:
	send_move_intent()


## Warm construction-wood floor (#589).
func _floor_tint() -> Color:
	return Color(1.0, 0.92, 0.78)


## Dark warm mood for the construction-site backdrop (#1162).
func _mood() -> Color:
	return Color(0.18, 0.14, 0.09).lerp(Color(0.35, 0.28, 0.16), 0.3)


func _arena_half() -> float:
	return WallBuilders.ARENA_HALF + 1.0


## Crate-face floor (#1162): PlaneMesh with the IMG-059 texture replacing the
## default tile floor, tiled for a construction-yard look.
func _build_floor() -> void:
	var half := _arena_half()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(half * 2.0, half * 2.0)
	var material := StandardMaterial3D.new()
	material.albedo_texture = CRATE_FACE_TEXTURE
	material.albedo_color = Color(1.0, 0.92, 0.78)
	material.uv1_scale = Vector3(FLOOR_TEXTURE_TILES, FLOOR_TEXTURE_TILES, 1.0)
	material.metallic = 0.0
	material.roughness = 0.9
	mesh.material = material
	var floor_node := MeshInstance3D.new()
	floor_node.name = "CrateFloor"
	floor_node.mesh = mesh
	floor_node.position.y = -0.01
	arena.add_child(floor_node)


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
		# Blueprint table and brick pile near each team's home zone (#1162).
		_build_blueprint_table(team_index, side)
		_build_brick_pile(team_index, side)
	for slot: int in names:
		var marker := _make_crate(Color.WHITE)
		marker.scale *= 0.7
		marker.visible = false
		arena.add_child(marker)
		_carry_markers[slot] = marker
		# Hard hat pool: one dome per slot, hidden initially (#1162).
		var hat := _make_hard_hat(slot)
		_hard_hats[slot] = hat
	# Construction-site dressing (#1162).
	_build_scaffolding()
	_build_crane()
	scatter_rim_props(RIM_PROP_SCENES, RIM_PROP_COUNT, RIM_PROP_SEED)


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


# --- Construction-site dressing (#1162) ---------------------------------------


## Scaffolding at the four arena corners: vertical posts with cross beams.
func _build_scaffolding() -> void:
	var half := _arena_half() - 1.0
	var corners := [
		Vector2(-half, -half),
		Vector2(-half, half),
		Vector2(half, -half),
		Vector2(half, half),
	]
	for corner: Vector2 in corners:
		var scaffold := Node3D.new()
		scaffold.name = "Scaffold_%.0f_%.0f" % [corner.x, corner.y]
		# Vertical posts (front-left, back-right)
		for offset: Vector2 in [Vector2(-0.3, -0.3), Vector2(0.3, 0.3)]:
			var post := _make_scaffold_mesh(
				Vector3(SCAFFOLD_POST_W, SCAFFOLD_POST_H, SCAFFOLD_POST_W), Color(0.85, 0.75, 0.25)
			)
			post.position = Vector3(corner.x + offset.x, SCAFFOLD_POST_H / 2.0, corner.y + offset.y)
			scaffold.add_child(post)
		# Horizontal cross beam at top (x-direction)
		var beam1 := _make_scaffold_mesh(
			Vector3(SCAFFOLD_BEAM_L, SCAFFOLD_BEAM_W, SCAFFOLD_BEAM_W), Color(0.8, 0.7, 0.2)
		)
		beam1.position = Vector3(corner.x, SCAFFOLD_POST_H - 0.2, corner.y)
		scaffold.add_child(beam1)
		# Horizontal cross beam at top (z-direction)
		var beam2 := _make_scaffold_mesh(
			Vector3(SCAFFOLD_BEAM_W, SCAFFOLD_BEAM_W, SCAFFOLD_BEAM_L), Color(0.8, 0.7, 0.2)
		)
		beam2.position = Vector3(corner.x, SCAFFOLD_POST_H - 0.2, corner.y)
		scaffold.add_child(beam2)
		arena.add_child(scaffold)


## A simple BoxMesh with a solid color — reusable scaffold/crane part.
func _make_scaffold_mesh(size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.3
	material.roughness = 0.6
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	return node


## Center crane: tall pole with a horizontal boom and a dangling hook.
func _build_crane() -> void:
	var crane := Node3D.new()
	crane.name = "Crane"
	# Pole
	var pole := _make_scaffold_mesh(
		Vector3(CRANE_POLE_RADIUS * 2.0, CRANE_POLE_H, CRANE_POLE_RADIUS * 2.0),
		Color(0.8, 0.7, 0.2)
	)
	pole.position.y = CRANE_POLE_H / 2.0
	crane.add_child(pole)
	# Boom (horizontal arm)
	var boom := _make_scaffold_mesh(
		Vector3(CRANE_BOOM_L, CRANE_BOOM_W, CRANE_BOOM_W), Color(0.85, 0.75, 0.25)
	)
	boom.position = Vector3(CRANE_BOOM_L / 2.0 - 0.3, CRANE_POLE_H - 0.2, 0.0)
	crane.add_child(boom)
	# Hook cable (thin cylinder)
	var cable := CylinderMesh.new()
	cable.top_radius = 0.02
	cable.bottom_radius = 0.02
	cable.height = CRANE_HOOK_H
	var cable_material := StandardMaterial3D.new()
	cable_material.albedo_color = Color(0.4, 0.4, 0.4)
	cable.material = cable_material
	var cable_node := MeshInstance3D.new()
	cable_node.mesh = cable
	cable_node.position = Vector3(CRANE_BOOM_L - 0.3, CRANE_POLE_H - CRANE_HOOK_H / 2.0, 0.0)
	crane.add_child(cable_node)
	# Hook ring (torus)
	var ring := TorusMesh.new()
	ring.inner_radius = CRANE_HOOK_RING_RADIUS - CRANE_HOOK_TUBE
	ring.outer_radius = CRANE_HOOK_RING_RADIUS
	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = Color(0.3, 0.3, 0.35)
	ring_material.metallic = 0.5
	ring_material.roughness = 0.4
	ring.material = ring_material
	var ring_node := MeshInstance3D.new()
	ring_node.mesh = ring
	ring_node.position = Vector3(CRANE_BOOM_L - 0.3, CRANE_POLE_H - CRANE_HOOK_H - 0.05, 0.0)
	crane.add_child(ring_node)
	arena.add_child(crane)


## Hard hat for a slot: a colored dome on the rig's head (#1162).
func _make_hard_hat(slot: int) -> Node3D:
	var color := player_color(slot)
	var mesh := SphereMesh.new()
	mesh.radius = HARD_HAT_RADIUS
	mesh.height = HARD_HAT_HEIGHT
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.2
	material.roughness = 0.7
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	var hat := MeshInstance3D.new()
	hat.name = "HardHat_%d" % slot
	hat.mesh = mesh
	hat.visible = false
	return hat


## Blueprint table near a team's home zone (#1162): a simple table with a
## glowing blue blueprint on top.
func _build_blueprint_table(team_index: int, side: float) -> void:
	var table := Node3D.new()
	table.name = "BlueprintTable%d" % team_index
	# Table top
	var top := BoxMesh.new()
	top.size = Vector3(TABLE_W, 0.06, TABLE_D)
	var top_material := StandardMaterial3D.new()
	top_material.albedo_color = Color(0.5, 0.35, 0.2)
	top_material.metallic = 0.1
	top_material.roughness = 0.8
	top.material = top_material
	var top_node := MeshInstance3D.new()
	top_node.mesh = top
	top_node.position.y = TABLE_H
	table.add_child(top_node)
	# Legs
	for leg_offset: Vector2 in [
		Vector2(-0.4, -0.3),
		Vector2(0.4, 0.3),
		Vector2(-0.4, 0.3),
		Vector2(0.4, -0.3),
	]:
		var leg := BoxMesh.new()
		leg.size = Vector3(TABLE_LEG_W, TABLE_H, TABLE_LEG_W)
		var leg_material := StandardMaterial3D.new()
		leg_material.albedo_color = Color(0.4, 0.3, 0.2)
		leg.material = leg_material
		var leg_node := MeshInstance3D.new()
		leg_node.mesh = leg
		leg_node.position = Vector3(leg_offset.x, TABLE_H / 2.0, leg_offset.y)
		table.add_child(leg_node)
	# Blueprint: emissive blue plane on top
	var bp_mesh := PlaneMesh.new()
	bp_mesh.size = BLUEPRINT_SIZE
	var bp_material := StandardMaterial3D.new()
	bp_material.albedo_color = Color(0.15, 0.3, 0.7)
	bp_material.emission_enabled = true
	bp_material.emission = Color(0.15, 0.3, 0.7)
	bp_material.emission_energy_multiplier = 0.6
	bp_material.metallic = 0.0
	bp_material.roughness = 0.5
	bp_mesh.material = bp_material
	var bp_node := MeshInstance3D.new()
	bp_node.mesh = bp_mesh
	bp_node.position = Vector3(0.0, TABLE_H + 0.04, 0.0)
	bp_node.rotation.x = -PI / 2.0
	table.add_child(bp_node)
	# Position behind the team's wall
	var home_x := side * (WallBuilders.WALL_X + 1.2)
	table.position = to_arena(Vector2(home_x, -1.5))
	arena.add_child(table)


## A pile of loose bricks near a team's home zone (#1162).
func _build_brick_pile(team_index: int, side: float) -> void:
	var pile := Node3D.new()
	pile.name = "BrickPile%d" % team_index
	pile.position = to_arena(Vector2(side * (WallBuilders.WALL_X + 1.2), 2.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xB17 + team_index
	for i in BRICK_PILE_COUNT:
		var brick := BoxMesh.new()
		brick.size = Vector3(BRICK_W, BRICK_H, BRICK_D)
		var material := StandardMaterial3D.new()
		# Alternate brick tones
		material.albedo_color = Color(
			0.55 + rng.randf() * 0.15, 0.3 + rng.randf() * 0.1, 0.15 + rng.randf() * 0.05
		)
		brick.material = material
		var brick_node := MeshInstance3D.new()
		brick_node.mesh = brick
		# Scatter bricks in a small pile
		brick_node.position = Vector3(
			rng.randf_range(-0.3, 0.3),
			BRICK_H / 2.0 + rng.randf() * 0.1,
			rng.randf_range(-0.3, 0.3)
		)
		brick_node.rotation = Vector3(rng.randf() * 0.5, rng.randf() * TAU, rng.randf() * 0.5)
		pile.add_child(brick_node)
	arena.add_child(pile)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	blocks = game.get("blocks", [])
	walls = game.get("walls", [0, 0])
	teams = game.get("teams", [])
	for i in _floor_pool.size():
		var node := _floor_pool[i]
		if i < blocks.size():
			var block: Array = blocks[i]
			# Crate pivot is at its base, so floor blocks sit at height 0.
			node.position = to_arena(
				Vector2(float(block[WallBuilders.BL_X]), float(block[WallBuilders.BL_Y])), 0.0
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
		# Hard hat on carrying players (#1162).
		var hat: Node3D = _hard_hats.get(slot)
		if hat != null:
			if carrying and not hat.visible:
				hat.visible = true
				# Parent to the rig so it follows head motion.
				if hat.get_parent() != rig:
					if hat.get_parent() != null:
						hat.get_parent().remove_child(hat)
					rig.add_child(hat)
				hat.position = Vector3(0.0, 1.5, 0.0)
			elif not carrying and hat.visible:
				hat.visible = false
		rig.display_name = player_name(slot) + ("  🧱" if carrying else "")
		if slot == my_slot and carrying and not bool(_carrying_seen.get(slot, false)):
			# Picking up a floor block isn't currency (#728).
			play_sfx(&"pop")
		_carrying_seen[slot] = carrying
