extends GutTest
## Faulty Wiring sim (M10-16): a hidden-saboteur co-op repair. Crew fill wires by
## standing on them, the saboteur cuts fixed ones and never repairs, crew win on
## an all-lit board and the saboteur wins the timeout. The saboteur's identity is
## private (#254) and never rides the shared snapshot.


func _game(player_slots: Array[int]) -> FaultyWiring:
	var game := FaultyWiring.new()
	game.meta = FaultyWiring.make_meta()
	game.setup(player_slots, 7)
	return game


func _a_crew_slot(game: FaultyWiring) -> int:
	for slot: int in game.slots:
		if slot != game.saboteur:
			return slot
	return -1


func test_meta_registers_in_the_catalog() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.is_registered(&"faulty_wiring"))
	var meta := MinigameCatalog.meta_of(&"faulty_wiring")
	assert_eq(meta.category, MinigameMeta.Category.SABOTAGE)
	assert_eq(meta.min_players, 4)
	MinigameCatalog.clear()


func test_setup_picks_one_saboteur_and_breaks_every_wire() -> void:
	var game := _game([0, 1, 2, 3])
	assert_true(game.saboteur in game.slots, "the saboteur is one of the players")
	assert_eq(game.wires.size(), FaultyWiring.WIRE_COUNT)
	for wire: Dictionary in game.wires:
		assert_false(wire.fixed, "every wire starts dead")


func test_only_the_saboteur_learns_their_role() -> void:
	var game := _game([0, 1, 2, 3])
	assert_eq(game.get_private_snapshot(game.saboteur), {"saboteur": true})
	for slot: int in game.slots:
		if slot != game.saboteur:
			assert_eq(game.get_private_snapshot(slot), {}, "crew learn nothing")
	assert_false(game.get_snapshot().has("saboteur"), "the shared snapshot stays anonymous")


func test_a_crew_member_on_a_wire_repairs_it() -> void:
	var game := _game([0, 1, 2, 3])
	var crew := _a_crew_slot(game)
	game.positions[crew] = game.wires[0].pos
	for _i in 60:
		game.tick(0.1)  # 6 s of repair, past REPAIR_SEC
	assert_true(game.wires[0].fixed, "a crew member fills the wire they stand on")


func test_the_saboteur_standing_on_a_wire_does_not_repair_it() -> void:
	var game := _game([0, 1, 2, 3])
	game.positions[game.saboteur] = game.wires[0].pos
	for slot: int in game.slots:
		if slot != game.saboteur:
			game.positions[slot] = Vector2.ZERO  # centre, clear of the wire ring
	for _i in 60:
		game.tick(0.1)
	assert_false(game.wires[0].fixed, "the saboteur's presence never repairs")
	assert_almost_eq(float(game.wires[0].progress), 0.0, 0.001)


func test_the_saboteur_cuts_a_fixed_wire_open() -> void:
	var game := _game([0, 1, 2, 3])
	game.wires[0].fixed = true
	game.wires[0].progress = 1.0
	game.positions[game.saboteur] = game.wires[0].pos
	game.handle_input(game.saboteur, {"act": true})
	assert_false(game.wires[0].fixed, "the saboteur cuts the wire back open")


func test_crew_cannot_cut_wires() -> void:
	var game := _game([0, 1, 2, 3])
	var crew := _a_crew_slot(game)
	game.wires[0].fixed = true
	game.positions[crew] = game.wires[0].pos
	game.handle_input(crew, {"act": true})
	assert_true(game.wires[0].fixed, "only the saboteur can cut")


func test_crew_win_the_instant_every_wire_is_lit() -> void:
	var game := _game([0, 1, 2, 3])
	for wire: Dictionary in game.wires:
		wire.fixed = true
		wire.progress = 1.0
	game.tick(0.1)
	assert_true(game.finished)
	var placements: Array = game.get_results().placements
	assert_false(game.saboteur in placements[0], "the crew take first")
	assert_true(game.saboteur in placements[1], "the saboteur ranks last on a crew win")


func test_saboteur_wins_the_timeout_with_a_dead_wire() -> void:
	var game := _game([0, 1, 2, 3])
	game.duration_override = 1.0
	game.tick(1.0)  # reaches the duration with wires still dead
	assert_true(game.finished)
	var placements: Array = game.get_results().placements
	assert_true(game.saboteur in placements[0], "the saboteur wins when a wire stays dead")
