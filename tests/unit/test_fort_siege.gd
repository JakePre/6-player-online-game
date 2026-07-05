extends GutTest
## Fort Siege (PHASE2.md $4 #29): gate walls out attackers, battering and
## breaching, contested capture, the mid-game swap, and time-vs-depth
## ranking.

const TICK := 1.0 / 30.0


func _game(player_slots: Array[int] = [0, 1, 2, 3]) -> FortSiege:
	var game := FortSiege.new()
	game.meta = FortSiege.make_meta()
	game.setup(player_slots, 42)
	return game


func _raider(game: FortSiege) -> int:
	return game.teams[game.attacking][0]


func _defender(game: FortSiege) -> int:
	return game.teams[1 - game.attacking][0]


func _breach(game: FortSiege) -> void:
	game.gate_hp = 0.0


func test_meta_catalog_and_even_rule() -> void:
	var meta := FortSiege.make_meta()
	assert_eq(meta.id, &"fort_siege")
	assert_eq(meta.category, MinigameMeta.Category.TEAM)
	assert_eq(meta.max_players, 12)
	assert_true(meta.even_players, "never drafted at 3 or 5 (#178)")
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.instantiate(&"fort_siege") is FortSiege)
	MinigameCatalog.clear()


## No-crowd fairness (M15 12-cap, ADR 003 addendum): 6v6 splits evenly and
## every spawn stays within the arena — the gate/core mechanics have zero
## exclusivity (more attackers only ever helps, never contends), so the only
## real constraint is spawn geometry.
func test_setup_splits_six_v_six_within_arena_at_twelve_players() -> void:
	var player_slots: Array[int] = []
	for i in 12:
		player_slots.append(i)
	var game := _game(player_slots)
	assert_eq((game.teams[0] as Array).size(), 6)
	assert_eq((game.teams[1] as Array).size(), 6)
	for slot in 12:
		var pos: Vector2 = game.positions[slot]
		assert_lt(absf(pos.x), FortSiege.ARENA_HALF, "spawn row stays inside the arena")


## The gate-battering mechanic has no per-node cap: every attacker touching
## the gate contributes, so a full team of 6 batters strictly faster than a
## team of 2.
func test_more_attackers_batter_the_gate_faster() -> void:
	var small := _game([0, 1, 2, 3] as Array[int])  # 2v2
	for raider: int in small.teams[small.attacking]:
		small.positions[raider] = Vector2(0.0, FortSiege.GATE_Y)
	small.tick(TICK)
	var small_damage := FortSiege.GATE_MAX_HP - small.gate_hp

	var player_slots: Array[int] = []
	for i in 12:
		player_slots.append(i)
	var big := _game(player_slots)  # 6v6
	for raider: int in big.teams[big.attacking]:
		big.positions[raider] = Vector2(0.0, FortSiege.GATE_Y)
	big.tick(TICK)
	var big_damage := FortSiege.GATE_MAX_HP - big.gate_hp

	assert_gt(big_damage, small_damage, "a full 6-attacker team batters faster than 2")


func test_setup_walls_attackers_out() -> void:
	var game := _game()
	assert_true(game.team_mode)
	var raider := _raider(game)
	assert_gt((game.positions[raider] as Vector2).y, FortSiege.GATE_Y, "raiders start outside")
	assert_lt(
		(game.positions[_defender(game)] as Vector2).y, FortSiege.GATE_Y, "defenders start inside"
	)
	# A raider pushing south sticks at the wall.
	game.handle_input(raider, {"mx": 0.0, "my": -1.0})
	for _i in 90:
		game.tick(TICK)
	assert_almost_eq(
		(game.positions[raider] as Vector2).y,
		FortSiege.GATE_Y + FortSiege.PLAYER_RADIUS,
		0.01,
		"the standing gate walls raiders out"
	)


func test_defenders_pass_the_gate_freely() -> void:
	var game := _game()
	var defender := _defender(game)
	game.positions[defender] = Vector2(0.0, FortSiege.GATE_Y - 1.0)
	game.handle_input(defender, {"mx": 0.0, "my": 1.0})
	for _i in 60:
		game.tick(TICK)
	assert_gt((game.positions[defender] as Vector2).y, FortSiege.GATE_Y, "defenders sortie freely")


func test_battering_drains_and_breaches_the_gate() -> void:
	var game := _game()
	var raider := _raider(game)
	game.positions[raider] = Vector2(0.0, FortSiege.GATE_Y + FortSiege.PLAYER_RADIUS)
	var before := game.gate_hp
	game.tick(TICK)
	assert_lt(game.gate_hp, before, "contact batters the gate")
	_breach(game)
	game.handle_input(raider, {"mx": 0.0, "my": -1.0})
	for _i in 60:
		game.tick(TICK)
	assert_lt(
		(game.positions[raider] as Vector2).y, FortSiege.GATE_Y, "a breached gate lets them in"
	)


func test_contested_core_stalls_uncontested_fills() -> void:
	var game := _game()
	_breach(game)
	var raider := _raider(game)
	var defender := _defender(game)
	game.positions[raider] = FortSiege.CORE_POS
	game.positions[defender] = FortSiege.CORE_POS
	game.tick(TICK)
	assert_eq(game.capture, 0.0, "a defender on the core stalls the meter")
	game.positions[defender] = Vector2(5.0, 5.0)
	game.tick(TICK)
	assert_gt(game.capture, 0.0, "uncontested holding fills it")


func test_capture_records_time_and_swaps_sides() -> void:
	var game := _game()
	_breach(game)
	game.capture = 1.0 - TICK / FortSiege.CAPTURE_SEC
	game.positions[_raider(game)] = FortSiege.CORE_POS
	game.tick(TICK)
	assert_true(game.runs[0].captured, "first siege resolved as a capture")
	assert_eq(game.phase, FortSiege.Phase.SWAP)
	var swap_ticks := int(ceil(FortSiege.SWAP_SEC / TICK)) + 1
	for _i in swap_ticks:
		game.tick(TICK)
	assert_eq(game.attacking, 1, "sides swap for the second siege")
	assert_eq(game.gate_hp, FortSiege.GATE_MAX_HP, "fresh gate for the second siege")
	assert_eq(game.capture, 0.0)


func test_shove_bounces_attackers() -> void:
	var game := _game()
	var raider := _raider(game)
	var defender := _defender(game)
	game.positions[defender] = Vector2(0.0, 0.0)
	game.positions[raider] = Vector2(0.5, 0.0)
	game.handle_input(defender, {"act": true})
	assert_gt((game.knocks[raider] as Vector2).length(), 0.0, "shove knocks the raider")
	assert_gt(float(game.shove_cooldowns[defender]), 0.0, "shove starts its cooldown")


func test_attackers_cannot_shove() -> void:
	var game := _game()
	var raider := _raider(game)
	var defender := _defender(game)
	game.positions[raider] = Vector2(0.0, 0.0)
	game.positions[defender] = Vector2(0.5, 0.0)
	game.handle_input(raider, {"act": true})
	assert_eq((game.knocks[defender] as Vector2).length(), 0.0, "storming has no shove")


func test_faster_capture_wins() -> void:
	var game := _game()
	game.runs = [
		{"captured": true, "time": 20.0, "progress": 24.0},
		{"captured": true, "time": 12.0, "progress": 24.0},
	]
	assert_eq(game._rank_players(), [game.teams[1], game.teams[0]])


func test_lone_captor_beats_non_captor() -> void:
	var game := _game()
	game.runs = [
		{"captured": false, "time": FortSiege.SIEGE_SEC, "progress": 23.9},
		{"captured": true, "time": 39.0, "progress": 24.0},
	]
	assert_eq(game._rank_players(), [game.teams[1], game.teams[0]])


func test_two_failed_runs_compare_depth_and_tie() -> void:
	var game := _game()
	game.runs = [
		{"captured": false, "time": FortSiege.SIEGE_SEC, "progress": 8.0},
		{"captured": false, "time": FortSiege.SIEGE_SEC, "progress": 3.0},
	]
	assert_eq(game._rank_players(), [game.teams[0], game.teams[1]])
	game.runs[1] = {"captured": false, "time": FortSiege.SIEGE_SEC, "progress": 8.0}
	assert_eq(game._rank_players(), [game.slots], "identical runs are a full tie")


func test_snapshot_shape_and_junk_input() -> void:
	var game := _game()
	game.handle_input(0, {"act": "garbage", "mx": "junk"})
	game.handle_input(99, {"act": true})
	var snapshot := game.get_snapshot()
	assert_eq(snapshot.players.size(), 4)
	assert_eq(snapshot.teams.size(), 2)
	assert_eq(snapshot.times, [-1.0, -1.0])
	assert_eq(int(snapshot.attacking), 0)
	assert_almost_eq(float(snapshot.gate), 1.0, 0.001)
