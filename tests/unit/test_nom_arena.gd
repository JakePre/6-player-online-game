extends GutTest
## Nom Arena server simulation (M14-10): growth by dots, eating smaller blobs,
## idle decay, the lunge, the seeded maze walls (#1027, ring removed #1069),
## the #954 Power Pellet, size-vs-speed, and ranking.

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


## #1027: the seeded maze — four-fold mirrored walls, deterministic per seed,
## with every dot spawned clear of them. The ring is gone (#1069).
func test_walls_are_seeded_symmetric_and_keep_dots_clear() -> void:
	var game := _game()
	assert_eq(game.walls.size(), NomArena.WALLS_PER_QUADRANT * 4, "each rect mirrored x4")
	for wall: Dictionary in game.walls:
		var mirrored := 0
		for other: Dictionary in game.walls:
			var wall_pos: Vector2 = wall.pos
			var other_pos: Vector2 = other.pos
			if (
				absf(absf(wall_pos.x) - absf(other_pos.x)) < 0.001
				and absf(absf(wall_pos.y) - absf(other_pos.y)) < 0.001
			):
				mirrored += 1
		assert_eq(mirrored, 4, "every wall has its four mirror images")
	for dot in game.dots:
		assert_false(game._inside_a_wall(dot), "dots never spawn inside the maze")
	var again := _game()
	assert_eq(game.walls, again.walls, "same seed = same maze")


## #1027: a blob can't drive through a wall — the deepest a real step can
## reach is a shallow face overlap, and the sim slides it back out flush.
func test_walls_block_blobs() -> void:
	var game := _game()
	var wall: Dictionary = game.walls[0]
	var wall_pos: Vector2 = wall.pos
	var wall_half: Vector2 = wall.half
	game.dots.clear()
	game.positions[0] = wall_pos + Vector2(wall_half.x + game.radius_of(0) * 0.4, 0.0)
	game.tick(TICK)
	var gap: float = absf(float((game.positions[0] as Vector2).x) - wall_pos.x)
	assert_gte(
		gap + 0.001, wall_half.x + game.radius_of(0), "the wall pushes the blob back out flush"
	)


## #1027: the pellet never spawns buried in the maze.
func test_pellet_spawn_clears_the_walls() -> void:
	var game := _game()
	for _i in 20:
		var point := game._pellet_spawn_point()
		assert_false(game._inside_a_wall(point), "pellet spawn is wall-clear")


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


# --- Power Pellet (#954) --------------------------------------------------------


## The pellet lands PELLET_INTERVAL_SEC in, and never within PELLET_CLEARANCE
## of a player.
func test_pellet_spawns_on_cadence_with_clearance() -> void:
	var game := _game()
	game.positions[0] = Vector2(3.0, 0.0)
	game.positions[1] = Vector2(-3.0, 0.0)
	var ticks := int(NomArena.PELLET_INTERVAL_SEC / TICK) - 2
	for _i in ticks:
		game.tick(TICK)
	assert_eq(game.pellet, Vector2.INF, "no pellet before the interval")
	for _i in 4:
		game.tick(TICK)
	assert_ne(game.pellet, Vector2.INF, "pellet on the field after ~20s")
	for slot in 2:
		assert_gte(
			(game.positions[slot] as Vector2).distance_to(game.pellet),
			NomArena.PELLET_CLEARANCE - game.radius_of(slot),
			"spawn respects player clearance"
		)


func test_eating_the_pellet_grants_frenzy_and_rearms_the_timer() -> void:
	var game := _game()
	game.pellet = game.positions[0]
	game.tick(TICK)
	assert_eq(game.pellet, Vector2.INF, "pellet consumed")
	assert_gt(float(game._frenzy_left[0]), NomArena.FRENZY_SEC - 0.1, "eater is frenzied")
	assert_almost_eq(
		float(game._pellet_timer), NomArena.PELLET_INTERVAL_SEC, 0.01, "next pellet rearmed"
	)
	var snapshot := game.get_snapshot()
	assert_gt(float(snapshot.players[0][NomArena.PS_FRENZY]), 0.0, "frenzy on the wire")
	assert_eq(snapshot.pellet, [], "no pellet key payload while none is up")


## A frenzied, lunging blob bites FRENZY_STEAL off a touched rival — exactly
## once per rival per lunge, and the victim never drops below MIN_MASS.
func test_frenzy_bite_steals_mass_once_per_lunge() -> void:
	var game := _game()
	game.dots.clear()
	game.masses[0] = 8.0
	game.masses[1] = 20.0
	game.positions[0] = Vector2.ZERO
	game.positions[1] = Vector2(0.5, 0.0)
	game._frenzy_left[0] = NomArena.FRENZY_SEC
	game.handle_input(0, {"mx": 1.0, "my": 0.0, "lunge": true})
	var biter_before := float(game.masses[0])
	var victim_before := float(game.masses[1])
	game.tick(TICK)
	var taken := victim_before * NomArena.FRENZY_STEAL
	assert_almost_eq(float(game.masses[1]), victim_before - taken, 0.3, "victim loses 30%")
	assert_gt(float(game.masses[0]), biter_before, "the biter gains what was taken")
	# Still overlapping on the next tick of the SAME lunge: no second bite.
	var after_first := float(game.masses[1])
	game.tick(TICK)
	assert_almost_eq(
		float(game.masses[1]), after_first, after_first * 0.01, "one bite per rival per lunge"
	)


func test_frenzy_grants_no_speed_change() -> void:
	var game := _game()
	var base := game._speed(0)
	game._frenzy_left[0] = NomArena.FRENZY_SEC
	assert_almost_eq(game._speed(0), base, 0.0001, "frenzy is positioning, not speed")


func test_frenzy_expires() -> void:
	var game := _game()
	game._frenzy_left[0] = 2.0 * TICK
	game.tick(TICK)
	game.tick(TICK)
	game.tick(TICK)
	assert_eq(float(game._frenzy_left[0]), 0.0)
	assert_eq(float(game.get_snapshot().players[0][NomArena.PS_FRENZY]), 0.0)
