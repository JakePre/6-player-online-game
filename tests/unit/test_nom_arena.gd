extends GutTest
## Nom Arena server simulation (M14-10): growth by dots, eating smaller blobs,
## idle decay, the lunge, the closing boundary, size-vs-speed, and ranking.

const TICK := 1.0 / 30.0


func _game(count: int = 2) -> NomArena:
	var game := NomArena.new()
	game.meta = NomArena.make_meta()
	var player_slots: Array[int] = []
	for i in count:
		player_slots.append(i)
	game.setup(player_slots, 42)
	return game


func test_meta_and_catalog() -> void:
	var meta := NomArena.make_meta()
	assert_eq(meta.id, &"nom_arena")
	assert_eq(meta.category, MinigameMeta.Category.FFA)
	assert_eq(meta.duration_sec, 60.0, "owner: QUICK, 60 s hard cap")
	assert_false(meta.control_spec.is_empty(), "ships a #832 structured control spec")
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.instantiate(&"nom_arena") is NomArena)
	MinigameCatalog.clear()


func test_setup_seeds_blobs_and_dense_dots() -> void:
	var game := _game(4)
	assert_eq(game.dots.size(), NomArena.DOT_COUNT, "dense dots")
	for slot in 4:
		assert_eq(float(game.masses[slot]), NomArena.START_MASS)


func test_eating_a_dot_grows_the_blob() -> void:
	var game := _game()
	game.dots.clear()
	game.dots.append(game.positions[0])  # a dot under the blob
	game._eat_dots()
	assert_almost_eq(float(game.masses[0]), NomArena.START_MASS + NomArena.DOT_MASS, 0.001)


func test_bigger_blob_swallows_a_smaller_overlapping_one() -> void:
	var game := _game()
	game.masses[0] = 20.0
	game.masses[1] = 8.0
	game.positions[0] = Vector2.ZERO
	game.positions[1] = Vector2(0.4, 0.0)  # inside slot 0's radius
	game._eat_players()
	assert_almost_eq(float(game.masses[0]), 28.0, 0.001, "absorbs the prey's mass")
	assert_eq(float(game.masses[1]), NomArena.MIN_MASS, "the eaten respawn small")


func test_similar_sizes_do_not_eat() -> void:
	var game := _game()
	game.masses[0] = 10.0
	game.masses[1] = 9.0  # ratio 1.11 < EAT_RATIO
	game.positions[0] = Vector2.ZERO
	game.positions[1] = Vector2(0.3, 0.0)
	game._eat_players()
	assert_eq(float(game.masses[0]), 10.0, "not big enough to swallow")
	assert_eq(float(game.masses[1]), 9.0)


func test_idle_mass_decays() -> void:
	var game := _game()
	game.dots.clear()
	game.masses[0] = 20.0
	game.positions[0] = Vector2.ZERO  # inside the boundary
	for _i in 30:
		game.tick(TICK)
	assert_lt(float(game.masses[0]), 20.0, "sitting still melts you")
	assert_gt(float(game.masses[0]), NomArena.MIN_MASS)


func test_lunge_dashes_costs_mass_and_goes_on_cooldown() -> void:
	var game := _game()
	game.handle_input(0, {"mx": 0.0, "my": -1.0, "lunge": true})
	assert_gt(float(game._lunge_left[0]), 0.0, "dashing")
	assert_gt(float(game._lunge_cd[0]), 0.0, "on cooldown")
	assert_almost_eq(float(game.masses[0]), NomArena.START_MASS - NomArena.LUNGE_MASS_COST, 0.001)
	# A second lunge mid-cooldown is refused.
	var mass_after := float(game.masses[0])
	game.handle_input(0, {"lunge": true})
	assert_almost_eq(float(game.masses[0]), mass_after, 0.001, "no double-lunge")


## #783: the lunge dashes along the current heading, not a fixed direction. The
## bug read the lunge packet's own dir — which a separate lunge packet lacks —
## so every lunge went straight up regardless of where you steered.
func test_lunge_aims_along_current_heading() -> void:
	var game := _game()
	game.positions[0] = Vector2.ZERO
	# Steer right, then lunge in a packet that carries no direction of its own.
	game.handle_input(0, {"mx": 1.0, "my": 0.0})
	game.handle_input(0, {"lunge": true})
	var tol := Vector2.ONE * 0.001
	assert_almost_eq(
		game._lunge_dir[0] as Vector2, Vector2.RIGHT, tol, "aimed along the heading, not up"
	)
	# The lunge-only packet must not have stomped the heading to zero either.
	assert_almost_eq(game.move_dirs[0] as Vector2, Vector2.RIGHT, tol, "heading preserved")
	game.tick(TICK)
	assert_gt(float(game.positions[0].x), 0.0, "the dash actually carries you rightward")


## Lunging while dead still falls back to a forward dash, not an undefined one.
func test_lunge_without_a_heading_falls_back_forward() -> void:
	var game := _game()
	game.handle_input(0, {"mx": 0.0, "my": 0.0})
	game.handle_input(0, {"lunge": true})
	assert_almost_eq(
		game._lunge_dir[0] as Vector2,
		Vector2(0.0, -1.0),
		Vector2.ONE * 0.001,
		"default forward when idle"
	)


func test_boundary_closes_in_late_and_bleeds_stragglers() -> void:
	var game := _game()
	assert_almost_eq(game._boundary_radius(), NomArena.ARENA_HALF, 0.01, "full arena early")
	game.elapsed = 60.0  # end of the round
	assert_lt(game._boundary_radius(), NomArena.ARENA_HALF, "the ring has closed")
	# A blob left outside the closed ring bleeds mass fast.
	game.dots.clear()
	game.masses[0] = 20.0
	game.positions[0] = Vector2(NomArena.ARENA_HALF, 0.0)  # outside the tiny late ring
	game.tick(TICK)
	assert_lt(float(game.masses[0]), 20.0 - 0.2, "outside the ring hurts")


func test_bigger_blobs_move_slower() -> void:
	var game := _game()
	game.masses[0] = 10.0
	game.masses[1] = 60.0
	assert_gt(game._speed(0), game._speed(1), "fat is slow")


func test_ranking_by_mass_descending() -> void:
	var game := _game(3)
	game.masses[0] = 15.0
	game.masses[1] = 40.0
	game.masses[2] = 15.0
	assert_eq(game._rank_players(), [[1], [0, 2]], "biggest first, equals tie")
