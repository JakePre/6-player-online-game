extends GutTest
## Tumble Run (M14-09): vertical climb on the side-scroll bones — laddered
## ledges, crumbling footing, falling boulders that knock climbers down
## (no elimination), and summit-then-height placement.

const TICK := 1.0 / 30.0


func _game(player_slots: Array[int] = [0, 1]) -> TumbleRun:
	var game := TumbleRun.new()
	game.meta = TumbleRun.make_meta()
	game.setup(player_slots, 42)
	return game


func _to_climb(game: TumbleRun) -> void:
	while game.phase == TumbleRun.Phase.COUNTDOWN and not game.finished:
		game.tick(TICK)


func test_meta_and_catalog() -> void:
	var meta := TumbleRun.make_meta()
	assert_eq(meta.id, &"tumble_run")
	assert_eq(meta.max_players, 8)
	assert_false(meta.controls_text.is_empty())
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.instantiate(&"tumble_run") is TumbleRun)
	MinigameCatalog.clear()


func test_setup_spawns_on_the_floor_below_the_ledges() -> void:
	var game := _game([0, 1, 2] as Array[int])
	assert_eq(game.climbers.size(), 3)
	for slot in [0, 1, 2]:
		assert_false(bool(game.climbers[slot].summit))
		assert_lt(float(game.climbers[slot].height), TumbleRun.GOAL_HEIGHT)
		assert_true(game.sim.has_body(slot))


func test_ledges_are_a_side_alternating_ladder() -> void:
	var rects := TumbleRun.ledges()
	assert_eq(rects.size(), TumbleRun.LEDGE_COUNT)
	assert_gt(rects[0].position.x, 0.0, "first ledge on the right")
	assert_lt(rects[1].position.x, 0.0, "second on the left")
	assert_gt(rects[1].get_center().y, rects[0].get_center().y, "each ledge climbs higher")


func test_countdown_freezes_climbing_then_release() -> void:
	var game := _game()
	game.handle_input(0, {"mx": 1.0})
	game.tick(TICK)
	assert_almost_eq(float(game.sim.body_of(0).move_x), 0.0, 0.001, "frozen in countdown")
	_to_climb(game)
	game.handle_input(0, {"mx": 1.0})
	assert_almost_eq(float(game.sim.body_of(0).move_x), 1.0, 0.001, "climbing frees movement")


func test_crumble_ledges_cycle_solid_and_gone() -> void:
	var game := _game()
	_to_climb(game)
	var crumble := TumbleRun._crumble_indices()
	assert_gt(crumble.size(), 0, "some ledges crumble")
	var index: int = crumble[0]
	assert_true(game.crumble_state[index], "starts solid")
	# Run past the solid window into the gone window.
	for _i in int((TumbleRun.CRUMBLE_SOLID_SEC + 0.2) / TICK):
		game.tick(TICK)
	assert_false(game.crumble_state[index], "the ledge crumbles away")
	# A gone ledge is not in the sim's one-way set.
	var gone_rect := TumbleRun.ledges()[index]
	assert_false(gone_rect in game.sim.one_way, "the sim drops the crumbled ledge")


func test_reaching_the_summit_records_finish_order() -> void:
	var game := _game()
	_to_climb(game)
	game.sim.body_of(0).pos = Vector2(0.0, TumbleRun.GOAL_HEIGHT + 0.5)
	game.tick(TICK)
	assert_true(bool(game.climbers[0].summit), "at the top = summited")
	assert_eq(game.summit_order, [0])


func test_boulder_knocks_a_climber_down_and_stuns() -> void:
	var game := _game()
	_to_climb(game)
	var climber: Dictionary = game.climbers[0]
	game.sim.body_of(0).pos = Vector2(0.0, 5.0)
	# Drop a boulder onto the climber's head.
	game.boulders.append({"pos": Vector2(0.0, 5.3), "vel": Vector2.ZERO})
	game.tick(TICK)
	assert_gt(float(climber.stun), 0.0, "the hit stuns")
	assert_ne(float(game.sim.body_of(0).vel.x), 0.0, "and pops them off sideways")


func test_stunned_climber_ignores_input() -> void:
	var game := _game()
	_to_climb(game)
	game.climbers[0].stun = TumbleRun.STUN_SEC
	game.handle_input(0, {"mx": 1.0})
	game.tick(TICK)
	assert_almost_eq(float(game.sim.body_of(0).move_x), 0.0, 0.001, "no climbing mid-tumble")


func test_boulders_spawn_and_fall_over_time() -> void:
	var game := _game()
	_to_climb(game)
	var before := game.boulders.size()
	for _i in int(TumbleRun.BOULDER_INTERVAL / TICK) + 2:
		game.tick(TICK)
	assert_gt(game.boulders.size(), before, "boulders keep coming")
	assert_lt(float(game.boulders[0].pos.y), TumbleRun.GOAL_HEIGHT + 4.0, "and they fall")


func test_summit_beats_height_in_the_ranking() -> void:
	var game := _game([0, 1] as Array[int])
	_to_climb(game)
	# Slot 1 is higher, but slot 0 tops out.
	game.climbers[0].summit = true
	game.summit_order = [0]
	game.climbers[0].height = 10.0
	game.climbers[1].height = 25.0
	game.phase_left = 0.0
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements[0], [0], "the summiter wins despite less height")
	assert_eq(game.get_results().placements[1], [1])


func test_everyone_summiting_ends_early() -> void:
	var game := _game([0, 1] as Array[int])
	_to_climb(game)
	game.sim.body_of(0).pos = Vector2(0.0, TumbleRun.GOAL_HEIGHT + 0.5)
	game.sim.body_of(1).pos = Vector2(1.0, TumbleRun.GOAL_HEIGHT + 0.5)
	game.tick(TICK)
	assert_true(game.finished, "all topped out ends the round")


func test_snapshot_shape_and_junk_input() -> void:
	var game := _game()
	_to_climb(game)
	game.handle_input(0, {"bogus": true})
	game.handle_input(9, {"jump": true})
	game.tick(TICK)
	var snap := game.get_snapshot()
	for key in ["players", "boulders", "crumble", "phase", "standings"]:
		assert_true(snap.has(key), "%s replicates" % key)
	assert_eq((snap.players[0] as Array).size(), TumbleRun.PS_COUNT)
	assert_eq((snap.crumble as Array).size(), TumbleRun.LEDGE_COUNT)
