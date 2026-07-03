extends GutTest
## Snapshot interpolation (M12-04): 30 Hz snapshot positions become per-slot
## samples that an internal-process pass slides between every frame. Driven
## here with explicit clocks so nothing depends on wall time.

var view: MinigameView


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/king_of_the_hill/king_of_the_hill_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice"}, 0)


func _render_at(pos: Vector2) -> void:
	view.render({"players": {0: [pos.x, pos.y, 0]}, "zone": []})


func test_first_sample_snaps_the_rig_in_place() -> void:
	_render_at(Vector2(3.0, -2.0))
	var rig: CharacterRig = view.rig_for_slot(0)
	assert_almost_eq(rig.position.x, 3.0, 0.001)
	assert_almost_eq(rig.position.z, -2.0, 0.001)


func test_next_sample_slides_instead_of_popping() -> void:
	_render_at(Vector2(0.0, 0.0))
	_render_at(Vector2(1.0, 0.0))
	var rig: CharacterRig = view.rig_for_slot(0)
	assert_almost_eq(rig.position.x, 0.0, 0.001, "no pop at sample arrival")
	var sample: Dictionary = view._rig_samples[0]
	view._interpolate_rigs(float(sample.at) + float(sample.interval) * 0.5)
	assert_almost_eq(rig.position.x, 0.5, 0.001, "halfway through the interval")
	view._interpolate_rigs(float(sample.at) + float(sample.interval))
	assert_almost_eq(rig.position.x, 1.0, 0.001, "arrived at the snapshot position")


func test_interpolation_clamps_at_the_target() -> void:
	_render_at(Vector2(0.0, 0.0))
	_render_at(Vector2(1.0, 2.0))
	var sample: Dictionary = view._rig_samples[0]
	view._interpolate_rigs(float(sample.at) + float(sample.interval) * 10.0)
	var rig: CharacterRig = view.rig_for_slot(0)
	assert_almost_eq(rig.position.x, 1.0, 0.001, "never overshoots when snapshots stall")
	assert_almost_eq(rig.position.z, 2.0, 0.001)


func test_teleport_sized_jumps_snap() -> void:
	_render_at(Vector2(0.0, 0.0))
	_render_at(Vector2(8.0, 0.0))
	var rig: CharacterRig = view.rig_for_slot(0)
	assert_almost_eq(rig.position.x, 8.0, 0.001, "respawn-scale jumps do not slide")


func test_hidden_rigs_are_left_alone() -> void:
	_render_at(Vector2(0.0, 0.0))
	_render_at(Vector2(1.0, 0.0))
	var rig: CharacterRig = view.rig_for_slot(0)
	rig.visible = false
	rig.position = Vector3(9.0, 0.0, 9.0)
	var sample: Dictionary = view._rig_samples[0]
	view._interpolate_rigs(float(sample.at) + float(sample.interval))
	assert_almost_eq(rig.position.x, 9.0, 0.001, "eliminated rigs keep their pose position")
