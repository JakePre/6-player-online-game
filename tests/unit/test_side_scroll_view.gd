extends GutTest
## SideScrollView (M14-00): the 2D presentation base draws the sim's stage,
## manages palette-colored rigs with nameplates, flips y-up world space to
## screen, and interpolates snapshots (M12-04 pattern, world-space samples).

var view: SideScrollView


func before_each() -> void:
	view = SideScrollView.new()
	add_child_autofree(view)
	view.size = Vector2(800.0, 450.0)
	view.setup({0: "Alice", 1: "Bob"}, 0)
	view.setup_stage(
		[Rect2(-10.0, -1.0, 20.0, 1.0)] as Array[Rect2],
		[Rect2(-2.0, 2.0, 4.0, 0.5)] as Array[Rect2],
		Rect2(-12.0, -6.0, 24.0, 18.0)
	)


func test_stage_builds_one_panel_per_platform() -> void:
	assert_eq(view._platform_nodes.size(), 2, "solids + one-way lids each get a panel")
	assert_gt(view._platform_nodes[0].size.x, 0.0, "laid out to screen size")


func test_world_to_screen_flips_y_and_centers() -> void:
	var low := view.world_to_screen(Vector2(0.0, 0.0))
	var high := view.world_to_screen(Vector2(0.0, 5.0))
	assert_lt(high.y, low.y, "higher world y is higher on screen")
	assert_almost_eq(low.x, view.size.x / 2.0, 0.001, "world x=0 is horizontally centered")


func test_render_builds_palette_rigs_with_nameplates() -> void:
	view.render_side_scroll({0: [0.0, 0.5, 1, 1], 1: [2.0, 0.5, -1, 1]})
	var rig := view.rig_for_slot(0)
	assert_not_null(rig)
	var plate: Label = rig.get_node("Plate")
	assert_eq(plate.text, "Alice")
	assert_eq(plate.get_theme_color(&"font_color"), PlayerPalette.color_for_slot(0))
	assert_not_null(view.rig_for_slot(1))


func test_facing_leans_the_eye() -> void:
	view.render_side_scroll({0: [0.0, 0.5, 1, 1]})
	var eye: Panel = view.rig_for_slot(0).get_node("Eye")
	var right_x := eye.position.x
	view.render_side_scroll({0: [0.0, 0.5, -1, 1]})
	assert_lt(eye.position.x, right_x, "facing left moves the eye left")


func test_first_sample_snaps_then_later_samples_interpolate() -> void:
	view.render_side_scroll({0: [1.0, 0.5, 1, 1]})
	var first: Dictionary = view._samples[0]
	assert_eq(first.from, first.to, "first sighting snaps in place")
	view.render_side_scroll({0: [1.5, 0.5, 1, 1]})
	var second: Dictionary = view._samples[0]
	assert_eq(second.to, Vector2(1.5, 0.5))
	assert_ne(second.from, second.to, "later samples slide from the current pose")


func test_teleport_sized_jumps_snap_instead_of_sliding() -> void:
	view.render_side_scroll({0: [0.0, 0.5, 1, 1]})
	view.render_side_scroll({0: [9.0, 0.5, 1, 1]})
	var sample: Dictionary = view._samples[0]
	assert_eq(sample.from, sample.to, "a respawn-sized jump snaps")


func test_sample_position_lerps_by_elapsed_time() -> void:
	var sample := {"from": Vector2.ZERO, "to": Vector2(2.0, 0.0), "at": 0.0, "interval": 1.0}
	assert_almost_eq(view._sample_position(sample, 0.5).x, 1.0, 0.001, "midway at half time")
	assert_almost_eq(view._sample_position(sample, 2.0).x, 2.0, 0.001, "clamps at the target")


func test_render_tolerates_missing_and_short_data() -> void:
	view.render_side_scroll({})
	view.render_side_scroll({0: [1.0]})
	assert_null(view.rig_for_slot(0), "short samples are ignored")
