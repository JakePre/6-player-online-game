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


func test_max_players_raised_to_twelve() -> void:
	assert_eq(MeteorShower.make_meta().max_players, 12)


func test_control_spec_present() -> void:
	assert_false(
		MeteorShower.make_meta().control_spec.is_empty(), "ships a #832 structured control spec"
	)


## M15: at 12 players the arena and both zone radii grow together, so
## METEOR_RADIUS stays the same fraction of the final zone as at 6.
func test_arena_and_zone_scale_at_twelve_preserving_final_zone_density() -> void:
	var baseline := _game_with(6)
	var baseline_area_per_player := PI * baseline._zone_min * baseline._zone_min / 6.0

	var game := _game_with(12)
	assert_gt(game._play_half, MeteorShower.ARENA_HALF, "the arena grows for a crowd")
	assert_gt(game._zone_start, MeteorShower.ZONE_START_RADIUS)
	assert_gt(game._zone_min, MeteorShower.ZONE_MIN_RADIUS)
	var area_per_player := PI * game._zone_min * game._zone_min / 12.0
	assert_almost_eq(
		area_per_player, baseline_area_per_player, 0.01, "final-zone area-per-player holds steady"
	)
	# METEOR_RADIUS itself doesn't scale, so as the zone grows a meteor covers
	# a *smaller* fraction of it — the endgame crush gets no worse at 12.
	var ratio := MeteorShower.METEOR_RADIUS / game._zone_min
	var baseline_ratio := MeteorShower.METEOR_RADIUS / baseline._zone_min
	assert_lt(ratio, baseline_ratio, "a meteor covers less of the bigger final zone, not more")


## Backward compatibility: at the 6-player baseline nothing scales.
func test_six_players_unchanged() -> void:
	var game := _game_with(6)
	assert_almost_eq(game._play_half, MeteorShower.ARENA_HALF, 0.001)
	assert_almost_eq(game._zone_start, MeteorShower.ZONE_START_RADIUS, 0.001)
	assert_almost_eq(game._zone_min, MeteorShower.ZONE_MIN_RADIUS, 0.001)


## Spawns fan out over rings (no overlap) and stay inside the scaled zone.
func test_spawns_distinct_and_within_zone_at_twelve() -> void:
	var game := _game_with(12)
	var seen := {}
	for slot in 12:
		var pos: Vector2 = game.positions[slot]
		assert_lt(pos.length(), game.zone_radius(), "spawn inside the scaled zone")
		seen[pos] = true
	assert_eq(seen.size(), 12, "every player gets a distinct spawn")
