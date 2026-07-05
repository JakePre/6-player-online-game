extends GutTest
## The Mole (PHASE2.md $4 #30): co-op fuel deliveries, the hidden saboteur
## (#254 private snapshots), the unattributed spark tell, the vote, and
## outcome scoring. The leak tests are the load-bearing ones.

const TICK := 1.0 / 30.0


func _game(player_slots: Array[int] = [0, 1, 2, 3]) -> TheMole:
	var game := TheMole.new()
	game.meta = TheMole.make_meta()
	game.setup(player_slots, 42)
	return game


func _crew(game: TheMole) -> int:
	for slot: int in game.slots:
		if slot != game.mole:
			return slot
	return -1


func test_meta_and_catalog() -> void:
	var meta := TheMole.make_meta()
	assert_eq(meta.id, &"the_mole")
	assert_eq(meta.category, MinigameMeta.Category.SABOTAGE)
	assert_eq(meta.max_players, 8)
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.instantiate(&"the_mole") is TheMole)
	MinigameCatalog.clear()


## No-crowd fairness (M15 8-cap, owner override — see ADR 003 addendum): the
## fixed fuel-cell economy stays close enough to the 6-player baseline at 8
## that no scaling is needed. Exactly one mole regardless of headcount.
func test_setup_handles_eight_players() -> void:
	var player_slots: Array[int] = []
	for i in 8:
		player_slots.append(i)
	var game := _game(player_slots)
	assert_eq(game.carrying.size(), 8)
	var mole_count := 0
	for slot in 8:
		assert_false(game.carrying[slot])
		if slot == game.mole:
			mole_count += 1
	assert_eq(mole_count, 1, "exactly one mole at any headcount")
	for slot in 8:
		var pos: Vector2 = game.positions[slot]
		assert_lt(pos.length(), TheMole.ARENA_HALF, "spawn stays inside the arena")


func test_role_reaches_only_the_mole() -> void:
	var game := _game()
	assert_true(game.mole in game.slots, "someone is the mole")
	assert_eq(game.get_private_snapshot(game.mole), {"role": "mole"})
	assert_eq(game.get_private_snapshot(_crew(game)), {}, "the crew learns nothing")


func test_shared_snapshot_never_leaks_the_role_before_reveal() -> void:
	var game := _game()
	var work_json := JSON.stringify(game.get_snapshot())
	assert_false(work_json.contains("role"), "no role key in the shared WORK snapshot")
	assert_false(work_json.contains("reveal"), "no reveal before REVEAL")
	game.phase = TheMole.Phase.VOTE
	assert_false(JSON.stringify(game.get_snapshot()).contains("reveal"))
	game.phase = TheMole.Phase.REVEAL
	assert_eq(int(game.get_snapshot().reveal.mole), game.mole, "the reveal finally names them")


func test_deliveries_fill_the_machine() -> void:
	var game := _game()
	var hauler := _crew(game)
	game.cells.clear()
	game.cells.append(game.positions[hauler])
	game.tick(TICK)
	assert_true(game.carrying[hauler], "standing on a cell grabs it")
	game.positions[hauler] = TheMole.MACHINE_POS
	game.tick(TICK)
	assert_false(game.carrying[hauler])
	assert_eq(game.progress, 1, "delivery fuels the machine")


func test_sabotage_drains_sparks_and_cools_down() -> void:
	var game := _game()
	game.progress = 3
	game.positions[game.mole] = TheMole.MACHINE_POS
	game.handle_input(game.mole, {"act": true})
	assert_eq(game.progress, 2, "sabotage drains a cell")
	assert_true(game.get_snapshot().sparked, "the machine sparks — unattributed")
	game.handle_input(game.mole, {"act": true})
	assert_eq(game.progress, 2, "cooldown blocks the double-drain")


func test_crew_action_never_sabotages() -> void:
	var game := _game()
	game.progress = 3
	var crew := _crew(game)
	game.positions[crew] = TheMole.MACHINE_POS
	game.handle_input(crew, {"act": true})
	assert_eq(game.progress, 3, "only the mole drains")


func test_filling_the_machine_starts_the_vote() -> void:
	var game := _game()
	game.progress = TheMole.CELL_TARGET
	game.tick(TICK)
	assert_eq(game.phase, TheMole.Phase.VOTE)
	assert_true(game.success)


func test_timeout_fails_the_crew() -> void:
	var game := _game()
	game.phase_elapsed = TheMole.WORK_SEC
	game.tick(TICK)
	assert_eq(game.phase, TheMole.Phase.VOTE)
	assert_false(game.success)


func test_votes_only_count_in_the_vote_phase() -> void:
	var game := _game()
	game.handle_input(0, {"vote": 1})
	assert_eq(game.votes.size(), 0, "no voting during WORK")
	game.phase = TheMole.Phase.VOTE
	game.handle_input(0, {"vote": 0})
	assert_eq(game.votes.size(), 0, "self-votes are ignored")
	game.handle_input(0, {"vote": 99})
	assert_eq(game.votes.size(), 0, "unknown slots are ignored")
	game.handle_input(0, {"vote": 1})
	game.handle_input(0, {"vote": 2})
	assert_eq(int(game.votes[0]), 2, "the last vote counts")


func test_everyone_voting_ends_the_vote_early_and_tallies() -> void:
	var game := _game()
	game.phase = TheMole.Phase.VOTE
	for slot: int in game.slots:
		var target: int = game.mole if slot != game.mole else _crew(game)
		game.handle_input(slot, {"vote": target})
	game.tick(TICK)
	assert_eq(game.phase, TheMole.Phase.REVEAL)
	assert_true(game.caught, "a unanimous crew catches the mole")


func test_scoring_success_and_catch() -> void:
	var game := _game()
	game.success = true
	game.caught = true
	var voter := _crew(game)
	game.votes[voter] = game.mole
	assert_eq(
		game._points(voter),
		TheMole.CREW_SUCCESS_POINTS + TheMole.CORRECT_VOTE_POINTS,
		"crew scores the job plus the correct vote"
	)
	assert_eq(game._points(game.mole), 0, "a caught mole on a finished job gets nothing")


func test_scoring_failed_job_and_escape() -> void:
	var game := _game()
	game.success = false
	game.caught = false
	assert_eq(
		game._points(game.mole),
		TheMole.MOLE_FAIL_POINTS + TheMole.MOLE_UNCAUGHT_POINTS,
		"a clean getaway pays double"
	)
	assert_eq(game._points(_crew(game)), 0)


func test_reveal_phase_finishes_with_point_ranking() -> void:
	var game := _game()
	game.success = false
	game.caught = false
	game.phase = TheMole.Phase.REVEAL
	game.phase_elapsed = TheMole.REVEAL_SEC
	game.tick(TICK)
	assert_true(game.finished)
	var placements: Array = game.get_results().placements
	assert_eq(placements[0], [game.mole], "the escaped mole tops a failed run")
