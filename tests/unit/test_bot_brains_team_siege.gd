extends GutTest
## Team-siege bot brains (M19-02, #686): fort_siege, wall_builders — split from
## test_bot_brains.gd to keep each suite under the public-method lint cap. Pure
## think() calls on crafted snapshots.


func _play_state(id: String, game: Dictionary) -> Dictionary:
	return {"state": MatchController.State.PLAY, "minigame": id, "game": game}


# --- fort_siege ------------------------------------------------------------


func test_fort_siege_brain_attacker_batters_the_standing_gate() -> void:
	var brain := BotBrains.brain_for(&"fort_siege", 0, 1)
	# Slot 0 attacks (team 0), starts well above the gate line -> push down.
	var game := {
		"phase": FortSiege.Phase.SIEGE,
		"attacking": 0,
		"gate": 1.0,
		"capture": 0.0,
		"players": {0: [0.0, 5.0], 1: [0.0, -8.0]},
		"teams": [[0], [1]],
		"times": [-1.0, -1.0],
	}
	var intent := brain.think(_play_state("fort_siege", game), {})
	assert_lt(float(intent.my), 0.0, "attacker above the gate -> push down toward it")


func test_fort_siege_brain_attacker_runs_at_the_home_relic_once_the_gate_falls() -> void:
	var brain := BotBrains.brain_for(&"fort_siege", 0, 1)
	var game := {
		"phase": FortSiege.Phase.SIEGE,
		"attacking": 0,
		"gate": 0.0,
		"capture": 0.0,
		"relic": [FortSiege.CORE_POS.x, FortSiege.CORE_POS.y, FortSiege.RelicState.AT_CORE, -1],
		"players": {0: [0.0, FortSiege.GATE_Y], 1: [0.0, -8.0]},
		"teams": [[0], [1]],
		"times": [-1.0, -1.0],
	}
	var intent := brain.think(_play_state("fort_siege", game), {})
	assert_lt(float(intent.my), 0.0, "gate down -> converge on the relic at the plinth (#1028)")


func test_fort_siege_brain_thief_sprints_the_relic_out() -> void:
	var brain := BotBrains.brain_for(&"fort_siege", 0, 1)
	var game := {
		"phase": FortSiege.Phase.SIEGE,
		"attacking": 0,
		"gate": 0.0,
		"capture": 0.4,
		"relic": [0.0, -5.0, FortSiege.RelicState.CARRIED, 0],
		"players": {0: [0.0, -5.0], 1: [0.0, -8.0]},
		"teams": [[0], [1]],
		"times": [-1.0, -1.0],
	}
	var intent := brain.think(_play_state("fort_siege", game), {})
	assert_gt(float(intent.my), 0.0, "carrying the relic -> run it out past the escape line")


func test_fort_siege_brain_defender_shoves_an_attacker_in_range() -> void:
	var brain := BotBrains.brain_for(&"fort_siege", 1, 1)
	# Slot 1 defends (team 1); an attacker sits well within shove range.
	var game := {
		"phase": FortSiege.Phase.SIEGE,
		"attacking": 0,
		"gate": 1.0,
		"capture": 0.0,
		"players": {0: [0.5, FortSiege.GATE_Y], 1: [0.0, FortSiege.GATE_Y]},
		"teams": [[0], [1]],
		"times": [-1.0, -1.0],
	}
	var intent := brain.think(_play_state("fort_siege", game), {})
	assert_true(intent.get("act", false), "attacker within shove radius -> shove")


func test_fort_siege_brain_defender_falls_back_to_the_home_relic_once_the_gate_falls() -> void:
	var brain := BotBrains.brain_for(&"fort_siege", 1, 1)
	var game := {
		"phase": FortSiege.Phase.SIEGE,
		"attacking": 0,
		"gate": 0.0,
		"capture": 0.0,
		"relic": [FortSiege.CORE_POS.x, FortSiege.CORE_POS.y, FortSiege.RelicState.AT_CORE, -1],
		"players": {0: [0.0, -8.0], 1: [0.0, FortSiege.GATE_Y - 2.0]},
		"teams": [[0], [1]],
		"times": [-1.0, -1.0],
	}
	var intent := brain.think(_play_state("fort_siege", game), {})
	assert_lt(float(intent.my), 0.0, "gate down -> defender guards the relic on its plinth")


func test_fort_siege_brain_defender_chases_the_thief() -> void:
	var brain := BotBrains.brain_for(&"fort_siege", 1, 1)
	# The thief carries the relic ABOVE the defender: the chase heads +y, the
	# opposite of the old fall-back-to-the-core instinct.
	var game := {
		"phase": FortSiege.Phase.SIEGE,
		"attacking": 0,
		"gate": 0.0,
		"capture": 0.5,
		"relic": [0.0, -3.5, FortSiege.RelicState.CARRIED, 0],
		"players": {0: [0.0, -3.5], 1: [0.0, -7.0]},
		"teams": [[0], [1]],
		"times": [-1.0, -1.0],
	}
	var intent := brain.think(_play_state("fort_siege", game), {})
	assert_gt(float(intent.my), 0.0, "defender chases the carrier, not the empty plinth (#1028)")


func test_fort_siege_brain_defender_moves_to_return_a_loose_relic() -> void:
	var brain := BotBrains.brain_for(&"fort_siege", 1, 1)
	var game := {
		"phase": FortSiege.Phase.SIEGE,
		"attacking": 0,
		"gate": 0.0,
		"capture": 0.5,
		"relic": [4.0, -4.0, FortSiege.RelicState.DROPPED, -1],
		"players": {0: [-6.0, 6.0], 1: [0.0, -4.0]},
		"teams": [[0], [1]],
		"times": [-1.0, -1.0],
	}
	var intent := brain.think(_play_state("fort_siege", game), {})
	assert_gt(float(intent.mx), 0.0, "defender heads for the loose relic to send it home")


func test_fort_siege_brain_idles_during_swap() -> void:
	var brain := BotBrains.brain_for(&"fort_siege", 0, 1)
	var game := {
		"phase": FortSiege.Phase.SWAP,
		"attacking": 1,
		"gate": 1.0,
		"capture": 0.0,
		"players": {0: [0.0, 0.0], 1: [0.0, -8.0]},
		"teams": [[0], [1]],
		"times": [-1.0, -1.0],
	}
	assert_true(
		brain.think(_play_state("fort_siege", game), {}).is_empty(), "swap phase -> nothing to do"
	)


# --- wall_builders -----------------------------------------------------------


func test_wall_builders_brain_carries_a_held_block_home() -> void:
	var brain := BotBrains.brain_for(&"wall_builders", 0, 1)
	# Slot 0 is on team 0 (wall at -WALL_X), holding a block near the middle.
	var game := {
		"players": {0: [0.0, 0.0, 1]},
		"blocks": [],
		"walls": [0, 0],
		"wall_x": WallBuilders.WALL_X,
		"teams": [[0], [1]],
	}
	var intent := brain.think(_play_state("wall_builders", game), {})
	assert_lt(float(intent.mx), 0.0, "carrying -> haul it home to the -x wall")


func test_wall_builders_brain_grabs_the_nearest_floor_block() -> void:
	var brain := BotBrains.brain_for(&"wall_builders", 0, 1)
	var game := {
		"players": {0: [0.0, 0.0, 0]},
		"blocks": [[3.0, 0.0], [-6.0, 0.0]],
		"walls": [0, 0],
		"wall_x": WallBuilders.WALL_X,
		"teams": [[0], [1]],
	}
	var intent := brain.think(_play_state("wall_builders", game), {})
	assert_gt(float(intent.mx), 0.0, "nearer block is to the right -> head there first")


func test_wall_builders_brain_steals_from_the_enemy_wall_with_no_blocks_up() -> void:
	var brain := BotBrains.brain_for(&"wall_builders", 0, 1)
	# No floor blocks, but the enemy (team 1, +x wall) has height -> go pry one.
	var game := {
		"players": {0: [0.0, 0.0, 0]},
		"blocks": [],
		"walls": [0, 3],
		"wall_x": WallBuilders.WALL_X,
		"teams": [[0], [1]],
	}
	var intent := brain.think(_play_state("wall_builders", game), {})
	assert_gt(float(intent.mx), 0.0, "enemy wall (+x) has blocks to steal -> head there")


func test_wall_builders_brain_idles_with_nothing_to_do() -> void:
	var brain := BotBrains.brain_for(&"wall_builders", 0, 1)
	var game := {
		"players": {0: [0.0, 0.0, 0]},
		"blocks": [],
		"walls": [0, 0],
		"wall_x": WallBuilders.WALL_X,
		"teams": [[0], [1]],
	}
	assert_true(
		brain.think(_play_state("wall_builders", game), {}).is_empty(),
		"no floor blocks and nothing to steal -> hold"
	)
