extends GutTest
## Musical Platforms sim (M10-02): music/stop phases, exclusive claims, and
## musical-chairs elimination. Server-side logic only.

const TICK := 1.0 / 30.0


func _game_with(count: int) -> MusicalPlatforms:
	var game := MusicalPlatforms.new()
	game.meta = MusicalPlatforms.make_meta()
	var player_slots: Array[int] = []
	for i in count:
		player_slots.append(i)
	game.setup(player_slots, 7)
	return game


## Forces the STOP phase deterministically instead of waiting out the music.
func _force_stop(game: MusicalPlatforms) -> void:
	game.phase = MusicalPlatforms.Phase.MUSIC
	game._phase_left = 0.0
	game.tick(TICK)


func test_music_phase_spawns_no_platforms() -> void:
	var game := _game_with(4)
	assert_eq(game.phase, MusicalPlatforms.Phase.MUSIC)
	assert_eq(game.platforms.size(), 0)


func test_stop_spawns_one_platform_fewer_than_players() -> void:
	var game := _game_with(4)
	_force_stop(game)
	assert_eq(game.phase, MusicalPlatforms.Phase.STOP)
	assert_eq(game.platforms.size(), 3)
	for a in game.platforms.size():
		for b in game.platforms.size():
			if a != b:
				var gap: float = (game.platforms[a].pos as Vector2).distance_to(
					game.platforms[b].pos
				)
				assert_gte(gap, MusicalPlatforms.PLATFORM_SPACING, "platforms keep their spacing")


func test_first_player_on_a_platform_claims_it_exclusively() -> void:
	var game := _game_with(3)
	_force_stop(game)
	var platform: Dictionary = game.platforms[0]
	game.positions[0] = platform.pos
	game.positions[1] = platform.pos + Vector2(0.1, 0.0)
	game.tick(TICK)
	assert_eq(platform.claimed_by, 0, "lowest processed player standing there claims it")
	game.tick(TICK)
	assert_eq(platform.claimed_by, 0, "claims never change hands")


func test_a_player_cannot_claim_two_platforms() -> void:
	var game := _game_with(3)
	_force_stop(game)
	game.positions[0] = game.platforms[0].pos
	game.tick(TICK)
	game.positions[0] = game.platforms[1].pos
	game.tick(TICK)
	assert_eq(game.platforms[1].claimed_by, -1, "second platform stays free")


func test_stop_timeout_downs_everyone_without_a_platform() -> void:
	# Four players, three platforms: only two claim, so one platform stays
	# free and the scramble must run out its timer (no early end).
	var game := _game_with(4)
	_force_stop(game)
	game.positions[0] = game.platforms[0].pos
	game.positions[1] = game.platforms[1].pos
	game.positions[2] = Vector2(-8.0, -8.0)
	game.positions[3] = Vector2(8.0, -8.0)
	game.tick(TICK)
	assert_eq(game.phase, MusicalPlatforms.Phase.STOP, "a free platform keeps the scramble going")
	game._phase_left = 0.0
	game.tick(TICK)
	assert_eq(game.down_order, [[2, 3]])
	assert_eq(game.phase, MusicalPlatforms.Phase.MUSIC, "back to the music")
	assert_eq(game.platforms.size(), 0)
	assert_false(game.finished, "two players still standing")


func test_all_claimed_ends_the_scramble_early() -> void:
	var game := _game_with(3)
	_force_stop(game)
	game.positions[0] = game.platforms[0].pos
	game.positions[1] = game.platforms[1].pos
	game.positions[2] = Vector2(-8.0, -8.0)
	game.tick(TICK)
	assert_eq(game.phase, MusicalPlatforms.Phase.MUSIC, "no need to wait out the timer")
	assert_eq(game.down_order, [[2]])


func test_musical_chairs_runs_to_a_winner() -> void:
	var game := _game_with(3)
	_force_stop(game)
	game.positions[0] = game.platforms[0].pos
	game.positions[1] = game.platforms[1].pos
	game.positions[2] = Vector2(-8.0, -8.0)
	game.tick(TICK)
	_force_stop(game)
	assert_eq(game.platforms.size(), 1, "two players left, one platform")
	game.positions[0] = game.platforms[0].pos
	game.positions[1] = Vector2(8.0, 8.0)
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[0], [1], [2]])


func test_timeout_ranks_survivors_ahead_of_the_fallen() -> void:
	var game := _game_with(3)
	game.duration_override = TICK
	_force_stop(game)
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[0, 1, 2]], "nobody down yet: everyone ties")


func test_snapshot_shape() -> void:
	var game := _game_with(3)
	_force_stop(game)
	var snapshot := game.get_snapshot()
	assert_eq(snapshot.players.size(), 3)
	assert_eq(snapshot.phase, MusicalPlatforms.Phase.STOP)
	assert_eq(snapshot.platforms.size(), 2)
	assert_eq((snapshot.platforms[0] as Array).size(), 3, "[x, y, claimed_by]")
	assert_eq(snapshot.fallen, [])
