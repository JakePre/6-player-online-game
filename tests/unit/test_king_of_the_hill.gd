extends GutTest
## King of the Hill server simulation (M4-01): zone scoring, shrink,
## relocation, and points ranking.

const TICK := 1.0 / 30.0


func _make_game(player_count: int) -> KingOfTheHill:
	var game := KingOfTheHill.new()
	game.meta = KingOfTheHill.make_meta()
	var slots: Array[int] = []
	for i in player_count:
		slots.append(i)
	game.setup(slots, 42)
	return game


func test_setup_spreads_players_with_zone_at_center() -> void:
	var game := _make_game(4)
	assert_eq(game.zone_center, Vector2.ZERO)
	assert_eq(game.zone_radius(), KingOfTheHill.ZONE_START_RADIUS)
	for slot in 4:
		assert_eq(game.points(slot), 0)
		assert_lt(
			(game.positions[slot] as Vector2).length(), KingOfTheHill.ARENA_HALF, "spawn in arena"
		)


func test_standing_in_zone_scores_over_time() -> void:
	var game := _make_game(2)
	game.positions[0] = Vector2.ZERO
	game.positions[1] = Vector2(KingOfTheHill.ARENA_HALF, KingOfTheHill.ARENA_HALF)
	for _i in 60:
		game.tick(TICK)
	assert_almost_eq(game.score_accum[0] as float, KingOfTheHill.POINTS_PER_SEC * 2.0, 0.01)
	assert_eq(game.points(1), 0, "player outside the zone scores nothing")


func test_everyone_inside_scores_simultaneously() -> void:
	var game := _make_game(3)
	for slot in 3:
		game.positions[slot] = Vector2.ZERO
	game.positions[2] = Vector2(KingOfTheHill.ARENA_HALF, 0.0)
	for _i in 30:
		game.tick(TICK)
	assert_eq(game.points(0), game.points(1), "co-occupants score at the same rate")
	assert_eq(game.points(2), 0)


func test_zone_shrinks_over_lifetime() -> void:
	var game := _make_game(2)
	var start := game.zone_radius()
	game.zone_age = KingOfTheHill.ZONE_LIFETIME_SEC * 0.999
	assert_lt(game.zone_radius(), start)
	assert_almost_eq(game.zone_radius(), KingOfTheHill.ZONE_MIN_RADIUS, 0.01)


func test_zone_relocates_after_lifetime_and_resets() -> void:
	var game := _make_game(2)
	game.zone_age = KingOfTheHill.ZONE_LIFETIME_SEC
	game.tick(TICK)
	assert_ne(game.zone_center, Vector2.ZERO, "zone moved away from its old spot")
	assert_lt(game.zone_age, 1.0, "lifetime restarted")
	assert_gt(
		game.zone_center.distance_to(Vector2.ZERO),
		KingOfTheHill.ZONE_START_RADIUS,
		"new zone is not straddleable from the old one"
	)
	var margin := KingOfTheHill.ARENA_HALF - KingOfTheHill.ZONE_MARGIN
	assert_between(game.zone_center.x, -margin, margin, "zone stays inside the arena")
	assert_between(game.zone_center.y, -margin, margin, "zone stays inside the arena")


func test_movement_follows_input_and_clamps_to_arena() -> void:
	var game := _make_game(2)
	game.handle_input(0, {"mx": 1.0, "my": 0.0})
	for _i in 240:
		game.tick(TICK)
	assert_eq((game.positions[0] as Vector2).x, KingOfTheHill.ARENA_HALF)


func test_input_direction_is_capped_at_unit_length() -> void:
	var game := _make_game(2)
	game.handle_input(0, {"mx": 100.0, "my": 100.0})
	assert_almost_eq((game.move_dirs[0] as Vector2).length(), 1.0, 0.001)


func test_ranking_groups_ties_no_pickup_coins() -> void:
	var game := _make_game(4)
	game.duration_override = 0.1
	game.score_accum = {0: 3.2, 1: 7.9, 2: 3.5, 3: 0.0}
	game.tick(0.2)
	assert_true(game.finished)
	var results := game.get_results()
	assert_eq(results.placements, [[1], [0, 2], [3]], "int points tie 0 and 2 at 3")
	assert_eq(results.pickup_coins, {}, "placement-only game (SPEC $5)")


func test_snapshot_lists_players_and_zone() -> void:
	var game := _make_game(2)
	var snapshot := game.get_snapshot()
	assert_eq(snapshot.players.size(), 2)
	var entry: Array = snapshot.players[0]
	assert_eq(entry.size(), 3, "x, y, points")
	assert_eq((snapshot.zone as Array).size(), 3, "x, y, radius")


# --- #139 overhaul: drift, pillars, items -------------------------------------


func test_zone_drifts_between_jumps() -> void:
	var game := _make_game(2)
	var start: Vector2 = game.zone_center
	for _i in 60:
		game.tick(TICK)
	assert_gt(game.zone_center.distance_to(start), 0.5, "the zone visibly moves (#139)")


func test_pillars_seed_inside_the_arena_and_block_movement() -> void:
	var game := _make_game(2)
	assert_eq(game.pillars.size(), KingOfTheHill.PILLAR_COUNT)
	var pillar: Vector2 = game.pillars[0]
	game.positions[0] = pillar
	game.tick(TICK)
	var gap := KingOfTheHill.PILLAR_RADIUS + KingOfTheHill.PLAYER_RADIUS
	assert_gt(game.positions[0].distance_to(pillar) + 0.001, gap, "pushed out of the pillar (#139)")


func test_item_pickup_and_shove() -> void:
	var game := _make_game(2)
	game.items.append({"pos": Vector2(2.0, 2.0), "type": KingOfTheHill.Item.SHOVE})
	game.positions[0] = Vector2(2.0, 2.0)
	game.positions[1] = Vector2(3.0, 2.0)
	game.tick(TICK)
	assert_eq(int(game.held.get(0, -1)), int(KingOfTheHill.Item.SHOVE))
	assert_eq(game.items.size(), 0)
	var before: Vector2 = game.positions[1]
	game.handle_input(0, {"use": true})
	assert_false(game.held.has(0), "item consumed")
	assert_gt(game.positions[1].distance_to(before), 1.0, "shoved away (#139)")


func test_anchor_freezes_the_zone() -> void:
	var game := _make_game(2)
	game.held[0] = KingOfTheHill.Item.ANCHOR
	var center: Vector2 = game.zone_center
	var age: float = game.zone_age
	game.handle_input(0, {"use": true})
	for _i in 30:
		game.tick(TICK)
	assert_eq(game.zone_center, center, "anchored zone does not drift")
	assert_eq(game.zone_age, age, "anchored zone does not age")
	assert_true(game.get_snapshot().anchored)


func test_use_without_item_is_a_noop() -> void:
	var game := _make_game(2)
	game.handle_input(0, {"use": true})
	assert_false(game.held.has(0))


func test_snapshot_carries_pillars_items_held() -> void:
	var game := _make_game(2)
	game.items.append({"pos": Vector2(1.0, 1.0), "type": KingOfTheHill.Item.ANCHOR})
	game.held[1] = KingOfTheHill.Item.SHOVE
	var snapshot := game.get_snapshot()
	assert_eq(snapshot.pillars.size(), KingOfTheHill.PILLAR_COUNT)
	assert_eq(snapshot.items, [[1.0, 1.0, 1]])
	assert_eq(snapshot.held, {1: KingOfTheHill.Item.SHOVE})
	assert_false(snapshot.anchored)


func test_players_are_solid() -> void:
	var game := _make_game(2)
	game.positions[0] = Vector2(0.0, 0.0)
	game.positions[1] = Vector2(0.4, 0.0)
	game.tick(TICK)
	assert_gt(
		game.positions[1].distance_to(game.positions[0]), 0.4, "overlapping bodies separate (#260)"
	)


func test_item_pickup_pays_points() -> void:
	var game := _make_game(2)
	game.items.append({"pos": Vector2(2.0, 2.0), "type": KingOfTheHill.Item.SHOVE})
	game.positions[0] = Vector2(2.0, 2.0)
	var before: float = game.score_accum[0]
	game.tick(TICK)
	assert_almost_eq(
		float(game.score_accum[0]) - before,
		KingOfTheHill.ITEM_PICKUP_POINTS,
		0.2,
		"grabbing pays instantly (#260)"
	)


func test_max_players_raised_to_twelve() -> void:
	assert_eq(KingOfTheHill.make_meta().max_players, 12)


## M15: a fixed-size hill is exactly the body-blocking scrum the ADR flags, so
## a 12-player match grows both the arena AND the zone itself.
func test_arena_and_zone_scale_at_twelve() -> void:
	var game := _make_game(12)
	assert_gt(game._play_half, KingOfTheHill.ARENA_HALF, "the arena grows for a crowd")
	assert_gt(game._zone_start_radius, KingOfTheHill.ZONE_START_RADIUS, "the hill grows too")
	assert_gt(game._zone_min_radius, KingOfTheHill.ZONE_MIN_RADIUS, "so does its shrunk floor")
	assert_almost_eq(
		game.zone_radius(), game._zone_start_radius, 0.001, "starts at the scaled size"
	)


## Backward compatibility: at the 6-player baseline nothing scales.
func test_six_players_unchanged() -> void:
	var game := _make_game(6)
	assert_almost_eq(game._play_half, KingOfTheHill.ARENA_HALF, 0.001)
	assert_almost_eq(game._zone_start_radius, KingOfTheHill.ZONE_START_RADIUS, 0.001)
	assert_almost_eq(game._zone_min_radius, KingOfTheHill.ZONE_MIN_RADIUS, 0.001)


## Spawns fan out over rings (no overlap) and stay inside the scaled arena.
func test_spawns_distinct_and_within_arena_at_twelve() -> void:
	var game := _make_game(12)
	var seen := {}
	for slot in 12:
		var pos: Vector2 = game.positions[slot]
		assert_lte(pos.length(), game._play_half, "spawn inside the scaled arena")
		seen[pos] = true
	assert_eq(seen.size(), 12, "every player gets a distinct spawn")


## The scaled zone still shrinks to its (scaled) minimum and still relocates
## meaningfully clear of its old spot, at a full 12-player lobby.
func test_zone_shrink_and_relocation_scale_too() -> void:
	var game := _make_game(12)
	game.zone_age = KingOfTheHill.ZONE_LIFETIME_SEC
	assert_almost_eq(game.zone_radius(), game._zone_min_radius, 0.01)
	var previous := game.zone_center
	game._relocate_zone()
	assert_gte(
		game.zone_center.distance_to(previous),
		game._zone_start_radius * 1.5,
		"still jumps meaningfully clear of the old zone"
	)
