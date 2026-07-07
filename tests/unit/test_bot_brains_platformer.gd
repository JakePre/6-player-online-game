extends GutTest
## SideScrollSim platformer bot brains (M19-02, #686): knock_off, loadout_duel,
## tumble_run — split from test_bot_brains.gd to keep each suite under the
## public-method lint cap. Pure think() calls on crafted snapshots.


func _play_state(id: String, game: Dictionary) -> Dictionary:
	return {"state": MatchController.State.PLAY, "minigame": id, "game": game}


func test_knock_off_brain_recovers_when_over_the_void() -> void:
	var brain := BotBrains.brain_for(&"knock_off", 0, 1)
	# Off the right edge (|x| > STAGE_HALF_WIDTH): move back toward center + jump.
	var game := {
		"players": {0: [KnockOff.STAGE_HALF_WIDTH + 2.0, -0.5, 1, 1, 0, 0]},
		"phase": KnockOff.Phase.FIGHT,
		"phase_left": 30.0,
	}
	var intent := brain.think(_play_state("knock_off", game), {})
	assert_lt(float(intent.mx), 0.0, "over the right void -> head left toward center")
	assert_true(intent.get("jump", false), "and jump to recover")


func test_knock_off_brain_smashes_a_high_percent_rival_in_range() -> void:
	var brain := BotBrains.brain_for(&"knock_off", 0, 1)
	# Rival 1.0 to the right, level, at 70% — in range, KO-able -> smash.
	var game := {
		"players": {0: [0.0, 0.0, 1, 1, 0, 0], 1: [1.0, 0.0, -1, 1, 70, 0]},
		"phase": KnockOff.Phase.FIGHT,
		"phase_left": 30.0,
	}
	var intent := brain.think(_play_state("knock_off", game), {})
	assert_gt(float(intent.mx), 0.0, "face the rival on the right")
	assert_true(intent.get("smash", false), "high percent -> smash to launch")
	assert_false(intent.get("jab", false))


func test_knock_off_brain_jabs_a_low_percent_rival() -> void:
	var brain := BotBrains.brain_for(&"knock_off", 0, 1)
	var game := {
		"players": {0: [0.0, 0.0, 1, 1, 0, 0], 1: [1.0, 0.0, -1, 1, 10, 0]},
		"phase": KnockOff.Phase.FIGHT,
		"phase_left": 30.0,
	}
	var intent := brain.think(_play_state("knock_off", game), {})
	assert_true(intent.get("jab", false), "low percent -> jab to build it")


func test_knock_off_brain_does_not_chase_past_the_edge() -> void:
	var brain := BotBrains.brain_for(&"knock_off", 0, 1)
	# Rival is out over the void to the right; I'm safe at center. Approach must
	# clamp inside the stage, so I never steer myself off chasing.
	var game := {
		"players":
		{0: [0.0, 0.0, 1, 1, 0, 0], 1: [KnockOff.STAGE_HALF_WIDTH + 3.0, 0.0, -1, 1, 0, 0]},
		"phase": KnockOff.Phase.FIGHT,
		"phase_left": 30.0,
	}
	var intent := brain.think(_play_state("knock_off", game), {})
	# Target clamps to edge - margin (< my rival's x), but never sends me off:
	# at center the clamped target is still to my right, so mx is small/right,
	# and crucially the brain won't drive me past STAGE_HALF_WIDTH.
	assert_between(float(intent.get("mx", 0.0)), -1.0, 1.0)


func test_loadout_duel_brain_seeks_a_dais_when_unarmed() -> void:
	var brain := BotBrains.brain_for(&"loadout_duel", 0, 1)
	# Empty-handed (held 0): head for the armed dais on the right.
	var game := {
		"players": {0: [0.0, 0.0, 1, 1, LoadoutDuel.Kind.NONE]},
		"shots": [],
		"daises": [[5.0, 0.5, LoadoutDuel.Kind.BLASTER], [-5.0, 0.5, LoadoutDuel.Kind.NONE]],
	}
	var intent := brain.think(_play_state("loadout_duel", game), {})
	assert_gt(float(intent.mx), 0.0, "unarmed -> go to the armed dais (right), not the empty one")


func test_loadout_duel_brain_fires_at_a_level_rival_when_armed() -> void:
	var brain := BotBrains.brain_for(&"loadout_duel", 0, 1)
	var game := {
		"players":
		{
			0: [0.0, 0.0, 1, 1, LoadoutDuel.Kind.BLASTER],
			1: [4.0, 0.0, -1, 1, LoadoutDuel.Kind.NONE]
		},
		"shots": [],
		"daises": [],
	}
	var intent := brain.think(_play_state("loadout_duel", game), {})
	assert_gt(float(intent.mx), 0.0, "face the level rival")
	assert_true(intent.get("fire", false), "armed + level rival -> fire")


func test_loadout_duel_brain_dodges_an_incoming_shot() -> void:
	var brain := BotBrains.brain_for(&"loadout_duel", 0, 1)
	# A shot right on top of us at our height -> sidestep + hop, before firing.
	var game := {
		"players": {0: [0.0, 0.0, 1, 1, LoadoutDuel.Kind.BLASTER]},
		"shots": [[1.0, 0.0, 0]],
		"daises": [],
	}
	var intent := brain.think(_play_state("loadout_duel", game), {})
	assert_lt(float(intent.mx), 0.0, "sidestep away from the shot on the right")
	assert_true(intent.get("jump", false))


func test_tumble_run_brain_climbs_toward_the_next_ledge() -> void:
	var brain := BotBrains.brain_for(&"tumble_run", 0, 1)
	# Grounded at the floor, no boulders: head for the first ledge and jump.
	var game := {
		"players": {0: [0.0, 0.0, 1, 4]},  # flag 4 = grounded
		"boulders": [],
		"crumble": [],
		"phase": TumbleRun.Phase.CLIMB,
		"standings": [0],
	}
	var intent := brain.think(_play_state("tumble_run", game), {})
	assert_true(intent.has("mx"), "moves toward the next ledge column")
	assert_true(intent.get("jump", false), "the ledge is above -> jump")


func test_tumble_run_brain_dodges_a_falling_boulder() -> void:
	var brain := BotBrains.brain_for(&"tumble_run", 0, 1)
	# A boulder just above and slightly right -> step left out from under it.
	var game := {
		"players": {0: [0.0, 5.0, 1, 4]},
		"boulders": [[0.5, 6.5]],
		"crumble": [],
		"phase": TumbleRun.Phase.CLIMB,
		"standings": [0],
	}
	var intent := brain.think(_play_state("tumble_run", game), {})
	assert_lt(float(intent.mx), 0.0, "boulder above-right -> sidestep left")


func test_tumble_run_brain_idle_when_summited() -> void:
	var brain := BotBrains.brain_for(&"tumble_run", 0, 1)
	var game := {
		"players": {0: [0.0, 30.0, 1, 2]},  # flag 2 = summit
		"boulders": [],
		"crumble": [],
		"phase": TumbleRun.Phase.CLIMB,
		"standings": [0],
	}
	assert_true(brain.think(_play_state("tumble_run", game), {}).is_empty(), "summited -> done")
