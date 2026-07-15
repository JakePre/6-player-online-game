extends GutTest
## Payload Race (#932, reworked from the shared-cart Cart Push #175): two lanes,
## each team pushes its OWN cart by alternating ◀▶ beside it (sqrt-diminished by
## the crowd), monotonic per-lane progress, dash-shove sabotage, first-home /
## farther-on-timeout / dead-heat-ties ranking.

const TICK := 1.0 / 30.0


func _game(player_slots: Array[int] = [0, 1, 2, 3]) -> CartPush:
	var game := CartPush.new()
	game.meta = CartPush.make_meta()
	game.setup(player_slots, 42)
	return game


## Parks `slot` right at its own cart, in push reach.
func _at_own_cart(game: CartPush, slot: int) -> void:
	var team_index: int = game._team_of(slot)
	game.positions[slot] = game.cart_pos(team_index)
	game.move_dirs[slot] = Vector2.ZERO


## Parks `slot` far from both carts so it contributes nothing.
func _park(game: CartPush, slot: int) -> void:
	game.positions[slot] = Vector2(0.0, 0.0)
	game.move_dirs[slot] = Vector2.ZERO


## Sends `count` valid ◀▶ alternations from `slot` (phase flips each call).
func _push_n(game: CartPush, slot: int, count: int) -> void:
	for i in count:
		game.handle_input(slot, {"push": i % 2})


func test_setup_splits_even_teams_with_both_carts_at_the_start() -> void:
	var game := _game()
	assert_eq((game.teams[0] as Array).size(), 2)
	assert_eq((game.teams[1] as Array).size(), 2)
	assert_eq(game.progress[0], 0.0)
	assert_eq(game.progress[1], 0.0)
	for slot: int in game.slots:
		assert_eq(float(game.staggers[slot]), 0.0)


func test_max_players_raised_to_eight() -> void:
	assert_eq(CartPush.make_meta().max_players, 8)


func test_control_spec_present() -> void:
	assert_false(
		CartPush.make_meta().control_spec.is_empty(), "ships a #832 structured control spec"
	)


func test_setup_splits_four_v_four_within_arena_at_eight_players() -> void:
	var player_slots: Array[int] = []
	for i in 8:
		player_slots.append(i)
	var game := _game(player_slots)
	assert_eq((game.teams[0] as Array).size(), 4)
	assert_eq((game.teams[1] as Array).size(), 4)
	for slot in 8:
		var pos: Vector2 = game.positions[slot]
		assert_lt(absf(pos.y), CartPush.ARENA_HALF, "spawn row stays inside the arena")


func test_alternation_at_own_cart_advances_that_cart() -> void:
	var game := _game()
	for slot: int in game.slots:
		_park(game, slot)
	var pusher: int = game.teams[0][0]
	_at_own_cart(game, pusher)
	_push_n(game, pusher, 1)
	assert_almost_eq(game.progress[0], CartPush.PUSH_PER_ALTERNATION, 0.001)
	assert_eq(game.progress[1], 0.0, "the other lane's cart never moved")


func test_holding_one_phase_does_not_push() -> void:
	var game := _game()
	for slot: int in game.slots:
		_park(game, slot)
	var pusher: int = game.teams[0][0]
	_at_own_cart(game, pusher)
	game.handle_input(pusher, {"push": 0})  # first phase counts (differs from -1)
	var after_one := float(game.progress[0])
	game.handle_input(pusher, {"push": 0})  # same phase: no alternation, no push
	game.handle_input(pusher, {"push": 0})
	assert_almost_eq(game.progress[0], after_one, 0.001, "only alternations count")


func test_push_only_counts_beside_your_own_cart() -> void:
	var game := _game()
	for slot: int in game.slots:
		_park(game, slot)  # off in the middle of the arena, away from the carts
	var pusher: int = game.teams[0][0]
	_push_n(game, pusher, 4)
	assert_eq(game.progress[0], 0.0, "out of reach of the cart, mashing does nothing")


func test_crowd_diminishes_each_pushers_contribution() -> void:
	var player_slots: Array[int] = []
	for i in 8:
		player_slots.append(i)
	var game := _game(player_slots)
	for slot: int in game.slots:
		_park(game, slot)
	# Pack all four of team 0 onto their cart, then push once.
	for slot: int in game.teams[0]:
		_at_own_cart(game, slot)
	var lead: int = game.teams[0][0]
	_push_n(game, lead, 1)
	assert_almost_eq(
		game.progress[0],
		CartPush.PUSH_PER_ALTERNATION / sqrt(4.0),
		0.001,
		"four sharing the cart each add ~half a lone pusher"
	)


func test_progress_is_monotonic_and_capped_at_the_finish() -> void:
	var game := _game()
	for slot: int in game.slots:
		_park(game, slot)
	var pusher: int = game.teams[0][0]
	game.progress[0] = CartPush.TRACK_LENGTH - 0.1
	_at_own_cart(game, pusher)
	_push_n(game, pusher, 1)
	assert_almost_eq(game.progress[0], CartPush.TRACK_LENGTH, 0.001, "clamped at the finish")


func test_staggered_pushers_cannot_push() -> void:
	var game := _game()
	for slot: int in game.slots:
		_park(game, slot)
	var pusher: int = game.teams[0][0]
	_at_own_cart(game, pusher)
	game.staggers[pusher] = 1.0
	_push_n(game, pusher, 3)
	assert_eq(game.progress[0], 0.0, "a staggered pusher's mash is ignored")


func test_shove_winds_up_then_knocks_back_and_staggers() -> void:
	var game := _game()
	for slot: int in game.slots:
		_park(game, slot)
	var shover: int = game.teams[0][0]
	var victim: int = game.teams[1][0]
	game.positions[shover] = Vector2.ZERO
	game.positions[victim] = Vector2(1.0, 0.0)
	game.handle_input(shover, {"shove": true})
	game.tick(TICK)
	assert_eq(float(game.staggers[victim]), 0.0, "windup has not landed yet")
	game.tick(CartPush.SHOVE_WINDUP_SEC)
	assert_gt(float(game.staggers[victim]), 0.0, "shove landed after the windup")
	assert_gt((game.positions[victim] as Vector2).x, 1.0, "knocked away")
	assert_gt(float(game.shove_cooldowns[shover]), 0.0)
	# On cooldown: another shove input is refused.
	game.handle_input(shover, {"shove": true})
	assert_eq(float(game.shove_windups[shover]), 0.0)


func test_cart_reaching_the_finish_ends_with_that_teams_win() -> void:
	var game := _game()
	game.progress[0] = CartPush.TRACK_LENGTH
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements[0], game.teams[0])


func test_timeout_ranks_by_farther_cart_and_a_dead_heat_ties() -> void:
	var game := _game()
	game.progress[0] = 3.0
	game.progress[1] = 1.0
	assert_eq(game._rank_players()[0], game.teams[0], "the farther cart's team leads")
	game.progress[1] = 3.0
	assert_eq(game._rank_players(), [game.slots], "a dead heat ties everyone")


func test_snapshot_exposes_carts_teams_and_typed_player_rows() -> void:
	var game := _game()
	var snap := game.get_snapshot()
	assert_true(snap.has("carts"))
	assert_eq((snap.carts as Array).size(), 2)
	assert_true(snap.has("teams"))
	for slot: int in game.slots:
		var row: Array = snap.players[slot]
		assert_eq(row.size(), CartPush.PLAYER_SCHEMA.size(), "row width matches the schema")
		for i in row.size():
			assert_eq(typeof(row[i]), int(CartPush.PLAYER_SCHEMA[i]), "slot %d typed" % i)
