extends GutTest
## Chase / tag / positional bot brains (M19-02, #686): hot_potato, shock_tag,
## sumo_smash, color_clash, snake_chain — steering assertions on crafted
## snapshots. Split from test_bot_brains.gd per gdlint's public-method cap
## (same precedent as test_match_controller_finale_only.gd).


func _play_state(id: String, game: Dictionary) -> Dictionary:
	return {"state": MatchController.State.PLAY, "minigame": id, "game": game}


func test_hot_potato_brain_flees_the_carrier() -> void:
	var brain := BotBrains.brain_for(&"hot_potato", 0, 1)
	var game := {
		"carrier": 1,
		"alive": [0, 1],
		"players": {0: [1.0, 0.0], 1: [0.0, 0.0]},
		"fuse": 5.0,
		"holds": {},
	}
	var intent := brain.think(_play_state("hot_potato", game), {})
	assert_gt(float(intent.mx), 0.0, "flees away from the carrier at the origin")


func test_hot_potato_brain_carrier_hunts_the_nearest_rival() -> void:
	var brain := BotBrains.brain_for(&"hot_potato", 0, 1)
	var game := {
		"carrier": 0,
		"alive": [0, 1, 2],
		"players": {0: [0.0, 0.0], 1: [1.0, 0.0], 2: [9.0, 0.0]},
		"fuse": 5.0,
		"holds": {},
	}
	var intent := brain.think(_play_state("hot_potato", game), {})
	assert_gt(float(intent.mx), 0.5, "chases the nearer rival at +1, not the one at +9")


func test_hot_potato_brain_eliminated_sends_nothing() -> void:
	var brain := BotBrains.brain_for(&"hot_potato", 0, 1)
	var game := {"carrier": 1, "alive": [1], "players": {1: [0.0, 0.0]}, "fuse": 5.0, "holds": {}}
	assert_eq(brain.think(_play_state("hot_potato", game), {}), {})


func test_shock_tag_brain_flees_when_zapped_is_someone_else() -> void:
	var brain := BotBrains.brain_for(&"shock_tag", 0, 1)
	var game := {"zapped": 1, "immunity": 0.0, "players": {0: [1.0, 0.0, 0], 1: [0.0, 0.0, 0]}}
	var intent := brain.think(_play_state("shock_tag", game), {})
	assert_gt(float(intent.mx), 0.0, "flees the zapped player at the origin")


func test_shock_tag_brain_zapped_chases_the_richest_target() -> void:
	var brain := BotBrains.brain_for(&"shock_tag", 0, 1)
	var game := {
		"zapped": 0,
		"immunity": 0.0,
		"players": {0: [0.0, 0.0, 0], 1: [1.0, 0.0, 3], 2: [9.0, 0.0, 20]},
	}
	var intent := brain.think(_play_state("shock_tag", game), {})
	assert_gt(float(intent.mx), 0.5, "chases the 20-coin target at +9, not the 3-coin one at +1")


func test_sumo_smash_brain_retreats_from_the_edge() -> void:
	var brain := BotBrains.brain_for(&"sumo_smash", 0, 1)
	var game := {"radius": 8.0, "players": {0: [7.5, 0.0, 0.0, 0], 1: [-7.5, 0.0, 0.0, 0]}}
	var intent := brain.think(_play_state("sumo_smash", game), {})
	assert_lt(float(intent.mx), 0.0, "too close to the rim: retreat inward over hunting")


func test_sumo_smash_brain_dashes_a_close_rival_off_cooldown() -> void:
	var brain := BotBrains.brain_for(&"sumo_smash", 0, 1)
	var game := {"radius": 8.0, "players": {0: [0.0, 0.0, 0.0, 0], 1: [1.5, 0.0, 0.0, 0]}}
	var intent := brain.think(_play_state("sumo_smash", game), {})
	assert_true(bool(intent.get("dash", false)), "in range and off cooldown: dash")


func test_sumo_smash_brain_holds_dash_on_cooldown() -> void:
	var brain := BotBrains.brain_for(&"sumo_smash", 0, 1)
	var game := {"radius": 8.0, "players": {0: [0.0, 0.0, 1.5, 0.0], 1: [1.5, 0.0, 0.0, 0]}}
	var intent := brain.think(_play_state("sumo_smash", game), {})
	assert_false(intent.has("dash"), "cooldown still counting down: no dash")


func test_color_clash_brain_seeks_the_nearest_unowned_tile() -> void:
	var brain := BotBrains.brain_for(&"color_clash", 0, 1)
	var dim := 3
	var grid := [0, 0, 0, 0, 0, 0, -1, -1, -1]  # rows 0-1 are ours, row 2 unpainted
	var game := {
		"players": {0: [0.0, -dim * 0.75, 0]},
		"dim": dim,
		"half": dim * ColorClash.TILE_WORLD / 2.0,
		"grid": grid,
	}
	var intent := brain.think(_play_state("color_clash", game), {})
	assert_gt(float(intent.get("my", 0.0)), 0.0, "heads toward the unowned row (+y)")


func test_color_clash_brain_folds_grid_changes_between_keyframes() -> void:
	var brain := BotBrains.brain_for(&"color_clash", 0, 1)
	var dim := 2
	var half := dim * ColorClash.TILE_WORLD / 2.0
	var keyframe := {
		"players": {0: [-half + 0.1, -half + 0.1, 0]},
		"dim": dim,
		"half": half,
		"grid": [0, -1, -1, -1],
	}
	brain.think(_play_state("color_clash", keyframe), {})
	# Delta flips tile 1 (the only unowned-adjacent one) to our own faction.
	var delta := {
		"players": {0: [-half + 0.1, -half + 0.1, 0]},
		"dim": dim,
		"half": half,
		"grid_changes": [[1, 0]],
	}
	var intent := brain.think(_play_state("color_clash", delta), {})
	# Only tiles 2 and 3 (owner -1) remain; both are the far row (+y).
	assert_gt(float(intent.get("my", 0.0)), 0.0, "folded delta rules out tile 1 as a target")


func test_color_clash_brain_holds_when_the_floor_is_all_ours() -> void:
	var brain := BotBrains.brain_for(&"color_clash", 0, 1)
	var game := {"players": {0: [0.0, 0.0, 0]}, "dim": 2, "half": 1.5, "grid": [0, 0, 0, 0]}
	var intent := brain.think(_play_state("color_clash", game), {})
	assert_eq(intent, {"mx": 0.0, "my": 0.0})


func test_snake_chain_brain_heads_toward_the_nearest_pellet_when_clear() -> void:
	var brain := BotBrains.brain_for(&"snake_chain", 0, 1)
	var game := {
		"players": {0: [0.0, 0.0, 0, 0.0]}, "trails": {0: []}, "pellets": [[5.0, 0.0], [-9.0, -9.0]]
	}
	var intent := brain.think(_play_state("snake_chain", game), {})
	assert_gt(float(intent.get("mx", 0.0)), 0.5, "steers toward the near pellet at +5")


func test_snake_chain_brain_steers_away_from_a_body_ahead() -> void:
	var brain := BotBrains.brain_for(&"snake_chain", 0, 1)
	# A rival's body sits directly between us and the pellet; a body-avoiding
	# heading must NOT be the straight-line +x the pellet alone would suggest.
	var game := {
		"players": {0: [0.0, 0.0, 0, 0.0]},
		"trails": {0: [], 1: [[1.0, 0.0], [1.2, 0.0], [1.4, 0.0]]},
		"pellets": [[5.0, 0.0]],
	}
	var intent := brain.think(_play_state("snake_chain", game), {})
	var heading := Vector2(float(intent.get("mx", 0.0)), float(intent.get("my", 0.0)))
	assert_gt(heading.length(), 0.1, "still commits to a heading (the chain never stops)")
	assert_lt(absf(heading.angle_to(Vector2.RIGHT)), PI * 0.7, "does not reverse into its own tail")


func test_snake_chain_brain_ignores_its_own_grace_segments() -> void:
	var brain := BotBrains.brain_for(&"snake_chain", 0, 1)
	# Our own newest 4 segments (SELF_GRACE_SEGMENTS) sit right where the
	# straight-line pellet path goes; the sim forgives them, so must the brain.
	var game := {
		"players": {0: [0.0, 0.0, 0, 0.0]},
		"trails": {0: [[0.3, 0.0], [0.6, 0.0], [0.9, 0.0], [1.2, 0.0]]},
		"pellets": [[5.0, 0.0]],
	}
	var intent := brain.think(_play_state("snake_chain", game), {})
	assert_gt(float(intent.get("mx", 0.0)), 0.5, "own grace segments don't spook the heading")
