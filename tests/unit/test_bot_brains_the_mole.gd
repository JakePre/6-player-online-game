extends GutTest
## The Mole hidden-role bot brain (M19-02, #686 · Blackout #958): crew hauling,
## sabotage timing, spark-suspect voting, and the Blackout charge — steering/
## decision assertions on crafted snapshots. Split from test_bot_brains.gd per
## gdlint's public-method cap (same precedent as test_bot_brains_chase_tag.gd).


func _play_state(id: String, game: Dictionary) -> Dictionary:
	return {"state": MatchController.State.PLAY, "minigame": id, "game": game}


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


## #958: the mole cuts the lights when rivals crowd the machine and the charge
## is still in hand; a spent charge never re-triggers.
func test_the_mole_brain_cuts_the_lights_when_the_crew_crowds_the_machine() -> void:
	var brain := BotBrains.brain_for(&"the_mole", 0, 1)
	var game := {
		"phase": TheMole.Phase.WORK,
		"progress": 4,
		"sparked": false,
		# Two rivals right on the machine with the mole — about to pin the drain.
		"players": {0: [0.5, 0.0, 0], 1: [0.0, 0.5, 0], 2: [-0.5, 0.0, 0]},
		"cells": [],
	}
	var private := {"role": "mole", "blackout_ready": true}
	var intent := brain.think(_play_state("the_mole", game), private)
	assert_true(bool(intent.get("blackout", false)), "a crowded machine spends the blackout")


func test_the_mole_brain_holds_a_spent_blackout() -> void:
	var brain := BotBrains.brain_for(&"the_mole", 0, 1)
	var game := {
		"phase": TheMole.Phase.WORK,
		"progress": 4,
		"sparked": false,
		"players": {0: [0.5, 0.0, 0], 1: [0.0, 0.5, 0], 2: [-0.5, 0.0, 0]},
		"cells": [],
	}
	var private := {"role": "mole", "blackout_ready": false}
	var intent := brain.think(_play_state("the_mole", game), private)
	assert_false(bool(intent.get("blackout", false)), "no charge -> no blackout")
