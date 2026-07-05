extends GutTest
## SideScrollSim (M14-00): pure-math server platforming — gravity, landing,
## run feel, buffered/coyote/air jumps, one-way lids, walls, knockback, and
## the replication snapshot shape shared by the side-view games.

const TICK := 1.0 / 30.0

var sim: SideScrollSim


func before_each() -> void:
	sim = SideScrollSim.new()
	# One long ground slab whose walkable lid sits at y = 0.
	sim.solids = [Rect2(-10.0, -1.0, 20.0, 1.0)]
	sim.bounds = Rect2(-12.0, -6.0, 24.0, 18.0)


func _steps(count: int) -> void:
	for _i in count:
		sim.step(TICK)


func test_gravity_pulls_bodies_onto_the_ground() -> void:
	sim.add_body(0, Vector2(0.0, 3.0))
	assert_false(bool(sim.body_of(0).grounded), "spawns airborne")
	_steps(30)
	assert_true(bool(sim.body_of(0).grounded), "a second of gravity lands it")
	assert_almost_eq(float((sim.body_of(0).pos as Vector2).y), SideScrollSim.HALF.y, 0.001)
	assert_almost_eq(float((sim.body_of(0).vel as Vector2).y), 0.0, 0.001)


func test_running_accelerates_to_speed_and_friction_stops() -> void:
	sim.add_body(0, Vector2(0.0, SideScrollSim.HALF.y))
	sim.set_move(0, 1.0)
	_steps(15)
	assert_almost_eq(float((sim.body_of(0).vel as Vector2).x), sim.run_speed, 0.001, "at speed")
	sim.set_move(0, 0.0)
	_steps(15)
	assert_almost_eq(float((sim.body_of(0).vel as Vector2).x), 0.0, 0.001, "friction stops it")


func test_facing_tracks_last_direction_moved() -> void:
	sim.add_body(0, Vector2.ZERO)
	sim.set_move(0, -0.4)
	assert_eq(int(sim.body_of(0).facing), -1)
	sim.set_move(0, 0.0)
	assert_eq(int(sim.body_of(0).facing), -1, "letting go keeps the last facing")


func test_grounded_jump_launches_at_jump_velocity() -> void:
	sim.add_body(0, Vector2(0.0, 3.0))
	_steps(30)
	sim.press_jump(0)
	sim.step(TICK)
	assert_almost_eq(float((sim.body_of(0).vel as Vector2).y), sim.jump_velocity, 0.001)
	assert_false(bool(sim.body_of(0).grounded))


func test_airborne_jump_is_refused_without_air_jumps() -> void:
	sim.add_body(0, Vector2(0.0, 4.0))
	sim.step(TICK)
	sim.press_jump(0)
	# Burn past the buffer window while still falling: no jump ever fires.
	_steps(5)
	assert_lt(float((sim.body_of(0).vel as Vector2).y), 0.0, "still falling — no mid-air jump")


func test_buffered_press_fires_on_landing() -> void:
	# A generous buffer isolates the mechanism from exact landing-tick math:
	# press mid-fall, land around tick 6, and the buffered press fires on
	# the first grounded tick after touchdown.
	sim.jump_buffer_sec = 0.3
	sim.add_body(0, Vector2(0.0, 1.2))
	sim.press_jump(0)
	_steps(7)
	assert_gt(
		float((sim.body_of(0).vel as Vector2).y), 0.0, "the pre-landing press jumps on touchdown"
	)


func test_coyote_window_allows_a_late_jump_off_a_ledge() -> void:
	sim.solids = [Rect2(-10.0, -1.0, 10.0, 1.0)]  # ground ends at x = 0
	sim.add_body(0, Vector2(-0.2, SideScrollSim.HALF.y))
	sim.set_move(0, 1.0)
	# Tick 1 accelerates at air rates (bodies spawn a hair above ground),
	# so clearing the ledge with the trailing edge takes five ticks.
	_steps(5)
	assert_false(bool(sim.body_of(0).grounded), "off the ledge")
	sim.press_jump(0)
	sim.step(TICK)
	assert_gt(float((sim.body_of(0).vel as Vector2).y), 0.0, "coyote jump fires")


func test_coyote_window_expires() -> void:
	sim.solids = [Rect2(-10.0, -1.0, 10.0, 1.0)]
	sim.add_body(0, Vector2(-0.2, SideScrollSim.HALF.y))
	sim.set_move(0, 1.0)
	_steps(4)
	sim.set_move(0, 0.0)
	_steps(4)  # ~0.13 s airborne > coyote_sec (0.1)
	sim.press_jump(0)
	_steps(2)
	assert_lt(float((sim.body_of(0).vel as Vector2).y), 0.0, "too late — keeps falling")


func test_air_jumps_grant_exactly_that_many_extras() -> void:
	sim.max_air_jumps = 1
	sim.add_body(0, Vector2(0.0, 5.0))
	sim.step(TICK)
	sim.press_jump(0)
	sim.step(TICK)
	assert_almost_eq(float((sim.body_of(0).vel as Vector2).y), sim.jump_velocity, 0.001, "double")
	_steps(12)  # ride the arc past its apex so the body is falling again
	assert_lt(float((sim.body_of(0).vel as Vector2).y), 0.0, "past the apex")
	sim.press_jump(0)
	sim.step(TICK)
	assert_lt(float((sim.body_of(0).vel as Vector2).y), 0.0, "the second extra is refused")


func test_one_way_lid_catches_falls_but_passes_jumps() -> void:
	sim.one_way = [Rect2(-2.0, 2.0, 4.0, 0.5)]  # lid at y = 2.5
	sim.add_body(0, Vector2(0.0, 5.0))
	_steps(30)
	assert_almost_eq(
		float((sim.body_of(0).pos as Vector2).y),
		2.5 + SideScrollSim.HALF.y,
		0.001,
		"landed on the lid"
	)
	sim.press_jump(0)
	_steps(8)
	var rising_through: Vector2 = sim.body_of(0).pos
	assert_gt(rising_through.y, 3.2, "the jump carries up through the platform")
	_steps(40)
	assert_almost_eq(
		float((sim.body_of(0).pos as Vector2).y),
		2.5 + SideScrollSim.HALF.y,
		0.001,
		"falls back onto the lid"
	)


func test_solid_wall_blocks_horizontal_motion() -> void:
	sim.solids.append(Rect2(2.0, 0.0, 1.0, 3.0))
	sim.add_body(0, Vector2(0.0, SideScrollSim.HALF.y))
	sim.set_move(0, 1.0)
	_steps(30)
	assert_almost_eq(
		float((sim.body_of(0).pos as Vector2).x), 2.0 - SideScrollSim.HALF.x, 0.001, "at the wall"
	)
	assert_almost_eq(float((sim.body_of(0).vel as Vector2).x), 0.0, 0.001)


func test_ceiling_stops_upward_motion() -> void:
	sim.solids.append(Rect2(-2.0, 2.0, 4.0, 1.0))  # underside at y = 2
	sim.add_body(0, Vector2(0.0, SideScrollSim.HALF.y))
	sim.step(TICK)
	sim.press_jump(0)
	# The unobstructed arc would apex near y = 3.1; the ceiling caps the
	# whole flight at its underside instead.
	var peak := 0.0
	for _i in 12:
		sim.step(TICK)
		peak = maxf(peak, float((sim.body_of(0).pos as Vector2).y))
	assert_almost_eq(peak, 2.0 - SideScrollSim.HALF.y, 0.001, "bonked at the underside")


func test_impulse_shoves_and_lifts() -> void:
	sim.add_body(0, Vector2(0.0, 3.0))
	_steps(30)
	sim.apply_impulse(0, Vector2(6.0, 10.0))
	assert_false(bool(sim.body_of(0).grounded), "an upward kick lifts")
	sim.step(TICK)
	assert_gt(float((sim.body_of(0).pos as Vector2).x), 0.0, "carried sideways")
	assert_gt(float((sim.body_of(0).pos as Vector2).y), SideScrollSim.HALF.y, "and upward")


func test_out_slots_reports_bodies_past_the_bounds() -> void:
	sim.solids = []
	sim.add_body(0, Vector2(0.0, 3.0))
	sim.add_body(1, Vector2(0.0, 3.0))
	sim.remove_body(1)
	_steps(60)
	assert_eq(sim.out_slots(), [0], "the un-removed body fell out the bottom")


func test_snapshot_players_shape() -> void:
	sim.add_body(3, Vector2(1.234, 3.0))
	sim.set_move(3, -1.0)
	_steps(30)
	var snap := sim.snapshot_players()
	assert_true(snap.has(3))
	var sample: Array = snap[3]
	assert_eq(sample.size(), 4)
	assert_eq(int(sample[2]), -1, "facing replicates")
	assert_eq(int(sample[3]), 1, "grounded replicates")
