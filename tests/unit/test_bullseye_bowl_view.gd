extends GutTest
## Bullseye Bowl client view (M10-07): renders replicated snapshots in the
## shared iso-arena without simulating anything locally.

const VIEW_SCENE: PackedScene = preload("res://src/minigames/bullseye_bowl/bullseye_bowl_view.tscn")

var view: MinigameView


func before_each() -> void:
	view = VIEW_SCENE.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_eq(
		MinigameCatalog.view_scene_path(&"bullseye_bowl"),
		"res://src/minigames/bullseye_bowl/bullseye_bowl_view.tscn"
	)


func test_setup_builds_a_lane_target_and_ball_per_player() -> void:
	assert_not_null(view.arena.get_node("Lane0"))
	assert_not_null(view.arena.get_node("Target1"))
	assert_false(view.arena.get_node("Ball0").visible, "no flight yet")


## #1128 GFX: the lane wears the wood-court grain (opaque, not the old
## translucent tint), flanked by a gutter rail on each side, and rocks ring
## the alley perimeter.
func test_gfx_lane_texture_gutters_and_rim_props() -> void:
	var lane: MeshInstance3D = view.arena.get_node("Lane0")
	var lane_mat := lane.mesh.material as StandardMaterial3D
	assert_eq(lane_mat.albedo_texture, view.LANE_TEXTURE)
	assert_not_null(view.arena.get_node("Gutter0L"))
	assert_not_null(view.arena.get_node("Gutter0R"))
	var props: Node = view.arena.get_node("RimProps")
	assert_eq(props.get_child_count(), view.RIM_PROP_COUNT)


## #588: adjacent targets otherwise blend into one board at iso distance —
## odd lanes swap to an alternate ring palette for separation.
func test_adjacent_lanes_alternate_ring_palettes() -> void:
	var outer0: MeshInstance3D = view.arena.get_node("Target0/Ring0")
	var outer1: MeshInstance3D = view.arena.get_node("Target1/Ring0")
	var mat0: StandardMaterial3D = outer0.mesh.material
	var mat1: StandardMaterial3D = outer1.mesh.material
	assert_eq(mat0.albedo_color, view.RING_COLORS[2], "even lane keeps the base outer ring color")
	assert_eq(
		mat1.albedo_color, view.RING_COLORS_ALT[2], "odd lane swaps to the alt outer ring color"
	)
	assert_ne(mat0.albedo_color, mat1.albedo_color, "adjacent lanes read as distinct boards")


func test_target_slides_and_ball_rolls_with_the_snapshot() -> void:
	view.render({"players": {0: [0, 8, 0.5, 1.5], 1: [0, 8, -1.0, -0.5]}})
	var target: Node3D = view.arena.get_node("Target0")
	var lane_x: float = view._lanes[0].center_x
	assert_almost_eq(target.position.x, lane_x + 1.5, 0.001, "target offset from lane center")
	var ball: MeshInstance3D = view.arena.get_node("Ball0")
	assert_true(ball.visible)
	assert_almost_eq(ball.position.z, 0.0, 0.001, "halfway down the lane at t=0.5")
	assert_false(view.arena.get_node("Ball1").visible, "no flight for the idle player")


func test_score_and_balls_ride_the_nameplate() -> void:
	view.render({"players": {0: [12, 3, -1.0, 0.0]}})
	assert_string_contains(view.rig_for_slot(0).display_name, "12 pts")
	assert_string_contains(view.rig_for_slot(0).display_name, "3 balls")


func test_bullseye_jump_shakes_once() -> void:
	watch_signals(view)
	view.render({"players": {0: [3, 5, -1.0, 0.0]}})
	assert_signal_not_emitted(view, "shake_requested", "seeding snapshot stays calm")
	view.render({"players": {0: [4, 5, -1.0, 0.0]}})
	assert_signal_not_emitted(view, "shake_requested", "an outer-ring point is no fanfare")
	view.render({"players": {0: [9, 4, -1.0, 0.0]}})
	assert_signal_emitted(view, "shake_requested", "a bullseye rattles the screen")


## Signature cues (#728): bell for a bullseye, hit for a lesser ring, both
## heard only by the roller (slot 0 is my_slot per before_each's setup call).
func test_bullseye_plays_bell_and_outer_ring_plays_hit() -> void:
	watch_signals(view)
	view.render({"players": {0: [0, 8, -1.0, 0.0]}})
	view.render({"players": {0: [1, 7, -1.0, 0.0]}})
	assert_signal_emitted_with_parameters(view, "sfx_requested", [&"hit"], "an outer point")
	view.render({"players": {0: [6, 6, -1.0, 0.0]}})
	assert_signal_emitted_with_parameters(view, "sfx_requested", [&"bell"], "a bullseye")


## A roll that lands beyond every ring (no score change) used to be silent.
func test_a_clean_miss_plays_error() -> void:
	watch_signals(view)
	view.render({"players": {0: [0, 8, 0.5, 0.0]}})  # mid-flight
	assert_signal_not_emitted(view, "sfx_requested", "still airborne, nothing to hear yet")
	view.render({"players": {0: [0, 7, -1.0, 0.0]}})  # landed, same score
	assert_signal_emitted_with_parameters(view, "sfx_requested", [&"error"], "a clean miss")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)


## M13-14: balls spin with flight progress, ring hits flash at the target.
func test_ball_spins_with_flight_progress() -> void:
	view.render({"players": {0: [0, 8, 0.25, 0.0], 1: [0, 8, -1.0, 0.0]}})
	var ball: MeshInstance3D = view.arena.get_node("Ball0")
	var spin_a: float = ball.rotation.x
	view.render({"players": {0: [0, 8, 0.5, 0.0], 1: [0, 8, -1.0, 0.0]}})
	assert_ne(ball.rotation.x, spin_a, "the roll advances with the flight")


func test_ring_hits_flash_scaled_to_value() -> void:
	view.render({"players": {0: [0, 7, -1.0, 0.0]}})
	var before: int = view.arena.get_child_count()
	view.render({"players": {0: [1, 6, -1.0, 0.0]}})
	assert_eq(view.arena.get_child_count(), before + 1, "an outer point twinkles")
	view.render({"players": {0: [6, 5, -1.0, 0.0]}})
	assert_eq(view.arena.get_child_count(), before + 2, "a bullseye bursts")


## M15-07: lanes keep their tuned pitch, so the camera framing grows linearly
## with the lane bank — and lobbies at the 6-player baseline keep the classic
## framing exactly.
func test_camera_framing_grows_with_the_lane_bank() -> void:
	assert_almost_eq(
		view._arena_half(),
		BullseyeBowl.LANE_LENGTH * 0.75,
		0.001,
		"small lobbies keep the classic framing"
	)
	var crowd := {}
	for slot in 24:
		crowd[slot] = "P%d" % (slot + 1)
	var big: MinigameView3D = VIEW_SCENE.instantiate()
	add_child_autofree(big)
	big.setup(crowd, 0)
	assert_almost_eq(
		big._arena_half(),
		BullseyeBowl.LANE_LENGTH * 0.75 * 4.0,
		0.001,
		"24 lanes widen the shot four-fold"
	)
	# Every lane still exists and keeps the tuned pitch between neighbours.
	var lane_23: Dictionary = big._lanes[23]
	var lane_22: Dictionary = big._lanes[22]
	assert_almost_eq(
		float(lane_23.center_x) - float(lane_22.center_x), BullseyeBowl.LANE_SPACING, 0.001
	)


## #797: low headcounts widen the pitch to fill the arena the baseline
## already tunes for, instead of clustering every lane at the fixed pitch.
func test_low_headcount_widens_lane_pitch() -> void:
	var lane_0: Dictionary = view._lanes[0]
	var lane_1: Dictionary = view._lanes[1]
	var pitch: float = float(lane_1.center_x) - float(lane_0.center_x)
	assert_gt(pitch, BullseyeBowl.LANE_SPACING, "2 players get more than the packed baseline pitch")


## The outer lanes of a widened low-count bank still land within the tuned
## <=6 arena half-width — spread to fill it, not spill past it.
func test_widened_lanes_stay_within_the_tuned_arena_half() -> void:
	var lane_1: Dictionary = view._lanes[1]
	assert_lt(absf(float(lane_1.center_x)), view._arena_half(), "outer lane stays inside the arena")


## A full baseline bank (6 players) keeps the exact classic pitch — the
## widening only kicks in below the baseline headcount.
func test_baseline_headcount_keeps_the_classic_pitch() -> void:
	var six := {}
	for slot in 6:
		six[slot] = "P%d" % (slot + 1)
	var baseline_view: MinigameView3D = VIEW_SCENE.instantiate()
	add_child_autofree(baseline_view)
	baseline_view.setup(six, 0)
	var lane_0: Dictionary = baseline_view._lanes[0]
	var lane_1: Dictionary = baseline_view._lanes[1]
	assert_almost_eq(
		float(lane_1.center_x) - float(lane_0.center_x),
		BullseyeBowl.LANE_SPACING,
		0.001,
		"a full baseline bank isn't widened"
	)
