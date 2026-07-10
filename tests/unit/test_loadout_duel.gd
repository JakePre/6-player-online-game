extends GutTest
## Loadout Duel (M14-01): arena shooter on the side-scroll bones — dais
## grabs, the five loadouts, one-hit KOs with a shield eating one, knockback,
## sub-round survival scoring, and the best-of-three aggregate placement.

const TICK := 1.0 / 30.0


func _game(player_slots: Array[int] = [0, 1]) -> LoadoutDuel:
	var game := LoadoutDuel.new()
	game.meta = LoadoutDuel.make_meta()
	game.setup(player_slots, 42)
	return game


## Advance into the FIGHT phase (past the opening countdown).
func _to_fight(game: LoadoutDuel) -> void:
	while game.phase == LoadoutDuel.Phase.COUNTDOWN and not game.finished:
		game.tick(TICK)


## #788: the loadout daises sit on platforms ~3 u up, unreachable with the
## shared default jump. The bumped jump must clear onto the first tier (lid 3.0,
## so a body stands at ~3.5).
func test_jump_reaches_the_first_platform_tier() -> void:
	var game := _game()
	var sim := game.sim
	sim.remove_body(0)
	sim.add_body(0, Vector2(6.5, 0.5))  # grounded under the right platform
	sim.body_of(0).grounded = true
	sim.press_jump(0)
	var apex := 0.5
	for _i in 40:
		sim.step(TICK)
		apex = maxf(apex, float(sim.body_of(0).pos.y))
	assert_gte(apex, 3.5, "the jump clears onto the first loadout platform")


func test_meta_and_catalog() -> void:
	var meta := LoadoutDuel.make_meta()
	assert_eq(meta.id, &"loadout_duel")
	assert_eq(meta.max_players, 8)
	assert_false(meta.controls_text.is_empty())
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.instantiate(&"loadout_duel") is LoadoutDuel)
	MinigameCatalog.clear()


func test_setup_spawns_fighters_alive_on_the_stage() -> void:
	var game := _game([0, 1, 2, 3] as Array[int])
	assert_eq(game.fighters.size(), 4)
	for slot in [0, 1, 2, 3]:
		assert_true(bool(game.fighters[slot].alive))
		assert_eq(int(game.fighters[slot].held), LoadoutDuel.Kind.NONE, "empty-handed")
		assert_true(game.sim.has_body(slot))


func test_countdown_freezes_input_then_fight_frees_it() -> void:
	var game := _game()
	game.handle_input(0, {"mx": 1.0})
	game.tick(TICK)
	assert_almost_eq(float(game.sim.body_of(0).move_x), 0.0, 0.001, "no steering mid-countdown")
	_to_fight(game)
	game.handle_input(0, {"mx": 1.0})
	assert_almost_eq(float(game.sim.body_of(0).move_x), 1.0, 0.001, "FIGHT frees movement")


func test_walking_over_a_dais_grabs_the_weapon_and_empties_it() -> void:
	var game := _game()
	_to_fight(game)
	var dais: Dictionary = game.daises[0]
	dais.kind = LoadoutDuel.Kind.BLASTER
	game.sim.body_of(0).pos = dais.pos
	game.tick(TICK)
	assert_eq(int(game.fighters[0].held), LoadoutDuel.Kind.BLASTER, "grabbed off the dais")
	assert_eq(int(game.fighters[0].ammo), int(LoadoutDuel.AMMO[LoadoutDuel.Kind.BLASTER]))
	assert_eq(int(dais.kind), LoadoutDuel.Kind.NONE, "the dais is spent")
	assert_gt(float(dais.refill_at), 0.0, "and cooling down")


func test_full_hand_does_not_grab_a_second_weapon() -> void:
	var game := _game()
	_to_fight(game)
	game.fighters[0].held = LoadoutDuel.Kind.HAMMER
	game.fighters[0].ammo = 4
	var dais: Dictionary = game.daises[0]
	dais.kind = LoadoutDuel.Kind.BLASTER
	game.sim.body_of(0).pos = dais.pos
	game.tick(TICK)
	assert_eq(int(game.fighters[0].held), LoadoutDuel.Kind.HAMMER, "keeps what it holds")
	assert_eq(int(dais.kind), LoadoutDuel.Kind.BLASTER, "the dais stays full")


func test_shield_pickup_is_independent_of_the_held_weapon() -> void:
	var game := _game()
	_to_fight(game)
	game.fighters[0].held = LoadoutDuel.Kind.BLASTER
	game.fighters[0].ammo = 3
	var dais: Dictionary = game.daises[0]
	dais.kind = LoadoutDuel.Kind.SHIELD
	game.sim.body_of(0).pos = dais.pos
	game.tick(TICK)
	assert_true(bool(game.fighters[0].shield), "armor grabbed while armed")
	assert_eq(int(game.fighters[0].held), LoadoutDuel.Kind.BLASTER, "weapon untouched")


func test_blaster_bolt_kos_a_rival() -> void:
	var game := _game()
	_to_fight(game)
	game.fighters[0].held = LoadoutDuel.Kind.BLASTER
	game.fighters[0].ammo = 3
	game.sim.body_of(0).facing = 1
	game.sim.body_of(0).pos = Vector2(0.0, 0.5)
	game.sim.body_of(1).pos = Vector2(3.0, 0.5)
	game.handle_input(0, {"fire": true})
	assert_eq(game.projectiles.size(), 1, "one bolt away")
	for _i in 20:
		game.tick(TICK)
		if not bool(game.fighters[1].alive):
			break
	assert_false(bool(game.fighters[1].alive), "the bolt connects and KOs")


func test_shield_eats_one_hit_and_shatters() -> void:
	var game := _game()
	_to_fight(game)
	game.fighters[1].shield = true
	game._resolve_hit(1, Vector2(0.0, 1.0))
	assert_true(bool(game.fighters[1].alive), "shield saved the life")
	assert_false(bool(game.fighters[1].shield), "but it shattered")
	game._resolve_hit(1, Vector2(0.0, 1.0))
	assert_false(bool(game.fighters[1].alive), "the next hit lands for real")


func test_a_hit_shoves_the_victim_away_from_the_source() -> void:
	var game := _game()
	_to_fight(game)
	game.fighters[1].shield = true
	game.sim.body_of(1).pos = Vector2(2.0, 1.0)
	game._resolve_hit(1, Vector2(0.0, 1.0))
	assert_gt(float(game.sim.body_of(1).vel.x), 0.0, "knocked to the right, away from the source")


func test_hammer_swing_kos_someone_in_front_but_not_behind() -> void:
	var game := _game([0, 1, 2] as Array[int])
	_to_fight(game)
	game.fighters[0].held = LoadoutDuel.Kind.HAMMER
	game.fighters[0].ammo = 4
	game.sim.body_of(0).pos = Vector2(0.0, 1.0)
	game.sim.body_of(0).facing = 1
	game.sim.body_of(1).pos = Vector2(1.0, 1.0)  # in front
	game.sim.body_of(2).pos = Vector2(-1.0, 1.0)  # behind
	game.handle_input(0, {"fire": true})
	assert_false(bool(game.fighters[1].alive), "the duck in front is bonked")
	assert_true(bool(game.fighters[2].alive), "the one behind is spared")


func test_boomer_explodes_and_catches_a_cluster() -> void:
	var game := _game([0, 1, 2] as Array[int])
	_to_fight(game)
	# Two rivals bunched where the lob will land.
	game.sim.body_of(1).pos = Vector2(1.0, 0.6)
	game.sim.body_of(2).pos = Vector2(1.6, 0.6)
	game._explode(Vector2(1.3, 0.6))
	assert_false(bool(game.fighters[1].alive))
	assert_false(bool(game.fighters[2].alive), "the blast radius catches both")


func test_thrown_weapon_bonks_even_when_empty() -> void:
	var game := _game()
	_to_fight(game)
	game.fighters[0].held = LoadoutDuel.Kind.BLASTER
	game.fighters[0].ammo = 1
	game.sim.body_of(0).pos = Vector2(0.0, 0.5)
	game.sim.body_of(0).facing = 1
	game.sim.body_of(1).pos = Vector2(2.5, 0.5)
	game.handle_input(0, {"throw": true})
	assert_eq(int(game.fighters[0].held), LoadoutDuel.Kind.NONE, "you let go of it")
	assert_eq(game.projectiles.size(), 1)
	for _i in 20:
		game.tick(TICK)
		if not bool(game.fighters[1].alive):
			break
	assert_false(bool(game.fighters[1].alive), "the flung gun bonks for the KO")


func test_running_off_the_stage_is_a_ko() -> void:
	var game := _game()
	_to_fight(game)
	game.sim.body_of(0).pos = Vector2(50.0, 1.0)  # way past the bounds
	game.tick(TICK)
	assert_false(bool(game.fighters[0].alive), "off the edge is out")


func test_last_duck_standing_ends_the_sub_round() -> void:
	var game := _game([0, 1, 2] as Array[int])
	_to_fight(game)
	game._ko(1)
	game._ko(2)
	game.tick(TICK)
	assert_eq(game.phase, LoadoutDuel.Phase.ROUND_OVER, "one alive ends the bout")
	assert_gt(int(game.total_score[0]), int(game.total_score[1]), "the survivor scores highest")


func test_best_of_three_aggregates_into_placements() -> void:
	var game := _game()
	# Drive all three sub-rounds: slot 0 wins each by outlasting slot 1.
	for _round in LoadoutDuel.SUB_ROUNDS:
		_to_fight(game)
		game._ko(1)
		# Let ROUND_OVER elapse into the next sub-round (or the finish).
		for _i in 120:
			game.tick(TICK)
			if game.finished or game.phase == LoadoutDuel.Phase.COUNTDOWN:
				break
	assert_true(game.finished, "three sub-rounds end the game")
	var placements: Array = game.get_results().placements
	assert_eq(placements[0], [0], "the repeat winner takes first")


func test_snapshot_shape_and_junk_input() -> void:
	var game := _game()
	_to_fight(game)
	game.handle_input(0, {"bogus": true})
	game.handle_input(9, {"fire": true})
	game.tick(TICK)
	var snap := game.get_snapshot()
	for key in ["players", "shots", "daises", "phase", "sub_round", "scores"]:
		assert_true(snap.has(key), "%s replicates" % key)
	assert_eq((snap.players[0] as Array).size(), LoadoutDuel.PS_COUNT)
	assert_eq((snap.daises as Array).size(), LoadoutDuel.dais_positions().size())
	assert_true(int(snap.players[0][3]) & 1 > 0, "the alive bit is set")
