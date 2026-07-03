extends GutTest
## Meteor Shower sim (M10-01): telegraphed impacts, the shrinking safe zone,
## and last-one-standing ranking. Server-side logic only.

const TICK := 1.0 / 30.0


func _game_with(count: int) -> MeteorShower:
	var game := MeteorShower.new()
	game.meta = MeteorShower.make_meta()
	var player_slots: Array[int] = []
	for i in count:
		player_slots.append(i)
	game.setup(player_slots, 7)
	return game


func test_setup_spawns_players_inside_the_zone() -> void:
	var game := _game_with(4)
	for slot: int in game.slots:
		var pos: Vector2 = game.positions[slot]
		assert_lt(pos.length(), game.zone_radius())


func test_players_move_with_intent() -> void:
	var game := _game_with(2)
	game.positions[0] = Vector2.ZERO
	game.handle_input(0, {"mx": 1.0, "my": 0.0})
	game.tick(TICK)
	assert_almost_eq(game.positions[0].x, MeteorShower.MOVE_SPEED * TICK, 0.001)


func test_meteors_spawn_inside_the_zone_over_time() -> void:
	var game := _game_with(2)
	for _i in 90:
		game.tick(TICK)
	var seen := game.meteors.size() + game.down_order.size()
	assert_gt(seen, 0, "three seconds in, meteors exist (or already landed)")
	for meteor: Dictionary in game.meteors:
		assert_lt((meteor.pos as Vector2).length(), game.zone_radius())


func test_meteor_impact_downs_players_under_it() -> void:
	var game := _game_with(3)
	game.positions[0] = Vector2(2.0, 0.0)
	game.positions[1] = Vector2(-4.0, 0.0)
	game.positions[2] = Vector2(0.0, 4.0)
	game.meteors = [{"pos": Vector2(2.0, 0.0), "left": 0.01}]
	game.tick(TICK)
	assert_eq(game.down_order, [[0]], "only the player under the impact goes down")
	assert_false(game.finished, "two players still standing")


func test_leaving_the_zone_downs_you() -> void:
	var game := _game_with(3)
	game.positions[0] = Vector2(MeteorShower.ARENA_HALF, 0.0)
	game.tick(TICK)
	assert_eq(game.down_order, [[0]], "outside the fresh zone radius = out")


func test_last_one_standing_wins_with_down_order_reversed() -> void:
	var game := _game_with(3)
	game.meteors = [{"pos": game.positions[2], "left": 0.01}]
	game.tick(TICK)
	game.meteors = [{"pos": game.positions[1], "left": 0.01}]
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[0], [1], [2]])


func test_simultaneous_downs_share_a_tie_group() -> void:
	var game := _game_with(3)
	game.positions[0] = Vector2(-6.0, 0.0)
	game.positions[1] = Vector2(3.0, 0.0)
	game.positions[2] = Vector2(3.2, 0.0)
	game.meteors = [{"pos": Vector2(3.1, 0.0), "left": 0.01}]
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[0], [1, 2]])


func test_timeout_ranks_survivors_ahead_of_the_fallen() -> void:
	var game := _game_with(3)
	game.duration_override = TICK * 2.0
	game.meteors = [{"pos": game.positions[2], "left": 0.01}]
	game.tick(TICK)
	game.tick(TICK)
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[0, 1], [2]])


func test_zone_shrinks_after_the_grace_period() -> void:
	var game := _game_with(2)
	assert_almost_eq(game.zone_radius(), MeteorShower.ZONE_START_RADIUS, 0.001)
	game.elapsed = MeteorShower.ZONE_GRACE_SEC + MeteorShower.ZONE_SHRINK_SEC
	assert_almost_eq(game.zone_radius(), MeteorShower.ZONE_MIN_RADIUS, 0.001)


func test_snapshot_shape() -> void:
	var game := _game_with(2)
	game.meteors = [{"pos": Vector2(1.0, -2.0), "left": 0.5}]
	var snapshot := game.get_snapshot()
	assert_eq(snapshot.players.size(), 2)
	assert_eq(snapshot.zone, [0.0, 0.0, snappedf(game.zone_radius(), 0.01)])
	assert_eq(snapshot.meteors, [[1.0, -2.0, 0.5]])
	assert_eq(snapshot.fallen, [])
