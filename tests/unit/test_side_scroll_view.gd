extends GutTest
## SideScrollView (M14-00): the 2D presentation base draws the sim's stage,
## manages palette-colored rigs with nameplates, flips y-up world space to
## screen, and interpolates snapshots (M12-04 pattern, world-space samples).

var view: SideScrollView
var _saved_show_names := false


func before_each() -> void:
	_saved_show_names = MinigameView.show_names
	view = SideScrollView.new()
	add_child_autofree(view)
	view.size = Vector2(800.0, 450.0)
	view.setup({0: "Alice", 1: "Bob"}, 0)
	view.setup_stage(
		[Rect2(-10.0, -1.0, 20.0, 1.0)] as Array[Rect2],
		[Rect2(-2.0, 2.0, 4.0, 0.5)] as Array[Rect2],
		Rect2(-12.0, -6.0, 24.0, 18.0)
	)


func after_each() -> void:
	MinigameView.show_names = _saved_show_names


func test_stage_builds_one_panel_per_platform() -> void:
	assert_eq(view._platform_nodes.size(), 2, "solids + one-way lids each get a panel")
	assert_gt(view._platform_nodes[0].size.x, 0.0, "laid out to screen size")


func test_world_to_screen_flips_y_and_centers() -> void:
	var low := view.world_to_screen(Vector2(0.0, 0.0))
	var high := view.world_to_screen(Vector2(0.0, 5.0))
	assert_lt(high.y, low.y, "higher world y is higher on screen")
	assert_almost_eq(low.x, view.size.x / 2.0, 0.001, "world x=0 is horizontally centered")


func test_render_builds_palette_rigs_with_nameplates() -> void:
	MinigameView.show_names = true
	view.render_side_scroll({0: [0.0, 0.5, 1, 1], 1: [2.0, 0.5, -1, 1]})
	var rig := view.rig_for_slot(0)
	assert_not_null(rig)
	var plate: Label = rig.get_node("Plate")
	assert_eq(plate.text, "P1 Alice")
	assert_eq(plate.get_theme_color(&"font_color"), PlayerPalette.color_for_slot(0))
	assert_not_null(view.rig_for_slot(1))


## #580: nameplates off by default — the plate shows just the number badge
## until show_names is switched on.
func test_plate_shows_number_badge_only_by_default() -> void:
	MinigameView.show_names = false
	view.render_side_scroll({0: [0.0, 0.5, 1, 1]})
	var plate: Label = view.rig_for_slot(0).get_node("Plate")
	assert_eq(plate.text, "P1", "off shows just the number badge")


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


## #925: the shared HUD helper offsets below the match chrome so the headline
## no longer clips under the bar.
func test_sidescroll_hud_clears_the_chrome() -> void:
	var hud := view.make_sidescroll_hud()
	assert_almost_eq(
		hud.position.y, MinigameView3D.CHROME_CLEARANCE_Y, 0.5, "HUD sits below the chrome bar"
	)
	assert_eq(hud.get_parent(), view, "mounted on the view, over the stage layers")


## #925: solid platforms wear the stone texture, jump-through lids wear wood,
## and each carries a bright standable top edge.
func test_platforms_are_textured_by_kind_with_a_top_edge() -> void:
	var solid := view._platform_nodes[0]
	var lid := view._platform_nodes[1]
	var solid_style := solid.get_theme_stylebox(&"panel") as StyleBoxTexture
	var lid_style := lid.get_theme_stylebox(&"panel") as StyleBoxTexture
	assert_eq(solid_style.texture, view.SOLID_TEXTURE, "solids wear stone")
	assert_eq(lid_style.texture, view.ONE_WAY_TEXTURE, "one-way lids wear wood")
	assert_not_null(solid.get_node("TopEdge"), "a walkable top edge")
	assert_gt((solid.get_node("TopEdge") as ColorRect).size.x, 0.0, "laid out to width")


## #925: the fighters are characters now — two eyes and four limbs, not a bare
## capsule. Body/Eye/Plate keep their names so the shared paths still work.
func test_rig_has_character_parts() -> void:
	view.render_side_scroll({0: [0.0, 0.5, 1, 1]})
	var rig := view.rig_for_slot(0)
	for part in ["Body", "Eye", "Eye2", "Plate", "LegL", "LegR", "ArmL", "ArmR"]:
		assert_not_null(rig.get_node(part), "rig has a %s" % part)


## #1038: the shared hit reaction flashes the rig, opens a pose-protection
## window, and throws a spark burst.
func test_play_hit_flashes_and_sparks_the_rig() -> void:
	view.render_side_scroll({0: [0.0, 0.5, 1, 1]})
	var rig := view.rig_for_slot(0)
	var before := view._rig_layer.get_child_count()
	view.play_hit(0)
	assert_ne(rig.modulate, Color.WHITE, "the flinch flashes the rig")
	assert_true(view.is_hit_playing(0), "the flinch window is open")
	assert_eq(
		view._rig_layer.get_child_count(), before + view.HIT_SPARK_COUNT, "a spark burst spawns"
	)


## #1038: no rig for the slot -> nothing happens.
func test_play_hit_is_a_noop_without_a_rig() -> void:
	view.play_hit(99)
	assert_false(view.is_hit_playing(99), "no rig means no flinch")


## #1038: reduced motion keeps the (static) flash but drops the flying sparks.
func test_play_hit_under_reduced_motion_flashes_without_sparks() -> void:
	var saved := ArenaFX.reduced_motion
	ArenaFX.reduced_motion = true
	view.render_side_scroll({0: [0.0, 0.5, 1, 1]})
	var before := view._rig_layer.get_child_count()
	view.play_hit(0)
	assert_ne(view.rig_for_slot(0).modulate, Color.WHITE, "the flash still fires")
	assert_eq(view._rig_layer.get_child_count(), before, "no flying sparks under reduced motion")
	ArenaFX.reduced_motion = saved


## #925: both eyes lean toward the facing direction.
func test_both_eyes_lean_with_facing() -> void:
	view.render_side_scroll({0: [0.0, 0.5, 1, 1]})
	var rig := view.rig_for_slot(0)
	var eye_right: float = (rig.get_node("Eye") as Panel).position.x
	var eye2_right: float = (rig.get_node("Eye2") as Panel).position.x
	view.render_side_scroll({0: [0.0, 0.5, -1, 1]})
	assert_lt((rig.get_node("Eye") as Panel).position.x, eye_right, "lead eye follows facing")
	assert_lt((rig.get_node("Eye2") as Panel).position.x, eye2_right, "trailing eye too")
