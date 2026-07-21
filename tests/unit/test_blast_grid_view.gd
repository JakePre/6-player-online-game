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


## PR #1074 (was #929): soft (destructible) walls are the real MDL-018 crate
## model; indestructible pillars stay flat-colored boxes — structural, not
## crates.
func test_soft_walls_are_crate_models_pillars_stay_boxes() -> void:
	var g := _full_grid()
	g[_cell(2, 2)] = BlastGrid.Cell.SOLID
	g[_cell(3, 3)] = BlastGrid.Cell.SOFT
	view.render({"grid": g, "players": {}, "bombs": [], "flames": [], "powerups": []})
	var pillar_root: Node3D = view._blocks[_cell(2, 2)] as Node3D
	assert_not_null(pillar_root, "pillar has a root node")
	var pillar := pillar_root.find_child("Pillar", true, false) as MeshInstance3D
	assert_not_null(pillar, "pillar contains a MeshInstance3D child")
	var pillar_mat := (pillar.mesh as BoxMesh).material as StandardMaterial3D
	assert_null(pillar_mat.albedo_texture, "pillars stay flat-colored")
	var meshes := pillar_root.find_children("*", "MeshInstance3D", true, false)
	assert_gt(meshes.size(), 1, "pillar root has pillar mesh + cap mesh")
	var crate: Node3D = view._blocks[_cell(3, 3)]
	assert_false(crate is MeshInstance3D, "soft wall is the instanced crate scene")
	assert_gt(
		crate.find_children("*", "MeshInstance3D", true, false).size(),
		0,
		"the crate scene carries the model's meshes"
	)


## #929: powerups read as a billboard icon (flame=range, bomb=extra bomb)
## instead of a plain colored blob.
func test_powerup_icons_match_their_kind() -> void:
	view.render(
		{
			"grid": _full_grid(),
			"players": {},
			"bombs": [],
			"flames": [],
			"powerups": [[_cell(1, 1), BlastGrid.Power.RANGE], [_cell(2, 2), BlastGrid.Power.BOMB]]
		}
	)
	assert_eq(view._power_nodes[0].text, view.RANGE_ICON)
	assert_eq(view._power_nodes[1].text, view.BOMB_ICON)


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


# --- #949 homage visuals ------------------------------------------------------


## Skulls render as the MDL-016 model in their own pool; range/bomb stay glyphs.
func test_cursed_skull_uses_its_own_model_pool() -> void:
	(
		view
		. render(
			{
				"grid": _full_grid(),
				"players": {},
				"bombs": [],
				"flames": [],
				"powerups":
				[[_cell(2, 1), BlastGrid.Power.SKULL], [_cell(2, 2), BlastGrid.Power.RANGE]],
			}
		)
	)
	assert_eq(view._skull_nodes.size(), 1, "the skull went to the model pool")
	assert_eq(view._power_nodes.size(), 1, "the range glyph stayed in the label pool")


## A cursed player wears the skull icon on the nameplate (#949).
func test_cursed_player_wears_the_skull_nameplate() -> void:
	(
		view
		. render(
			{
				"grid": _full_grid(),
				"players": {0: [0.0, 0.0, 2, 1, 1]},  # PS_CURSED = 1
				"bombs": [],
				"flames": [],
				"powerups": [],
			}
		)
	)
	assert_string_contains(
		view.rig_for_slot(0).display_name, view.CURSED_ICON, "skull on nameplate"
	)


## Border-revenge riders re-show the eliminated rig at its border spot, ghosted.
func test_border_rider_shows_ghosted_on_the_border() -> void:
	(
		view
		. render(
			{
				"grid": _full_grid(),
				"players": {0: [0.0, 0.0, 2, 1, 0]},
				"bombs": [],
				"flames": [],
				"powerups": [],
				"revenge": [[6.0, 0.0, 1]],  # slot 1 rides the border
			}
		)
	)
	var ghost := view.rig_for_slot(1)
	assert_true(ghost.visible, "the eliminated rider is shown on the border")
	assert_eq(ghost.player_color, view.GHOST_COLOR, "ghost-tinted")


## A sliding bomb (#949) renders at its continuous x,y, not its cell center.
func test_sliding_bomb_renders_at_its_continuous_position() -> void:
	var slid := Vector2(3.3, -1.1)
	(
		view
		. render(
			{
				"grid": _full_grid(),
				"players": {},
				"bombs": [[_cell(1, 1), 1.2, slid.x, slid.y, 0]],
				"flames": [],
				"powerups": [],
			}
		)
	)
	var expected := view.to_arena(slid, BlastGrid.CELL_SIZE * 0.32)
	assert_almost_eq(view._bomb_nodes[0].position.x, expected.x, 0.001)
	assert_almost_eq(view._bomb_nodes[0].position.z, expected.z, 0.001)
