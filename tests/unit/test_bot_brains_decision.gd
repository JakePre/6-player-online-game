extends GutTest
## Decision/deduction bot brains (M19-02, #686): memory_match, poison_feast,
## pickpocket_plaza — split from test_bot_brains.gd to keep each suite under the
## public-method lint cap. Pure think() calls on crafted snapshots.


func _play_state(id: String, game: Dictionary) -> Dictionary:
	return {"state": MatchController.State.PLAY, "minigame": id, "game": game}


# --- memory_match --------------------------------------------------------------


func test_memory_match_brain_heads_for_a_safe_tile_while_shown() -> void:
	var brain := BotBrains.brain_for(&"memory_match", 0, 1)
	# Safe tile 0 sits at the top-left corner (-5, -5); we start bottom-right.
	var game := {
		"players": {0: [5.0, 5.0]},
		"phase": MemoryMatch.Phase.SHOW,
		"safe_tiles": [0],
		"grid_size": MemoryMatch.GRID_SIZE,
		"round": 0,
		"fallen": [],
	}
	var intent := brain.think(_play_state("memory_match", game), {})
	assert_lt(float(intent.mx), 0.0, "safe tile is up-left -> move left")
	assert_lt(float(intent.my), 0.0, "safe tile is up-left -> move up")


func test_memory_match_brain_remembers_the_pattern_after_dark() -> void:
	var brain := BotBrains.brain_for(&"memory_match", 0, 1)
	brain.error_rate = 0.0  # test clean recall; the slip has its own test (#962)
	# Show the pattern once so the brain can memorise it...
	var shown := {
		"players": {0: [5.0, 5.0]},
		"phase": MemoryMatch.Phase.SHOW,
		"safe_tiles": [0],
		"grid_size": MemoryMatch.GRID_SIZE,
		"round": 0,
		"fallen": [],
	}
	brain.think(_play_state("memory_match", shown), {})
	# ...then go dark (safe_tiles blank) and confirm it still steers to tile 0.
	var dark := {
		"players": {0: [5.0, 5.0]},
		"phase": MemoryMatch.Phase.DARK,
		"safe_tiles": [],
		"grid_size": MemoryMatch.GRID_SIZE,
		"round": 0,
		"fallen": [],
	}
	var intent := brain.think(_play_state("memory_match", dark), {})
	assert_lt(float(intent.mx), 0.0, "remembered safe tile up-left -> still move left in the dark")
	assert_lt(float(intent.my), 0.0, "remembered safe tile up-left -> still move up in the dark")


func test_memory_match_brain_holds_once_on_a_safe_tile() -> void:
	var brain := BotBrains.brain_for(&"memory_match", 0, 1)
	# Standing dead centre of safe tile 0 (-5, -5): nothing to do but wait.
	var game := {
		"players": {0: [-5.0, -5.0]},
		"phase": MemoryMatch.Phase.SHOW,
		"safe_tiles": [0],
		"grid_size": MemoryMatch.GRID_SIZE,
		"round": 0,
		"fallen": [],
	}
	var intent := brain.think(_play_state("memory_match", game), {})
	assert_almost_eq(float(intent.get("mx", 0.0)), 0.0, 0.01, "already safe -> hold x")
	assert_almost_eq(float(intent.get("my", 0.0)), 0.0, 0.01, "already safe -> hold y")


## #962: perfect recall makes every memory-game bot survive → full-survivor
## ties. Under the #818 error knob the bot sometimes blanks and commits to a
## single wrongly-recalled tile when the lights go out — producing the human
## failures that spread placements. (The generic aim-jitter can't do this: the
## remembered tile is a destination, not an aim it can wobble.)
func test_memory_match_brain_can_misremember_under_the_error_knob() -> void:
	var brain := BotBrains.brain_for(&"memory_match", 0, 1)
	brain.error_rate = 1.0  # force the slip every round
	var shown := {
		"players": {0: [5.0, 5.0]},
		"phase": MemoryMatch.Phase.SHOW,
		"safe_tiles": [0, 35],
		"grid_size": MemoryMatch.GRID_SIZE,
		"round": 0,
		"fallen": [],
	}
	brain.think(_play_state("memory_match", shown), {})
	assert_eq(brain._known_safe, [0, 35], "both tiles memorized cleanly while shown")
	var dark := {
		"players": {0: [5.0, 5.0]},
		"phase": MemoryMatch.Phase.DARK,
		"safe_tiles": [],
		"grid_size": MemoryMatch.GRID_SIZE,
		"round": 0,
		"fallen": [],
	}
	brain.think(_play_state("memory_match", dark), {})
	assert_eq(brain._known_safe.size(), 1, "blanked to a single wrongly-recalled tile in the dark")


# --- poison_feast --------------------------------------------------------------


func test_poison_feast_brain_beelines_the_golden_course() -> void:
	var brain := BotBrains.brain_for(&"poison_feast", 0, 1)
	# A cheap clean dish is right next to us, the golden is far left -> golden wins.
	var game := {
		"players": {0: [0.0, 0.0, 0, 0]},
		"dishes": [[1, 1.0, 0.0, PoisonFeast.Tier.CLEAN], [2, -5.0, 0.0, PoisonFeast.Tier.GOLDEN]],
		"pot": 0,
	}
	var intent := brain.think(_play_state("poison_feast", game), {})
	assert_lt(float(intent.mx), 0.0, "golden dwarfs the near clean -> head for it")


func test_poison_feast_brain_banks_the_pot_with_a_clean_bite() -> void:
	var brain := BotBrains.brain_for(&"poison_feast", 0, 1)
	# Pot is up for grabs: a nearer spiced dish is a trap; take the safe clean.
	var game := {
		"players": {0: [0.0, 0.0, 0, 0]},
		"dishes": [[1, -1.0, 0.0, PoisonFeast.Tier.SPICED], [2, 3.0, 0.0, PoisonFeast.Tier.CLEAN]],
		"pot": 5,
	}
	var intent := brain.think(_play_state("poison_feast", game), {})
	assert_gt(float(intent.mx), 0.0, "pot on the table -> claim it with the clean dish (right)")


func test_poison_feast_brain_prefers_value_over_a_near_gamble() -> void:
	var brain := BotBrains.brain_for(&"poison_feast", 0, 1)
	# Even-money delicacy is closest, but a positive-EV spiced is worth the walk.
	var game := {
		"players": {0: [0.0, 0.0, 0, 0]},
		"dishes":
		[[1, 1.0, 0.0, PoisonFeast.Tier.DELICACY], [2, -3.0, 0.0, PoisonFeast.Tier.SPICED]],
		"pot": 0,
	}
	var intent := brain.think(_play_state("poison_feast", game), {})
	assert_lt(float(intent.mx), 0.0, "skip the near delicacy -> go to the spiced dish (left)")


func test_poison_feast_brain_gambles_when_only_delicacies_remain() -> void:
	var brain := BotBrains.brain_for(&"poison_feast", 0, 1)
	var game := {
		"players": {0: [0.0, 0.0, 0, 0]},
		"dishes": [[1, 4.0, 0.0, PoisonFeast.Tier.DELICACY]],
		"pot": 0,
	}
	var intent := brain.think(_play_state("poison_feast", game), {})
	assert_gt(float(intent.mx), 0.0, "nothing safer left -> take the delicacy gamble (right)")


# --- pickpocket_plaza ----------------------------------------------------------


func test_pickpocket_guard_arrests_a_suspect_in_range() -> void:
	var brain := BotBrains.brain_for(&"pickpocket_plaza", 2, 1)
	# Our puppeted body is crowd[0] at origin; a suspect thief is 0.5 away.
	var game := {
		"crowd": [[0.0, 0.0]],
		"thieves": {1: [0.5, 0.0, 0, 1]},
		"guard": 2,
		"scores": {},
		"alarm": false,
		"time_left": 30.0,
	}
	var intent := brain.think(_play_state("pickpocket_plaza", game), {"role": "guard", "body": 0})
	assert_true(intent.get("act", false), "suspect within arrest range -> arrest")


func test_pickpocket_guard_shadows_the_nearest_thief_when_none_suspect() -> void:
	var brain := BotBrains.brain_for(&"pickpocket_plaza", 2, 1)
	var game := {
		"crowd": [[0.0, 0.0]],
		"thieves": {1: [5.0, 0.0, 0, 0]},
		"guard": 2,
		"scores": {},
		"alarm": false,
		"time_left": 30.0,
	}
	var intent := brain.think(_play_state("pickpocket_plaza", game), {"role": "guard", "body": 0})
	assert_gt(float(intent.get("mx", 0.0)), 0.0, "no suspect -> move toward the thief (right)")
	assert_false(intent.get("act", false), "don't waste an arrest with nobody arrestable")


func test_pickpocket_thief_breaks_away_while_suspect() -> void:
	var brain := BotBrains.brain_for(&"pickpocket_plaza", 0, 1)
	# We just lifted (suspect flag set); a body sits to our right — any could be
	# the guard, so peel off to the left.
	var game := {
		"crowd": [[1.0, 0.0]],
		"thieves": {0: [0.0, 0.0, 0, 1]},
		"guard": 3,
		"scores": {},
		"alarm": false,
		"time_left": 30.0,
	}
	var intent := brain.think(_play_state("pickpocket_plaza", game), {})
	assert_lt(float(intent.mx), 0.0, "suspect -> break away from the nearest body (left)")


func test_pickpocket_thief_works_the_nearest_villager_when_clear() -> void:
	var brain := BotBrains.brain_for(&"pickpocket_plaza", 0, 1)
	var game := {
		"crowd": [[3.0, 0.0]],
		"thieves": {0: [0.0, 0.0, 0, 0]},
		"guard": 3,
		"scores": {},
		"alarm": false,
		"time_left": 30.0,
	}
	var intent := brain.think(_play_state("pickpocket_plaza", game), {})
	assert_gt(float(intent.mx), 0.0, "clear to work -> close on the nearest villager (right)")


func test_pickpocket_thief_frozen_while_stunned() -> void:
	var brain := BotBrains.brain_for(&"pickpocket_plaza", 0, 1)
	var game := {
		"crowd": [[3.0, 0.0]],
		"thieves": {0: [0.0, 0.0, 1, 0]},
		"guard": 3,
		"scores": {},
		"alarm": false,
		"time_left": 30.0,
	}
	assert_true(
		brain.think(_play_state("pickpocket_plaza", game), {}).is_empty(), "stunned -> no input"
	)
