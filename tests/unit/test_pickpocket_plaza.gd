extends GutTest
## Pickpocket Plaza (PHASE2.md $4 #31): the hidden guard (private snapshots,
## #254), crowd wandering, proximity lifting with the suspect window, arrests,
## and coin ranking. The secrecy tests are the load-bearing ones — the shared
## snapshot must never leak which crowd body is the guard.

const TICK := 1.0 / 30.0


func _game(player_slots: Array[int] = [0, 1, 2, 3]) -> PickpocketPlaza:
	var game := PickpocketPlaza.new()
	game.meta = PickpocketPlaza.make_meta()
	game.setup(player_slots, 42)
	return game


func _a_thief(game: PickpocketPlaza) -> int:
	return game.thieves[0]


## Park a thief on a villager for long enough to lift a coin, re-anchoring each
## tick so the crowd's drift never breaks contact. Returns the lifted body.
func _lift_once(game: PickpocketPlaza, thief: int, body: int) -> void:
	var ticks := int(ceil(PickpocketPlaza.LIFT_SEC / TICK)) + 2
	for _i in ticks:
		game.positions[thief] = game.crowd[body]
		game.tick(TICK)


func test_meta_and_catalog() -> void:
	var meta := PickpocketPlaza.make_meta()
	assert_eq(meta.id, &"pickpocket_plaza")
	assert_eq(meta.category, MinigameMeta.Category.SABOTAGE)
	assert_eq(meta.min_players, 3)
	assert_eq(meta.max_players, 6)
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.instantiate(&"pickpocket_plaza") is PickpocketPlaza)
	MinigameCatalog.clear()


func test_setup_seats_one_guard_and_the_rest_as_thieves() -> void:
	var game := _game()
	assert_true(game.guard in game.slots, "someone is the guard")
	assert_eq(game.thieves.size(), 3, "everyone else is a thief")
	assert_false(game.guard in game.thieves)
	assert_eq(game.crowd.size(), PickpocketPlaza.CROWD_SIZE)
	assert_true(game.guard_body >= 0 and game.guard_body < PickpocketPlaza.CROWD_SIZE)
	for slot: int in game.thieves:
		var pos: Vector2 = game.positions[slot]
		assert_lt(absf(pos.x), PickpocketPlaza.ARENA_HALF + 0.001, "thief spawns inside the plaza")
		assert_lt(absf(pos.y), PickpocketPlaza.ARENA_HALF + 0.001)


func test_role_reaches_only_the_guard() -> void:
	var game := _game()
	var secret := game.get_private_snapshot(game.guard)
	assert_eq(secret.get("role", ""), "guard", "the guard learns their role")
	assert_eq(int(secret.get("body", -1)), game.guard_body, "and which body they wear")
	assert_eq(game.get_private_snapshot(_a_thief(game)), {}, "a thief learns nothing")


func test_shared_snapshot_never_leaks_the_disguise_before_reveal() -> void:
	var game := _game()
	var snapshot := game.get_snapshot()
	var json := JSON.stringify(snapshot)
	assert_false(json.contains('"body"'), "no body key in the shared snapshot")
	assert_false(json.contains("role"), "no role key either")
	assert_eq(snapshot.crowd.size(), PickpocketPlaza.CROWD_SIZE, "every body is written")
	assert_eq(int(snapshot.guard), game.guard, "the guard SLOT is public")
	assert_false(snapshot.has("reveal"), "no reveal while the job runs")


func test_reveal_only_after_finish() -> void:
	var game := _game()
	assert_false(game.get_snapshot().has("reveal"))
	game.duration_override = TICK
	game.tick(TICK)
	assert_true(game.finished)
	var reveal: Dictionary = game.get_snapshot().reveal
	assert_eq(int(reveal.guard), game.guard, "the reveal finally names the guard")
	assert_eq(int(reveal.body), game.guard_body, "and the body they wore")


func test_lifting_a_coin_marks_a_suspect() -> void:
	var game := _game()
	var thief := _a_thief(game)
	# A body the guard isn't wearing, so we test plain pickpocketing.
	var body := (game.guard_body + 1) % PickpocketPlaza.CROWD_SIZE
	_lift_once(game, thief, body)
	assert_eq(int(game.loot[thief]), 1, "a beat of contact lifts one coin")
	assert_gt(float(game.suspect_until[thief]), game.elapsed, "the lifter is now a suspect")


func test_pickpocketed_villager_goes_empty_on_cooldown() -> void:
	var game := _game()
	var thief := _a_thief(game)
	var body := (game.guard_body + 1) % PickpocketPlaza.CROWD_SIZE
	_lift_once(game, thief, body)
	assert_gt(float(game._body_cd[body]), 0.0, "the villager is empty for a spell")
	# Immediately camping the same body yields nothing more until it refills.
	game.positions[thief] = game.crowd[body]
	game.tick(TICK)
	assert_eq(int(game.loot[thief]), 1, "no double-dip on a spent villager")


func test_guard_arrests_a_nearby_suspect() -> void:
	var game := _game()
	var thief := _a_thief(game)
	game.loot[thief] = 5
	game.suspect_until[thief] = game.elapsed + PickpocketPlaza.SUSPECT_SEC
	game.positions[thief] = game.crowd[game.guard_body]
	game.handle_input(game.guard, {"act": true})
	assert_gt(float(game.stun[thief]), 0.0, "a caught thief is stunned")
	assert_eq(int(game.loot[thief]), 5 - PickpocketPlaza.DROP_COINS, "and shaken down")
	assert_eq(game.arrests, 1, "the guard scores the collar")
	assert_lt(float(game.suspect_until[thief]), game.elapsed, "no double jeopardy")


func test_arrest_spares_a_non_suspect() -> void:
	var game := _game()
	var thief := _a_thief(game)
	# Standing right next to the guard but not a recent lifter.
	game.suspect_until[thief] = -1.0
	game.positions[thief] = game.crowd[game.guard_body]
	game.handle_input(game.guard, {"act": true})
	assert_eq(float(game.stun[thief]), 0.0, "an innocent bystander walks free")
	assert_eq(game.arrests, 0)


func test_arrest_has_a_cooldown() -> void:
	var game := _game()
	var thief := _a_thief(game)
	var other := game.thieves[1]
	for hot: int in [thief, other]:
		game.suspect_until[hot] = game.elapsed + PickpocketPlaza.SUSPECT_SEC
		game.positions[hot] = game.crowd[game.guard_body]
	game.handle_input(game.guard, {"act": true})
	game.handle_input(game.guard, {"act": true})
	assert_eq(game.arrests, 1, "the cooldown blocks a double arrest")


func test_stunned_thief_cannot_move_or_lift() -> void:
	var game := _game()
	var thief := _a_thief(game)
	game.stun[thief] = PickpocketPlaza.STUN_SEC
	var before: Vector2 = game.positions[thief]
	game.handle_input(thief, {"mx": 1.0, "my": 0.0})
	game.tick(TICK)
	assert_eq(game.positions[thief], before, "a stunned thief is frozen")
	var body := (game.guard_body + 1) % PickpocketPlaza.CROWD_SIZE
	game.stun[thief] = PickpocketPlaza.STUN_SEC
	_lift_once(game, thief, body)
	assert_eq(int(game.loot[thief]), 0, "and cannot lift")


func test_thieves_cannot_arrest() -> void:
	var game := _game()
	var thief := _a_thief(game)
	var victim := game.thieves[1]
	game.suspect_until[victim] = game.elapsed + PickpocketPlaza.SUSPECT_SEC
	game.positions[victim] = game.positions[thief]
	game.handle_input(thief, {"act": true})
	assert_eq(game.arrests, 0, "only the guard makes arrests")
	assert_eq(float(game.stun[victim]), 0.0)


func test_guard_drives_their_own_crowd_body() -> void:
	var game := _game()
	var before: Vector2 = game.crowd[game.guard_body]
	game.handle_input(game.guard, {"mx": 1.0, "my": 0.0})
	for _i in 10:
		game.tick(TICK)
	assert_gt(game.crowd[game.guard_body].x, before.x, "the guard steers their disguise")


func test_scoring_and_pickup_coins() -> void:
	var game := _game([0, 1, 2, 3] as Array[int])
	var guard := game.guard
	game.arrests = 2
	var ranked: Array[int] = game.thieves.duplicate()
	game.loot[ranked[0]] = 9
	game.loot[ranked[1]] = 4
	game.loot[ranked[2]] = 4
	game.duration_override = TICK
	game.tick(TICK)
	assert_true(game.finished)
	var results := game.get_results()
	# Guard = 2 * 3 = 6 coins; slots ranked by coins, ties grouped.
	assert_eq(int(results.pickup_coins[guard]), 2 * PickpocketPlaza.ARREST_POINTS)
	assert_eq(int(results.pickup_coins[ranked[0]]), 9)
	assert_eq(results.placements[0], [ranked[0]], "the richest thief tops the board")


func test_snapshot_shape_and_junk_input() -> void:
	var game := _game()
	game.handle_input(_a_thief(game), {"act": "garbage", "mx": "junk"})
	game.handle_input(99, {"act": true})
	var snapshot := game.get_snapshot()
	assert_eq(snapshot.thieves.size(), 3)
	assert_eq(snapshot.crowd.size(), PickpocketPlaza.CROWD_SIZE)
	assert_eq(snapshot.scores.size(), 4, "a score for every slot")
	assert_false(bool(snapshot.alarm))
