extends GutTest
## Fort Siege (PHASE2.md $4 #29; #1028 relic rework): gate walls out
## attackers, battering and breaching, the relic heist (grab, carry-slow,
## shove-drop, defender return, escape), the mid-game swap, and time-vs-depth
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
	assert_false(meta.control_spec.is_empty(), "ships a #832 structured control spec")
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


## Battering is now an explicit swing (#808), but still has no per-node cap:
## every attacker at the gate contributes a swing, so a full team of 6 lands
## strictly more damage per volley than a team of 2.
func test_more_attackers_batter_the_gate_faster() -> void:
	var small := _game([0, 1, 2, 3] as Array[int])  # 2v2
	for raider: int in small.teams[small.attacking]:
		small.positions[raider] = Vector2(0.0, FortSiege.GATE_Y)
		small.handle_input(raider, {"act": true})
	var small_damage := FortSiege.GATE_MAX_HP - small.gate_hp

	var player_slots: Array[int] = []
	for i in 12:
		player_slots.append(i)
	var big := _game(player_slots)  # 6v6
	for raider: int in big.teams[big.attacking]:
		big.positions[raider] = Vector2(0.0, FortSiege.GATE_Y)
		big.handle_input(raider, {"act": true})
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
	game.handle_input(raider, {"act": true})  # a swing at the gate (#808)
	assert_lt(game.gate_hp, before, "a swing batters the gate")
	_breach(game)
	game.handle_input(raider, {"mx": 0.0, "my": -1.0})
	for _i in 60:
		game.tick(TICK)
	assert_lt(
		(game.positions[raider] as Vector2).y, FortSiege.GATE_Y, "a breached gate lets them in"
	)


## #808: a swing lands one hit then goes on cooldown — mashing can't out-DPS the
## old proximity rate, so balance holds.
func test_batter_is_cooldown_gated() -> void:
	var game := _game()
	var raider := _raider(game)
	game.positions[raider] = Vector2(0.0, FortSiege.GATE_Y)
	game.handle_input(raider, {"act": true})
	var after_one := game.gate_hp
	assert_almost_eq(
		after_one, FortSiege.GATE_MAX_HP - FortSiege.BATTER_DAMAGE, 0.001, "one swing = one hit"
	)
	game.handle_input(raider, {"act": true})
	assert_eq(game.gate_hp, after_one, "a second swing is on cooldown — no extra damage")
	for _i in int(ceil(FortSiege.BATTER_COOLDOWN_SEC / TICK)) + 1:
		game.tick(TICK)
	game.handle_input(raider, {"act": true})
	assert_lt(game.gate_hp, after_one, "the next swing lands once the cooldown clears")


## #808: the defender's one button repairs the gate when unthreatened, but
## shoves the instant a raider is on them.
func test_defender_repairs_when_alone_and_shoves_when_raided() -> void:
	var game := _game()
	var defender := _defender(game)
	var raider := _raider(game)
	game.gate_hp = FortSiege.GATE_MAX_HP - 3.0
	game.positions[defender] = Vector2(0.0, FortSiege.GATE_Y)
	game.positions[raider] = Vector2(8.0, 8.0)  # far off
	game.handle_input(defender, {"act": true})
	assert_almost_eq(
		game.gate_hp,
		FortSiege.GATE_MAX_HP - 3.0 + FortSiege.REPAIR_AMOUNT,
		0.001,
		"repairs the gate when unthreatened",
	)
	game.positions[raider] = Vector2(0.5, FortSiege.GATE_Y)  # now in reach
	var hp_before := game.gate_hp
	game.handle_input(defender, {"act": true})
	assert_eq(game.gate_hp, hp_before, "a threatened defender shoves, not repairs")
	assert_gt((game.knocks[raider] as Vector2).length(), 0.0, "the raider is shoved off")


## #808: the additive snapshot keys the view reads — contested flag and per-slot
## action seq/kind — are present and correct.
func test_snapshot_exposes_relic_and_action_state() -> void:
	var game := _game()
	var raider := _raider(game)
	game.positions[raider] = Vector2(0.0, FortSiege.GATE_Y)
	game.handle_input(raider, {"act": true})
	var snap := game.get_snapshot()
	var relic: Array = snap.relic
	assert_eq(relic.size(), 4, "relic ships as [x, y, state, carrier]")
	assert_eq(int(relic[2]), FortSiege.RelicState.AT_CORE, "starts home on the plinth")
	assert_eq(int(relic[3]), -1, "nobody carries it yet")
	var state: Array = snap.players[raider]
	assert_eq(state.size(), FortSiege.PS_COUNT, "player array carries the new fields")
	assert_gt(int(state[FortSiege.PS_ACT_SEQ]), 0, "a swing bumps the action counter")
	assert_eq(int(state[FortSiege.PS_ACT_KIND]), FortSiege.Act.BATTER, "and records its kind")


func test_relic_untouchable_behind_a_standing_gate() -> void:
	var game := _game()
	var raider := _raider(game)
	game.positions[raider] = FortSiege.CORE_POS  # forced through the wall
	game.tick(TICK)
	assert_eq(game.relic_state, FortSiege.RelicState.AT_CORE, "no heist while the gate stands")


func test_raider_grabs_the_relic_and_is_slowed() -> void:
	var game := _game()
	_breach(game)
	var raider := _raider(game)
	game.positions[raider] = FortSiege.CORE_POS
	game.tick(TICK)
	assert_eq(game.relic_state, FortSiege.RelicState.CARRIED, "a touch takes the relic")
	assert_eq(game.relic_carrier, raider)
	# The thief lugs it: one full-thrust tick covers CARRY_SLOW of a free run.
	game.positions[raider] = Vector2(0.0, 0.0)
	game.knocks[raider] = Vector2.ZERO
	game.handle_input(raider, {"mx": 1.0, "my": 0.0})
	game.tick(TICK)
	assert_almost_eq(
		float(game.positions[raider].x),
		FortSiege.MOVE_SPEED * FortSiege.CARRY_SLOW * TICK,
		0.001,
		"the carrier runs slowed"
	)


func test_escape_scores_the_run_and_swaps_sides() -> void:
	var game := _game()
	_breach(game)
	var raider := _raider(game)
	game.relic_state = FortSiege.RelicState.CARRIED
	game.relic_carrier = raider
	game.positions[raider] = Vector2(0.0, FortSiege.ESCAPE_Y + 0.1)
	game.tick(TICK)
	assert_true(game.runs[0].captured, "carrying the relic out scores the heist")
	assert_eq(game.phase, FortSiege.Phase.SWAP)
	var swap_ticks := int(ceil(FortSiege.SWAP_SEC / TICK)) + 1
	for _i in swap_ticks:
		game.tick(TICK)
	assert_eq(game.attacking, 1, "sides swap for the second siege")
	assert_eq(game.gate_hp, FortSiege.GATE_MAX_HP, "fresh gate for the second siege")
	assert_eq(game.relic_state, FortSiege.RelicState.AT_CORE, "relic home for the second siege")
	assert_eq(game.capture, 0.0)


func test_shoved_thief_drops_the_relic() -> void:
	var game := _game()
	_breach(game)
	var raider := _raider(game)
	var defender := _defender(game)
	game.relic_state = FortSiege.RelicState.CARRIED
	game.relic_carrier = raider
	game.positions[raider] = Vector2(4.0, 4.0)
	game.positions[defender] = Vector2(4.5, 4.0)
	game.handle_input(defender, {"act": true})
	assert_eq(game.relic_state, FortSiege.RelicState.DROPPED, "the shove jars the relic loose")
	assert_eq(game.relic_carrier, -1)
	assert_almost_eq(float(game.relic_pos.x), 4.0, 0.001, "it drops where the thief stood")


func test_defender_touch_returns_a_loose_relic() -> void:
	var game := _game()
	_breach(game)
	game.relic_state = FortSiege.RelicState.DROPPED
	game.relic_pos = Vector2(6.0, 6.0)
	game.relic_return_left = FortSiege.RELIC_AUTO_RETURN_SEC
	game.positions[_defender(game)] = Vector2(6.0, 6.2)
	game.tick(TICK)
	assert_eq(game.relic_state, FortSiege.RelicState.AT_CORE, "a defender's touch sends it home")


func test_raider_wins_a_simultaneous_touch() -> void:
	var game := _game()
	_breach(game)
	var raider := _raider(game)
	game.relic_state = FortSiege.RelicState.DROPPED
	game.relic_pos = Vector2(6.0, 6.0)
	game.relic_return_left = FortSiege.RELIC_AUTO_RETURN_SEC
	game.positions[raider] = Vector2(6.0, 5.8)
	game.positions[_defender(game)] = Vector2(6.0, 6.2)
	game.tick(TICK)
	assert_eq(game.relic_state, FortSiege.RelicState.CARRIED, "the re-grab beats the return")
	assert_eq(game.relic_carrier, raider)


func test_loose_relic_walks_home_after_the_timer() -> void:
	var game := _game()
	_breach(game)
	game.relic_state = FortSiege.RelicState.DROPPED
	game.relic_pos = Vector2(8.0, 8.0)  # far from every spawn
	game.relic_return_left = TICK / 2.0
	game.tick(TICK)
	assert_eq(game.relic_state, FortSiege.RelicState.AT_CORE, "an unattended relic homes itself")


func test_failed_run_depth_records_best_relic_progress() -> void:
	var game := _game()
	_breach(game)
	var raider := _raider(game)
	game.relic_state = FortSiege.RelicState.CARRIED
	game.relic_carrier = raider
	# Midway between plinth and escape line.
	var mid_y := (FortSiege.CORE_POS.y + FortSiege.ESCAPE_Y) / 2.0
	game.positions[raider] = Vector2(0.0, mid_y)
	game.tick(TICK)
	assert_almost_eq(game.capture, 0.5, 0.05, "depth meter tracks how far the relic got")
	game._drop_relic(game.relic_pos)
	game._return_relic()
	game.tick(TICK)
	assert_gte(game.capture, 0.5, "the meter is monotonic — a foiled heist still counts")


func test_shove_bounces_attackers() -> void:
	var game := _game()
	var raider := _raider(game)
	var defender := _defender(game)
	game.positions[defender] = Vector2(0.0, 0.0)
	game.positions[raider] = Vector2(0.5, 0.0)
	game.handle_input(defender, {"act": true})
	assert_gt((game.knocks[raider] as Vector2).length(), 0.0, "shove knocks the raider")
	assert_gt(float(game.shove_cooldowns[defender]), 0.0, "shove starts its cooldown")
	assert_eq(game.shove_hits[raider], 1, "the raider's hit counter ticks once")


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
