extends GutTest
## Dodgeball bot brain (#791): grabs loose balls, aims at the nearest hostile
## with a lead, and throws; empty-handed under fire it dodges or (sometimes)
## attempts a catch — the tunable imperfection knob (#715/#818). Its own file
## because test_bot_brains.gd sits at gdlint's public-method cap.


func _play_state(game: Dictionary) -> Dictionary:
	return {"state": MatchController.State.PLAY, "minigame": "dodgeball", "game": game}


func _brain(slot := 0, seed_value := 1) -> BotBrain:
	return BotBrains.brain_for(&"dodgeball", slot, seed_value)


func test_registry_maps_dodgeball_not_ro_sham_bo() -> void:
	assert_true(BotBrains.has_brain(&"dodgeball"))
	assert_false(BotBrains.has_brain(&"ro_sham_bo"), "the retired brain is gone")
	assert_true(_brain() is DodgeballBrain)


func test_runs_at_the_nearest_loose_ball_when_empty() -> void:
	var game := {
		"players": {0: [0.0, 0.0, 1.0, 0.0, 0, -1]},
		"balls": [[3.0, 0.0, Dodgeball.BallState.LOOSE, -1]],
		"team_mode": false,
	}
	var intent := _brain().think(_play_state(game), {})
	assert_gt(float(intent.get("mx", 0.0)), 0.5, "steers toward the loose ball")


func test_aims_and_throws_at_the_nearest_hostile_when_holding() -> void:
	var game := {
		"players": {0: [0.0, 0.0, 1.0, 0.0, 1, -1], 1: [4.0, 0.0, -1.0, 0.0, 0, -1]},
		"balls": [[0.0, 0.0, Dodgeball.BallState.HELD, 0]],
		"team_mode": false,
	}
	var intent := _brain().think(_play_state(game), {})
	assert_true(bool(intent.get("act", false)), "presses to throw")
	assert_gt(float(intent.get("mx", 0.0)), 0.3, "aims toward the rival on +x")


func test_team_brain_ignores_teammates_as_targets() -> void:
	# Holding, a teammate on +x and an enemy on -x: it must aim at the enemy.
	var game := {
		"players":
		{
			0: [0.0, 0.0, 1.0, 0.0, 1, 0],
			1: [4.0, 0.0, 0.0, 0.0, 0, 0],  # teammate
			2: [-4.0, 0.0, 0.0, 0.0, 0, 1],  # enemy
		},
		"balls": [[0.0, 0.0, Dodgeball.BallState.HELD, 0]],
		"team_mode": true,
	}
	var intent := _brain().think(_play_state(game), {})
	assert_lt(float(intent.get("mx", 0.0)), 0.0, "aims at the enemy, not the teammate")


func test_eliminated_bot_does_nothing() -> void:
	# Not present in the players map (eliminated) -> no intent.
	var game := {"players": {1: [0.0, 0.0, 0.0, 0.0, 0, -1]}, "balls": [], "team_mode": false}
	assert_eq(_brain(0).think(_play_state(game), {}), {})


func test_sometimes_attempts_a_catch_under_fire_not_always() -> void:
	# An incoming flying ball: across seeds the bot must sometimes try a catch
	# and sometimes dodge — a perfect always-catch bot would break the game.
	var game := {
		"players": {0: [0.0, 0.0, 1.0, 0.0, 0, -1]},
		"balls": [[1.5, 0.0, Dodgeball.BallState.FLYING, 1]],
		"team_mode": false,
	}
	var catches := 0
	var dodges := 0
	for seed_value in 40:
		var intent := _brain(0, seed_value).think(_play_state(game), {})
		if bool(intent.get("act", false)):
			catches += 1
		else:
			dodges += 1
	assert_gt(catches, 0, "some seeds attempt the catch")
	assert_gt(dodges, 0, "some seeds dodge instead — not a perfect catcher")
