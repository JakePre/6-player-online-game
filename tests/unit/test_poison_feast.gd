extends GutTest
## Poison Feast server simulation (reworked per #174): tiered dish spawning,
## clean/poisoned eating, the pot economy, stagger, the golden final course,
## and score ranking.

const TICK := 1.0 / 30.0


func _make_game(player_count: int) -> PoisonFeast:
	var game := PoisonFeast.new()
	game.meta = PoisonFeast.make_meta()
	var slots: Array[int] = []
	for i in player_count:
		slots.append(i)
	game.setup(slots, 42)
	return game


## Replaces the random table with one crafted dish and parks slot 0 on it.
func _serve(game: PoisonFeast, tier: PoisonFeast.Tier, poisoned: bool) -> void:
	game.dishes.clear()
	game.dishes.append({"id": 999, "pos": Vector2.ZERO, "tier": tier, "poisoned": poisoned})
	game.positions[0] = Vector2.ZERO
	game.move_dirs[0] = Vector2.ZERO


func test_setup_spreads_players_with_zero_scores_and_serves_a_wave() -> void:
	var game := _make_game(4)
	for slot in 4:
		assert_eq(game.score[slot], 0)
		assert_eq(game.staggers[slot], 0.0)
	assert_eq(game.dishes.size(), PoisonFeast.DISHES_PER_WAVE)
	for dish: Dictionary in game.dishes:
		assert_true(dish.tier in PoisonFeast.TIER_STATS, "spawned tiers come from the table")


func test_clean_dish_scores_its_points() -> void:
	var game := _make_game(2)
	_serve(game, PoisonFeast.Tier.CLEAN, false)
	game.tick(TICK)
	assert_eq(game.score[0], 1)
	assert_eq(game.pot, 0)


func test_poisoned_dish_costs_points_feeds_the_pot_and_staggers() -> void:
	var game := _make_game(2)
	_serve(game, PoisonFeast.Tier.DELICACY, true)
	game.tick(TICK)
	assert_eq(game.score[0], -6)
	assert_eq(game.pot, 6)
	assert_gt(float(game.staggers[0]), 0.0)


func test_staggered_players_cannot_eat() -> void:
	var game := _make_game(2)
	game.staggers[0] = PoisonFeast.STAGGER_SEC
	_serve(game, PoisonFeast.Tier.CLEAN, false)
	game.tick(TICK)
	assert_eq(game.score[0], 0, "staggered mouth stays shut")
	assert_eq(game.dishes.size(), 1)


func test_next_clean_bite_claims_the_pot() -> void:
	var game := _make_game(2)
	game.pot = 9
	_serve(game, PoisonFeast.Tier.SPICED, false)
	game.tick(TICK)
	assert_eq(game.score[0], 3 + 9)
	assert_eq(game.pot, 0)


func test_golden_dish_serves_near_the_end_and_pays_double_pot() -> void:
	var game := _make_game(2)
	game.duration_override = 10.0
	game.pot = 5
	# Park everyone away from the table so nothing is eaten accidentally.
	for slot in 2:
		game.positions[slot] = Vector2(PoisonFeast.ARENA_HALF, PoisonFeast.ARENA_HALF)
	while game.elapsed < 10.0 - PoisonFeast.GOLDEN_AT_REMAINING_SEC:
		game.tick(TICK)
	assert_true(game.golden_served)
	var golden: Array = game.dishes.filter(
		func(dish: Dictionary) -> bool: return dish.tier == PoisonFeast.Tier.GOLDEN
	)
	assert_eq(golden.size(), 1)
	assert_eq(golden[0].pos, Vector2.ZERO)

	game.dishes.assign(golden)
	game.positions[0] = Vector2.ZERO
	game.move_dirs[0] = Vector2.ZERO
	var pot_before: int = game.pot
	var before: int = game.score[0]
	game.tick(TICK)
	assert_eq(
		game.score[0],
		before + PoisonFeast.GOLDEN_BASE_POINTS + pot_before * PoisonFeast.GOLDEN_POT_MULTIPLIER
	)
	assert_eq(game.pot, 0)


func test_stagger_wears_off_and_slows_movement() -> void:
	var game := _make_game(2)
	game.dishes.clear()
	game.staggers[0] = 0.2
	game.positions[0] = Vector2.ZERO
	game.handle_input(0, {"mx": 1.0, "my": 0.0})
	game.tick(0.1)
	var slowed: float = (game.positions[0] as Vector2).x
	assert_almost_eq(slowed, PoisonFeast.MOVE_SPEED * PoisonFeast.STAGGER_MOVE_SCALE * 0.1, 0.01)
	game.tick(0.2)  # stagger expires during this step
	game.tick(0.1)
	var free_step: float = (game.positions[0] as Vector2).x - slowed
	assert_gt(free_step, PoisonFeast.MOVE_SPEED * 0.1 * 0.9)


func test_ranking_orders_by_score_with_ties_grouped() -> void:
	var game := _make_game(3)
	game.score[0] = 4
	game.score[1] = 9
	game.score[2] = 4
	var placements := game._rank_players()
	assert_eq(placements[0], [1])
	assert_eq(placements[1], [0, 2])
