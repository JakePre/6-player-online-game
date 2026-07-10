extends GutTest
## Target Range client view: renders replicated targets/aims in the iso arena
## without local simulation, and (M13-17) breaks shot targets with a burst.

const VIEW_SCENE: PackedScene = preload("res://src/minigames/target_range/target_range_view.tscn")

var view: MinigameView3D


func before_each() -> void:
	view = VIEW_SCENE.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func _burst_count() -> int:
	var count := 0
	for child in view.arena.get_children():
		if child is CPUParticles3D:
			count += 1
	return count


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_not_null(view.arena.get_node("Crosshair0"))


## #790: rigs are pooled hidden (#601) and this stationary view places them once
## in _line_up_rigs, so a snapshot must reveal the round's shooters or they never
## render at all. Reveal is snapshot-driven (the scores keys), matching #780.
func test_render_reveals_the_shooter_rigs() -> void:
	assert_false(view.rig_for_slot(0).visible, "rigs start hidden until a snapshot reveals them")
	view.render({"scores": {0: 0, 1: 0}, "targets": [], "aims": {}})
	assert_true(view.rig_for_slot(0).visible, "the round's shooters become visible")
	assert_true(view.rig_for_slot(1).visible)


## A target present one snapshot and gone the next, while on-screen, was shot —
## it pops a break burst where it stood.
func test_shooting_a_target_breaks_it_with_a_burst() -> void:
	view.render({"targets": [[1, 0.0, 3.0, 0.5, TargetRange.Kind.STANDARD]]})
	assert_eq(_burst_count(), 0, "no burst while the target is alive")
	view.render({"targets": []})
	assert_gt(_burst_count(), 0, "the broken target pops a burst")


## A target recycled off the far edge (sim drift, not a hit) leaves from beyond
## the arena and pops nothing.
func test_drifted_off_target_does_not_burst() -> void:
	var off_x := TargetRange.ARENA_HALF + 5.0
	view.render({"targets": [[2, off_x, 3.0, 0.5, TargetRange.Kind.STANDARD]]})
	view.render({"targets": []})
	assert_eq(_burst_count(), 0, "an off-screen recycle is silent")


## M15-07: a 24-shooter crowd wraps into ranks stepping toward the gallery,
## all staying clear of the target band (BAND_NEAR is -1).
func test_crowd_wraps_toward_the_gallery() -> void:
	var crowd := {}
	for slot in 24:
		crowd[slot] = "P%d" % (slot + 1)
	var big: MinigameView3D = VIEW_SCENE.instantiate()
	add_child_autofree(big)
	big.setup(crowd, 0)
	var depths := {}
	for slot in 24:
		var rig: CharacterRig = big.rig_for_slot(slot)
		depths[snappedf(rig.position.z, 0.01)] = true
		assert_lte(rig.position.z, big.FIRING_LINE + 0.001, "no rank behind the firing line")
		assert_gt(rig.position.z, 2.0, "every rank stays clear of the target band")
	assert_eq(depths.size(), 3, "24 shooters stand in three ranks")


## M15 → 24: the view widens with the gallery, so a target shot near the new
## edge (past the old ±8) still pops instead of being mistaken for a drift-off.
func test_wide_arena_bursts_shots_past_the_old_edge() -> void:
	var crowd := {}
	for slot in 24:
		crowd[slot] = "P%d" % (slot + 1)
	var big: MinigameView3D = VIEW_SCENE.instantiate()
	add_child_autofree(big)
	big.setup(crowd, 0)
	assert_almost_eq(big._half, TargetRange.arena_half_for(24), 0.001, "view half matches the sim")
	var edge_x := TargetRange.ARENA_HALF + 4.0  # 12: past the old edge, inside the scaled one
	assert_lt(edge_x, big._half, "the shot is inside the widened arena")
	var bursts := 0
	for child in big.arena.get_children():
		if child is CPUParticles3D:
			bursts += 1
	big.render({"targets": [[7, edge_x, 3.0, 0.5, TargetRange.Kind.STANDARD]]})
	big.render({"targets": []})
	var after := 0
	for child in big.arena.get_children():
		if child is CPUParticles3D:
			after += 1
	assert_gt(after, bursts, "a shot near the wide edge still breaks with a burst")


# --- Mouse aim + fire feedback (#579) ---


## The bug: mouse motion was handled in _unhandled_input, but the view roots are
## default MOUSE_FILTER_STOP Controls that swallow it first, so aiming did
## nothing. It's now in _input (runs before GUI picking). A synthetic motion
## event must reach the handler and drive the aim projection.
func test_mouse_motion_is_handled_in_input() -> void:
	# Poison the aim out of bounds; a mouse-motion event routed through _input
	# must recompute it via the (clamped) floor projection. On the old code —
	# where mouse lived in _unhandled_input and _input was the base no-op — the
	# poisoned value would survive, so this distinguishes the fix.
	view._aim = Vector2(9999.0, 9999.0)
	view._input(InputEventMouseMotion.new())
	assert_lte(absf(view._aim.x), view._half + 0.001, "_input reprojected + clamped the aim")
	assert_lte(absf(view._aim.y), view._half + 0.001)


## The floor projection is sane: a ray straight down the iso camera lands inside
## the gallery, and the result is always clamped to +/- the arena half.
func test_screen_to_floor_projects_inside_the_gallery() -> void:
	view.size = Vector2(1280, 720)
	# Explicit types: `view` is typed MinigameView3D but _screen_to_floor is on
	# the subclass, so `:=` inference fails CI's stricter parser (§11).
	var hit: Vector2 = view._screen_to_floor(Vector2(640, 360))
	assert_between(hit.x, -view._half, view._half, "projected x stays in the gallery")
	assert_between(hit.y, -view._half, view._half, "projected z stays in the gallery")
	# A far off-screen point still clamps rather than flying to infinity.
	var far: Vector2 = view._screen_to_floor(Vector2(99999, 99999))
	assert_lte(absf(far.x), view._half + 0.001, "off-screen aim clamps to the arena")


## Firing now makes noise and flashes: a shot cue, a muzzle burst at the shooter,
## and the tracer streak (was silent + tracer-only before).
func test_fire_shot_plays_a_cue_and_flashes() -> void:
	watch_signals(view)
	var before := _burst_count()
	view._fire_shot()
	assert_signal_emitted_with_parameters(view, "sfx_requested", [&"laser"], "a shot cue fires")
	assert_gt(_burst_count(), before, "a muzzle flash bursts at the shooter")
