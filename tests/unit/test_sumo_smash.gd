extends GutTest
## Sumo Smash (SPEC $7 #5): dash cooldown, shove transfer, ring-out ordering
## with ties, timeout ranking, and 2/4/6/8-player setup balance. Capped at 8
## by design (ADR 003, M15) — the platform stays this one tiny disc on
## purpose, so there is no arena/spawn scaling to wire in.

const TICK := 1.0 / 30.0
## #927 regression floor: a full 6-bot field should brawl for a real stretch,
## not evaporate in ~2s from an overtuned dash-shove flinging everyone off spawn.
const MIN_BOT_ROUND_SEC := 6.0
## The universal "not a 2-second farce" floor applied to every player count.
const ANTI_WIPE_SEC := 2.5


func _game(player_slots: Array[int] = [0, 1]) -> SumoSmash:
	var game := SumoSmash.new()
	game.meta = SumoSmash.make_meta()
	game.setup(player_slots, 42)
	return game


func _seed_bot_round(count: int, seed_value: int = 42) -> SumoSmash:
	var player_slots: Array[int] = []
	for i in count:
		player_slots.append(i)
	var game := SumoSmash.new()
	game.meta = SumoSmash.make_meta()
	game.setup(player_slots, seed_value)
	return game


## Drives every live slot with its real bot brain, ticking until the round ends
## or the timeout. Returns how many seconds the round lasted.
func _run_bot_round(count: int, seed_value: int = 42) -> float:
	var game := _seed_bot_round(count, seed_value)
	var brains := {}
	for slot: int in game.slots:
		brains[slot] = BotBrains.brain_for(&"sumo_smash", slot, slot)
	var t := 0.0
	while not game.finished and t < game.meta.duration_sec:
		var match_state := {"game": game.get_snapshot()}
		for slot: int in game.slots:
			if game._elim.is_in(slot, game.slots):
				game.handle_input(slot, brains[slot].think(match_state, {}))
		game.tick(TICK)
		t += TICK
	return t


func test_meta() -> void:
	var meta := SumoSmash.make_meta()
	assert_eq(meta.id, &"sumo_smash")
	assert_eq(meta.category, MinigameMeta.Category.FFA)
	assert_eq(meta.min_players, 2)
	assert_eq(meta.max_players, 8)
	assert_false(meta.control_spec.is_empty(), "ships a #832 structured control spec")


func test_registered_in_catalog() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	var game := MinigameCatalog.instantiate(&"sumo_smash")
	assert_true(game is SumoSmash)
	assert_eq(game.meta.id, &"sumo_smash")


func test_spawns_scale_with_player_count() -> void:
	for count: int in [2, 4, 6, 8]:
		var player_slots: Array[int] = []
		for slot in count:
			player_slots.append(slot)
		var game := _game(player_slots)
		assert_eq(game.positions.size(), count)
		for slot: int in player_slots:
			var pos: Vector2 = game.positions[slot]
			assert_almost_eq(
				pos.length(), SumoSmash.PLATFORM_RADIUS * 0.6, 0.001, "%d players" % count
			)


## M15: the max-capacity 8-player ring is generously spaced on the unscaled
## disc (~3.8 units apart vs. a 1.0-unit contact radius) — the ADR's "8 by
## design" cap needs no arena growth to stay fair.
func test_eight_players_spawn_without_overlap() -> void:
	var player_slots: Array[int] = []
	for slot in 8:
		player_slots.append(slot)
	var game := _game(player_slots)
	for i in player_slots.size():
		for j in range(i + 1, player_slots.size()):
			var apart: float = game.positions[player_slots[i]].distance_to(
				game.positions[player_slots[j]]
			)
			assert_gt(apart, SumoSmash.PLAYER_RADIUS * 2.0, "no two spawns overlap at 8")


func test_movement() -> void:
	var game := _game()
	game.positions[0] = Vector2.ZERO
	game.handle_input(0, {"mx": 1.0, "my": 0.0})
	game.tick(1.0)
	assert_almost_eq(game.positions[0].x, SumoSmash.MOVE_SPEED, 0.2)


func test_dash_accelerates_and_cools_down() -> void:
	var game := _game()
	game.positions[0] = Vector2.ZERO
	game.positions[1] = Vector2(0.0, -6.0)
	game.handle_input(0, {"mx": 1.0, "my": 0.0, "dash": true})
	assert_eq(game.cooldown_left[0], SumoSmash.DASH_COOLDOWN_SEC)
	game.tick(TICK)
	var dashed: Vector2 = game.positions[0]
	assert_gt(dashed.x, (SumoSmash.MOVE_SPEED + SumoSmash.DASH_SPEED) * TICK * 0.8)
	# A second dash during cooldown does not restart it.
	game.handle_input(0, {"mx": 1.0, "my": 0.0, "dash": true})
	assert_lt(float(game.cooldown_left[0]), SumoSmash.DASH_COOLDOWN_SEC)


func test_dash_requires_a_heading() -> void:
	var game := _game()
	game.handle_input(0, {"mx": 0.0, "my": 0.0, "dash": true})
	assert_eq(float(game.cooldown_left[0]), 0.0, "no heading, no dash")


func test_contact_shoves_both_players() -> void:
	var game := _game()
	game.positions[0] = Vector2(-0.4, 0.0)
	game.positions[1] = Vector2(0.4, 0.0)
	game.tick(TICK)
	assert_lt(float(game.knocks[0].x), 0.0)
	assert_gt(float(game.knocks[1].x), 0.0)


func test_dashing_shove_is_stronger() -> void:
	var plain := _game()
	plain.positions[0] = Vector2(-0.4, 0.0)
	plain.positions[1] = Vector2(0.4, 0.0)
	plain.tick(TICK)
	var dashing := _game()
	dashing.positions[0] = Vector2(-0.4, 0.0)
	dashing.positions[1] = Vector2(0.4, 0.0)
	dashing.handle_input(0, {"mx": 1.0, "my": 0.0, "dash": true})
	dashing.tick(TICK)
	assert_gt(float(dashing.knocks[1].x), float(plain.knocks[1].x))


func test_ringout_order_becomes_placements() -> void:
	var game := _game([0, 1, 2] as Array[int])
	for slot: Variant in [2, 0]:
		game.positions[slot] = Vector2(SumoSmash.PLATFORM_RADIUS + 1.0, 0.0)
		game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[1], [0], [2]])
	assert_eq(game.get_results().pickup_coins, {})


func test_same_tick_ringouts_tie() -> void:
	var game := _game([0, 1, 2] as Array[int])
	game.positions[0] = Vector2(SumoSmash.PLATFORM_RADIUS + 1.0, 0.0)
	game.positions[2] = Vector2(-SumoSmash.PLATFORM_RADIUS - 1.0, 0.0)
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[1], [0, 2]])


func test_rung_out_players_ignore_input_and_snapshot() -> void:
	var game := _game([0, 1, 2] as Array[int])
	game.positions[0] = Vector2(SumoSmash.PLATFORM_RADIUS + 1.0, 0.0)
	game.tick(TICK)
	game.handle_input(0, {"mx": 1.0, "my": 0.0})
	assert_eq(game.move_dirs[0], Vector2.ZERO, "out players cannot steer")
	var snapshot := game.get_snapshot()
	assert_false(snapshot.players.has(0))
	assert_eq(snapshot.out, [[0]])


func test_timeout_survivors_tie_ahead_of_ringouts() -> void:
	var game := _game([0, 1, 2] as Array[int])
	game.positions[2] = Vector2(SumoSmash.PLATFORM_RADIUS + 1.0, 0.0)
	game.tick(TICK)
	game.duration_override = game.elapsed + TICK
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[0, 1], [2]])


## #927: a fresh 6-bot round must not resolve in the first couple of seconds
## (the render audit caught it ending at ~2s of a 30s round — the whole field
## ring-out from an overtuned dash-shove at spawn).
func test_six_bot_round_does_not_evaporate() -> void:
	var duration := _run_bot_round(6)
	gut.p("6-bot sumo round lasted %.2fs" % duration)
	assert_gt(duration, MIN_BOT_ROUND_SEC, "a 6-bot round should be a brawl, not a fast wipe")


## #927: the round-length collapse was a whole class, not just the 6-player
## frame — the knockback retune must leave every common count resolving as a
## real brawl: never the ~2s wipe, never a 60s stalemate that only ends on the
## timeout. Sumo has no RNG (fixed spawn ring, deterministic brains), so each
## count is a single reproducible trajectory this pins down.
func test_bot_rounds_across_counts_neither_wipe_nor_stall() -> void:
	for count: int in [4, 6, 8]:
		var duration := _run_bot_round(count)
		assert_gt(duration, ANTI_WIPE_SEC, "%d-bot round is not a ~2s wipe" % count)
		assert_lt(
			duration,
			SumoSmash.make_meta().duration_sec,
			"%d-bot round resolves by ring-out, not a timeout stalemate" % count
		)


func test_snapshot_shape() -> void:
	var game := _game()
	var snapshot := game.get_snapshot()
	assert_eq(snapshot.radius, SumoSmash.PLATFORM_RADIUS)
	assert_eq(snapshot.players.size(), 2)
	assert_eq(snapshot.players[0].size(), SumoSmash.PS_COUNT)
	assert_eq(snapshot.out, [])
