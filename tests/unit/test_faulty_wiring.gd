extends GutTest
## Faulty Wiring server simulation (M10-16, M15 12-cap): proximity repair, the
## hidden saboteur's cut + cooldown, the private-role channel, the win/timeout
## resolutions, the reveal hold, score ranking, and spawn spacing at scale.

const TICK := 1.0 / 30.0


func _make_game(player_count: int) -> FaultyWiring:
	var game := FaultyWiring.new()
	game.meta = FaultyWiring.make_meta()
	var slots: Array[int] = []
	for i in player_count:
		slots.append(i)
	game.setup(slots, 42)
	return game


## The saboteur is chosen deterministically from the seed, so tests can pin
## a crew member and the saboteur without guessing.
func _a_crew_member(game: FaultyWiring) -> int:
	for slot: int in game.slots:
		if slot != game.saboteur:
			return slot
	return -1


func test_setup_seeds_broken_nodes_and_one_saboteur() -> void:
	var game := _make_game(4)
	assert_eq(game.nodes.size(), FaultyWiring.NODE_POSITIONS.size())
	for value in game.nodes:
		assert_eq(value, 0.0, "every node starts broken")
	assert_true(game.saboteur in game.slots, "exactly one seeded saboteur")
	assert_eq(game.phase, FaultyWiring.Phase.WORK)


func test_standing_on_a_node_repairs_it() -> void:
	var game := _make_game(4)
	var crew := _a_crew_member(game)
	game.positions[crew] = FaultyWiring.NODE_POSITIONS[0]
	game.tick(TICK)
	assert_gt(game.nodes[0], 0.0, "a nearby player repairs the node")
	assert_gt(float(game._repair_contribution[crew]), 0.0, "and is credited for it")


func test_repair_stacking_is_capped() -> void:
	# Four repairers on one node apply only MAX_STACKED_REPAIRERS worth.
	var game := _make_game(6)
	for slot in 4:
		game.positions[slot] = FaultyWiring.NODE_POSITIONS[0]
	game.tick(TICK)
	var capped := FaultyWiring.REPAIR_RATE * FaultyWiring.MAX_STACKED_REPAIRERS * TICK
	assert_almost_eq(float(game.nodes[0]), capped, 0.0001, "stacking beyond the cap adds nothing")


func test_only_the_saboteur_can_cut() -> void:
	var game := _make_game(4)
	var crew := _a_crew_member(game)
	game.nodes[0] = 1.0
	game.positions[crew] = FaultyWiring.NODE_POSITIONS[0]
	# A crew slot sending a forged cut packet does nothing.
	game._handle_input(crew, {"mx": 0.0, "my": 0.0, "cut": true})
	game.tick(TICK)
	assert_eq(float(game.nodes[0]), 1.0, "a crew cut packet is ignored")


func test_saboteur_cut_knocks_a_node_down_and_sparks_it() -> void:
	var game := _make_game(4)
	game.nodes[0] = 1.0
	game.positions[game.saboteur] = FaultyWiring.NODE_POSITIONS[0]
	var pulse_before: int = game._spark_pulses[0]
	game._handle_input(game.saboteur, {"mx": 0.0, "my": 0.0, "cut": true})
	game.tick(TICK)
	assert_almost_eq(
		float(game.nodes[0]), 1.0 - FaultyWiring.CUT_AMOUNT, 0.05, "the cut takes a chunk off"
	)
	assert_eq(game._spark_pulses[0], pulse_before + 1, "and sparks the node for the view")
	assert_gt(game._cut_cooldown, 0.0, "the cut goes on cooldown")


func test_cut_respects_its_cooldown() -> void:
	var game := _make_game(4)
	game.nodes[0] = 1.0
	game.positions[game.saboteur] = FaultyWiring.NODE_POSITIONS[0]
	game._handle_input(game.saboteur, {"cut": true})
	game.tick(TICK)
	var after_first: float = game.nodes[0]
	# A second cut while the cooldown is live is refused.
	game._handle_input(game.saboteur, {"cut": true})
	game.tick(TICK)
	assert_almost_eq(float(game.nodes[0]), after_first, 0.02, "no second cut mid-cooldown")


## The role only reaches the saboteur's own slot, and only during WORK (#254).
func test_private_snapshot_reveals_the_role_only_to_the_saboteur() -> void:
	var game := _make_game(4)
	var crew := _a_crew_member(game)
	assert_eq(game.get_private_snapshot(game.saboteur).get("role", ""), "saboteur")
	assert_eq(game.get_private_snapshot(crew), {}, "crew learn nothing")
	# After the round resolves, even the saboteur's private channel closes.
	game._resolve("crew")
	assert_eq(game.get_private_snapshot(game.saboteur), {}, "no private role outside WORK")


func test_shared_snapshot_hides_the_saboteur_until_reveal() -> void:
	var game := _make_game(4)
	assert_false(game.get_snapshot().has("saboteur"), "the shared snapshot is anonymous in WORK")
	game._resolve("crew")
	assert_eq(game.get_snapshot().get("saboteur"), game.saboteur, "reveal exposes them")


func test_all_nodes_repaired_wins_for_the_crew() -> void:
	var game := _make_game(4)
	for i in game.nodes.size():
		game.nodes[i] = 1.0
	game.tick(TICK)
	assert_eq(game.phase, FaultyWiring.Phase.REVEAL)
	assert_eq(game.outcome, "crew")
	assert_false(game.finished, "the reveal holds before finishing")


func test_reveal_holds_then_finishes_with_crew_on_top() -> void:
	var game := _make_game(4)
	var crew := _a_crew_member(game)
	game._repair_contribution[crew] = 1.0
	for i in game.nodes.size():
		game.nodes[i] = 1.0
	game.tick(TICK)  # enters REVEAL
	# Run past the reveal hold.
	for _i in int(FaultyWiring.REVEAL_SEC / TICK) + 2:
		game.tick(TICK)
	assert_true(game.finished, "the round finishes after the reveal hold")
	var placements: Array = game.get_results().placements
	assert_true(crew in placements[0], "a crew winner tops the ranking, saboteur trails")
	assert_true(game.saboteur in placements[placements.size() - 1])


func test_timeout_wins_for_the_saboteur() -> void:
	var game := _make_game(4)
	game._cuts_made = 2
	game._time_left = TICK * 0.5  # one tick tips it over
	game.tick(TICK)
	assert_eq(game.outcome, "saboteur")
	for _i in int(FaultyWiring.REVEAL_SEC / TICK) + 2:
		game.tick(TICK)
	assert_true(game.finished)
	var placements: Array = game.get_results().placements
	assert_true(game.saboteur in placements[0], "the saboteur tops the ranking on a timeout win")


func test_max_players_raised_to_twelve() -> void:
	assert_eq(FaultyWiring.make_meta().max_players, 12)


## M15: a plain bump per the ADR 003 addendum — MAX_STACKED_REPAIRERS (3) x
## NODE_POSITIONS (4) is a built-in ceiling of 12 usefully-occupied slots, so
## no arena/economy scaling was needed. Verify the fixed single-ring spawn
## still spaces everyone out cleanly at the new cap.
func test_spawns_distinct_and_non_overlapping_at_twelve() -> void:
	var game := _make_game(12)
	var seen := {}
	for slot in 12:
		var pos: Vector2 = game.positions[slot]
		seen[pos] = true
		for other in 12:
			if other == slot:
				continue
			var apart: float = pos.distance_to(game.positions[other])
			assert_gt(apart, FaultyWiring.PLAYER_RADIUS * 2.0, "no two spawns overlap at 12")
	assert_eq(seen.size(), 12, "every player gets a distinct spawn")


## The addendum's math: four nodes can each usefully hold three repairers, so
## a full 12-player crowd (minus the saboteur) can all contribute at once —
## nobody is structurally locked out of the co-op at the new cap.
func test_twelve_players_can_fully_staff_every_node() -> void:
	var game := _make_game(12)
	for i in game.nodes.size():
		for j in FaultyWiring.MAX_STACKED_REPAIRERS:
			var slot: int = i * FaultyWiring.MAX_STACKED_REPAIRERS + j
			game.positions[slot] = FaultyWiring.NODE_POSITIONS[i]
	game.tick(TICK)
	var capped := FaultyWiring.REPAIR_RATE * FaultyWiring.MAX_STACKED_REPAIRERS * TICK
	for i in game.nodes.size():
		assert_almost_eq(
			float(game.nodes[i]), capped, 0.0001, "node %d repairs at the full stacked rate" % i
		)
