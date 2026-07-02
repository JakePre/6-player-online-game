extends GutTest
## Hot Potato server simulation (M4-02): bomb transfer + cooldown, carrier
## speed buff, fuse eliminations with respawn, blast-cap and lone-survivor
## endings, hold-time ranking, movement, and snapshot shape.

const TICK := 1.0 / 30.0


func _make_game(player_count: int) -> HotPotato:
	var game := HotPotato.new()
	game.meta = HotPotato.make_meta()
	var slots: Array[int] = []
	for i in player_count:
		slots.append(i)
	game.setup(slots, 42)
	return game


## Parks every player in a distinct corner region so nobody overlaps.
func _spread_players(game: HotPotato) -> void:
	for i in game.slots.size():
		var x := -HotPotato.ARENA_HALF + 3.0 * i
		game.positions[game.slots[i]] = Vector2(x, HotPotato.ARENA_HALF * float(i % 2 * 2 - 1))


## First alive slot that is not `excluded` (slot order).
func _first_other(game: HotPotato, excluded: int) -> int:
	for slot: int in game.alive_slots():
		if slot != excluded:
			return slot
	return -1


func test_setup_picks_carrier_and_fuse_in_range() -> void:
	var game := _make_game(4)
	assert_true(game.carrier in game.slots, "carrier is one of the players")
	assert_between(game.fuse, HotPotato.FUSE_MIN_SEC, HotPotato.FUSE_MAX_SEC)
	assert_eq(game.blasts, 0)
	for slot in 4:
		assert_eq(game.hold_time[slot], 0.0)
		assert_true(game.is_alive(slot))
		var pos: Vector2 = game.positions[slot]
		assert_lt(pos.length(), HotPotato.ARENA_HALF, "spawn in arena")


func test_bomb_transfers_on_contact() -> void:
	var game := _make_game(3)
	_spread_players(game)
	var victim := _first_other(game, game.carrier)
	game.positions[victim] = game.positions[game.carrier] + Vector2(HotPotato.PLAYER_RADIUS, 0.0)
	game.tick(TICK)
	assert_eq(game.carrier, victim, "contact passes the bomb")
	assert_gt(game.transfer_cooldown, 0.0, "transfer arms the cooldown")


func test_transfer_cooldown_blocks_ping_pong() -> void:
	var game := _make_game(3)
	_spread_players(game)
	var first: int = game.carrier
	var victim := _first_other(game, first)
	game.positions[victim] = game.positions[first]
	game.tick(TICK)
	assert_eq(game.carrier, victim)
	for _i in 10:
		game.tick(TICK)
	assert_eq(game.carrier, victim, "bomb stays put during the cooldown")
	for _i in 20:
		game.tick(TICK)
	assert_eq(game.carrier, first, "bomb passes back once the cooldown expires")


func test_carrier_moves_ten_percent_faster() -> void:
	var game := _make_game(3)
	_spread_players(game)
	var chaser: int = game.carrier
	var runner := _first_other(game, chaser)
	game.positions[chaser] = Vector2(-HotPotato.ARENA_HALF, -HotPotato.ARENA_HALF)
	game.positions[runner] = Vector2(-HotPotato.ARENA_HALF, HotPotato.ARENA_HALF)
	game.handle_input(chaser, {"mx": 1.0, "my": 0.0})
	game.handle_input(runner, {"mx": 1.0, "my": 0.0})
	game.tick(0.1)
	var chaser_dx: float = (game.positions[chaser] as Vector2).x + HotPotato.ARENA_HALF
	var runner_dx: float = (game.positions[runner] as Vector2).x + HotPotato.ARENA_HALF
	assert_almost_eq(chaser_dx, HotPotato.MOVE_SPEED * HotPotato.CARRIER_SPEED_MULT * 0.1, 0.001)
	assert_almost_eq(runner_dx, HotPotato.MOVE_SPEED * 0.1, 0.001)


func test_fuse_blast_eliminates_carrier_and_respawns_bomb() -> void:
	var game := _make_game(4)
	_spread_players(game)
	var doomed: int = game.carrier
	game.fuse = 0.001
	game.tick(TICK)
	assert_false(game.is_alive(doomed), "carrier eliminated at fuse zero")
	assert_eq(game.eliminated.size(), 1)
	assert_eq(game.eliminated[0], doomed)
	assert_eq(game.blasts, 1)
	assert_false(game.finished, "round continues after the first blast")
	assert_true(game.is_alive(game.carrier), "bomb respawned on a survivor")
	assert_ne(game.carrier, doomed)
	assert_between(game.fuse, HotPotato.FUSE_MIN_SEC - TICK, HotPotato.FUSE_MAX_SEC)


func test_three_blasts_finish_the_round() -> void:
	var game := _make_game(6)
	_spread_players(game)
	for blast in 3:
		assert_false(game.finished, "alive before blast %d" % blast)
		game.fuse = 0.001
		game.tick(TICK)
	assert_eq(game.blasts, 3)
	assert_true(game.finished, "third blast ends the round")
	var placements: Array = game.get_results().placements
	assert_eq(placements.size(), 4, "3 survivors tied at ~0 hold + 3 solo eliminated groups")
	assert_eq(placements[1], [game.eliminated[2]], "last eliminated ranks best of the dead")
	assert_eq(placements[3], [game.eliminated[0]], "first eliminated ranks last")
	assert_eq(game.get_results().pickup_coins, {}, "placement-only game (SPEC $5)")


func test_finishes_early_when_one_player_remains() -> void:
	var game := _make_game(3)
	_spread_players(game)
	game.fuse = 0.001
	game.tick(TICK)
	assert_false(game.finished, "two players still alive")
	game.fuse = 0.001
	game.tick(TICK)
	assert_true(game.finished, "lone survivor ends the round before the blast cap")
	assert_eq(game.blasts, 2)
	var placements: Array = game.get_results().placements
	assert_eq(placements.size(), 3)
	assert_eq((placements[0] as Array).size(), 1, "survivor alone on top")


func test_ranking_survivors_by_hold_time_then_elimination_order() -> void:
	var game := _make_game(5)
	_spread_players(game)
	game.eliminated.assign([4, 3])
	game.hold_time = {0: 2.01, 1: 5.0, 2: 2.04, 3: 6.0, 4: 3.0}
	# Park the bomb on an eliminated slot so the finishing tick's hold accrual
	# cannot disturb the survivor hold times under test.
	game.carrier = 3
	game.duration_override = 0.05
	game.tick(0.1)
	assert_true(game.finished)
	var placements: Array = game.get_results().placements
	var top: Array = placements[0]
	top.sort()
	assert_eq(top, [0, 2], "snapped 2.0s holds tie for first")
	assert_eq(placements[1], [1], "longer-holding survivor ranks below")
	assert_eq(placements[2], [3], "later elimination beats earlier")
	assert_eq(placements[3], [4])


func test_movement_follows_input_and_clamps_to_arena() -> void:
	var game := _make_game(3)
	_spread_players(game)
	game.handle_input(0, {"mx": 1.0, "my": 0.0})
	for _i in 240:
		if game.finished:
			break
		game.tick(TICK)
	assert_eq((game.positions[0] as Vector2).x, HotPotato.ARENA_HALF)


func test_input_capped_and_ignored_for_eliminated_players() -> void:
	var game := _make_game(3)
	game.handle_input(0, {"mx": 100.0, "my": 100.0})
	assert_almost_eq((game.move_dirs[0] as Vector2).length(), 1.0, 0.001)
	game.eliminated.assign([1])
	game.handle_input(1, {"mx": 1.0, "my": 0.0})
	assert_eq(game.move_dirs[1], Vector2.ZERO, "eliminated players cannot move")


func test_snapshot_shape_and_snapping() -> void:
	var game := _make_game(4)
	game.positions[0] = Vector2(1.2345, -2.3456)
	game.hold_time[0] = 1.2345
	game.fuse = 9.8765
	game.eliminated.assign([3])
	var snapshot := game.get_snapshot()
	assert_eq(snapshot.players.size(), 4, "eliminated players stay visible")
	assert_eq(snapshot.players[0], [1.23, -2.35])
	assert_almost_eq(float(snapshot.holds[0]), 1.2, 0.0001, "hold snapped to 0.1")
	assert_almost_eq(float(snapshot.fuse), 9.9, 0.0001, "fuse snapped to 0.1")
	assert_true(snapshot.carrier in game.slots)
	assert_eq(snapshot.alive, [0, 1, 2])
