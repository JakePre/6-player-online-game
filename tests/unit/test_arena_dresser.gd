extends GutTest
## ArenaDresser (#948): the arena-dressing logic extracted from MinigameView3D
## — the tiled floor and the rim-prop ring. Tested directly against a bare
## arena node so the seam is verifiable without standing up a whole view.

const PLATFORM_SCENE := preload("res://assets/environment/kenney_platformer_kit/platform.glb")
const GRASS_SCENE := preload("res://assets/environment/kenney_platformer_kit/block-grass.glb")


func _arena() -> Node3D:
	var arena := Node3D.new()
	add_child_autofree(arena)
	return arena


## A trivial packed Node3D so the scatter tests don't depend on a kit mesh.
func _stub_prop() -> PackedScene:
	var root := Node3D.new()
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed


func _tile_mesh(scene: PackedScene) -> Mesh:
	var tile := scene.instantiate()
	var mesh := (tile.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	tile.free()
	return mesh


# --- build_floor -------------------------------------------------------------


func test_build_floor_adds_a_tinted_floor_node() -> void:
	var arena := _arena()
	var dresser := ArenaDresser.new(arena)
	var floor_node := dresser.build_floor(PLATFORM_SCENE, Color.WHITE, 8.0)
	assert_eq(floor_node.name, "Floor", "the floor node is named Floor")
	assert_eq(floor_node.get_parent(), arena, "parented to the arena")
	assert_gt(floor_node.multimesh.instance_count, 0, "tiles the play area")
	assert_true(floor_node.material_override is StandardMaterial3D, "a per-view material override")


func test_floor_material_is_a_duplicate_so_a_tint_never_bleeds() -> void:
	var a := ArenaDresser.new(_arena()).build_floor(PLATFORM_SCENE, Color.RED, 6.0)
	var b := ArenaDresser.new(_arena()).build_floor(PLATFORM_SCENE, Color.BLUE, 6.0)
	assert_ne(a.material_override, b.material_override, "each floor owns its material")


func test_mesh_top_measures_each_tile_thickness() -> void:
	# The thin platform vs the full grass block — very different tops, so the
	# per-mesh measure is what seats both flush at y=0 (build_floor negates it).
	assert_almost_eq(
		ArenaDresser._mesh_top(_tile_mesh(PLATFORM_SCENE)), 0.195, 0.01, "thin platform"
	)
	assert_almost_eq(ArenaDresser._mesh_top(_tile_mesh(GRASS_SCENE)), 1.0, 0.01, "full grass block")


# --- scatter_rim_props -------------------------------------------------------


func test_scatter_places_the_requested_count_under_a_container() -> void:
	var arena := _arena()
	var container := ArenaDresser.new(arena).scatter_rim_props([_stub_prop()], 12, 1, 8.0)
	assert_eq(container.name, "RimProps")
	assert_eq(container.get_parent(), arena, "hangs off the arena root")
	assert_eq(container.get_child_count(), 12, "one node per requested prop")


func test_scattered_props_sit_on_the_ground_outside_the_play_area() -> void:
	var half := 8.0
	var container := ArenaDresser.new(_arena()).scatter_rim_props([_stub_prop()], 16, 5, half)
	for prop: Node3D in container.get_children():
		assert_almost_eq(prop.position.y, 0.0, 0.001, "ground-seated")
		var ground := Vector2(prop.position.x, prop.position.z).length()
		assert_gte(ground, half, "past the play-area edge")


func test_scatter_is_deterministic_for_a_seed() -> void:
	var scenes: Array[PackedScene] = [_stub_prop()]
	var a := ArenaDresser.new(_arena()).scatter_rim_props(scenes, 8, 42, 8.0)
	var b := ArenaDresser.new(_arena()).scatter_rim_props(scenes, 8, 42, 8.0)
	var c := ArenaDresser.new(_arena()).scatter_rim_props(scenes, 8, 99, 8.0)
	assert_eq((a.get_child(0) as Node3D).position, (b.get_child(0) as Node3D).position, "same seed")
	assert_ne((a.get_child(0) as Node3D).position, (c.get_child(0) as Node3D).position, "diff seed")


func test_scatter_tolerates_empty_inputs() -> void:
	var dresser := ArenaDresser.new(_arena())
	assert_eq(dresser.scatter_rim_props([], 10, 0, 8.0).get_child_count(), 0, "no scenes")
	assert_eq(
		dresser.scatter_rim_props([_stub_prop()], 0, 0, 8.0).get_child_count(), 0, "zero count"
	)
