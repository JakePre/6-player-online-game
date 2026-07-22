extends GutTest
## Color Clash client view (M8-10): renders replicated snapshots in the
## shared iso-arena without simulating anything locally.

var view: MinigameView3D


func _new_view(player_names: Dictionary) -> MinigameView3D:
	var scene: PackedScene = load("res://src/minigames/color_clash/color_clash_view.tscn")
	var instance: MinigameView3D = scene.instantiate()
	add_child_autofree(instance)
	instance.setup(player_names, 0)
	return instance


func before_each() -> void:
	view = _new_view({0: "Alice", 1: "Bob"})


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"color_clash"),
		"res://src/minigames/color_clash/color_clash_view.tscn"
	)


func test_setup_builds_iso_arena_with_paint_tiles() -> void:
	assert_not_null(view.arena)
	assert_not_null(view.rig_for_slot(0))
	var tiles: MultiMeshInstance3D = view.arena.get_node("PaintTiles")
	assert_eq(tiles.multimesh.instance_count, ColorClash.GRID_SIZE * ColorClash.GRID_SIZE)


## #1127 GFX: the floor wears the stone-paver texture, and rocks ring the grid.
func test_gfx_floor_texture_and_rim_props() -> void:
	var mat := (view.arena.get_node("Floor") as MultiMeshInstance3D).material_override
	assert_eq((mat as StandardMaterial3D).albedo_texture, view.FLOOR_TEXTURE)
	var props := view.arena.get_node("RimProps")
	assert_eq(props.get_child_count(), view.RIM_PROP_COUNT)


## #1127: the score monument builds lazily once any tile has a faction, one
## band per faction, and its label tracks the live tile counts — in
## team_mode.
func test_gfx_monument_builds_lazily_and_tracks_counts() -> void:
	assert_null(view.arena.get_node_or_null("ScoreMonument"), "no monument before any paint")
	view.render({"players": {}, "grid": [], "teams": [[0], [1]], "counts": {0: 12, 1: 9}})
	var monument := view.arena.get_node("ScoreMonument")
	assert_not_null(monument)
	assert_not_null(monument.get_node("Band0"))
	assert_not_null(monument.get_node("Band1"))
	assert_eq((monument.get_node("MonumentLabel") as Label3D).text, "12 : 9")


## #1127: `teams` stays empty in FFA (team_count_for returns 0, #178) — the
## monument must still build from `counts` alone, one band per slot-faction.
func test_gfx_monument_builds_in_ffa_mode_with_no_teams() -> void:
	view.render({"players": {}, "grid": [], "teams": [], "counts": {0: 4, 2: 7}})
	var monument := view.arena.get_node("ScoreMonument")
	assert_not_null(monument, "FFA still builds the monument from counts")
	assert_not_null(monument.get_node("Band0"))
	assert_not_null(monument.get_node("Band2"))
	assert_eq((monument.get_node("MonumentLabel") as Label3D).text, "4 : 7")


## M15 → 24: the tile mesh sizes to the scaled grid the sim will paint, from
## the head count alone (no snapshot needed), so both stay in lockstep.
func test_paint_mesh_scales_with_lobby() -> void:
	var names := {}
	for i in 24:
		names[i] = "P%d" % i
	var big := _new_view(names)
	var tiles: MultiMeshInstance3D = big.arena.get_node("PaintTiles")
	var dim := ColorClash.grid_dim_for(24)
	assert_eq(dim, 24)
	assert_eq(tiles.multimesh.instance_count, dim * dim, "one instance per scaled tile")


func test_render_replaces_replicated_state() -> void:
	view.render({"players": {0: [1.0, 2.0, 0]}, "grid": [0, -1, 1], "teams": []})
	assert_eq(view.players.size(), 1)
	assert_eq(view.grid, [0, -1, 1])
	view.render({"players": {}, "grid": [1], "teams": [[0], [1]]})
	assert_eq(view.players.size(), 0, "each snapshot fully replaces the last")
	assert_eq(view.teams, [[0], [1]])


func test_painted_tiles_take_faction_colors() -> void:
	var full_grid: Array = []
	full_grid.resize(ColorClash.GRID_SIZE * ColorClash.GRID_SIZE)
	full_grid.fill(ColorClash.UNPAINTED)
	full_grid[0] = 0
	view.render({"players": {}, "grid": full_grid, "teams": []})
	assert_ne(view.tile_color(0), view.tile_color(1))
	assert_eq(view.tile_color(0), PlayerPalette.color_for_slot(0).darkened(0.15))


func test_team_tiles_use_first_teammate_color() -> void:
	view.render({"players": {}, "grid": [1], "teams": [[0], [1]]})
	assert_eq(view.tile_color(0), PlayerPalette.color_for_slot(1).darkened(0.15))


func test_rig_follows_player_snapshot() -> void:
	view.render({"players": {0: [4.0, -2.0, 0]}, "grid": [], "teams": []})
	var rig: CharacterRig = view.rig_for_slot(0)
	assert_almost_eq(rig.position.x, 4.0, 0.001)
	assert_almost_eq(rig.position.z, -2.0, 0.001)


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.grid, [])


func _full_grid(fill: int = ColorClash.UNPAINTED) -> Array:
	var grid_data: Array = []
	grid_data.resize(ColorClash.GRID_SIZE * ColorClash.GRID_SIZE)
	grid_data.fill(fill)
	return grid_data


## M13-21: the first grid sighting seeds the splat diff silently.
## +1 below in every case is the #1127 score monument: it builds lazily, once,
## the first time `counts` arrives non-empty — the same render each of these
## triggers it on.
func test_first_snapshot_seeds_without_splats() -> void:
	var before: int = view.arena.get_child_count()
	view.render({"players": {}, "grid": _full_grid(0), "teams": [], "counts": {0: 144}})
	assert_eq(view.arena.get_child_count(), before + 1, "first sighting seeds silently")


func test_fresh_paint_splats() -> void:
	var grid_data := _full_grid()
	view.render({"players": {}, "grid": grid_data, "teams": [], "counts": {}})
	var before: int = view.arena.get_child_count()
	grid_data = grid_data.duplicate()
	grid_data[5] = 0
	view.render({"players": {}, "grid": grid_data, "teams": [], "counts": {0: 1}})
	assert_eq(view.arena.get_child_count(), before + 2, "a repainted tile = one splat + monument")


func test_mass_repaint_splats_are_capped() -> void:
	view.render({"players": {}, "grid": _full_grid(), "teams": [], "counts": {}})
	var before: int = view.arena.get_child_count()
	view.render({"players": {}, "grid": _full_grid(0), "teams": [], "counts": {0: 144}})
	var cap: int = view.MAX_SPLATS_PER_SNAPSHOT
	assert_eq(
		view.arena.get_child_count(), before + cap + 1, "mass repaint splats are capped + monument"
	)


## M13-21: coverage shimmer follows the leading faction and advances each
## snapshot; a dead heat has no leader.
func test_leading_faction_shimmer_advances() -> void:
	view.render({"players": {}, "grid": [0, 0, 1], "teams": [], "counts": {0: 2, 1: 1}})
	assert_eq(view.leading_faction(), 0)
	var boost_a: float = view.shimmer_boost()
	view.render({"players": {}, "grid": [0, 0, 1], "teams": [], "counts": {0: 2, 1: 1}})
	assert_ne(view.shimmer_boost(), boost_a, "shimmer advances across snapshots")


func test_tied_coverage_has_no_leader() -> void:
	view.render({"players": {}, "grid": [0, 1], "teams": [], "counts": {0: 1, 1: 1}})
	assert_eq(view.leading_faction(), ColorClash.UNPAINTED)


# --- #479: keyframe / delta grid reconstruction ----------------------------


## A keyframe carries the full grid; a following delta folds a changed tile into
## the grid the client already holds, without a full resend.
func test_delta_folds_into_the_held_grid() -> void:
	view.render({"players": {}, "grid": [0, -1, 1], "teams": [], "counts": {}})
	view.render({"players": {}, "grid_changes": [[1, 0]], "teams": [], "counts": {}})
	assert_eq(view.grid, [0, 0, 1], "the delta repaints only tile 1")


## A delta arriving before any keyframe has nothing to build on and is ignored —
## a rejoiner waits out the bounded window for the next keyframe.
func test_delta_before_first_keyframe_is_ignored() -> void:
	view.render({"players": {}, "grid_changes": [[0, 1]], "teams": [], "counts": {}})
	assert_eq(view.grid, [], "no keyframe yet -> nothing to reconstruct")


## The headline self-heal (#479): snapshots are unreliable_ordered, so a dropped
## delta leaves a tile stale — the next keyframe restores the true grid.
func test_dropped_delta_heals_on_next_keyframe() -> void:
	view.render({"players": {}, "grid": [0, -1, -1], "teams": [], "counts": {}})
	# The server flips tile 1 and 2, but that delta never arrives (dropped).
	assert_eq(view.grid, [0, -1, -1], "the client's grid is stale after the drop")
	# The next keyframe carries the true grid and heals the miss.
	view.render({"players": {}, "grid": [0, 0, 1], "teams": [], "counts": {}})
	assert_eq(view.grid, [0, 0, 1], "the keyframe restores the true grid")


# --- Authoritative grid dimension (#662, sibling of Thin Ice #578) ---


## A grid of `dim`x`dim`, tile 0 painted faction 0, the rest unpainted.
func _grid_of(dim: int) -> Array:
	var g: Array = []
	g.resize(dim * dim)
	g.fill(ColorClash.UNPAINTED)
	g[0] = 0
	return g


## A held-but-disconnected member inflates names.size() past a grid_dim_for
## boundary, so the view's estimate (dim 14 for 8) overshoots the sim's
## authoritative dim (13 for the 7 active slots). The view must rebuild its
## tile grid to the snapshot's dim, or the flat grid scrambles onto wrong nodes.
func test_view_adopts_snapshot_dim_when_estimate_is_wrong() -> void:
	var names := {}
	for i in 8:
		names[i] = "P%d" % i
	var v := _new_view(names)
	assert_eq(v._dim, ColorClash.grid_dim_for(8), "estimate is 14 from 8 members")
	var sim_dim := ColorClash.grid_dim_for(7)  # 13 active slots
	(
		v
		. render(
			{
				"players": {},
				"grid": _grid_of(sim_dim),
				"teams": [],
				"counts": {},
				"dim": sim_dim,
				"half": ColorClash.arena_half_for(7),
			}
		)
	)
	assert_eq(v._dim, sim_dim, "the view rebuilt to the authoritative dim")
	var tiles: MultiMeshInstance3D = v.arena.get_node("PaintTiles")
	assert_eq(tiles.multimesh.instance_count, sim_dim * sim_dim, "tile grid matches the sim")
	assert_eq(v.grid.size(), sim_dim * sim_dim, "the keyframe grid folded onto the fresh grid")
	assert_ne(v.tile_color(0), v.UNPAINTED_COLOR, "the painted tile maps to node 0, not scrambled")


## The common all-connected path (estimate already matches) never churns the
## MultiMesh — same node, same instance count.
func test_matching_dim_does_not_rebuild() -> void:
	var before: MultiMeshInstance3D = view.arena.get_node("PaintTiles")
	var dim := ColorClash.grid_dim_for(2)
	view.render({"players": {}, "grid": _grid_of(dim), "teams": [], "counts": {}, "dim": dim})
	assert_same(
		view.arena.get_node("PaintTiles"), before, "no rebuild when the dim already matches"
	)


## After a rebuild the delta-fold baseline resets: a grid_changes computed
## against the old width is not applied to the fresh grid — it waits for a
## keyframe (#479), so no stale-width tile leaks through.
func test_stale_width_delta_is_not_applied_after_rebuild() -> void:
	var names := {}
	for i in 8:
		names[i] = "P%d" % i
	var v := _new_view(names)
	var sim_dim := ColorClash.grid_dim_for(7)
	# A delta-only snapshot at the corrected dim: the rebuild drops the baseline,
	# so this delta has nothing to fold onto and is ignored until a keyframe.
	v.render({"players": {}, "grid_changes": [[5, 0]], "teams": [], "counts": {}, "dim": sim_dim})
	assert_eq(v._dim, sim_dim, "still adopts the authoritative dim")
	assert_eq(v.grid, [], "the stale-width delta is not folded onto the fresh grid")
