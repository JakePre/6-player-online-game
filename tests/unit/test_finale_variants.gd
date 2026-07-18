extends GutTest
## The finale-variant framework (#936): the registry itself, the match
## controller's random per-match pick + config pin, the FINALE_PLAY snapshot
## carrying the variant id, and shop loadouts reaching a non-Gauntlet variant
## through the shared apply_loadouts interface.

const TICK := 1.0 / 30.0


func _make_room(player_count: int) -> Room:
	var room := Room.new()
	room.code = "TEST42"
	for i in player_count:
		room.add_member(100 + i, "P%d" % i, "token%d" % i)
	return room


func _finale_controller(variant: String) -> MatchController:
	var config := {"seed": 7, "finale": true, "finale_only": true, "finale_coins": 100}
	if variant != "":
		config["finale_variant"] = variant
	return MatchController.new(_make_room(2), config)


func _into_play(controller: MatchController) -> void:
	controller.start()
	controller.handle_input(0, {"shop": {"action": "confirm"}})
	controller.handle_input(1, {"shop": {"action": "confirm"}})
	controller.tick(TICK)


func test_registry_lists_variants_with_views_and_names() -> void:
	var ids := FinaleVariants.ids()
	assert_has(ids, &"gauntlet")
	assert_has(ids, &"storm_court")
	for id: StringName in ids:
		assert_true(
			ResourceLoader.exists(FinaleVariants.view_scene_path(id)),
			"%s has a mountable view scene" % id
		)
		assert_false(FinaleVariants.display_name(id).is_empty())
	assert_true(FinaleVariants.is_finale(&"storm_court"))
	assert_false(FinaleVariants.is_finale(&"coin_scramble"))


func test_instantiate_builds_the_right_sim_and_junk_falls_back() -> void:
	assert_true(FinaleVariants.instantiate(&"storm_court") is StormCourt)
	assert_true(FinaleVariants.instantiate(&"gauntlet") is Gauntlet)
	assert_true(FinaleVariants.instantiate(&"nonsense") is Gauntlet, "junk = Gauntlet fallback")


func test_config_pins_the_variant_and_the_snapshot_carries_it() -> void:
	var controller := _finale_controller("storm_court")
	_into_play(controller)
	assert_eq(controller.state, MatchController.State.FINALE_PLAY)
	assert_true(controller.game is StormCourt, "the pinned variant runs")
	assert_eq(
		String(controller.get_snapshot().minigame),
		"storm_court",
		"clients mount the right finale view from the snapshot id"
	)


func test_shop_loadout_reaches_a_non_gauntlet_variant() -> void:
	var controller := _finale_controller("storm_court")
	controller.start()
	controller.handle_input(0, {"shop": {"action": "buy", "item": "extra_life"}})
	controller.handle_input(0, {"shop": {"action": "confirm"}})
	controller.handle_input(1, {"shop": {"action": "confirm"}})
	controller.tick(TICK)
	var court := controller.game as StormCourt
	assert_not_null(court)
	assert_eq(court.lives[0], 2, "the bought extra life landed via apply_loadouts")
	assert_eq(court.lives[1], 1)


func test_unpinned_pick_is_seed_deterministic_and_from_the_pool() -> void:
	var a := _finale_controller("")
	_into_play(a)
	var b := _finale_controller("")
	_into_play(b)
	assert_eq(a._finale_id, b._finale_id, "same seed = same draw")
	assert_has(FinaleVariants.ids(), a._finale_id, "drawn from the registry pool")
