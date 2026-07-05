extends GutTest
## Blast Grid client view (M14-06): renders the replicated grid, bombs,
## flames, power-ups and players without simulating anything locally.

const VIEW_SCENE: PackedScene = preload("res://src/minigames/blast_grid/blast_grid_view.tscn")
const G := BlastGrid.GRID

var view: MinigameView3D


func before_each() -> void:
	view = VIEW_SCENE.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func _full_grid(kind: int = BlastGrid.Cell.EMPTY) -> Array:
	var out: Array = []
	out.resize(G * G)
	out.fill(kind)
	return out


func _cell(r: int, c: int) -> int:
	return r * G + c


## Logical block count from the view's own map — `queue_free()` defers a frame,
## so counting arena children would lag a destroyed wall by one render.
func _block_count() -> int:
	return view._blocks.size()


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"blast_grid"),
		"res://src/minigames/blast_grid/blast_grid_view.tscn"
	)


func test_renders_pillar_and_soft_blocks() -> void:
	var g := _full_grid()
	g[_cell(2, 2)] = BlastGrid.Cell.SOLID
	g[_cell(3, 3)] = BlastGrid.Cell.SOFT
	view.render({"grid": g, "players": {}, "bombs": [], "flames": [], "powerups": []})
	assert_eq(_block_count(), 2, "one node per pillar/soft cell")


func test_destroyed_soft_wall_frees_its_block_and_puffs() -> void:
	var g := _full_grid()
	g[_cell(3, 3)] = BlastGrid.Cell.SOFT
	view.render({"grid": g, "players": {}, "bombs": [], "flames": [], "powerups": []})
	assert_eq(_block_count(), 1)
	var before := view.arena.get_child_count()
	g = g.duplicate()
	g[_cell(3, 3)] = BlastGrid.Cell.EMPTY
	view.render({"grid": g, "players": {}, "bombs": [], "flames": [], "powerups": []})
	assert_eq(_block_count(), 0, "the block is freed when the wall is gone")
	assert_gt(view.arena.get_child_count(), before - 1, "a dust puff spawns")


func test_a_new_flame_bursts_and_shakes() -> void:
	watch_signals(view)
	view.render({"grid": _full_grid(), "players": {}, "bombs": [], "flames": [], "powerups": []})
	view.render(
		{"grid": _full_grid(), "players": {}, "bombs": [], "flames": [_cell(1, 1)], "powerups": []}
	)
	assert_signal_emitted(view, "shake_requested", "a detonation shakes the screen")


func test_bombs_and_powerups_render() -> void:
	(
		view
		. render(
			{
				"grid": _full_grid(),
				"players": {},
				"bombs": [[_cell(1, 1), 1.2]],
				"flames": [],
				"powerups": [[_cell(2, 1), BlastGrid.Power.RANGE]],
			}
		)
	)
	# Bomb + power-up meshes live in the pools.
	assert_eq(view._bomb_nodes.size(), 1)
	assert_eq(view._power_nodes.size(), 1)


func test_players_update_and_eliminated_hide() -> void:
	(
		view
		. render(
			{
				"grid": _full_grid(),
				"players": {0: [0.0, 0.0, 3, 2]},
				"bombs": [],
				"flames": [],
				"powerups": [],
			}
		)
	)
	assert_true(view.rig_for_slot(0).visible, "a listed player is shown")
	assert_false(view.rig_for_slot(1).visible, "an eliminated (absent) player is hidden")
	assert_string_contains(view.rig_for_slot(0).display_name, "3", "range on the nameplate")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.grid, [])


## End-to-end: a real sim snapshot renders without error.
func test_renders_a_real_sim_snapshot() -> void:
	var sim := BlastGrid.new()
	sim.meta = BlastGrid.make_meta()
	sim.setup([0, 1] as Array[int], 7)
	sim.tick(1.0 / 30.0)
	view.render(sim.get_snapshot())
	assert_gt(_block_count(), 0, "the real grid renders pillars/soft walls")
	assert_true(view.rig_for_slot(0).visible)
