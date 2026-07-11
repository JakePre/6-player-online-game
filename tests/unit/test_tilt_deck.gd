extends GutTest
## Tilt Deck sim (#794): the tilt-toward-crowd physics, edge falls, ramping
## sensitivity, cargo drops, edge coins, and coin-then-survival ranking.

const TICK := 1.0 / 30.0


func _game(count: int = 2) -> TiltDeck:
	var game := TiltDeck.new()
	game.meta = TiltDeck.make_meta()
	var player_slots: Array[int] = []
	for i in count:
		player_slots.append(i)
	game.setup(player_slots, 42)
	return game


func test_meta_and_catalog_swap() -> void:
	var meta := TiltDeck.make_meta()
	assert_eq(meta.id, &"tilt_deck")
	assert_eq(meta.max_players, 24)
	assert_false(meta.control_spec.is_empty(), "ships a #832 structured control spec")
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.instantiate(&"tilt_deck") is TiltDeck)
	assert_false(MinigameCatalog.is_registered(&"beat_bounce"), "Beat Bounce is retired (#794)")
	MinigameCatalog.clear()


func test_setup_spreads_players_and_stocks_edge_coins() -> void:
	var game := _game(4)
	for slot in 4:
		assert_lt(
			(game.positions[slot] as Vector2).length(), TiltDeck.DECK_RADIUS, "spawns on deck"
		)
	assert_eq(game.coins.size(), TiltDeck.MAX_COINS, "the floor is stocked with coins")
	for coin: Vector2 in game.coins:
		assert_gte(
			coin.length(),
			TiltDeck.COIN_EDGE_MIN * TiltDeck.DECK_RADIUS,
			"coins spawn out at the edge"
		)


## The whole point: a lopsided crowd leans the deck toward them.
func test_deck_leans_toward_the_crowd() -> void:
	var game := _game(4)
	for slot in 4:
		game.positions[slot] = Vector2(5.0, 0.0)  # everyone on the +x side
	for _i in 10:
		game._coin_accum = -INF  # keep coin waves out of the way
		game.tick(TICK)
	assert_gt((game.tilt as Vector2).x, 0.1, "the deck pitches toward the +x pile")
	assert_almost_eq((game.tilt as Vector2).y, 0.0, 0.05, "no lean on the balanced axis")


func test_a_balanced_deck_stays_flat() -> void:
	var game := _game(2)
	game.positions[0] = Vector2(5.0, 0.0)
	game.positions[1] = Vector2(-5.0, 0.0)  # perfectly opposed
	for _i in 10:
		game.tick(TICK)
	assert_almost_eq((game.tilt as Vector2).length(), 0.0, 0.05, "opposed weights cancel out")


func test_sliding_past_the_rim_eliminates() -> void:
	var game := _game(2)
	game.positions[0] = Vector2(TiltDeck.DECK_RADIUS + 2.0, 0.0)  # already overboard
	game.tick(TICK)
	assert_false(game._is_in(0), "slid off the rim — out")
	assert_eq(game.down_order, [[0]])
	assert_true(game._is_in(1), "the one still aboard survives")


func test_sensitivity_ramps_over_the_round() -> void:
	var game := _game()
	var early := game.sensitivity()
	game.elapsed = 30.0
	assert_gt(game.sensitivity(), early, "the deck gets touchier as the round wears on")


func test_edge_coin_is_banked_on_pickup() -> void:
	var game := _game(2)
	game.coins.clear()
	game.positions[0] = Vector2(5.0, 0.0)
	game.coins.append(Vector2(5.0, 0.0))  # a coin right under player 0
	game._coin_accum = -INF  # suppress a refill wave this tick
	game.tick(TICK)
	assert_eq(int(game.coins_of[0]), 1, "standing on a coin banks it")


func test_cargo_drops_on_the_timer_and_expires() -> void:
	var game := _game(2)
	assert_eq(game.cargo.size(), 0, "no cargo at the start")
	game.elapsed = TiltDeck.CARGO_FIRST_SEC + 1.0
	game._cargo_next = TiltDeck.CARGO_FIRST_SEC
	game.tick(TICK)
	assert_eq(game.cargo.size(), 1, "a crate crashes down when its timer lands")
	# It weights the deck: a crate far on +x with players at centre leans +x.
	game.cargo[0].pos = Vector2(TiltDeck.DECK_RADIUS * 0.65, 0.0)
	for slot in 2:
		game.positions[slot] = Vector2.ZERO
	for _i in 8:
		game.tick(TICK)
	assert_gt((game.tilt as Vector2).x, 0.05, "the crate drags the lean toward its side")
	# And it lifts once its life runs out — re-centre the crew each tick so the
	# crate's own lean doesn't slide anyone overboard and end the round early.
	for _i in int(ceil(TiltDeck.CARGO_LIFE_SEC / TICK)) + 2:
		for slot in 2:
			game.positions[slot] = Vector2.ZERO
		game.tick(TICK)
	assert_eq(game.cargo.size(), 0, "the crate is gone after its life")


func test_ranking_puts_survivors_first_then_by_coins() -> void:
	var game := _game(3)
	# Slot 2 fell; slots 0 and 1 survive with 0 richer than 1.
	game.down_order = [[2]]
	game.coins_of = {0: 5, 1: 2, 2: 9}
	var placements := game._rank_players()
	assert_eq(placements[0], [0], "richest survivor first")
	assert_eq(placements[1], [1], "then the poorer survivor")
	assert_eq(placements[2], [2], "the fallen rank last regardless of their coins")
	assert_eq(game.get_results().pickup_coins, {0: 5, 1: 2, 2: 9}, "coins double as pickups")


func test_last_afloat_ends_the_round() -> void:
	var game := _game(2)
	game.positions[0] = Vector2(TiltDeck.DECK_RADIUS + 2.0, 0.0)
	game.tick(TICK)
	assert_true(game.finished, "one player left ends it")
	assert_eq(game.get_results().placements[0], [1], "the survivor wins")


func test_snapshot_shape() -> void:
	var game := _game(2)
	var snapshot := game.get_snapshot()
	assert_eq((snapshot.players[0] as Array).size(), TiltDeck.PS_COUNT, "[x, y, coins]")
	assert_eq((snapshot.tilt as Array).size(), 2, "tilt vector rides the wire")
	assert_eq(snapshot.deck_radius, TiltDeck.DECK_RADIUS)
	assert_eq(snapshot.fallen, [])
