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


## Runs the current scramble out to elimination (#804: an all-claimed board now
## holds for the grace window, so force the timeout to resolve it in one step).
func _resolve_scramble(game: MusicalPlatforms) -> void:
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


## #804: an all-claimed board no longer eliminates the odd one out instantly —
## the scramble holds open for the grace window first, then ends without
## waiting out the full timer.
func test_all_claimed_holds_for_the_grace_window_then_ends() -> void:
	var game := _game_with(3)
	_force_stop(game)
	game.positions[0] = game.platforms[0].pos
	game.positions[1] = game.platforms[1].pos
	game.positions[2] = Vector2(-8.0, -8.0)
	game.tick(TICK)
	assert_eq(
		game.phase, MusicalPlatforms.Phase.STOP, "grace window: no instant kill on a fast fill"
	)
	assert_eq(game.down_order, [], "nobody goes down during the grace window")
	# Wind the clock to just past the grace floor (but well before the timeout).
	game._phase_left = MusicalPlatforms.STOP_SEC - MusicalPlatforms.SCRAMBLE_GRACE_SEC
	game.tick(TICK)
	assert_eq(game.phase, MusicalPlatforms.Phase.MUSIC, "ends once the grace has elapsed")
	assert_eq(game.down_order, [[2]])


func test_musical_chairs_runs_to_a_winner() -> void:
	var game := _game_with(3)
	_force_stop(game)
	game.positions[0] = game.platforms[0].pos
	game.positions[1] = game.platforms[1].pos
	game.positions[2] = Vector2(-8.0, -8.0)
	game.tick(TICK)
	_resolve_scramble(game)
	assert_eq(game.down_order, [[2]], "round one eliminates the platform-less player")
	_force_stop(game)
	assert_eq(game.platforms.size(), 1, "two players left, one platform")
	game.positions[0] = game.platforms[0].pos
	game.positions[1] = Vector2(8.0, 8.0)
	game.tick(TICK)
	_resolve_scramble(game)
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
	assert_eq(
		(snapshot.platforms[0] as Array).size(), MusicalPlatforms.PT_COUNT, "[x, y, claimed_by]"
	)
	assert_eq(snapshot.fallen, [])


func test_max_players_raised_to_twelve() -> void:
	assert_eq(MusicalPlatforms.make_meta().max_players, 12)


func test_control_spec_present() -> void:
	assert_false(
		MusicalPlatforms.make_meta().control_spec.is_empty(), "ships a #832 structured control spec"
	)


## M15: a fixed-size ring cannot fit 11 well-spaced platforms, so the ring
## (and the arena) grow with the lobby to the same per-player-area formula.
func test_arena_and_platform_ring_scale_at_twelve() -> void:
	var game := _game_with(12)
	assert_gt(game._play_half, MusicalPlatforms.ARENA_HALF, "the arena grows for a crowd")
	assert_gt(
		game._platform_max_dist, MusicalPlatforms.PLATFORM_MAX_DIST, "the platform ring grows too"
	)


## The scaled ring must still reliably fit all 11 platforms a full 12-player
## lobby needs, correctly spaced — the actual regression the ADR flags.
func test_stop_spawns_eleven_well_spaced_platforms_at_twelve() -> void:
	var game := _game_with(12)
	_force_stop(game)
	assert_eq(game.platforms.size(), 11, "one platform fewer than 12 players")
	for a in game.platforms.size():
		for b in game.platforms.size():
			if a != b:
				var gap: float = (game.platforms[a].pos as Vector2).distance_to(
					game.platforms[b].pos
				)
				assert_gte(gap, MusicalPlatforms.PLATFORM_SPACING, "platforms keep their spacing")


## Backward compatibility: at the 6-player baseline nothing scales.
func test_six_players_unchanged() -> void:
	var game := _game_with(6)
	assert_almost_eq(game._play_half, MusicalPlatforms.ARENA_HALF, 0.001)
	assert_almost_eq(game._platform_max_dist, MusicalPlatforms.PLATFORM_MAX_DIST, 0.001)


## Spawns fan out over rings (no overlap) and stay inside the scaled arena.
func test_player_spawns_distinct_and_within_arena_at_twelve() -> void:
	var game := _game_with(12)
	var seen := {}
	for slot in 12:
		var pos: Vector2 = game.positions[slot]
		assert_lte(pos.length(), game._play_half, "spawn inside the scaled arena")
		seen[pos] = true
	assert_eq(seen.size(), 12, "every player gets a distinct spawn")
