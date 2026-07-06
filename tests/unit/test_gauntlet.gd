extends GutTest
## The Gauntlet finale (SPEC $6): shrinking platform, escalating hazards,
## lives/respawns, shop loadout effects, sabotage/grudge hooks, and the
## elimination-order placements that feed final ranking (M5-03).

const TICK := 1.0 / 30.0


func _gauntlet(player_slots: Array[int] = [0, 1]) -> Gauntlet:
	var game := Gauntlet.new()
	game.meta = Gauntlet.make_meta()
	game.setup(player_slots, 12345)
	return game


## Tick without hazard spawns getting in the way of a focused assertion.
func _quiet_tick(game: Gauntlet, seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		game._hazard_accum = -INF
		game.tick(TICK)
		left -= TICK


func test_meta() -> void:
	var meta := Gauntlet.make_meta()
	assert_eq(meta.id, &"gauntlet")
	assert_eq(meta.min_players, 2)
	assert_eq(meta.duration_sec, 180.0)


func test_setup_defaults_one_life_no_perks() -> void:
	var game := _gauntlet()
	assert_eq(game.lives, {0: 1, 1: 1})
	assert_eq(game.shields, {0: false, 1: false})
	assert_eq(game.sabotage_tokens, {0: 0, 1: 0})


func test_apply_loadouts() -> void:
	var game := _gauntlet()
	(
		game
		. apply_loadouts(
			{
				0:
				{
					"items":
					{&"extra_life": 2, &"shield": 1, &"speed_boost": 1, &"sabotage_token": 1},
					"coins_left": 10,
				},
				9: {"items": {&"extra_life": 1}, "coins_left": 0},
			}
		)
	)
	assert_eq(game.lives[0], 3)
	assert_true(game.shields[0])
	assert_true(game.speed_boosts[0])
	assert_eq(game.sabotage_tokens[0], 1)
	assert_eq(game.lives[1], 1, "unlisted slot keeps base loadout")
	assert_false(game.lives.has(9), "unknown slot ignored")


func test_platform_shrinks_in_stages_to_minimum() -> void:
	var game := _gauntlet()
	# Park both players near the center so neither falls off as it shrinks.
	game.positions[0] = Vector2(-1.0, 0.0)
	game.positions[1] = Vector2(1.0, 0.0)
	assert_eq(game.radius, Gauntlet.START_RADIUS)
	_quiet_tick(game, Gauntlet.SHRINK_STAGE_SEC + 0.1)
	assert_eq(game.radius, Gauntlet.START_RADIUS - Gauntlet.SHRINK_PER_STAGE)
	_quiet_tick(game, Gauntlet.SHRINK_STAGE_SEC * 20)
	assert_eq(game.radius, Gauntlet.MIN_RADIUS)


func test_walking_off_the_platform_costs_a_life() -> void:
	var game := _gauntlet([0, 1, 2])
	game.positions[0] = Vector2(game.radius + 1.0, 0.0)
	game._hazard_accum = -INF
	game.tick(TICK)
	assert_eq(game.lives[0], 0)
	assert_eq(game.elimination_order, [[0]])


func test_ko_with_lives_left_respawns_at_center_after_delay() -> void:
	var game := _gauntlet()
	game.apply_loadouts({0: {"items": {&"extra_life": 1}, "coins_left": 0}})
	game.positions[0] = Vector2(game.radius + 1.0, 0.0)
	game._hazard_accum = -INF
	game.tick(TICK)
	assert_eq(game.lives[0], 1)
	assert_false(game.finished)
	# Waiting out the respawn: not moved by input, not KO-able.
	game.handle_input(0, {"mx": 1.0, "my": 0.0})
	_quiet_tick(game, Gauntlet.RESPAWN_SEC - 0.5)
	assert_eq(game.positions[0], Vector2.ZERO)
	_quiet_tick(game, 1.0)
	assert_false(game._respawn_left.has(0))
	assert_eq(game.positions[0], Vector2.ZERO)


func test_shield_absorbs_one_ko_without_losing_a_life() -> void:
	var game := _gauntlet()
	game.apply_loadouts({0: {"items": {&"shield": 1}, "coins_left": 0}})
	game.positions[0] = Vector2(game.radius + 1.0, 0.0)
	game._hazard_accum = -INF
	game.tick(TICK)
	assert_eq(game.lives[0], 1)
	assert_false(game.shields[0], "shield consumed")
	assert_eq(game.positions[0], Vector2.ZERO, "pulled back to safety")
	assert_false(game.finished)


func test_speed_boost_moves_faster() -> void:
	var game := _gauntlet()
	game.apply_loadouts({0: {"items": {&"speed_boost": 1}, "coins_left": 0}})
	game.positions[0] = Vector2.ZERO
	game.positions[1] = Vector2(0.0, -5.0)
	game.handle_input(0, {"mx": 1.0, "my": 0.0})
	game._hazard_accum = -INF
	game.tick(1.0)
	assert_almost_eq(game.positions[0].x, Gauntlet.MOVE_SPEED * Gauntlet.SPEED_BOOST_MULT, 0.001)


func test_hazard_blast_kos_players_inside_after_warning() -> void:
	var game := _gauntlet([0, 1, 2])
	game.positions[0] = Vector2(3.0, 3.0)
	game.positions[1] = Vector2(-3.0, -3.0)
	game.positions[2] = Vector2(3.1, 3.1)
	game._spawn_hazard(Vector2(3.0, 3.0))
	_quiet_tick(game, Gauntlet.HAZARD_WARN_SEC - 0.2)
	assert_eq(game.lives[0], 1, "telegraph does not hurt yet")
	game._hazard_accum = -INF
	game.tick(0.5)
	assert_eq(game.lives[0], 0)
	assert_eq(game.lives[2], 0)
	assert_eq(game.lives[1], 1)
	assert_eq(game.elimination_order, [[0, 2]], "shared blast is a tie group")
	assert_true(game.finished, "one player left ends the finale")
	assert_eq(game.get_results().placements, [[1], [0, 2]])


func test_hazards_escalate() -> void:
	var game := _gauntlet()
	assert_almost_eq(game._hazard_interval(), Gauntlet.HAZARD_START_INTERVAL, 0.001)
	assert_almost_eq(game._hazard_radius(), Gauntlet.HAZARD_START_RADIUS, 0.001)
	game.elapsed = Gauntlet.HAZARD_RAMP_SEC * 2
	assert_almost_eq(game._hazard_interval(), Gauntlet.HAZARD_MIN_INTERVAL, 0.001)
	assert_almost_eq(game._hazard_radius(), Gauntlet.HAZARD_MAX_RADIUS, 0.001)


func test_hazards_spawn_on_a_timer() -> void:
	var game := _gauntlet()
	var ticks := int(ceil((Gauntlet.HAZARD_START_INTERVAL + 0.2) / TICK))
	for _i in ticks:
		game.tick(TICK)
	assert_gt(game.hazards.size() + game.elimination_order.size(), 0)


func test_sabotage_token_places_hazard_and_is_consumed() -> void:
	var game := _gauntlet()
	game.apply_loadouts({0: {"items": {&"sabotage_token": 1}, "coins_left": 0}})
	game.handle_input(0, {"sabotage": [2.0, 2.0]})
	assert_eq(game.hazards.size(), 1)
	assert_eq(game.sabotage_tokens[0], 0)
	game.handle_input(0, {"sabotage": [2.0, 2.0]})
	assert_eq(game.hazards.size(), 1, "no token, no hazard")


func test_sabotage_without_token_rejected() -> void:
	var game := _gauntlet()
	game.handle_input(0, {"sabotage": [0.0, 0.0]})
	assert_eq(game.hazards.size(), 0)


func test_grudge_only_for_eliminated_and_only_once() -> void:
	var game := _gauntlet([0, 1, 2])
	game.handle_input(0, {"grudge": [1.0, 1.0]})
	assert_eq(game.hazards.size(), 0, "alive players cannot grudge")
	game.positions[0] = Vector2(game.radius + 1.0, 0.0)
	game._hazard_accum = -INF
	game.tick(TICK)
	assert_eq(game.lives[0], 0)
	game.handle_input(0, {"grudge": [1.0, 1.0]})
	assert_eq(game.hazards.size(), 1, "eliminated player gets one grudge")
	game.handle_input(0, {"grudge": [1.0, 1.0]})
	assert_eq(game.hazards.size(), 1, "grudge is one-time")


func test_elimination_order_becomes_placements() -> void:
	var game := _gauntlet([0, 1, 2])
	for slot: Variant in [2, 0]:
		game.positions[slot] = Vector2(game.radius + 1.0, 0.0)
		game._hazard_accum = -INF
		game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[1], [0], [2]])
	assert_eq(game.get_results().pickup_coins, {}, "finale awards no coins")


func test_timeout_ranks_survivors_by_lives_then_reverse_elimination() -> void:
	var game := _gauntlet([0, 1, 2, 3])
	game.apply_loadouts({0: {"items": {&"extra_life": 1}, "coins_left": 0}})
	game.positions[3] = Vector2(game.radius + 1.0, 0.0)
	game._hazard_accum = -INF
	game.tick(TICK)
	assert_eq(game.lives[3], 0)
	game.duration_override = game.elapsed + TICK
	game._hazard_accum = -INF
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[0], [1, 2], [3]])


func test_snapshot_shape() -> void:
	var game := _gauntlet()
	game._spawn_hazard(Vector2(1.0, 1.0))
	var snapshot := game.get_snapshot()
	assert_eq(snapshot.radius, Gauntlet.START_RADIUS)
	assert_eq(snapshot.players.size(), 2)
	assert_eq(snapshot.players[0].size(), 4)
	assert_eq(snapshot.hazards.size(), 1)
	assert_eq(snapshot.hazards[0].size(), 4)
	assert_has(snapshot, "shrink_in")


## #583: the client telegraphs the doomed ring off shrink_in, which must count
## down through a full stage and wrap back up the instant a shrink lands.
func test_shrink_in_counts_down_and_wraps_after_a_stage() -> void:
	var game := _gauntlet()
	game.positions[0] = Vector2(-1.0, 0.0)
	game.positions[1] = Vector2(1.0, 0.0)
	assert_almost_eq(game.get_snapshot().shrink_in, Gauntlet.SHRINK_STAGE_SEC, 0.001)
	_quiet_tick(game, 5.0)
	assert_almost_eq(game.get_snapshot().shrink_in, Gauntlet.SHRINK_STAGE_SEC - 5.0, 0.05)
	# One more tick past the stage boundary so the wrap has definitely landed;
	# that overshoot is itself 0.1s into the fresh stage.
	_quiet_tick(game, Gauntlet.SHRINK_STAGE_SEC - 5.0 + 0.1)
	assert_almost_eq(
		float(game.get_snapshot().shrink_in),
		Gauntlet.SHRINK_STAGE_SEC - 0.1,
		0.1,
		"a landed shrink resets the countdown to a fresh stage"
	)


func test_overlapping_players_push_apart() -> void:
	var game := _gauntlet()
	game.positions[0] = Vector2(0.0, 0.0)
	game.positions[1] = Vector2(0.5, 0.0)
	game._hazard_accum = -INF
	game.tick(TICK)
	assert_gt(game.positions[1].x - game.positions[0].x, 0.5)


func _slots(count: int) -> Array[int]:
	var out: Array[int] = []
	for slot in count:
		out.append(slot)
	return out


## ADR 003: the finale scales to 24 — a bigger disc that shrinks faster so the
## squeeze keeps its pacing; the 6-player base is untouched.
func test_cap_raised_to_twentyfour() -> void:
	assert_eq(Gauntlet.make_meta().max_players, 24)


func test_platform_scales_with_head_count() -> void:
	assert_almost_eq(
		Gauntlet.start_radius_for(6), Gauntlet.START_RADIUS, 0.001, "the 6-player base is unchanged"
	)
	assert_almost_eq(
		Gauntlet.start_radius_for(2), Gauntlet.START_RADIUS, 0.001, "small lobbies too"
	)
	assert_gt(
		Gauntlet.start_radius_for(24), Gauntlet.start_radius_for(6), "24 players get a bigger disc"
	)
	assert_gt(
		Gauntlet.shrink_per_stage_for(24), Gauntlet.SHRINK_PER_STAGE, "and a faster shrink to match"
	)


func test_setup_seeds_the_scaled_platform() -> void:
	var game := _gauntlet(_slots(24))
	assert_almost_eq(game.radius, Gauntlet.start_radius_for(24), 0.001)
	# Spawn ring sits on the scaled disc, not the base one.
	for slot in 24:
		assert_almost_eq(
			(game.positions[slot] as Vector2).length(),
			Gauntlet.start_radius_for(24) * 0.6,
			0.001,
			"players ring the scaled platform"
		)


## Pacing is preserved: the number of shrink stages to reach MIN_RADIUS stays
## close to the 6-player count despite the far larger 24-player disc.
func test_shrink_reaches_min_in_similar_stages() -> void:
	var stages_6 := _stages_to_min(6)
	var stages_24 := _stages_to_min(24)
	assert_lte(stages_24, stages_6 + 2, "the bigger disc still compresses in a similar time")
	assert_lt(
		float(stages_24) * Gauntlet.SHRINK_STAGE_SEC,
		Gauntlet.make_meta().duration_sec,
		"and reaches the floor well within the round"
	)


func _stages_to_min(count: int) -> int:
	var r := Gauntlet.start_radius_for(count)
	var step := Gauntlet.shrink_per_stage_for(count)
	var stages := 0
	while r > Gauntlet.MIN_RADIUS:
		r = maxf(r - step, Gauntlet.MIN_RADIUS)
		stages += 1
	return stages


## A full 24-player finale resolves within the round and ranks every slot
## exactly once — no crash, no dropped or duplicated player at scale.
func test_full_twentyfour_player_finale_resolves() -> void:
	var game := _gauntlet(_slots(24))
	var max_ticks := int(Gauntlet.make_meta().duration_sec / TICK) + 5
	var ticks := 0
	while not game.finished and ticks < max_ticks:
		game.tick(TICK)
		ticks += 1
	assert_true(game.finished, "the 24-player finale resolves within the round cap")
	var seen := {}
	for group: Array in game.get_results().placements:
		for slot: int in group:
			seen[slot] = true
	assert_eq(seen.size(), 24, "every player is ranked exactly once")
