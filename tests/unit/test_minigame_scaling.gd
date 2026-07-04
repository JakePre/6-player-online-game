extends GutTest
## Player-count scaling helpers (M15-04, ADR 003 F4): arena size + economy
## supply grow with headcount above the 6-player baseline, never below it.


func test_baseline_lobby_is_unchanged() -> void:
	assert_almost_eq(MinigameScaling.arena_half(9.0, 6), 9.0, 0.001, "6 players = tuned size")
	assert_eq(MinigameScaling.supply(4, 6), 4)


func test_small_lobbies_never_shrink() -> void:
	# Below baseline the values hold — a 2-player match keeps the tuned arena.
	assert_almost_eq(MinigameScaling.arena_half(9.0, 2), 9.0, 0.001)
	assert_eq(MinigameScaling.supply(4, 3), 4)


func test_arena_grows_with_the_square_root_of_headcount() -> void:
	# 24 players = 4x the baseline area, so 2x the side length.
	assert_almost_eq(MinigameScaling.arena_half(9.0, 24), 18.0, 0.001)
	# 12 players = 2x area, ~1.414x side.
	assert_almost_eq(MinigameScaling.arena_half(9.0, 12), 9.0 * sqrt(2.0), 0.001)


func test_supply_scales_linearly_with_headcount() -> void:
	assert_eq(MinigameScaling.supply(4, 12), 8, "double the players, double the supply")
	assert_eq(MinigameScaling.supply(4, 24), 16)
	assert_eq(MinigameScaling.supply(3, 24), 12)


func test_scaling_is_monotonic_up_to_24() -> void:
	var prev_arena := 0.0
	var prev_supply := 0
	for count in range(2, 25):
		var a := MinigameScaling.arena_half(9.0, count)
		var s := MinigameScaling.supply(6, count)
		assert_true(a >= prev_arena, "arena never shrinks as players are added")
		assert_true(s >= prev_supply, "supply never drops as players are added")
		prev_arena = a
		prev_supply = s


func test_custom_baseline() -> void:
	# A game balanced for 4 players scales relative to 4, not 6.
	assert_eq(MinigameScaling.supply(2, 8, 4), 4)
	assert_almost_eq(MinigameScaling.arena_half(10.0, 16, 4), 20.0, 0.001)
