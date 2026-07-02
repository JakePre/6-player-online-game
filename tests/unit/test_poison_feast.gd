extends GutTest
## Poison Feast server simulation (M4-14, SPEC $7 #15): movement, dish
## scoring, the hidden saboteur's poison credit, and ranking.

const TICK := 1.0 / 30.0


func _make_game(player_count: int) -> PoisonFeast:
	var game := PoisonFeast.new()
	game.meta = PoisonFeast.make_meta()
	var slots: Array[int] = []
	for i in player_count:
		slots.append(i)
	game.setup(slots, 42)
	return game


func test_setup_spreads_players_zero_scores_and_assigns_one_saboteur() -> void:
	var game := _make_game(4)
	for slot in 4:
		assert_eq(game.score[slot], 0)
		assert_lt(
			(game.positions[slot] as Vector2).length(), PoisonFeast.ARENA_HALF, "spawn in arena"
		)
	assert_true(game.saboteur in game.slots)


func test_movement_follows_input_and_clamps_to_arena() -> void:
	var game := _make_game(4)
	game.dishes.clear()
	game.handle_input(0, {"mx": 1.0, "my": 0.0})
	for _i in 240:
		game.tick(TICK)
		game.dishes.clear()  # Ignore pickups; this test is about movement.
	assert_eq((game.positions[0] as Vector2).x, PoisonFeast.ARENA_HALF)


func test_eating_a_safe_dish_awards_points() -> void:
	var game := _make_game(4)
	game.dishes = [{"pos": game.positions[0], "poisoned": false}]
	game.tick(TICK)
	assert_eq(game.score[0], PoisonFeast.SAFE_POINTS)
	assert_true(game.dishes.is_empty())


func test_eating_a_poisoned_dish_penalizes_eater_and_credits_saboteur() -> void:
	var game := _make_game(4)
	game.saboteur = 1
	game.dishes = [{"pos": game.positions[0], "poisoned": true}]
	game.tick(TICK)
	assert_eq(game.score[0], -PoisonFeast.POISON_PENALTY)
	assert_eq(game.score[1], PoisonFeast.POISON_CREDIT)


func test_saboteur_eating_their_own_poisoned_dish_gets_no_self_credit() -> void:
	var game := _make_game(4)
	game.saboteur = 0
	game.dishes = [{"pos": game.positions[0], "poisoned": true}]
	game.tick(TICK)
	assert_eq(game.score[0], -PoisonFeast.POISON_PENALTY)


func test_exactly_three_dishes_are_poisoned_across_the_full_spawn_budget() -> void:
	var game := _make_game(5)
	assert_eq(game._poisoned_spawn_indices.size(), PoisonFeast.POISONED_COUNT)
	for index: int in game._poisoned_spawn_indices:
		assert_between(index, 0, PoisonFeast.DISH_COUNT - 1)


func test_ranking_groups_tied_scores() -> void:
	var game := _make_game(4)
	game.score = {0: 3, 1: 7, 2: 3, 3: 0}
	assert_eq(game._rank_players(), [[1], [0, 2], [3]])


func test_snapshot_lists_players_and_dishes_without_revealing_poison() -> void:
	var game := _make_game(4)
	game.dishes = [{"pos": Vector2(1.0, 2.0), "poisoned": true}]
	var snapshot := game.get_snapshot()
	assert_eq(snapshot.players.size(), 4)
	assert_eq(snapshot.dishes.size(), 1)
	var dish_entry: Array = snapshot.dishes[0]
	assert_eq(dish_entry.size(), 2, "x, y only — no poisoned flag leaked to clients")
