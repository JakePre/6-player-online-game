extends GutTest
## Goal-seeking bot brains (M19, #684): the registry picks the right brain per
## minigame id (random fallback for uncovered games), and each archetype brain
## steers correctly given a crafted snapshot — pure think() calls, no scene.


func _play_state(id: String, game: Dictionary) -> Dictionary:
	return {"state": MatchController.State.PLAY, "minigame": id, "game": game}


func test_registry_picks_dedicated_brains_and_falls_back_to_random() -> void:
	assert_true(BotBrains.brain_for(&"coin_scramble", 0, 1) is CoinScrambleBrain)
	assert_true(BotBrains.brain_for(&"gauntlet", 0, 1) is GauntletBrain)
	assert_true(BotBrains.brain_for(&"heist_night", 0, 1) is RandomBrain, "uncovered id -> random")
	assert_false(BotBrains.has_brain(&"heist_night"))


func test_random_fallback_still_produces_intents() -> void:
	var brain := BotBrains.brain_for(&"heist_night", 0, 42)
	var intent := brain.think({}, {})
	assert_true(intent.has("mx"), "fallback keeps the pre-M19 random behavior")


func test_coin_scramble_brain_runs_at_the_nearest_coin() -> void:
	var brain := BotBrains.brain_for(&"coin_scramble", 0, 1)
	var intent := brain.think(
		_play_state(
			"coin_scramble", {"players": {0: [0.0, 0.0, 0]}, "coins": [[5.0, 0.0], [-1.0, 0.0]]}
		),
		{}
	)
	assert_lt(float(intent.mx), 0.0, "the coin at -1 is nearer than the one at +5")
	assert_almost_eq(float(intent.my), 0.0, 0.01)


func test_king_of_the_hill_brain_uses_held_item_then_seeks_zone() -> void:
	var brain := BotBrains.brain_for(&"king_of_the_hill", 0, 1)
	var holding := brain.think(
		_play_state(
			"king_of_the_hill",
			{"players": {0: [4.0, 0.0, 0]}, "zone": [0.0, 0.0, 2.0], "items": [], "held": {0: 0}}
		),
		{}
	)
	assert_true(holding.get("use", false), "a held item fires immediately")
	var seeking := brain.think(
		_play_state(
			"king_of_the_hill",
			{"players": {0: [4.0, 0.0, 0]}, "zone": [0.0, 0.0, 2.0], "items": [], "held": {}}
		),
		{}
	)
	assert_lt(float(seeking.mx), 0.0, "outside the zone, head toward its center")


func test_thin_ice_brain_leaves_a_breaking_tile_for_intact_ice() -> void:
	var brain := BotBrains.brain_for(&"thin_ice", 0, 1)
	# 3x3 grid, tile_size 2 -> half 3. Bot at center tile (1,1) which is
	# BREAKING; all others INTACT. It must move, and never return "stay".
	var tiles := [0, 0, 0, 0, 2, 0, 0, 0, 0]
	var intent := brain.think(
		_play_state(
			"thin_ice",
			{
				"grid_size": 3,
				"tile_size": 2.0,
				"tiles": tiles,
				"players": {0: [0.0, 0.0]},
				"fallen": []
			}
		),
		{}
	)
	var direction := Vector2(float(intent.get("mx", 0.0)), float(intent.get("my", 0.0)))
	assert_gt(direction.length(), 0.1, "standing on breaking ice demands movement")


func test_meteor_shower_brain_flees_a_telegraph_it_stands_in() -> void:
	var brain := BotBrains.brain_for(&"meteor_shower", 0, 1)
	var intent := brain.think(
		_play_state(
			"meteor_shower",
			{"players": {0: [3.0, 0.0]}, "zone": [0.0, 0.0, 10.0], "meteors": [[3.5, 0.0, 0.4]]}
		),
		{}
	)
	assert_lt(float(intent.mx), 0.0, "flee away from the meteor at +3.5")


func test_hurdle_dash_brain_jumps_hurdles_and_runs_otherwise() -> void:
	var brain := BotBrains.brain_for(&"hurdle_dash", 0, 1)
	var jumping := brain.think(
		_play_state(
			"hurdle_dash",
			{"players": {0: [10.0, 0, 0.0, false]}, "hurdles": [11.0, 30.0], "course_len": 100.0}
		),
		{}
	)
	assert_true(jumping.get("jump", false), "a hurdle 1.0 ahead demands a jump")
	var running := brain.think(
		_play_state(
			"hurdle_dash",
			{"players": {0: [10.0, 0, 0.0, false]}, "hurdles": [30.0], "course_len": 100.0}
		),
		{}
	)
	assert_gt(float(running.mx), 0.5, "clear track: run")
	var done := brain.think(
		_play_state(
			"hurdle_dash",
			{"players": {0: [100.0, 0, 0.0, true]}, "hurdles": [], "course_len": 100.0}
		),
		{}
	)
	assert_true(done.is_empty(), "finished runners send nothing")


func test_tug_of_war_brain_alternates_pull_phases() -> void:
	var brain := BotBrains.brain_for(&"tug_of_war", 0, 1)
	var first := int(brain.think({}, {}).pull)
	var second := int(brain.think({}, {}).pull)
	var third := int(brain.think({}, {}).pull)
	assert_ne(first, second, "phase flips every think — the sim counts changes")
	assert_eq(first, third)


func test_gauntlet_brain_buys_by_priority_then_confirms() -> void:
	var brain := BotBrains.brain_for(&"gauntlet", 0, 1)
	var rich := {
		"state": MatchController.State.FINALE_SHOP,
		"shop": {"players": {0: {"coins": 120, "items": {}, "confirmed": false}}},
	}
	assert_eq(brain.think(rich, {}).shop.item, "extra_life", "120c: the life comes first")
	var mid := {
		"state": MatchController.State.FINALE_SHOP,
		"shop": {"players": {0: {"coins": 60, "items": {}, "confirmed": false}}},
	}
	assert_eq(brain.think(mid, {}).shop.item, "shield", "60c: shield next")
	var broke := {
		"state": MatchController.State.FINALE_SHOP,
		"shop": {"players": {0: {"coins": 20, "items": {}, "confirmed": false}}},
	}
	assert_eq(brain.think(broke, {}).shop.action, "confirm", "nothing affordable: lock in")
	var confirmed := {
		"state": MatchController.State.FINALE_SHOP,
		"shop": {"players": {0: {"coins": 20, "items": {}, "confirmed": true}}},
	}
	assert_true(brain.think(confirmed, {}).is_empty(), "confirmed bots stay quiet")


func test_gauntlet_brain_flees_hazards_without_leaving_the_platform() -> void:
	var brain := BotBrains.brain_for(&"gauntlet", 0, 1)
	var intent := (
		brain
		. think(
			{
				"state": MatchController.State.FINALE_PLAY,
				"minigame": "gauntlet",
				"game":
				{
					"radius": 10.0,
					"players": {0: [2.0, 0.0, 1, 0.0]},
					"hazards": [[2.5, 0.0, 1.5, 0.8]]
				},
			},
			{}
		)
	)
	assert_lt(float(intent.mx), 0.0, "flee inward, away from the hazard at +2.5")
	var eliminated := (
		brain
		. think(
			{
				"state": MatchController.State.FINALE_PLAY,
				"minigame": "gauntlet",
				"game": {"radius": 10.0, "players": {}, "hazards": []},
			},
			{}
		)
	)
	assert_true(eliminated.is_empty(), "eliminated bots send nothing")


## #584 weapons: an armed bot swings when a rival is in reach; an unarmed bot
## walks to the nearest floor axe when no hazard threatens it.
func test_gauntlet_brain_grabs_axes_and_swings_in_range() -> void:
	var brain := BotBrains.brain_for(&"gauntlet", 0, 1)
	var armed := (
		brain
		. think(
			{
				"state": MatchController.State.FINALE_PLAY,
				"minigame": "gauntlet",
				"game":
				{
					"radius": 10.0,
					"players": {0: [0.0, 0.0, 1, 0.0, 3, 0, 0], 1: [1.0, 0.0, 1, 0.0, 0, 0, 0]},
					"hazards": [],
					"weapons": []
				},
			},
			{}
		)
	)
	assert_true(armed.get("swing", false), "rival 1.0 away is inside SWING_RANGE — swing")
	var unarmed := (
		brain
		. think(
			{
				"state": MatchController.State.FINALE_PLAY,
				"minigame": "gauntlet",
				"game":
				{
					"radius": 10.0,
					"players": {0: [0.0, 0.0, 1, 0.0, 0, 0, 0]},
					"hazards": [],
					"weapons": [[3.0, 0.0]]
				},
			},
			{}
		)
	)
	assert_gt(float(unarmed.get("mx", 0.0)), 0.0, "unarmed: head for the axe at +3")
