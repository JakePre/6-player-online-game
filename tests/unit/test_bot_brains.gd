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


# --- Hidden / rotating-role batch (M19-02, #686) ------------------------------


func test_the_mole_brain_drains_the_machine_when_progress_is_worth_it() -> void:
	var brain := BotBrains.brain_for(&"the_mole", 0, 1)
	var game := {
		"phase": TheMole.Phase.WORK,
		"progress": 5,
		"sparked": false,
		"players": {0: [0.0, 0.0, 0], 1: [4.0, 4.0, 0]},
		"cells": [[6.0, 0.0]],
	}
	var intent := brain.think(_play_state("the_mole", game), {"role": "mole"})
	assert_true(
		bool(intent.get("act", false)), "the mole at the machine with banked fuel sabotages"
	)


func test_the_mole_brain_crew_hauls_the_nearest_cell() -> void:
	var brain := BotBrains.brain_for(&"the_mole", 0, 1)
	var game := {
		"phase": TheMole.Phase.WORK,
		"progress": 1,
		"sparked": false,
		"players": {0: [0.0, 0.0, 0]},
		"cells": [[6.0, 0.0], [-9.0, 0.0]],
	}
	var intent := brain.think(_play_state("the_mole", game), {})
	assert_gt(float(intent.get("mx", 0.0)), 0.5, "crew runs at the nearer cell (+x)")
	assert_false(intent.has("act"), "crew never sabotages")


func test_the_mole_brain_crew_votes_the_sparked_suspect() -> void:
	var brain := BotBrains.brain_for(&"the_mole", 0, 1)
	# A spark fires (rising edge) with rival slot 2 standing on the machine.
	var work := {
		"phase": TheMole.Phase.WORK,
		"progress": 4,
		"sparked": true,
		"players": {0: [5.0, 5.0, 0], 1: [8.0, 0.0, 0], 2: [0.0, 0.0, 0]},
		"cells": [],
	}
	brain.think(_play_state("the_mole", work), {})
	var vote := {
		"phase": TheMole.Phase.VOTE,
		"players": {0: [5.0, 5.0, 0], 1: [8.0, 0.0, 0], 2: [0.0, 0.0, 0]},
		"cells": [],
	}
	var intent := brain.think(_play_state("the_mole", vote), {})
	assert_eq(int(intent.get("vote", -1)), 2, "votes the one caught at the machine on the spark")


func test_the_mole_brain_mole_votes_an_innocent() -> void:
	var brain := BotBrains.brain_for(&"the_mole", 1, 1)
	var vote := {
		"phase": TheMole.Phase.VOTE,
		"players": {0: [0.0, 0.0, 0], 1: [1.0, 1.0, 0], 2: [2.0, 2.0, 0]},
		"cells": [],
	}
	var intent := brain.think(_play_state("the_mole", vote), {"role": "mole"})
	assert_true(intent.has("vote"), "the mole casts a deflecting vote")
	assert_ne(int(intent.vote), 1, "never votes itself")


func test_faulty_wiring_brain_saboteur_cuts_the_best_node_off_cooldown() -> void:
	var brain := BotBrains.brain_for(&"faulty_wiring", 0, 1)
	var game := {
		"phase": FaultyWiring.Phase.WORK,
		"players": {0: [5.0, 5.0]},
		"nodes": [[5.0, 5.0, 0.8, 0], [-5.0, -5.0, 0.1, 0]],
	}
	var intent := brain.think(
		_play_state("faulty_wiring", game), {"role": "saboteur", "cut_cd": 0.0}
	)
	assert_true(bool(intent.get("cut", false)), "cuts the highest-value node it stands on")


func test_faulty_wiring_brain_saboteur_holds_cut_on_cooldown() -> void:
	var brain := BotBrains.brain_for(&"faulty_wiring", 0, 1)
	var game := {
		"phase": FaultyWiring.Phase.WORK,
		"players": {0: [5.0, 5.0]},
		"nodes": [[5.0, 5.0, 0.8, 0]],
	}
	var intent := brain.think(
		_play_state("faulty_wiring", game), {"role": "saboteur", "cut_cd": 2.0}
	)
	assert_false(intent.has("cut"), "no cut while the private cooldown is live")


func test_faulty_wiring_brain_crew_moves_to_an_unfinished_node() -> void:
	var brain := BotBrains.brain_for(&"faulty_wiring", 0, 1)
	var game := {
		"phase": FaultyWiring.Phase.WORK,
		"players": {0: [0.0, 0.0]},
		"nodes":
		[[-5.0, -5.0, 0.2, 0], [5.0, -5.0, 1.0, 0], [-5.0, 5.0, 1.0, 0], [5.0, 5.0, 1.0, 0]],
	}
	var intent := brain.think(_play_state("faulty_wiring", game), {})
	assert_lt(float(intent.get("mx", 0.0)), 0.0, "heads to node[0] (unfinished, its sl%count pick)")
	assert_false(intent.has("cut"), "crew never cuts")


func test_faulty_wiring_brain_idle_outside_work() -> void:
	var brain := BotBrains.brain_for(&"faulty_wiring", 0, 1)
	var game := {"phase": FaultyWiring.Phase.REVEAL, "players": {0: [0.0, 0.0]}, "nodes": []}
	assert_eq(brain.think(_play_state("faulty_wiring", game), {}), {}, "no input during the reveal")


func test_trap_corridor_brain_trapper_arms_interior_tiles() -> void:
	var brain := BotBrains.brain_for(&"trap_corridor", 0, 1)
	var game := {
		"phase": TrapCorridor.Phase.TRAPPING,
		"trapper": 0,
		"traps_left": 6,
		"players": {},
		"revealed": []
	}
	var intent := brain.think(_play_state("trap_corridor", game), {})
	assert_true(intent.has("trap"), "the trapper arms a tile")
	var col := int((intent.trap as Array)[0])
	assert_between(col, 1, TrapCorridor.COLS - 2, "never the safe start/finish columns")


func test_trap_corridor_brain_trapper_stops_at_budget() -> void:
	var brain := BotBrains.brain_for(&"trap_corridor", 0, 1)
	var game := {
		"phase": TrapCorridor.Phase.TRAPPING,
		"trapper": 0,
		"traps_left": 0,
		"players": {},
		"revealed": []
	}
	assert_eq(
		brain.think(_play_state("trap_corridor", game), {}), {}, "budget spent: nothing to arm"
	)


func test_trap_corridor_brain_runner_pushes_to_the_finish() -> void:
	var brain := BotBrains.brain_for(&"trap_corridor", 0, 1)
	var game := {
		"phase": TrapCorridor.Phase.RUNNING,
		"trapper": 1,
		"players": {0: [2.0, 0.0]},
		"revealed": []
	}
	var intent := brain.think(_play_state("trap_corridor", game), {})
	assert_almost_eq(float(intent.get("mx", 0.0)), 1.0, 0.001, "runs flat out toward the finish")


func test_trap_corridor_brain_runner_steers_to_a_sprung_safe_lane() -> void:
	var brain := BotBrains.brain_for(&"trap_corridor", 0, 1)
	# A revealed (already-sprung, safe) tile at col 3, row 4, two rows above us.
	var safe_tile := 3 * TrapCorridor.ROWS + 4
	var game := {
		"phase": TrapCorridor.Phase.RUNNING,
		"trapper": 1,
		"players": {0: [2.0, 0.0]},
		"revealed": [safe_tile],
	}
	var intent := brain.think(_play_state("trap_corridor", game), {})
	assert_gt(float(intent.get("my", 0.0)), 0.0, "steers toward the known-safe lane ahead")


func test_trap_corridor_brain_idle_when_not_your_turn_to_trap() -> void:
	var brain := BotBrains.brain_for(&"trap_corridor", 0, 1)
	var game := {
		"phase": TrapCorridor.Phase.TRAPPING,
		"trapper": 1,
		"traps_left": 6,
		"players": {},
		"revealed": []
	}
	assert_eq(
		brain.think(_play_state("trap_corridor", game), {}), {}, "non-trappers wait out TRAPPING"
	)
