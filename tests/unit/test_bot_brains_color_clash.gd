extends GutTest
## Color Clash painter brain home-turf bias (#955, M19-02). Split from
## test_bot_brains.gd per gdlint's public-method cap (same precedent as
## test_bot_brains_collector.gd).


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
