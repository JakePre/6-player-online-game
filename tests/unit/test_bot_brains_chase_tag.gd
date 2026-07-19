extends GutTest
## Chase / tag / positional bot brains (M19-02, #686): hot_potato, shock_tag,
## bey_brawl, color_clash, snake_chain — steering assertions on crafted
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


# Snapshot rows are [x, y, spin, clash_seq] (BeyBrawl.PS_*, #708).


func test_bey_brawl_brain_retreats_from_the_lip() -> void:
	var brain := BotBrains.brain_for(&"bey_brawl", 0, 1)
	var game := {"radius": 8.0, "players": {0: [7.5, 0.0, 1.0, 0], 1: [-7.5, 0.0, 0.1, 0]}}
	var intent := brain.think(_play_state("bey_brawl", game), {})
	assert_lt(float(intent.mx), 0.0, "a clash at the lip is a ring-out: back inside first")


func test_bey_brawl_brain_hunts_while_its_spin_is_healthier() -> void:
	var brain := BotBrains.brain_for(&"bey_brawl", 0, 1)
	var game := {"radius": 8.0, "players": {0: [0.0, 0.0, 0.9, 0], 1: [3.0, 0.0, 0.4, 0]}}
	var intent := brain.think(_play_state("bey_brawl", game), {})
	assert_gt(float(intent.mx), 0.5, "spin advantage: steer into the rival")


func test_bey_brawl_brain_evades_while_its_spin_is_weaker() -> void:
	var brain := BotBrains.brain_for(&"bey_brawl", 0, 1)
	var game := {"radius": 8.0, "players": {0: [0.0, 0.0, 0.3, 0], 1: [3.0, 0.0, 0.9, 0]}}
	var intent := brain.think(_play_state("bey_brawl", game), {})
	assert_lt(float(intent.mx), 0.0, "weaker meter: steer away and recover")


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


## Home-turf bias (#955): given two equidistant unpainted targets — a frontier
## tile that touches the bot's own paint and an interior tile that doesn't — the
## painter grows its own edge (the frontier tile), so it travels along its own
## colour highway rather than lunging into open turf. The interior tile has the
## lower index, so plain nearest-first would return IT on the tie; only the
## own-edge weight flips the pick to the frontier tile.
func test_color_clash_brain_grows_its_own_edge() -> void:
	var brain := BotBrains.brain_for(&"color_clash", 0, 1) as ColorClashBrain
	# 5x5 board, all our paint except a plus of unpainted tiles around index 12.
	# 12 (interior) is ringed by unpainted; 17 (below) touches own paint at 22.
	var g: Array = []
	g.resize(25)
	g.fill(0)
	for idx: int in [7, 11, 12, 13, 17]:
		g[idx] = ColorClash.UNPAINTED
	brain._grid = g
	brain._dim = 5
	assert_false(brain._touches_faction(12, 0, 5), "the interior tile touches no own paint")
	assert_true(brain._touches_faction(17, 0, 5), "the frontier tile touches own paint")
	# me is equidistant to tile 12 (0,0) and tile 17 (0,1.5): the perpendicular
	# bisector at y=0.75. half = 5 * TILE_WORLD / 2 = 3.75.
	var target := brain._nearest_unowned_tile(Vector2(0.0, 0.75), 0, 5, 3.75)
	assert_almost_eq(target.x, 0.0, 0.001)
	assert_almost_eq(
		target.y, 1.5, 0.001, "own-edge bias picks the frontier tile over the interior one"
	)


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


# --- #926: flee spacing + rim-orbit -------------------------------------------


## Two hot_potato fleers stacked side-on to the carrier push apart instead of
## smearing into the same spot (the corner-stacking degeneracy).
func test_hot_potato_brain_fleers_spread_apart() -> void:
	var game := {
		"carrier": 2,
		"alive": [0, 1, 2],
		"players": {0: [-0.1, 2.0], 1: [0.1, 2.0], 2: [0.0, -4.0]},
		"fuse": 5.0,
		"holds": {},
	}
	var i0 := BotBrains.brain_for(&"hot_potato", 0, 1).think(_play_state("hot_potato", game), {})
	var i1 := BotBrains.brain_for(&"hot_potato", 1, 1).think(_play_state("hot_potato", game), {})
	assert_lt(float(i0.mx), float(i1.mx), "stacked fleers push apart, not together")


## Two clean shock_tag fleers stacked side-on to the zapped chaser spread apart.
func test_shock_tag_brain_fleers_spread_apart() -> void:
	var game := {
		"zapped": 2,
		"immunity": 0.0,
		"players": {0: [-0.1, 2.0, 0], 1: [0.1, 2.0, 0], 2: [0.0, -4.0, 0]},
	}
	var i0 := BotBrains.brain_for(&"shock_tag", 0, 1).think(_play_state("shock_tag", game), {})
	var i1 := BotBrains.brain_for(&"shock_tag", 1, 1).think(_play_state("shock_tag", game), {})
	assert_lt(float(i0.mx), float(i1.mx), "clean fleers spread instead of stacking")


## A shock_tag fleer pinned at the rim, chased outward, slides along the edge
## instead of pushing uselessly off it.
func test_shock_tag_brain_slides_along_the_rim() -> void:
	var game := {"zapped": 1, "immunity": 0.0, "players": {0: [8.7, 0.0, 0], 1: [6.0, 0.0, 0]}}
	var intent := BotBrains.brain_for(&"shock_tag", 0, 1).think(_play_state("shock_tag", game), {})
	assert_lt(absf(float(intent.mx)), 0.2, "the outward radial push is dropped at the rim")
	assert_gt(absf(float(intent.my)), 0.9, "slides tangentially along the rim instead")
