class_name ArenaDresser
extends RefCounted
## Arena-dressing helper for MinigameView3D (#948): builds the tiled floor and
## scatters decorative rim props under a view's `arena`. Extracted from
## MinigameView3D so the repo's most-touched view base stops accreting every
## dressing feature in one class — the #939 stage-shell backdrop lands here
## next, composed the same way.
##
## Pure dressing: the view keeps its game-specific override hooks
## (`_floor_tile_scene`/`_floor_tint`/`_arena_half`) and passes their results
## in as parameters, so this helper never needs to know about a particular
## game and the per-game override contract is unchanged.

## Floor tiles are 1×1 world units; a game's tile mesh (thin platform or full
## block) is seated by its own top surface, so any thickness sits flush.
const FLOOR_TILE_SIZE := 1.0
## Rim props ring the play area in this band of `arena_half` (just past the
## edge, inside the camera frame), with per-prop angle/scale jitter.
const RIM_PROP_INNER := 1.1
const RIM_PROP_OUTER := 1.28
const RIM_PROP_ANGLE_JITTER := 0.22
const RIM_PROP_SCALE_MIN := 0.8
const RIM_PROP_SCALE_MAX := 1.2

var _arena: Node3D


func _init(arena: Node3D) -> void:
	_arena = arena


## Builds the tiled floor MultiMesh under the arena (#813): one tile mesh from
## `tile_scene`, seated so its top surface sits at y=0 whatever its thickness,
## tiled to cover a `2*arena_half` square, tinted by multiplying `tint` into a
## per-view duplicate of the tile's native material. Returns the "Floor" node,
## or null if the tile scene carries no mesh.
func build_floor(tile_scene: PackedScene, tint: Color, arena_half: float) -> MultiMeshInstance3D:
	var tile := tile_scene.instantiate()
	var tile_meshes := tile.find_children("*", "MeshInstance3D", true, false)
	var mesh_instance := tile_meshes[0] as MeshInstance3D if not tile_meshes.is_empty() else null
	var mesh: Mesh = mesh_instance.mesh if mesh_instance != null else null
	var base_material: Material = (
		mesh_instance.get_active_material(0) if mesh_instance != null else null
	)
	# Seat the tile's top surface at y=0 whatever its thickness (#813): the thin
	# `platform.glb` (~0.195) and the full `block-grass`/`block-snow` blocks
	# (~1.0) both sit flush, so a game can swap the mesh with no per-game offset.
	# The top comes from the mesh's own vertices (not get_aabb(), which reads 0
	# until the RenderingServer has drawn the mesh — hence the old hardcoded
	# offset); the multimesh renders this same mesh, so its extent is exact.
	# Measured before freeing the tile — a freed node's mesh reads no surfaces.
	var top := _mesh_top(mesh) if mesh != null else 0.0
	tile.free()
	if mesh == null:
		return null

	var tiles_per_side := int(ceil(arena_half * 2.0 / FLOOR_TILE_SIZE))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = tiles_per_side * tiles_per_side

	var start := -arena_half + FLOOR_TILE_SIZE * 0.5
	var i := 0
	for x in tiles_per_side:
		for z in tiles_per_side:
			var pos := Vector3(start + x * FLOOR_TILE_SIZE, -top, start + z * FLOOR_TILE_SIZE)
			multimesh.set_instance_transform(i, Transform3D(Basis(), pos))
			i += 1

	var floor_node := MultiMeshInstance3D.new()
	floor_node.name = "Floor"
	floor_node.multimesh = multimesh
	floor_node.material_override = _floor_material(base_material, tint)
	_arena.add_child(floor_node)
	return floor_node


## Scatters `count` non-interactive scenery props (#813) in a ring just outside
## the `arena_half` play area — ground-seated (base at y=0), spread evenly with
## per-slot angle jitter at a radius in [RIM_PROP_INNER, RIM_PROP_OUTER] ×
## arena_half, each with a random yaw and gentle scale jitter so a repeated mesh
## doesn't read as a stamped pattern. Seeded off `prop_seed` so the layout is
## stable frame-to-frame and reproducible. Returns the container ("RimProps").
func scatter_rim_props(
	scenes: Array[PackedScene], count: int, prop_seed: int, arena_half: float
) -> Node3D:
	var container := Node3D.new()
	container.name = "RimProps"
	_arena.add_child(container)
	if scenes.is_empty() or count <= 0:
		return container
	var rng := RandomNumberGenerator.new()
	rng.seed = prop_seed
	for i in count:
		var scene := scenes[rng.randi() % scenes.size()]
		var prop := scene.instantiate() as Node3D
		if prop == null:
			continue
		var angle := (
			TAU * float(i) / float(count)
			+ rng.randf_range(-RIM_PROP_ANGLE_JITTER, RIM_PROP_ANGLE_JITTER)
		)
		var radius := arena_half * rng.randf_range(RIM_PROP_INNER, RIM_PROP_OUTER)
		var ground := Vector2(cos(angle), sin(angle)) * radius
		prop.position = Vector3(ground.x, 0.0, ground.y)
		prop.rotation.y = rng.randf() * TAU
		var jitter := rng.randf_range(RIM_PROP_SCALE_MIN, RIM_PROP_SCALE_MAX)
		prop.scale = Vector3(jitter, jitter, jitter)
		container.add_child(prop)
	return container


## The highest vertex Y across a mesh's surfaces — its top surface in local
## space (#813). Read from vertex data so it is correct at setup, unlike
## Mesh.get_aabb() which returns an empty box until the mesh has been rendered.
static func _mesh_top(mesh: Mesh) -> float:
	var top := -INF
	for surface in mesh.get_surface_count():
		var verts: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for vertex: Vector3 in verts:
			top = maxf(top, vertex.y)
	return top if top != -INF else 0.0


## The floor's material, tinted per game (#589). Duplicates the native Kenney
## tile material so its texture/look is preserved, then multiplies in `tint`
## (white leaves it unchanged).
func _floor_material(base: Material, tint: Color) -> Material:
	var mat: StandardMaterial3D = (
		base.duplicate() if base is StandardMaterial3D else StandardMaterial3D.new()
	)
	mat.albedo_color = mat.albedo_color * tint
	return mat
