extends GutTest
## Cart Push (SPEC $7 #13): pushing needs contact + forward input, unattended
## carts roll back, blockers stall, first cart home wins, timeout ranks by
## progress.

const TICK := 1.0 / 30.0


func _game(player_slots: Array[int] = [0, 1, 2, 3]) -> CartPush:
	var game := CartPush.new()
	game.meta = CartPush.make_meta()
	game.setup(player_slots, 42)
	return game


## Puts `slot` right behind its team's cart, pushing forward.
func _push(game: CartPush, team_index: int, slot: int) -> void:
	var lane := -CartPush.LANE_Y if team_index == 0 else CartPush.LANE_Y
	game.positions[slot] = Vector2(float(game.cart_x[team_index]) - 1.0, lane)
	game.handle_input(slot, {"mx": 1.0, "my": 0.0})


func test_meta() -> void:
	var meta := CartPush.make_meta()
	assert_eq(meta.id, &"cart_push")
	assert_eq(meta.category, MinigameMeta.Category.TEAM)
	assert_eq(meta.min_players, 4)


func test_registered_in_catalog() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.instantiate(&"cart_push") is CartPush)
	MinigameCatalog.clear()


func test_team_shapes() -> void:
	for count: int in [4, 5, 6]:
		var player_slots: Array[int] = []
		for slot in count:
			player_slots.append(slot)
		var game := _game(player_slots)
		assert_true(game.team_mode)
		assert_eq(game.teams.size(), 2)
		var sizes := [game.teams[0].size(), game.teams[1].size()]
		sizes.sort()
		assert_eq(sizes, [count / 2, count - count / 2], "%d players" % count)


func test_pushing_advances_the_cart() -> void:
	var game := _game()
	var before: float = game.cart_x[0]
	_push(game, 0, game.teams[0][0])
	game.tick(TICK)
	assert_gt(float(game.cart_x[0]), before)


func test_pushing_needs_forward_input() -> void:
	var game := _game()
	game.cart_x[0] = 0.0
	var slot: int = game.teams[0][0]
	game.positions[slot] = Vector2(float(game.cart_x[0]) - 1.0, -CartPush.LANE_Y)
	game.handle_input(slot, {"mx": 0.0, "my": 0.0})
	var before: float = game.cart_x[0]
	game.tick(TICK)
	assert_lt(float(game.cart_x[0]), before, "idle contact does not push; cart rolls back")


func test_more_pushers_move_faster_up_to_cap() -> void:
	var solo := _game([0, 1, 2, 3, 4, 5] as Array[int])
	_push(solo, 0, solo.teams[0][0])
	solo.tick(TICK)
	var solo_gain := float(solo.cart_x[0]) - CartPush.TRACK_START
	var trio := _game([0, 1, 2, 3, 4, 5] as Array[int])
	for slot: int in trio.teams[0]:
		_push(trio, 0, slot)
	trio.tick(TICK)
	var trio_gain := float(trio.cart_x[0]) - CartPush.TRACK_START
	assert_gt(trio_gain, solo_gain)


func test_unattended_cart_rolls_back() -> void:
	var game := _game()
	game.cart_x[0] = 0.0
	game.tick(TICK)
	assert_lt(float(game.cart_x[0]), 0.0)
	game.cart_x[0] = CartPush.TRACK_START
	game.tick(TICK)
	assert_eq(float(game.cart_x[0]), CartPush.TRACK_START, "never below the start")


func test_opponent_in_front_blocks_the_cart() -> void:
	var game := _game()
	var pusher: int = game.teams[0][0]
	_push(game, 0, pusher)
	var blocker: int = game.teams[1][0]
	game.positions[blocker] = Vector2(float(game.cart_x[0]) + 1.0, -CartPush.LANE_Y)
	var before: float = game.cart_x[0]
	game.tick(TICK)
	assert_almost_eq(float(game.cart_x[0]), before, 0.5, "blocked cart neither advances nor rolls")
	assert_eq(game.blockers_of(0), 1)


func test_first_cart_at_depot_wins() -> void:
	var game := _game()
	game.cart_x[1] = CartPush.TRACK_END - 0.01
	_push(game, 1, game.teams[1][0])
	game.tick(TICK)
	assert_true(game.finished)
	var results := game.get_results()
	assert_true(results.team_mode)
	assert_eq(results.placements, [game.teams[1], game.teams[0]])
	assert_eq(results.pickup_coins, {})


func test_timeout_ranks_by_cart_progress() -> void:
	var game := _game()
	game.cart_x[0] = 3.0
	game.cart_x[1] = -2.0
	game.duration_override = game.elapsed + TICK
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements[0], game.teams[0])


func test_timeout_dead_heat_is_a_full_tie() -> void:
	var game := _game()
	game.duration_override = game.elapsed + TICK
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements.size(), 1)
	assert_eq(game.get_results().placements[0].size(), 4)


func test_snapshot_shape() -> void:
	var game := _game()
	var snapshot := game.get_snapshot()
	assert_eq(snapshot.players.size(), 4)
	assert_eq(snapshot.carts.size(), 2)
	assert_eq(snapshot.track, [CartPush.TRACK_START, CartPush.TRACK_END])
	assert_eq(snapshot.teams.size(), 2)
