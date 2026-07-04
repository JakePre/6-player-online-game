extends GutTest
## Thin Ice client view (M8-06): renders replicated snapshots in the shared
## iso-arena without simulating anything locally.

const VIEW_SCENE := preload("res://src/minigames/thin_ice/thin_ice_view.tscn")

var view: MinigameView


func before_each() -> void:
	view = VIEW_SCENE.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func _full_grid(state: int) -> Array:
	var grid: Array = []
	grid.resize(ThinIce.GRID_SIZE * ThinIce.GRID_SIZE)
	grid.fill(state)
	return grid


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"thin_ice"),
		"res://src/minigames/thin_ice/thin_ice_view.tscn"
	)


func test_setup_builds_ice_grid_over_water() -> void:
	assert_not_null(view.arena.get_node("Water"))
	assert_not_null(view.arena.get_node("Tile_0_0"))
	assert_not_null(
		view.arena.get_node("Tile_%d_%d" % [ThinIce.GRID_SIZE - 1, ThinIce.GRID_SIZE - 1])
	)
	assert_null(view.arena.get_node_or_null("Floor"), "default kit floor is replaced by the ice")


func test_tiles_follow_damage_states() -> void:
	var grid := _full_grid(ThinIce.TileState.INTACT)
	grid[0] = ThinIce.TileState.CRACKED
	grid[1] = ThinIce.TileState.GONE
	view.render({"tiles": grid, "players": {}, "fallen": []})
	var cracked: MeshInstance3D = view.arena.get_node("Tile_0_0")
	var gone: MeshInstance3D = view.arena.get_node("Tile_1_0")
	var intact: MeshInstance3D = view.arena.get_node("Tile_2_0")
	assert_true(cracked.visible)
	assert_eq(cracked.material_override, view._cracked_material)
	assert_false(gone.visible, "gone tiles vanish into the water")
	assert_eq(intact.material_override, view._intact_material)


func test_rig_follows_player_snapshot() -> void:
	view.render(
		{"tiles": _full_grid(ThinIce.TileState.INTACT), "players": {0: [3.0, -2.0]}, "fallen": []}
	)
	var rig: CharacterRig = view.rig_for_slot(0)
	assert_true(rig.visible)
	assert_almost_eq(rig.position.x, 3.0, 0.001)
	assert_almost_eq(rig.position.z, -2.0, 0.001)


func test_fallen_player_rig_disappears() -> void:
	var grid := _full_grid(ThinIce.TileState.INTACT)
	view.render({"tiles": grid, "players": {0: [0.0, 0.0], 1: [1.0, 1.0]}, "fallen": []})
	assert_true(view.rig_for_slot(1).visible)
	view.render({"tiles": grid, "players": {0: [0.0, 0.0]}, "fallen": [[1]]})
	assert_false(view.rig_for_slot(1).visible, "fall groups flatten to hidden rigs")
	assert_true(view.rig_for_slot(0).visible)


func test_render_replaces_replicated_state() -> void:
	var grid := _full_grid(ThinIce.TileState.INTACT)
	view.render({"tiles": grid, "players": {0: [1.0, -2.0]}, "fallen": []})
	assert_eq(view.players.size(), 1)
	assert_eq(view.players[0], [1.0, -2.0])
	view.render({"tiles": grid, "players": {}, "fallen": [[0]]})
	assert_eq(view.players.size(), 0, "each snapshot fully replaces the last")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.tiles.size(), 0)
	assert_eq(view.fallen.size(), 0)


## M6-02: a new fall shakes the screen; the first snapshot never does (so a
## mid-match rejoiner is not greeted with a shake).
func test_new_fall_requests_screen_shake() -> void:
	watch_signals(view)
	var grid := _full_grid(ThinIce.TileState.INTACT)
	view.render({"tiles": grid, "players": {0: [0.0, 0.0]}, "fallen": [[1]]})
	assert_signal_not_emitted(view, "shake_requested", "seeding snapshot stays calm")
	view.render({"tiles": grid, "players": {}, "fallen": [[1], [0]]})
	assert_signal_emitted(view, "shake_requested")


## M13-05: tiles chip when they crack, splash when they give way; the seeding
## snapshot fires nothing.
func test_tile_transitions_fire_fx_once_seeded() -> void:
	var grid := _full_grid(ThinIce.TileState.INTACT)
	grid[0] = ThinIce.TileState.CRACKED
	view.render({"tiles": grid, "players": {}, "fallen": []})
	var before: int = view.arena.get_child_count()
	var grid2 := grid.duplicate()
	grid2[1] = ThinIce.TileState.CRACKED
	grid2[0] = ThinIce.TileState.GONE
	view.render({"tiles": grid2, "players": {}, "fallen": []})
	assert_eq(view.arena.get_child_count(), before + 2, "one chip puff + one give-way splash")
	view.render({"tiles": grid2, "players": {}, "fallen": []})
	assert_eq(view.arena.get_child_count(), before + 2, "no transition, no FX")


## M15: the view mirrors the sim's grid-scaling formula, so a 12-player
## lobby builds a bigger tile grid matching what the snapshot's tiles array
## will be sized to.
func test_grid_scales_at_twelve_players() -> void:
	assert_eq(view._grid_size(), ThinIce.GRID_SIZE, "2 players = baseline grid")
	var big: MinigameView3D = VIEW_SCENE.instantiate()
	add_child_autofree(big)
	var names := {}
	for i in 12:
		names[i] = "P%d" % (i + 1)
	big.setup(names, 0)
	assert_gt(big._grid_size(), ThinIce.GRID_SIZE, "12 players get a bigger grid")
	var last: int = int(big._grid_size()) - 1
	assert_not_null(
		big.arena.get_node_or_null("Tile_%d_%d" % [last, last]), "the grown grid actually built"
	)
