extends GutTest
## Bomb Courier server simulation (M10-15): pickup/carry/deliver, fuse
## detonation + stun, defuse, the swap-dash, and score ranking.

const TICK := 1.0 / 30.0


func _make_game(player_count: int) -> BombCourier:
	var game := BombCourier.new()
	game.meta = BombCourier.make_meta()
	var slots: Array[int] = []
	for i in player_count:
		slots.append(i)
	game.setup(slots, 42)
	return game


## Gives `slot` a fresh package with a controlled fuse, parked at `pos`.
func _hand_package(game: BombCourier, slot: int, fuse: float, pos: Vector2) -> int:
	var id: int = game._next_id
	game._packages[id] = {"pos": pos, "fuse": fuse}
	game._next_id += 1
	game.carried[slot] = id
	game.positions[slot] = pos
	return id


func test_setup_stocks_the_pile_with_zero_scores() -> void:
	var game := _make_game(3)
	assert_eq(game._packages.size(), BombCourier.MAX_PILE)
	for slot in 3:
		assert_eq(game.score[slot], 0)
		assert_eq(game.carried[slot], -1)


func test_walking_onto_a_loose_package_picks_it_up() -> void:
	var game := _make_game(3)
	var id: int = game._packages.keys()[0]
	game.positions[0] = game._packages[id].pos
	game.move_dirs[0] = Vector2.ZERO
	game.tick(TICK)
	assert_eq(game.carried[0], id)


func test_delivery_scores_more_with_fuse_to_spare() -> void:
	var game := _make_game(3)
	_hand_package(game, 0, 5.0, BombCourier.DEPOT_POS)
	game.tick(TICK)
	assert_eq(game.carried[0], -1)
	assert_eq(game.score[0], BombCourier.DELIVER_BASE + 4 * BombCourier.DELIVER_FUSE_BONUS)


func test_fuse_expiry_detonates_stuns_and_penalizes_the_carrier() -> void:
	var game := _make_game(3)
	var id := _hand_package(game, 0, 0.05, Vector2.ZERO)
	game.tick(TICK)
	assert_eq(game.carried[0], -1)
	assert_false(game._packages.has(id))
	assert_eq(game.score[0], -BombCourier.DETONATE_PENALTY)
	assert_gt(float(game.staggers[0]), 0.0)


func test_defuse_zone_banks_a_small_score() -> void:
	var game := _make_game(3)
	_hand_package(game, 0, 3.0, BombCourier.DEFUSE_POS)
	game.tick(TICK)
	assert_eq(game.carried[0], -1)
	assert_eq(game.score[0], BombCourier.DEFUSE_POINTS)


func test_swap_dash_trades_packages_with_a_rival() -> void:
	var game := _make_game(3)
	var mine := _hand_package(game, 0, 6.0, Vector2.ZERO)
	var theirs := _hand_package(game, 1, 1.0, Vector2(0.5, 0.0))
	game.dash_timers[0] = BombCourier.DASH_SEC
	game.dash_dirs[0] = Vector2(1.0, 0.0)
	game._resolve_dash_swaps()
	assert_eq(game.carried[0], theirs, "dashed courier takes the rival's hot package")
	assert_eq(game.carried[1], mine)


func test_empty_dash_steals_a_carried_package() -> void:
	var game := _make_game(3)
	var theirs := _hand_package(game, 1, 4.0, Vector2(0.5, 0.0))
	game.positions[0] = Vector2.ZERO
	game.carried[0] = -1
	game.dash_timers[0] = BombCourier.DASH_SEC
	game._resolve_dash_swaps()
	assert_eq(game.carried[0], theirs)
	assert_eq(game.carried[1], -1)


func test_ranking_orders_by_score_with_ties_grouped() -> void:
	var game := _make_game(3)
	game.score[0] = 5
	game.score[1] = 9
	game.score[2] = 5
	var placements := game._rank_players()
	assert_eq(placements[0], [1])
	assert_eq(placements[1], [0, 2])
