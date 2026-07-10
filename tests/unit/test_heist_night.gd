extends GutTest
## Heist Night (SPEC $7 #17): light cycle, coin banking, dark-only rate-
## limited stealing, anonymity until the end reveal, and vault ranking.

const TICK := 1.0 / 30.0


func _game(player_slots: Array[int] = [0, 1, 2]) -> HeistNight:
	var game := HeistNight.new()
	game.meta = HeistNight.make_meta()
	game.setup(player_slots, 42)
	return game


func _make_dark(game: HeistNight) -> void:
	game.elapsed = HeistNight.LIGHT_SEC + 0.1


func test_meta() -> void:
	var meta := HeistNight.make_meta()
	assert_eq(meta.id, &"heist_night")
	assert_eq(meta.category, MinigameMeta.Category.SABOTAGE)
	assert_eq(meta.min_players, 3)
	assert_false(meta.control_spec.is_empty(), "ships a #832 structured control spec")


func test_registered_in_catalog() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.instantiate(&"heist_night") is HeistNight)
	MinigameCatalog.clear()


func test_setup_scales_with_player_count() -> void:
	for count: int in [3, 4, 6, 8]:
		var player_slots: Array[int] = []
		for slot in count:
			player_slots.append(slot)
		var game := _game(player_slots)
		assert_eq(game.vaults.size(), count)
		assert_eq(game.vault_pos.size(), count)


func test_max_players_raised_to_eight() -> void:
	assert_eq(HeistNight.make_meta().max_players, 8)


## No-crowd fairness (M15 8-cap): the vault ring already auto-distributes by
## slot count, and at 8 players every vault stays clear of its neighbours.
func test_vaults_are_spread_at_eight_players() -> void:
	var player_slots: Array[int] = []
	for i in 8:
		player_slots.append(i)
	var game := _game(player_slots)
	for a in 8:
		for b in range(a + 1, 8):
			var dist: float = (game.vault_pos[a] as Vector2).distance_to(game.vault_pos[b])
			assert_gt(dist, HeistNight.VAULT_RADIUS * 2.0, "vaults %d/%d don't overlap" % [a, b])


func test_light_cycle_from_elapsed() -> void:
	var game := _game()
	game.elapsed = 0.0
	assert_false(game.is_dark(), "starts lit")
	game.elapsed = HeistNight.LIGHT_SEC + 0.1
	assert_true(game.is_dark())
	game.elapsed = HeistNight.LIGHT_SEC + HeistNight.DARK_SEC + 0.1
	assert_false(game.is_dark(), "cycle repeats")


func test_pickup_banks_into_vault() -> void:
	var game := _game()
	game.coins.clear()
	game.coins.append(Vector2(0.0, 0.0))
	game.positions[0] = Vector2(0.1, 0.0)
	game.tick(TICK)
	assert_eq(game.vaults[0], 1)
	assert_eq(game.coins.size(), 0)


func test_no_stealing_while_lit() -> void:
	var game := _game()
	game.vaults[1] = 5
	game.positions[0] = game.vault_pos[1]
	# A full second of vault contact, all within the initial lit window.
	for _i in 30:
		game.tick(TICK)
	assert_false(game.is_dark())
	assert_eq(game.vaults[1], 5, "lights on, vaults safe")
	assert_eq(game.vaults[0], 0)


func test_dark_stealing_is_rate_limited_and_logged() -> void:
	var game := _game()
	game.vaults[1] = 5
	_make_dark(game)
	game.positions[0] = game.vault_pos[1]
	var ticks := int(ceil(HeistNight.STEAL_SEC_PER_COIN / TICK)) + 1
	for _i in ticks:
		game.tick(TICK)
	assert_eq(game.vaults[0], 1, "one coin per %.1fs of contact" % HeistNight.STEAL_SEC_PER_COIN)
	assert_eq(game.vaults[1], 4)
	assert_eq(game.steal_log, {0: {1: 1}})


func test_cannot_steal_from_empty_vault() -> void:
	var game := _game()
	_make_dark(game)
	game.positions[0] = game.vault_pos[1]
	for _i in 60:
		game.tick(TICK)
	assert_eq(game.vaults[0], 0)
	assert_false(game.steal_log.has(0))


func test_own_vault_is_not_a_target() -> void:
	var game := _game()
	game.vaults[0] = 5
	_make_dark(game)
	game.positions[0] = game.vault_pos[0]
	for _i in 60:
		game.tick(TICK)
	assert_eq(game.vaults[0], 5)


func test_snapshot_hides_players_in_the_dark() -> void:
	var game := _game()
	assert_eq(game.get_snapshot().players.size(), 3, "lit: everyone visible")
	assert_false(game.get_snapshot().dark)
	_make_dark(game)
	var snapshot := game.get_snapshot()
	assert_true(snapshot.dark)
	assert_eq(snapshot.players.size(), 0, "dark: nobody standing in a vault glow")
	assert_eq(snapshot.vaults.size(), 3, "vault totals stay visible")


## #806: the always-lit vaults reveal a silhouette even in the dark, so a player
## standing in a vault's glow is in the snapshot (server-decided, identical for
## every client) while a player out in the open dark stays hidden.
func test_dark_reveals_a_player_standing_in_a_vault_glow() -> void:
	var game := _game()
	_make_dark(game)
	game.positions[0] = game.vault_pos[1]  # onto another player's vault
	game.positions[2] = Vector2.ZERO  # arena centre, clear of every vault
	var players: Dictionary = game.get_snapshot().players
	assert_true(players.has(0), "a player in a vault's glow is revealed in the dark")
	assert_false(players.has(2), "a player out in the open dark stays hidden")


func test_steal_log_revealed_only_after_finish() -> void:
	var game := _game()
	game.vaults[1] = 3
	_make_dark(game)
	game.positions[0] = game.vault_pos[1]
	for _i in int(ceil(HeistNight.STEAL_SEC_PER_COIN / TICK)) + 1:
		game.tick(TICK)
	assert_false(game.get_snapshot().has("reveal"), "anonymous while playing")
	game.duration_override = game.elapsed + TICK
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_snapshot().reveal, {0: {1: 1}})


func test_richest_vault_wins_and_totals_become_pickup_coins() -> void:
	var game := _game()
	game.vaults[0] = 2
	game.vaults[1] = 7
	game.vaults[2] = 2
	game.duration_override = TICK
	game.coins.clear()
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[1], [0, 2]])
	assert_eq(game.get_results().pickup_coins, {0: 2, 1: 7, 2: 2})
