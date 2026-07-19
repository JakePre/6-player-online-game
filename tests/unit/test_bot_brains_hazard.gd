extends GutTest
## Hazard-survival bot brains (M19-02, #686): bullet_waltz, blast_grid,
## laser_limbo — split from test_bot_brains.gd to keep each suite under the
## public-method lint cap. Pure think() calls on crafted snapshots.


func _play_state(id: String, game: Dictionary) -> Dictionary:
	return {"state": MatchController.State.PLAY, "minigame": id, "game": game}


## An all-empty BlastGrid grid; callers stamp in the SOLID/SOFT cells they want.
func _empty_grid() -> Array:
	var grid: Array = []
	grid.resize(BlastGrid.GRID * BlastGrid.GRID)
	grid.fill(BlastGrid.Cell.EMPTY)
	return grid


# --- bullet_waltz --------------------------------------------------------------


func test_bullet_waltz_brain_flees_a_close_bullet() -> void:
	var brain := BotBrains.brain_for(&"bullet_waltz", 0, 1)
	# A bullet just to our right (well inside SENSE_RADIUS) -> steer left away.
	var game := {"players": {0: [3.0, 0.0, 0]}, "bullets": [[3.5, 0.0]], "out": []}
	var intent := brain.think(_play_state("bullet_waltz", game), {})
	assert_lt(float(intent.mx), 0.0, "bullet on the right -> move left away from it")


func test_bullet_waltz_brain_pushes_inward_at_the_rim() -> void:
	var brain := BotBrains.brain_for(&"bullet_waltz", 0, 1)
	# Hugging the right rim, no bullets: push back inward (negative x).
	var game := {"players": {0: [8.5, 0.0, 0]}, "bullets": [], "out": []}
	var intent := brain.think(_play_state("bullet_waltz", game), {})
	assert_lt(float(intent.mx), 0.0, "at the rim -> steer back toward center")


func test_bullet_waltz_brain_eases_to_a_ring_when_clear() -> void:
	var brain := BotBrains.brain_for(&"bullet_waltz", 0, 1)
	# Mid-arena, no bullets, off the rim and off center: drift to a calm ring.
	var game := {"players": {0: [3.0, 0.0, 0]}, "bullets": [], "out": []}
	var intent := brain.think(_play_state("bullet_waltz", game), {})
	assert_true(intent.has("mx"), "no threat -> still produces a gentle move")


## #959: with no imminent threat, chase graze EV toward a mid-range stream
## instead of fleeing to a corner (the #926 camping realignment).
func test_bullet_waltz_brain_hunts_a_mid_range_stream() -> void:
	var brain := BotBrains.brain_for(&"bullet_waltz", 0, 1)
	var game := {"players": {0: [3.0, 0.0, 0, 1]}, "bullets": [[5.2, 0.0]], "out": []}
	var intent := brain.think(_play_state("bullet_waltz", game), {})
	assert_gt(float(intent.mx), 0.0, "no danger -> drift toward the stream for grazes")


## #959: a crush of bullets converging in the panic radius spends the held bomb.
func test_bullet_waltz_brain_bombs_a_converging_crush() -> void:
	var brain := BotBrains.brain_for(&"bullet_waltz", 0, 1)
	var game := {
		"players": {0: [0.0, 0.0, 0, 1]},
		"bullets": [[1.5, 0.0], [-1.4, 0.3], [0.0, 1.6]],
		"out": [],
	}
	var intent := brain.think(_play_state("bullet_waltz", game), {})
	assert_true(intent.get("bomb", false), "a converging crush spends the held bomb")


## #959: an already-spent bomb (flag 0) never re-triggers — just dodge.
func test_bullet_waltz_brain_holds_a_spent_bomb() -> void:
	var brain := BotBrains.brain_for(&"bullet_waltz", 0, 1)
	var game := {
		"players": {0: [0.0, 0.0, 0, 0]},
		"bullets": [[1.5, 0.0], [-1.4, 0.3], [0.0, 1.6]],
		"out": [],
	}
	var intent := brain.think(_play_state("bullet_waltz", game), {})
	assert_false(intent.get("bomb", false), "no charge left -> no bomb")


# --- blast_grid ----------------------------------------------------------------


func test_blast_grid_brain_flees_a_flame_on_its_cell() -> void:
	var brain := BotBrains.brain_for(&"blast_grid", 0, 1)
	# Standing dead center (cell 60) on a flame -> step to a safe neighbor.
	var center := 5 * BlastGrid.GRID + 5
	var game := {
		"players": {0: [0.0, 0.0, 2, 1]},
		"grid": _empty_grid(),
		"bombs": [],
		"flames": [center],
		"powerups": [],
		"fallen": [],
	}
	var intent := brain.think(_play_state("blast_grid", game), {})
	assert_false(intent.is_empty(), "on a flame -> move off it")
	assert_true(intent.has("mx") and intent.has("my"), "produces a move")


func test_blast_grid_brain_holds_when_boxed_in() -> void:
	var brain := BotBrains.brain_for(&"blast_grid", 0, 1)
	# On a flame at center with every neighbor a SOLID wall -> nowhere to go.
	var center := 5 * BlastGrid.GRID + 5
	var grid := _empty_grid()
	for n: int in [center - BlastGrid.GRID, center + BlastGrid.GRID, center - 1, center + 1]:
		grid[n] = BlastGrid.Cell.SOLID
	var game := {
		"players": {0: [0.0, 0.0, 2, 1]},
		"grid": grid,
		"bombs": [],
		"flames": [center],
		"powerups": [],
		"fallen": [],
	}
	assert_true(
		brain.think(_play_state("blast_grid", game), {}).is_empty(), "boxed in on a flame -> hold"
	)


func test_blast_grid_brain_bombs_a_soft_wall_with_an_escape() -> void:
	var brain := BotBrains.brain_for(&"blast_grid", 0, 1)
	# Center, a SOFT wall on our right neighbor, open elsewhere -> bomb it (a
	# corner escape exists via any open orthogonal neighbor).
	var center := 5 * BlastGrid.GRID + 5
	var grid := _empty_grid()
	grid[center + 1] = BlastGrid.Cell.SOFT
	var game := {
		"players": {0: [0.0, 0.0, 2, 1]},
		"grid": grid,
		"bombs": [],
		"flames": [],
		"powerups": [],
		"fallen": [],
	}
	var intent := brain.think(_play_state("blast_grid", game), {})
	assert_true(intent.get("bomb", false), "adjacent soft wall + escape -> drop a bomb")


## #949: with an own resting bomb between us and a rival down a clear line, the
## bot walks into the bomb (positive mx toward it) to kick it their way.
func test_blast_grid_brain_kicks_a_bomb_at_a_rival_in_line() -> void:
	var brain := BotBrains.brain_for(&"blast_grid", 0, 1)
	var center := 5 * BlastGrid.GRID + 5
	var grid := _empty_grid()
	var bcell := center + 1
	var bpos := Vector2((6 - 5) * BlastGrid.CELL_SIZE, 0.0)  # cell center of center+1
	var rival_pos := Vector2((8 - 5) * BlastGrid.CELL_SIZE, 0.0)  # two cells past the bomb
	var game := {
		"players": {0: [0.0, 0.0, 2, 1, 0], 1: [rival_pos.x, rival_pos.y, 2, 1, 0]},
		"grid": grid,
		"bombs": [[bcell, BlastGrid.BOMB_FUSE, bpos.x, bpos.y, 0]],
		"flames": [],
		"powerups": [],
		"fallen": [],
	}
	var intent := brain.think(_play_state("blast_grid", game), {})
	assert_gt(
		float(intent.get("mx", 0.0)), 0.5, "steps right onto the bomb to kick it at the rival"
	)


func test_blast_grid_brain_seeks_a_distant_soft_wall() -> void:
	var brain := BotBrains.brain_for(&"blast_grid", 0, 1)
	# A SOFT wall three cells to our right, nothing adjacent -> advance toward it.
	var center := 5 * BlastGrid.GRID + 5
	var grid := _empty_grid()
	grid[center + 3] = BlastGrid.Cell.SOFT
	var game := {
		"players": {0: [0.0, 0.0, 2, 1]},
		"grid": grid,
		"bombs": [],
		"flames": [],
		"powerups": [],
		"fallen": [],
	}
	var intent := brain.think(_play_state("blast_grid", game), {})
	assert_gt(float(intent.get("mx", 0.0)), 0.0, "distant soft wall on the right -> head right")
	assert_false(intent.get("bomb", false), "not adjacent yet -> don't waste a bomb")


func test_blast_grid_brain_avoids_stepping_into_a_live_bombs_blast() -> void:
	var brain := BotBrains.brain_for(&"blast_grid", 0, 1)
	# Safe now, but a live bomb sits one cell up; its cross makes that cell (and
	# our own) dangerous. We must not walk up into it while seeking.
	var center := 5 * BlastGrid.GRID + 5
	var up := center - BlastGrid.GRID
	var grid := _empty_grid()
	var game := {
		"players": {0: [0.0, 0.0, 2, 1]},
		"grid": grid,
		"bombs": [[up, 1.0]],
		"flames": [],
		"powerups": [],
		"fallen": [],
	}
	var intent := brain.think(_play_state("blast_grid", game), {})
	# The center cell is inside the bomb's vertical cross -> survival kicks in and
	# we step to a neighbor that is NOT in the blast (left/right, never up).
	assert_false(intent.is_empty(), "in a bomb's blast line -> flee")
	assert_lte(float(intent.get("my", 0.0)), 0.0001, "never step up toward the bomb")


## #961 regression: standing on our OWN live bomb, every orthogonal neighbor is
## inside the blast cross, so there is no immediately-safe hop. The bot must
## still MOVE — stepping along the blast line toward the corner escape — not
## freeze on the bomb until it detonates (the round-length-collapse bug: bots
## mass-froze on their opening bombs and every round ended in ~3s).
func test_blast_grid_brain_flees_its_own_bomb_via_the_corner() -> void:
	var brain := BotBrains.brain_for(&"blast_grid", 0, 1)
	# Center, open grid, our own bomb underfoot. A safe cell exists two steps out
	# (any perpendicular turn off the cross), so the escape is reachable.
	var center := 5 * BlastGrid.GRID + 5
	var game := {
		"players": {0: [0.0, 0.0, 2, 1]},
		"grid": _empty_grid(),
		"bombs": [[center, BlastGrid.BOMB_FUSE]],
		"flames": [],
		"powerups": [],
		"fallen": [],
	}
	var intent := brain.think(_play_state("blast_grid", game), {})
	assert_false(
		intent.is_empty(), "on our own bomb -> step toward the corner escape, never freeze"
	)
	assert_true(intent.has("mx") and intent.has("my"), "produces a real move off the bomb cell")


# --- laser_limbo ---------------------------------------------------------------


func test_laser_limbo_brain_jumps_a_low_wall() -> void:
	var brain := BotBrains.brain_for(&"laser_limbo", 0, 1)
	# A LOW wall approaching from the left, within jump distance, grounded -> jump.
	var game := {
		"players": {0: [0.0, 0.0, 3, 0, 0]},
		"walls": [[-2.0, 1, LaserLimbo.WallKind.LOW, 0.0]],
		"fallen": [],
	}
	var intent := brain.think(_play_state("laser_limbo", game), {})
	assert_true(intent.get("jump", false), "low wall in range -> jump it")


func test_laser_limbo_brain_ducks_a_high_wall() -> void:
	var brain := BotBrains.brain_for(&"laser_limbo", 0, 1)
	var game := {
		"players": {0: [0.0, 0.0, 3, 0, 0]},
		"walls": [[-2.0, 1, LaserLimbo.WallKind.HIGH, 0.0]],
		"fallen": [],
	}
	var intent := brain.think(_play_state("laser_limbo", game), {})
	assert_true(intent.get("duck", false), "high wall in range -> duck under it")


func test_laser_limbo_brain_slides_into_a_gap() -> void:
	var brain := BotBrains.brain_for(&"laser_limbo", 0, 1)
	# A GAP wall approaching; its opening is above us -> slide up toward it.
	var game := {
		"players": {0: [0.0, 0.0, 3, 0, 0]},
		"walls": [[-4.0, 1, LaserLimbo.WallKind.GAP, 3.0]],
		"fallen": [],
	}
	var intent := brain.think(_play_state("laser_limbo", game), {})
	assert_gt(float(intent.get("my", 0.0)), 0.0, "gap opening above -> slide up into it")


func test_laser_limbo_brain_ignores_a_wall_moving_away() -> void:
	var brain := BotBrains.brain_for(&"laser_limbo", 0, 1)
	# A wall that has already passed us (moving right, now to our right) -> hold.
	var game := {
		"players": {0: [0.0, 0.0, 3, 0, 0]},
		"walls": [[2.0, 1, LaserLimbo.WallKind.LOW, 0.0]],
		"fallen": [],
	}
	assert_true(
		brain.think(_play_state("laser_limbo", game), {}).is_empty(),
		"a wall past us is no threat -> no evasion"
	)
